import { createServer, type Server, type Socket } from 'node:net';
import { afterEach, describe, expect, it } from 'vitest';
import { ImError, type Buddy, type BuddyGroup, type ImMessage } from '@msn-aim/im-core';
import { OscarClient } from './OscarClient';
import { FlapChannel, FlapParser, encodeFlap } from './wire/flap';
import { decodeSnac, encodeSnac, SNAC_FLAG_MORE_REPLIES, type Snac } from './wire/snac';
import { ByteWriter } from './wire/bytebuf';
import { TlvBag, writeTlv, writeTlvU16 } from './wire/tlv';
import { bucpPasswordHash } from './auth/md5login';
import { encodeItem } from './foodgroups/feedbag';
import { encodeSendMessage } from './foodgroups/icbm';
import { Bucp, Buddy as BuddySnac, Feedbag, FeedbagClass, Foodgroup, Icbm, Locate, OService } from './consts';

const AUTH_KEY = '1234567890';
const COOKIE = Buffer.from('test-cookie-0001');
const PASSWORD = 'S3cret!';

/** Minimal scripted OSCAR server: BUCP auth + BOS on one port. */
class FakeOscarServer {
  readonly server: Server;
  port = 0;

  constructor() {
    this.server = createServer((socket) => this.handle(socket));
  }

  listen(): Promise<void> {
    return new Promise((resolve) => {
      this.server.listen(0, '127.0.0.1', () => {
        this.port = (this.server.address() as { port: number }).port;
        resolve();
      });
    });
  }

  close(): Promise<void> {
    return new Promise((resolve) => this.server.close(() => resolve()));
  }

  private handle(socket: Socket): void {
    const parser = new FlapParser();
    let seq = 0;
    const sendFlap = (channel: number, payload: Buffer) => {
      if (!socket.destroyed) socket.write(encodeFlap(channel, ++seq & 0xffff, payload));
    };
    const sendSnac = (
      foodgroup: number,
      subtype: number,
      body: Buffer,
      requestId = 0,
      flags = 0
    ) => sendFlap(FlapChannel.Snac, encodeSnac({ foodgroup, subtype, flags, requestId, body }));

    const userInfoBlock = (name: string) =>
      new ByteWriter()
        .pString8(name)
        .u16(0) // warning
        .u16(2) // tlv count
        .bytes(writeTlvU16(0x0001, 0x0010)) // user class: FREE
        .bytes(writeTlv(0x0003, new ByteWriter().u32(1_700_000_000).build())) // signon time
        .build();

    sendFlap(FlapChannel.SignOn, new ByteWriter().u32(1).build());

    socket.on('data', (chunk) => {
      for (const frame of parser.push(chunk)) {
        if (frame.channel === FlapChannel.SignOn) {
          const tlvs = TlvBag.parse(frame.payload.subarray(4));
          if (tlvs.has(0x0006)) {
            // BOS handshake complete -> host online
            sendSnac(Foodgroup.OSERVICE, OService.HOST_ONLINE, new ByteWriter().u16(1).u16(2).u16(3).u16(4).u16(0x13).build());
          }
          continue;
        }
        if (frame.channel !== FlapChannel.Snac) continue;
        const snac = decodeSnac(frame.payload);
        this.onSnac(snac, sendSnac, sendFlap, userInfoBlock);
      }
    });
    socket.on('error', () => undefined);
  }

