import { ImError, TypedEmitter } from '@msn-aim/im-core';
import { createLogger } from '@msn-aim/shared';
import { ByteReader, ByteWriter } from '../wire/bytebuf';
import { TlvBag, writeTlv, writeTlvU16, writeTlvU32 } from '../wire/tlv';
import { SNAC_FLAG_MORE_REPLIES, type Snac } from '../wire/snac';
import { FlapChannel } from '../wire/flap';
import {
  AuthErrorCode,
  Bucp,
  Buddy as BuddySnac,
  CLIENT_BUILD,
  CLIENT_COUNTRY,
  CLIENT_DISTRIBUTION,
  CLIENT_ID,
  CLIENT_ID_STRING,
  CLIENT_LANGUAGE,
  CLIENT_LESSER,
  CLIENT_MAJOR,
  CLIENT_MINOR,
  Feedbag as FeedbagSnac,
  FeedbagClass,
  Foodgroup,
  Icbm as IcbmSnac,
  Locate as LocateSnac,
  OService
} from '../consts';
import { bucpPasswordHash } from '../auth/md5login';
import { OscarConnection } from './OscarConnection';
import { RateLimiter } from './RateLimiter';
import {
  encodeClientOnline,
  encodeClientVersions,
  encodeRateAck,
  encodeSetIdle,
  parseRateWarning
} from '../foodgroups/oservice';
import {
  LOCATE_TYPE_AWAY,
  LOCATE_TYPE_PROFILE,
  encodeSetInfo,
  encodeUserInfoQuery,
  parseUserInfoReply,
  type LocateUserInfoReply
} from '../foodgroups/locate';
import { parseBuddyEvent } from '../foodgroups/buddy';
import {
  encodeParamsSet,
  encodeSendMessage,
  encodeTyping,
  parseIncomingMessage,
  parseTyping,
  type IncomingMessage,
  type MtnEvent
} from '../foodgroups/icbm';
import {
  FEEDBAG_STATUS_MESSAGES,
  allocateGroupId,
  allocateItemId,
  buildTree,
  encodeGroupChildrenTlv,
  encodeItem,
  encodeQuery,
  parseReplyFrame,
  parseStatus,
  type FeedbagItem,
  type GroupEntry
} from '../foodgroups/feedbag';
import type { UserInfo } from '../codec/userinfo';

const log = createLogger('oscar:bos');

const LOGIN_TIMEOUT_MS = 45_000;
const MUTATION_TIMEOUT_MS = 15_000;

export interface BosSessionConfig {
  host: string;
  port: number;
  screenName: string;
  password: string;
}

export type BosStage =
  | 'idle'
  | 'auth-connect'
  | 'auth-key'
  | 'auth-login'
  | 'bos-connect'
  | 'host-ready'
  | 'rate-sync'
  | 'feedbag-sync'
  | 'online'
  | 'closed';

export interface BosSessionEvents {
  stage: (stage: BosStage) => void;
  buddyList: (groups: GroupEntry[]) => void;
  presence: (info: UserInfo, online: boolean) => void;
  message: (msg: IncomingMessage) => void;
  typing: (from: string, event: MtnEvent) => void;
  userInfo: (reply: LocateUserInfoReply) => void;
  rateWarning: (classId: number, code: number) => void;
  closed: (err?: ImError) => void;
  [key: string]: (...args: never[]) => void;
}

/**
 * The OSCAR session state machine: authenticates via BUCP, establishes
 * the BOS connection, negotiates services, syncs the Feedbag and then
 * exposes messaging/presence primitives. One instance per sign-on.
 */
export class BosSession extends TypedEmitter<BosSessionEvents> {
  private conn: OscarConnection | null = null;
  private readonly rate = new RateLimiter();
  private stage: BosStage = 'idle';
  private requestId = 1;
  private feedbagItems: FeedbagItem[] = [];
  private feedbagAccumulator: FeedbagItem[] = [];
  private pendingStatus: {
    requestId: number;
    resolve: (codes: number[]) => void;
    reject: (err: Error) => void;
    timer: NodeJS.Timeout;
  }[] = [];
  private loginResolve: (() => void) | null = null;
  private loginReject: ((err: ImError) => void) | null = null;
  private explicitDisconnect = false;

  constructor(private readonly config: BosSessionConfig) {
    super();
  }

  get currentStage(): BosStage {
    return this.stage;
  }

