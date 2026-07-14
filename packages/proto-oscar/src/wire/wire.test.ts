import { describe, expect, it } from 'vitest';
import { FlapParser, encodeFlap } from './flap';
import { decodeSnac, encodeSnac } from './snac';
import { TlvBag, writeTlv, writeTlvU16, writeTlvU32 } from './tlv';
import { ByteReader, ByteWriter } from './bytebuf';

describe('FLAP framing', () => {
  it('round-trips a frame', () => {
    const payload = Buffer.from('hello oscar', 'latin1');
    const encoded = encodeFlap(2, 0x1234, payload);
    expect(encoded.readUInt8(0)).toBe(0x2a);
    const frames = new FlapParser().push(encoded);
    expect(frames).toHaveLength(1);
    expect(frames[0]!.channel).toBe(2);
    expect(frames[0]!.sequence).toBe(0x1234);
    expect(frames[0]!.payload.equals(payload)).toBe(true);
  });

  it('reassembles frames split across arbitrary TCP chunk boundaries', () => {
    const a = encodeFlap(2, 1, Buffer.from('first frame'));
    const b = encodeFlap(5, 2, Buffer.alloc(0));
    const c = encodeFlap(2, 3, Buffer.from('third'));
    const stream = Buffer.concat([a, b, c]);
    // Feed one byte at a time — worst case fragmentation.
    const parser = new FlapParser();
    const frames = [];
    for (const byte of stream) frames.push(...parser.push(Buffer.from([byte])));
    expect(frames.map((f) => f.sequence)).toEqual([1, 2, 3]);
    expect(frames[0]!.payload.toString()).toBe('first frame');
    expect(frames[2]!.payload.toString()).toBe('third');
  });

  it('parses multiple frames arriving in one chunk', () => {
    const chunk = Buffer.concat([encodeFlap(2, 1, Buffer.from('a')), encodeFlap(2, 2, Buffer.from('b'))]);
    expect(new FlapParser().push(chunk)).toHaveLength(2);
  });

  it('throws on marker desync', () => {
    expect(() => new FlapParser().push(Buffer.from([0x00, 1, 0, 1, 0, 0]))).toThrow(/desync/);
  });
});

describe('SNAC codec', () => {
  it('round-trips', () => {
    const snac = {
      foodgroup: 0x0004,
      subtype: 0x0006,
      flags: 0,
      requestId: 0xdeadbeef >>> 0,
      body: Buffer.from([1, 2, 3])
    };
    const decoded = decodeSnac(encodeSnac(snac));
    expect(decoded).toMatchObject({ foodgroup: 4, subtype: 6, requestId: 0xdeadbeef >>> 0 });
    expect(decoded.body.equals(snac.body)).toBe(true);
  });

  it('skips the optional TLV block when flag 0x8000 is set', () => {
    const body = Buffer.concat([
      new ByteWriter().u16(4).bytes(Buffer.from([9, 9, 9, 9])).build(), // optional block
      Buffer.from('real body')
    ]);
    const decoded = decodeSnac(
      encodeSnac({ foodgroup: 1, subtype: 7, flags: 0x8000, requestId: 1, body })
    );
    expect(decoded.body.toString()).toBe('real body');
  });
});

describe('TLV codec', () => {
  it('parses a TLV list into a bag', () => {
    const buf = Buffer.concat([
      writeTlv(0x0001, 'screenname'),
      writeTlvU16(0x0016, 0x0109),
      writeTlvU32(0x0014, 0x11223344),
      writeTlv(0x0001, 'dupe')
    ]);
    const bag = TlvBag.parse(buf);
    expect(bag.string(0x0001)).toBe('screenname');
    expect(bag.all(0x0001)).toHaveLength(2);
    expect(bag.u16(0x0016)).toBe(0x0109);
    expect(bag.u32(0x0014)).toBe(0x11223344);
    expect(bag.has(0x0099)).toBe(false);
  });
});

describe('ByteReader/ByteWriter', () => {
  it('round-trips pascal strings and integers', () => {
    const buf = new ByteWriter().u8(7).u16(513).u32(70000).pString8('aim user').pString16('x').build();
    const r = new ByteReader(buf);
    expect(r.u8()).toBe(7);
    expect(r.u16()).toBe(513);
    expect(r.u32()).toBe(70000);
    expect(r.pString8()).toBe('aim user');
    expect(r.pString16()).toBe('x');
    expect(r.remaining).toBe(0);
  });

  it('throws on underrun', () => {
    expect(() => new ByteReader(Buffer.from([1])).u16()).toThrow(/underrun/);
  });
});
