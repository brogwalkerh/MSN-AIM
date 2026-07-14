import { ByteReader, ByteWriter } from './bytebuf';

/**
 * SNAC — the message unit carried in FLAP channel 2 frames.
 * Header: foodgroup u16, subtype u16, flags u16, requestId u32, then body.
 */
export interface Snac {
  foodgroup: number;
  subtype: number;
  flags: number;
  requestId: number;
  body: Buffer;
}

/** Flag bit: another SNAC with the same requestId follows (multi-part reply). */
export const SNAC_FLAG_MORE_REPLIES = 0x0001;
/** Flag bit: an optional TLV block is prepended to the body (u16 len + data). */
export const SNAC_FLAG_OPTIONAL_TLV_BLOCK = 0x8000;

export function encodeSnac(snac: Snac): Buffer {
  return new ByteWriter()
    .u16(snac.foodgroup)
    .u16(snac.subtype)
    .u16(snac.flags)
    .u32(snac.requestId)
    .bytes(snac.body)
    .build();
}

/**
 * Decode a SNAC from a FLAP channel-2 payload. When flag 0x8000 is set the
 * server prepends a u16-length-prefixed block (e.g. version info on rate
 * responses) — it is skipped so `body` always starts at the real content.
 */
export function decodeSnac(payload: Buffer): Snac {
  const r = new ByteReader(payload);
  const foodgroup = r.u16();
  const subtype = r.u16();
  const flags = r.u16();
  const requestId = r.u32();
  if (flags & SNAC_FLAG_OPTIONAL_TLV_BLOCK) {
    r.skip(r.u16());
  }
  return { foodgroup, subtype, flags, requestId, body: r.rest() };
}