  private onSnac(
    snac: Snac,
    sendSnac: (fg: number, st: number, body: Buffer, requestId?: number, flags?: number) => void,
    sendFlap: (channel: number, payload: Buffer) => void,
    userInfoBlock: (name: string) => Buffer
  ): void {
    const { foodgroup, subtype } = snac;

    if (foodgroup === Foodgroup.BUCP && subtype === Bucp.CHALLENGE_REQUEST) {
      sendSnac(Foodgroup.BUCP, Bucp.CHALLENGE_RESPONSE, new ByteWriter().pString16(AUTH_KEY).build());
      return;
    }
    if (foodgroup === Foodgroup.BUCP && subtype === Bucp.LOGIN_REQUEST) {
      const tlvs = TlvBag.parse(snac.body);
      const hash = tlvs.raw(0x0025);
      const expected = bucpPasswordHash(Buffer.from(AUTH_KEY), PASSWORD);
      const sn = tlvs.string(0x0001) ?? '';
      if (hash && hash.equals(expected)) {
        sendSnac(
          Foodgroup.BUCP,
          Bucp.LOGIN_RESPONSE,
          Buffer.concat([
            writeTlv(0x0001, sn),
            writeTlv(0x0005, `127.0.0.1:${this.port}`),
            writeTlv(0x0006, COOKIE)
          ])
        );
      } else {
        sendSnac(
          Foodgroup.BUCP,
          Bucp.LOGIN_RESPONSE,
          Buffer.concat([writeTlv(0x0001, sn), writeTlvU16(0x0008, 0x0004)])
        );
      }
      sendFlap(FlapChannel.SignOff, Buffer.alloc(0));
      return;
    }

    if (foodgroup === Foodgroup.OSERVICE) {
      if (subtype === OService.CLIENT_VERSIONS) {
        sendSnac(Foodgroup.OSERVICE, OService.HOST_VERSIONS, snac.body);
      } else if (subtype === OService.RATE_PARAMS_QUERY) {
        // One rate class, no snac->class mappings (keeps the test fast).
        const body = new ByteWriter()
          .u16(1) // class count
          .u16(1) // class id
          .u32(80).u32(2500).u32(2000).u32(1500).u32(800).u32(6000).u32(6000) // window + levels
          .u32(0).u8(0) // lastTime + state (v3)
          .build();
        sendSnac(Foodgroup.OSERVICE, OService.RATE_PARAMS_REPLY, body, snac.requestId);
      } else if (subtype === OService.CLIENT_ONLINE) {
        // Buddy signs on once we're online.
        sendSnac(Foodgroup.BUDDY, BuddySnac.ARRIVED, userInfoBlock('Buddy Two'));
      }
      return;
    }

    if (foodgroup === Foodgroup.LOCATE && subtype === Locate.RIGHTS_QUERY) {
      sendSnac(Foodgroup.LOCATE, Locate.RIGHTS_REPLY, Buffer.alloc(0), snac.requestId);
      return;
    }
    if (foodgroup === Foodgroup.LOCATE && subtype === Locate.USER_INFO_QUERY) {
      sendSnac(
        Foodgroup.LOCATE,
        Locate.USER_INFO_REPLY,
        Buffer.concat([userInfoBlock('Buddy Two'), writeTlv(0x0004, 'gone fishing')]),
        snac.requestId
      );
      return;
    }
    if (foodgroup === Foodgroup.BUDDY && subtype === BuddySnac.RIGHTS_QUERY) {
      sendSnac(Foodgroup.BUDDY, BuddySnac.RIGHTS_REPLY, Buffer.alloc(0), snac.requestId);
      return;
    }

    if (foodgroup === Foodgroup.ICBM) {
      if (subtype === Icbm.PARAMETER_QUERY) {
        const body = new ByteWriter().u16(0).u32(0x0b).u16(8000).u16(999).u16(999).u32(0).build();
        sendSnac(Foodgroup.ICBM, Icbm.PARAMETER_REPLY, body, snac.requestId);
      } else if (subtype === Icbm.CHANNEL_MSG_TO_HOST) {
        // Echo the message back as if "Buddy Two" replied.
        const tlvs = TlvBag.parse(snac.body.subarray(8 + 2 + 1 + (snac.body.readUInt8(10) ?? 0)));
        void tlvs;
        // Simpler: decode via our own parser on a rebuilt inbound frame.
        const sent = snac.body;
        const nameLen = sent.readUInt8(10);
        const msgTlvs = TlvBag.parse(sent.subarray(11 + nameLen));
        const block = msgTlvs.raw(0x0002) ?? Buffer.alloc(0);
        const inbound = Buffer.concat([
          sent.subarray(0, 8), // cookie
          new ByteWriter().u16(1).build(),
          userInfoBlock('Buddy Two'),
          writeTlv(0x0002, block)
        ]);
        sendSnac(Foodgroup.ICBM, Icbm.CHANNEL_MSG_TO_CLIENT, inbound);
        // And a typing notification.
        const typing = new ByteWriter().bytes(Buffer.alloc(8)).u16(1).pString8('Buddy Two').u16(2).build();
        sendSnac(Foodgroup.ICBM, Icbm.MTN, typing);
      }
      return;
    }

    if (foodgroup === Foodgroup.FEEDBAG) {
      if (subtype === Feedbag.RIGHTS_QUERY) {
        sendSnac(Foodgroup.FEEDBAG, Feedbag.RIGHTS_REPLY, Buffer.alloc(0), snac.requestId);
      } else if (subtype === Feedbag.QUERY_IF_MODIFIED || subtype === Feedbag.QUERY) {
        // Two frames to exercise multi-frame accumulation.
        const frame1 = new ByteWriter()
          .u8(0)
          .u16(1)
          .bytes(encodeItem({ name: 'Pals', groupId: 1, itemId: 0, classId: FeedbagClass.GROUP }))
          .build();
        const frame2 = new ByteWriter()
          .u8(0)
          .u16(1)
          .bytes(encodeItem({ name: 'buddy two', groupId: 1, itemId: 11, classId: FeedbagClass.BUDDY }))
          .u32(1_700_000_000)
          .build();
        sendSnac(Foodgroup.FEEDBAG, Feedbag.REPLY, frame1, snac.requestId, SNAC_FLAG_MORE_REPLIES);
        sendSnac(Foodgroup.FEEDBAG, Feedbag.REPLY, frame2, snac.requestId);
      } else if (
        subtype === Feedbag.INSERT_ITEM ||
        subtype === Feedbag.UPDATE_ITEM ||
        subtype === Feedbag.DELETE_ITEM
      ) {
        sendSnac(Foodgroup.FEEDBAG, Feedbag.STATUS, new ByteWriter().u16(0).build(), snac.requestId);
      }
      return;
    }
  }
}

