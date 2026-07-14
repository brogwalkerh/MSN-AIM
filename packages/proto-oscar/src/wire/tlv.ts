import { ByteReader, ByteWriter } from './bytebuf';

/** TLV: type u16, length u16, value. The workhorse container of OSCAR. */
export interface Tlv {
  type: number;
  value: Buffer;
}

export function writeTlv(type: number, value: Buffer | string | number[]): Buffer {
  const v = typeof value === 'string' ? Buffer.from(value, 'latin1') : Buffer.from(value);
  return new ByteWriter().u16(type).u16(v.length).bytes(v).build();
}

export function writeTlvU16(type: number, value: number): Buffer {
  return writeTlv(type, new ByteWriter().u16(value).build());
}

export function writeTlvU32(type: number, value: number): Buffer {
  return writeTlv(type, new ByteWriter().u32(value).build());
}

/** Read `count` TLVs (or all remaining when count is undefined). */
export function readTlvs(r: ByteReader, count?: number): Tlv[] {
  const tlvs: Tlv[] = [];
  while (count !== undefined ? tlvs.length < count : r.remaining >= 4) {
    const type = r.u16();
    const length = r.u16();
    tlvs.push({ type, value: r.bytes(length) });
  }
  return tlvs;
}

/** Convenience lookup over a decoded TLV list. */
export class TlvBag {
  private readonly map = new Map<number, Buffer[]>();

  constructor(tlvs: Tlv[]) {
    for (const t of tlvs) {
      const arr = this.map.get(t.type);
      if (arr) arr.push(t.value);
      else this.map.set(t.type, [t.value]);
    }
  }

  static parse(buf: Buffer, count?: number): TlvBag {
    return new TlvBag(readTlvs(new ByteReader(buf), count));
  }

  has(type: number): boolean {
    return this.map.has(type);
  }

  raw(type: number): Buffer | undefined {
    return this.map.get(type)?.[0];
  }

  all(type: number): Buffer[] {
    return this.map.get(type) ?? [];
  }

  u8(type: number): number | undefined {
    const b = this.raw(type);
    return b && b.length >= 1 ? b.readUInt8(0) : undefined;
  }

  u16(type: number): number | undefined {
    const b = this.raw(type);
    return b && b.length >= 2 ? b.readUInt16BE(0) : undefined;
  }

  u32(type: number): number | undefined {
    const b = this.raw(type);
    return b && b.length >= 4 ? b.readUInt32BE(0) : undefined;
  }

  string(type: number): string | undefined {
    return this.raw(type)?.toString('latin1');
  }
}