  get feedbag(): readonly FeedbagItem[] {
    return this.feedbagItems;
  }

  private setStage(stage: BosStage): void {
    this.stage = stage;
    log.debug(`stage -> ${stage}`);
    this.emit('stage', stage);
  }

  private nextRequestId(): number {
    this.requestId = (this.requestId + 1) & 0x7fffffff;
    return this.requestId;
  }

  /** Authenticate and run the session to ONLINE. */
  async login(): Promise<void> {
    if (this.stage !== 'idle') throw new Error('session already started');
    const { host, port, cookie } = await this.authenticate();
    await this.connectBos(host, port, cookie);
  }

  // ---------------------------------------------------------------- auth

  private async authenticate(): Promise<{ host: string; port: number; cookie: Buffer }> {
    this.setStage('auth-connect');
    const conn = new OscarConnection();
    try {
      await conn.connect(this.config.host, this.config.port);
    } catch (err) {
      throw new ImError('network', `Cannot reach ${this.config.host}:${this.config.port}: ${(err as Error).message}`);
    }

    return await new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        conn.destroy();
        reject(new ImError('network', 'Login timed out'));
      }, LOGIN_TIMEOUT_MS);
      const fail = (err: ImError) => {
        clearTimeout(timer);
        conn.destroy();
        reject(err);
      };

      conn.on('error', (err) => fail(new ImError('network', err.message)));
      conn.on('close', () => {
        // Normal after 17,03 (server closes); only an error mid-handshake.
        if (this.stage === 'auth-connect' || this.stage === 'auth-key') {
          fail(new ImError('network', 'Auth server closed connection unexpectedly'));
        }
      });

      conn.on('signOn', () => {
        // Server hello received; identify and request the MD5 challenge.
        conn.sendFlap(FlapChannel.SignOn, new ByteWriter().u32(1).build());
        this.setStage('auth-key');
        conn.sendSnac({
          foodgroup: Foodgroup.BUCP,
          subtype: Bucp.CHALLENGE_REQUEST,
          flags: 0,
          requestId: this.nextRequestId(),
          body: writeTlv(0x0001, this.config.screenName)
        });
      });

      conn.on('snac', (snac) => {
        if (snac.foodgroup !== Foodgroup.BUCP) return;
        if (snac.subtype === Bucp.CHALLENGE_RESPONSE) {
          const r = new ByteReader(snac.body);
          const authKey = r.bytes(r.u16());
          this.setStage('auth-login');
          conn.sendSnac({
            foodgroup: Foodgroup.BUCP,
            subtype: Bucp.LOGIN_REQUEST,
            flags: 0,
            requestId: this.nextRequestId(),
            body: this.buildLoginRequest(Buffer.from(authKey))
          });
        } else if (snac.subtype === Bucp.LOGIN_RESPONSE) {
          const tlvs = TlvBag.parse(snac.body);
          const errorCode = tlvs.u16(0x0008);
          if (errorCode !== undefined) {
            fail(
              new ImError(
                'auth-failed',
                AuthErrorCode[errorCode] ?? `Sign-on failed (error 0x${errorCode.toString(16)})`,
                true
              )
            );
            return;
          }
          const bosAddress = tlvs.string(0x0005);
          const cookie = tlvs.raw(0x0006);
          if (!bosAddress || !cookie) {
            fail(new ImError('protocol', 'Auth response missing BOS address or cookie'));
            return;
          }
          const [host, portStr] = bosAddress.split(':');
          clearTimeout(timer);
          conn.signOff();
          resolve({
            host: host || this.config.host,
            port: portStr ? parseInt(portStr, 10) : this.config.port,
            cookie: Buffer.from(cookie)
          });
        } else if (snac.subtype === Bucp.ERROR) {
          fail(new ImError('auth-failed', 'Authentication rejected', true));
        }
      });
    });
  }

  private buildLoginRequest(authKey: Buffer): Buffer {
    return Buffer.concat([
      writeTlv(0x0001, this.config.screenName),
      writeTlv(0x0025, bucpPasswordHash(authKey, this.config.password)),
      writeTlv(0x0003, CLIENT_ID_STRING),
      writeTlvU16(0x0016, CLIENT_ID),
      writeTlvU16(0x0017, CLIENT_MAJOR),
      writeTlvU16(0x0018, CLIENT_MINOR),
      writeTlvU16(0x0019, CLIENT_LESSER),
      writeTlvU16(0x001a, CLIENT_BUILD),
      writeTlvU32(0x0014, CLIENT_DISTRIBUTION),
      writeTlv(0x000f, CLIENT_LANGUAGE),
      writeTlv(0x000e, CLIENT_COUNTRY)
    ]);
  }

  // ----------------------------------------------------------------- bos

  private async connectBos(host: string, port: number, cookie: Buffer): Promise<void> {
    this.setStage('bos-connect');
    const conn = new OscarConnection();
    this.conn = conn;
    try {
      await conn.connect(host, port);
    } catch (err) {
      throw new ImError('network', `Cannot reach BOS ${host}:${port}: ${(err as Error).message}`);
    }

    return await new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.close(new ImError('network', 'Timed out negotiating session'));
      }, LOGIN_TIMEOUT_MS);
      this.loginResolve = () => {
        clearTimeout(timer);
        this.loginResolve = null;
        this.loginReject = null;
        resolve();
      };
      this.loginReject = (err) => {
        clearTimeout(timer);
        this.loginResolve = null;
        this.loginReject = null;
        reject(err);
      };

      conn.on('signOn', () => {
        conn.sendFlap(
          FlapChannel.SignOn,
          Buffer.concat([new ByteWriter().u32(1).build(), writeTlv(0x0006, cookie)])
        );
        this.setStage('host-ready');
      });
      conn.on('snac', (snac) => this.dispatch(snac));
      conn.on('closeFrame', (payload) => {
        const tlvs = TlvBag.parse(payload);
        const code = tlvs.u16(0x0009);
        const err =
          code !== undefined
            ? new ImError(
                code === 0x0001 ? 'auth-failed' : 'protocol',
                code === 0x0001
                  ? 'Signed on from another location'
                  : `Server closed the connection (code 0x${code.toString(16)})`,
                true
              )
            : undefined;
        this.close(err);
      });
      conn.on('error', (err) => {
        if (!this.explicitDisconnect) this.close(new ImError('network', err.message));
      });
      conn.on('close', () => {
        if (this.stage !== 'closed') this.close();
      });
    });
  }

  private send(foodgroup: number, subtype: number, body: Buffer, requestId?: number): number {
    const conn = this.conn;
    if (!conn) throw new ImError('network', 'Not connected');
    const id = requestId ?? this.nextRequestId();
    const snac: Snac = { foodgroup, subtype, flags: 0, requestId: id, body };
    const delay = this.rate.reserveSend(foodgroup, subtype);
    if (delay <= 0) {
      conn.sendSnac(snac);
    } else {
      log.debug(`rate limiter delaying ${foodgroup.toString(16)},${subtype.toString(16)} by ${delay}ms`);
      setTimeout(() => {
        if (this.stage !== 'closed') conn.sendSnac(snac);
      }, delay);
    }
    return id;
  }

  private dispatch(snac: Snac): void {
    const key = `${snac.foodgroup.toString(16).padStart(2, '0')},${snac.subtype
      .toString(16)
      .padStart(2, '0')}`;
    try {
      switch (snac.foodgroup) {
        case Foodgroup.OSERVICE:
          this.onOService(snac);
          break;
        case Foodgroup.LOCATE:
          if (snac.subtype === LocateSnac.USER_INFO_REPLY) {
            this.emit('userInfo', parseUserInfoReply(snac.body));
          }
          break;
        case Foodgroup.BUDDY:
          if (snac.subtype === BuddySnac.ARRIVED) {
            this.emit('presence', parseBuddyEvent(snac.body), true);
          } else if (snac.subtype === BuddySnac.DEPARTED) {
            this.emit('presence', parseBuddyEvent(snac.body), false);
          }
          break;
        case Foodgroup.ICBM:
          this.onIcbm(snac);
          break;
        case Foodgroup.FEEDBAG:
          this.onFeedbag(snac);
          break;
        default:
          log.debug(`unhandled SNAC ${key}`);
      }
    } catch (err) {
      log.warn(`error handling SNAC ${key}: ${(err as Error).message}`);
    }
  }

  private onOService(snac: Snac): void {
    switch (snac.subtype) {
      case OService.HOST_ONLINE:
        this.send(Foodgroup.OSERVICE, OService.CLIENT_VERSIONS, encodeClientVersions());
        this.setStage('rate-sync');
        this.send(Foodgroup.OSERVICE, OService.RATE_PARAMS_QUERY, Buffer.alloc(0));
        break;
      case OService.RATE_PARAMS_REPLY: {
        this.rate.parseRateParams(snac.body);
        this.send(Foodgroup.OSERVICE, OService.RATE_PARAMS_SUB_ADD, encodeRateAck(this.rate.classIds()));
        // Service negotiation, then the buddy list.
        this.send(Foodgroup.LOCATE, LocateSnac.RIGHTS_QUERY, Buffer.alloc(0));
        this.send(Foodgroup.BUDDY, BuddySnac.RIGHTS_QUERY, Buffer.alloc(0));
        this.send(Foodgroup.ICBM, IcbmSnac.PARAMETER_QUERY, Buffer.alloc(0));
        this.send(Foodgroup.FEEDBAG, FeedbagSnac.RIGHTS_QUERY, Buffer.alloc(0));
        this.setStage('feedbag-sync');
        this.feedbagAccumulator = [];
        this.send(Foodgroup.FEEDBAG, FeedbagSnac.QUERY_IF_MODIFIED, encodeQuery());
        break;
      }
      case OService.RATE_LIMIT_WARNING: {
        const { code, classId } = parseRateWarning(snac.body);
        this.rate.noteWarning(classId, code);
        this.emit('rateWarning', classId, code);
        break;
      }
      default:
        break;
    }
  }

  private onIcbm(snac: Snac): void {
    switch (snac.subtype) {
      case IcbmSnac.PARAMETER_REPLY:
        this.send(Foodgroup.ICBM, IcbmSnac.ADD_PARAMETERS, encodeParamsSet());
        break;
      case IcbmSnac.CHANNEL_MSG_TO_CLIENT: {
        const msg = parseIncomingMessage(snac.body);
        if (msg) this.emit('message', msg);
        break;
      }
      case IcbmSnac.MTN: {
        const { from, event } = parseTyping(snac.body);
        this.emit('typing', from, event);
        break;
      }
      case IcbmSnac.ERROR:
        log.warn('ICBM error from server');
        break;
      default:
        break;
    }
  }

  private onFeedbag(snac: Snac): void {
    switch (snac.subtype) {
      case FeedbagSnac.REPLY:
      case FeedbagSnac.REPLY_NOT_MODIFIED: {
        if (snac.subtype === FeedbagSnac.REPLY) {
          const frame = parseReplyFrame(snac.body);
          this.feedbagAccumulator.push(...frame.items);
        }
        const moreComing = (snac.flags & SNAC_FLAG_MORE_REPLIES) !== 0;
        if (!moreComing && this.stage === 'feedbag-sync') {
          this.feedbagItems = this.feedbagAccumulator;
          this.send(Foodgroup.FEEDBAG, FeedbagSnac.USE, Buffer.alloc(0));
          this.emit('buddyList', buildTree(this.feedbagItems));
          this.finalize();
        }
        break;
      }
      case FeedbagSnac.STATUS: {
        const codes = parseStatus(snac.body);
        const idx = this.pendingStatus.findIndex((p) => p.requestId === snac.requestId);
        const pending = idx >= 0 ? this.pendingStatus.splice(idx, 1)[0] : this.pendingStatus.shift();
        if (pending) {
          clearTimeout(pending.timer);
          pending.resolve(codes);
        }
        break;
      }
      default:
        break;
    }
  }

  private finalize(): void {
    // Advertise ourselves (empty profile, no capabilities) and go online.
    this.send(
      Foodgroup.LOCATE,
      LocateSnac.SET_INFO,
      encodeSetInfo({ profile: '', capabilities: Buffer.alloc(0) })
    );
    this.send(Foodgroup.OSERVICE, OService.CLIENT_ONLINE, encodeClientOnline());
    this.conn?.startKeepalive();
    this.setStage('online');
    // Ask for messages stored while we were offline (ignored if unsupported).
    this.send(Foodgroup.ICBM, IcbmSnac.OFFLINE_RETRIEVE, Buffer.alloc(0));
    this.loginResolve?.();
  }

  // ------------------------------------------------------------- actions

  private assertOnline(): void {
    if (this.stage !== 'online') throw new ImError('network', 'Not signed on');
  }

  sendIM(to: string, text: string, opts?: { autoResponse?: boolean }): void {
    this.assertOnline();
    this.send(
      Foodgroup.ICBM,
      IcbmSnac.CHANNEL_MSG_TO_HOST,
      encodeSendMessage(to, text, { storeOffline: true, autoResponse: opts?.autoResponse })
    );
  }

  sendTyping(to: string, event: MtnEvent): void {
    this.assertOnline();
    this.send(Foodgroup.ICBM, IcbmSnac.MTN, encodeTyping(to, event));
  }

  setAwayMessage(awayHtml: string): void {
    this.assertOnline();
    this.send(Foodgroup.LOCATE, LocateSnac.SET_INFO, encodeSetInfo({ awayMessage: awayHtml }));
  }

  setProfile(profileHtml: string): void {
    this.assertOnline();
    this.send(Foodgroup.LOCATE, LocateSnac.SET_INFO, encodeSetInfo({ profile: profileHtml }));
  }

  setIdle(seconds: number): void {
    this.assertOnline();
    this.send(Foodgroup.OSERVICE, OService.IDLE_NOTIFICATION, encodeSetIdle(seconds));
  }

  requestUserInfo(screenName: string, away = true): void {
    this.assertOnline();
    this.send(
      Foodgroup.LOCATE,
      LocateSnac.USER_INFO_QUERY,
      encodeUserInfoQuery(away ? LOCATE_TYPE_AWAY : LOCATE_TYPE_PROFILE, screenName)
    );
  }

  // --------------------------------------------------- feedbag mutations

  private mutate(subtype: number, body: Buffer): Promise<number[]> {
    this.assertOnline();
    return new Promise<number[]>((resolve, reject) => {
      const requestId = this.nextRequestId();
      const timer = setTimeout(() => {
        const idx = this.pendingStatus.findIndex((p) => p.requestId === requestId);
        if (idx >= 0) this.pendingStatus.splice(idx, 1);
        reject(new ImError('protocol', 'Buddy list update timed out'));
      }, MUTATION_TIMEOUT_MS);
      this.pendingStatus.push({ requestId, resolve, reject, timer });
      this.send(Foodgroup.FEEDBAG, subtype, body, requestId);
    });
  }

  private async mutateChecked(subtype: number, body: Buffer, what: string): Promise<void> {
    const codes = await this.mutate(subtype, body);
    const failure = codes.find((c) => c !== 0);
    if (failure !== undefined) {
      throw new ImError(
        'protocol',
        `${what} failed: ${FEEDBAG_STATUS_MESSAGES[failure] ?? `code 0x${failure.toString(16)}`}`
      );
    }
  }

  private findGroup(groupName: string): FeedbagItem | undefined {
    const needle = groupName.trim().toLowerCase();
    return this.feedbagItems.find(
      (i) => i.classId === FeedbagClass.GROUP && i.groupId !== 0 && i.name.trim().toLowerCase() === needle
    );
  }

  private groupChildren(groupId: number): number[] {
    return this.feedbagItems
      .filter((i) => i.classId === FeedbagClass.BUDDY && i.groupId === groupId)
      .map((i) => i.itemId);
  }

  async addGroup(name: string): Promise<number> {
    const existing = this.findGroup(name);
    if (existing) return existing.groupId;
    const groupId = allocateGroupId(this.feedbagItems);
    this.send(Foodgroup.FEEDBAG, FeedbagSnac.START_CLUSTER, Buffer.alloc(0));
    try {
      await this.mutateChecked(
        FeedbagSnac.INSERT_ITEM,
        encodeItem({ name, groupId, itemId: 0, classId: FeedbagClass.GROUP }),
        `Adding group "${name}"`
      );
    } finally {
      this.send(Foodgroup.FEEDBAG, FeedbagSnac.END_CLUSTER, Buffer.alloc(0));
    }
    this.feedbagItems.push({
      name,
      groupId,
      itemId: 0,
      classId: FeedbagClass.GROUP,
      tlvs: TlvBag.parse(Buffer.alloc(0)),
      rawTlvBlock: Buffer.alloc(0)
    });
    return groupId;
  }

  async addBuddy(screenName: string, groupName: string): Promise<void> {
    const groupId = await this.addGroup(groupName || 'Buddies');
    const itemId = allocateItemId(this.feedbagItems, groupId);
    this.send(Foodgroup.FEEDBAG, FeedbagSnac.START_CLUSTER, Buffer.alloc(0));
    try {
      await this.mutateChecked(
        FeedbagSnac.INSERT_ITEM,
        encodeItem({ name: screenName, groupId, itemId, classId: FeedbagClass.BUDDY }),
        `Adding ${screenName}`
      );
      this.feedbagItems.push({
        name: screenName,
        groupId,
        itemId,
        classId: FeedbagClass.BUDDY,
        tlvs: TlvBag.parse(Buffer.alloc(0)),
        rawTlvBlock: Buffer.alloc(0)
      });
      const group = this.feedbagItems.find(
        (i) => i.classId === FeedbagClass.GROUP && i.groupId === groupId
      );
      if (group) {
        await this.mutateChecked(
          FeedbagSnac.UPDATE_ITEM,
          encodeItem({
            name: group.name,
            groupId,
            itemId: 0,
            classId: FeedbagClass.GROUP,
            tlvBlock: encodeGroupChildrenTlv(this.groupChildren(groupId))
          }),
          'Updating group'
        );
      }
    } finally {
      this.send(Foodgroup.FEEDBAG, FeedbagSnac.END_CLUSTER, Buffer.alloc(0));
    }
    this.emit('buddyList', buildTree(this.feedbagItems));
  }

  async removeBuddy(screenName: string, groupName: string): Promise<void> {
    const needle = screenName.trim().toLowerCase().replace(/\s+/g, '');
    const group = groupName ? this.findGroup(groupName) : undefined;
    const item = this.feedbagItems.find(
      (i) =>
        i.classId === FeedbagClass.BUDDY &&
        i.name.trim().toLowerCase().replace(/\s+/g, '') === needle &&
        (group === undefined || i.groupId === group.groupId)
    );
    if (!item) throw new ImError('protocol', `${screenName} is not on the buddy list`);
    this.send(Foodgroup.FEEDBAG, FeedbagSnac.START_CLUSTER, Buffer.alloc(0));
    try {
      await this.mutateChecked(
        FeedbagSnac.DELETE_ITEM,
        encodeItem({
          name: item.name,
          groupId: item.groupId,
          itemId: item.itemId,
          classId: item.classId,
          tlvBlock: item.rawTlvBlock
        }),
        `Removing ${screenName}`
      );
      this.feedbagItems = this.feedbagItems.filter((i) => i !== item);
      const groupItem = this.feedbagItems.find(
        (i) => i.classId === FeedbagClass.GROUP && i.groupId === item.groupId
      );
      if (groupItem) {
        await this.mutateChecked(
          FeedbagSnac.UPDATE_ITEM,
          encodeItem({
            name: groupItem.name,
            groupId: groupItem.groupId,
            itemId: 0,
            classId: FeedbagClass.GROUP,
            tlvBlock: encodeGroupChildrenTlv(this.groupChildren(groupItem.groupId))
          }),
          'Updating group'
        );
      }
    } finally {
      this.send(Foodgroup.FEEDBAG, FeedbagSnac.END_CLUSTER, Buffer.alloc(0));
    }
    this.emit('buddyList', buildTree(this.feedbagItems));
  }

  async renameGroup(oldName: string, newName: string): Promise<void> {
    const group = this.findGroup(oldName);
    if (!group) throw new ImError('protocol', `No group named "${oldName}"`);
    await this.mutateChecked(
      FeedbagSnac.UPDATE_ITEM,
      encodeItem({
        name: newName,
        groupId: group.groupId,
        itemId: 0,
        classId: FeedbagClass.GROUP,
        tlvBlock: group.rawTlvBlock
      }),
      'Renaming group'
    );
    group.name = newName;
    this.emit('buddyList', buildTree(this.feedbagItems));
  }

  // ---------------------------------------------------------------- exit

  disconnect(): void {
    this.explicitDisconnect = true;
    this.conn?.signOff();
    this.close();
  }

  private close(err?: ImError): void {
    if (this.stage === 'closed') return;
    this.setStage('closed');
    for (const pending of this.pendingStatus.splice(0)) {
      clearTimeout(pending.timer);
      pending.reject(err ?? new ImError('network', 'Disconnected'));
    }
    this.conn?.destroy();
    this.conn = null;
    this.loginReject?.(err ?? new ImError('network', 'Disconnected during sign-on'));
    this.emit('closed', err);
  }
}