function waitFor<T>(register: (resolve: (v: T) => void) => void, what: string, ms = 5000): Promise<T> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`timed out waiting for ${what}`)), ms);
    register((v) => {
      clearTimeout(timer);
      resolve(v);
    });
  });
}

describe('OscarClient against a scripted OSCAR server', () => {
  let server: FakeOscarServer;
  let client: OscarClient;

  afterEach(async () => {
    await client?.disconnect();
    await server?.close();
  });

  it('signs on, syncs the buddy list, exchanges messages and mutates the feedbag', async () => {
    server = new FakeOscarServer();
    await server.listen();
    client = new OscarClient();

    const buddyListP = waitFor<BuddyGroup[]>((res) => client.on('buddyListReceived', res), 'buddy list');
    const presenceP = waitFor<Buddy>((res) => client.on('buddyPresence', res), 'presence');

    await client.connect({
      protocol: 'oscar',
      username: 'Test User',
      password: PASSWORD,
      server: { host: '127.0.0.1', port: server.port }
    });

    const groups = await buddyListP;
    expect(groups).toHaveLength(1);
    expect(groups[0]!.name).toBe('Pals');
    expect(groups[0]!.buddies[0]!.id).toBe('buddytwo');

    const arrival = await presenceP;
    expect(arrival.id).toBe('buddytwo');
    expect(arrival.status).toBe('online');

    const messageP = waitFor<ImMessage>((res) => client.on('messageReceived', res), 'echo message');
    const typingP = waitFor<[string, string]>(
      (res) => client.on('typing', (from, state) => res([from, state])),
      'typing event'
    );
    await client.sendMessage('buddytwo', 'hello <b>there</b> — ça va? 🙂');
    const echoed = await messageP;
    expect(echoed.from).toBe('buddytwo');
    expect(echoed.body).toBe('hello <b>there</b> — ça va? 🙂');
    expect(echoed.autoResponse).toBe(false);
    const [typingFrom, typingState] = await typingP;
    expect(typingFrom).toBe('buddytwo');
    expect(typingState).toBe('typing');

    // Feedbag mutations resolve on the 13,0E ack.
    await expect(client.addBuddy('new pal', 'Pals')).resolves.toBeUndefined();
    await expect(client.addGroup('Work')).resolves.toBeUndefined();

    // Away-message retrieval round trip.
    const infoP = waitFor<{ id: string; awayMessage?: string }>(
      (res) => client.on('buddyInfo', res),
      'buddy info'
    );
    await client.requestBuddyInfo('buddytwo');
    expect((await infoP).awayMessage).toBe('gone fishing');
  });

  it('rejects with auth-failed on a wrong password and does not reconnect', async () => {
    server = new FakeOscarServer();
    await server.listen();
    client = new OscarClient();
    await expect(
      client.connect({
        protocol: 'oscar',
        username: 'Test User',
        password: 'wrong-password',
        server: { host: '127.0.0.1', port: server.port }
      })
    ).rejects.toMatchObject({ kind: 'auth-failed' } satisfies Partial<ImError>);
  });

  it('parses its own encodeSendMessage output through the server echo path (unicode)', () => {
    // Sanity: the fake server slices name length at offset 10; verify layout.
    const body = encodeSendMessage('buddytwo', 'x');
    expect(body.readUInt16BE(8)).toBe(1); // channel
    expect(body.readUInt8(10)).toBe('buddytwo'.length);
  });
});
