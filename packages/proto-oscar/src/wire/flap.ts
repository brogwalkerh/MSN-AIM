/**
 * FLAP framing — the lowest OSCAR layer over TCP.
 * Frame: 0x2A, channel u8, sequence u16, dataLength u16, data.
 */

export const FLAP_MARKER = 0x2a;

export enum FlapChannel {
  SignOn = 1,
  Snac = 2,
  Error = 3,
  SignOff = 4,
  KeepAlive = 5
}

export interface FlapFrame {
  channel: number;
  sequence: number;
  payload: Buffer;
}

export function encodeFlap(channel: number, sequence: number, payload: Buffer): Buffer {
  if (payload.length > 0xffff) throw new RangeError('FLAP payload too large');
  const header = Buffer.allocUnsafe(6);
  header.writeUInt8(FLAP_MARKER, 0);
  header.writeUInt8(channel, 1);
  header.writeUInt16BE(sequence & 0xffff, 2);
  header.writeUInt16BE(payload.length, 4);
  return Buffer.concat([header, payload]);
}

/**
 * Incremental FLAP stream parser. Feed raw TCP chunks; complete frames are
 * returned as they materialize (handles partial headers/payloads and
 * multiple frames per chunk).
 */
export class FlapParser {
  private buffer: Buffer = Buffer.alloc(0);

  push(chunk: Buffer): FlapFrame[] {
    this.buffer = this.buffer.length === 0 ? chunk : Buffer.concat([this.buffer, chunk]);
    const frames: FlapFrame[] = [];
    for (;;) {
      if (this.buffer.length < 6) break;
      if (this.buffer.readUInt8(0) !== FLAP_MARKER) {
        throw new Error(
          `FLAP desync: expected marker 0x2a, got 0x${this.buffer.readUInt8(0).toString(16)}`
        );
      }
      const length = this.buffer.readUInt16BE(4);
      if (this.buffer.length < 6 + length) break;
      frames.push({
        channel: this.buffer.readUInt8(1),
        sequence: this.buffer.readUInt16BE(2),
        payload: Buffer.from(this.buffer.subarray(6, 6 + length))
      });
      this.buffer = Buffer.from(this.buffer.subarray(6 + length));
    }
    return frames;
  }
}
