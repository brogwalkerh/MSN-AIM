/**
 * OSCAR ICBM charset handling. The classic trap: message text is NOT UTF-8.
 *  - 0x0000 US-ASCII
 *  - 0x0002 UCS-2BE (UTF-16BE; surrogate pairs appear in the wild)
 *  - 0x0003 ISO-8859-1
 */
export const Charset = {
  ASCII: 0x0000,
  UCS2BE: 0x0002,
  LATIN1: 0x0003
} as const;

export function isSevenBitClean(text: string): boolean {
  for (let i = 0; i < text.length; i++) {
    if (text.charCodeAt(i) > 0x7f) return false;
  }
  return true;
}

function isLatin1Clean(text: string): boolean {
  for (let i = 0; i < text.length; i++) {
    if (text.charCodeAt(i) > 0xff) return false;
  }
  return true;
}

export interface EncodedText {
  charset: number;
  buffer: Buffer;
}

/** Pick the tightest charset the text fits in and encode. */
export function encodeText(text: string): EncodedText {
  if (isSevenBitClean(text)) {
    return { charset: Charset.ASCII, buffer: Buffer.from(text, 'latin1') };
  }
  if (isLatin1Clean(text)) {
    return { charset: Charset.LATIN1, buffer: Buffer.from(text, 'latin1') };
  }
  // UTF-16BE: encode LE then swap byte pairs.
  const le = Buffer.from(text, 'utf16le');
  const be = Buffer.from(le);
  be.swap16();
  return { charset: Charset.UCS2BE, buffer: be };
}

export function decodeText(charset: number, buffer: Buffer): string {
  switch (charset) {
    case Charset.UCS2BE: {
      const le = Buffer.from(buffer);
      if (le.length % 2 !== 0) {
        // Tolerate a truncated trailing byte rather than throwing mid-chat.
        return le.subarray(0, le.length - 1).swap16().toString('utf16le');
      }
      return le.swap16().toString('utf16le');
    }
    case Charset.ASCII:
    case Charset.LATIN1:
    default:
      return buffer.toString('latin1');
  }
}
