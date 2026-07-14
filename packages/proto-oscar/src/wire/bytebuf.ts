/** Cursor-based big-endian reader over a Buffer. OSCAR is big-endian throughout. */
export class ByteReader {
  private pos = 0;

  constructor(private readonly buf: Buffer) {}

  get remaining(): number {
    return this.buf.length - this.pos;
  }

  get offset(): number {
    return this.pos;
  }

  private need(n: number): void {
    if (this.remaining < n) {
      throw new RangeError(
        `buffer underrun: need ${n} bytes at offset ${this.pos}, have ${this.remaining}`
      );
    }
  }

  u8(): number {
    this.need(1);
    return this.buf.readUInt8(this.pos++);
  }

  u16(): number {
    this.need(2);
    const v = this.buf.readUInt16BE(this.pos);
    this.pos += 2;
    return v;
  }

  u32(): number {
    this.need(4);
    const v = this.buf.readUInt32BE(this.pos);
    this.pos += 4;
    return v;
  }

  bytes(n: number): Buffer {
    this.need(n);
    const v = this.buf.subarray(this.pos, this.pos + n);
    this.pos += n;
    return v;
  }

  rest(): Buffer {
    return this.bytes(this.remaining);
  }

  skip(n: number): void {
    this.need(n);
    this.pos += n;
  }

  /** u8 length-prefixed string (latin1) — OSCAR screen names. */
  pString8(): string {
    return this.bytes(this.u8()).toString('latin1');
  }

  /** u16 length-prefixed string (latin1). */
  pString16(): string {
    return this.bytes(this.u16()).toString('latin1');
  }
}

/** Growable big-endian writer. */
export class ByteWriter {
  private chunks: Buffer[] = [];

  u8(v: number): this {
    this.chunks.push(Buffer.from([v & 0xff]));
    return this;
  }

  u16(v: number): this {
    const b = Buffer.allocUnsafe(2);
    b.writeUInt16BE(v & 0xffff, 0);
    this.chunks.push(b);
    return this;
  }

  u32(v: number): this {
    const b = Buffer.allocUnsafe(4);
    b.writeUInt32BE(v >>> 0, 0);
    this.chunks.push(b);
    return this;
  }

  bytes(b: Buffer | Uint8Array): this {
    this.chunks.push(Buffer.from(b));
    return this;
  }

  /** u8 length-prefixed string (latin1). */
  pString8(s: string): this {
    const b = Buffer.from(s, 'latin1');
    if (b.length > 0xff) throw new RangeError('pString8 too long');
    return this.u8(b.length).bytes(b);
  }

  /** u16 length-prefixed string (latin1). */
  pString16(s: string): this {
    const b = Buffer.from(s, 'latin1');
    if (b.length > 0xffff) throw new RangeError('pString16 too long');
    return this.u16(b.length).bytes(b);
  }

  build(): Buffer {
    return Buffer.concat(this.chunks);
  }
}
