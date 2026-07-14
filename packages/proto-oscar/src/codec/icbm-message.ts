import { ByteReader, ByteWriter } from '../wire/bytebuf';
import { decodeText, encodeText } from './charset';

/**
 * ICBM channel-1 message payload — the contents of TLV 0x02 in
 * SNAC 04,06 / 04,07. A sequence of fragments:
 *   [id u8][version u8][length u16][data]
 * Fragment 5 = capabilities/features array, fragment 1 = message text:
 *   [charset u16][charset subset u16][encoded text]
 */
const FRAGMENT_CAPABILITIES = 0x05;
const FRAGMENT_TEXT = 0x01;

/** Standard "features" bytes advertised by classic AIM clients. */
const DEFAULT_FEATURES = Buffer.from([0x01, 0x01, 0x01, 0x02]);

export function encodeMessageBlock(text: string): Buffer {
  const { charset, buffer } = encodeText(text);
  const w = new ByteWriter();
  // Fragment 5: features
  w.u8(FRAGMENT_CAPABILITIES).u8(0x01).u16(DEFAULT_FEATURES.length).bytes(DEFAULT_FEATURES);
  // Fragment 1: message text
  w.u8(FRAGMENT_TEXT).u8(0x01).u16(buffer.length + 4).u16(charset).u16(0x0000).bytes(buffer);
  return w.build();
}

/**
 * Decode TLV 0x02 contents to message text. Concatenates all text
 * fragments (multi-fragment messages are rare but legal).
 */
export function decodeMessageBlock(block: Buffer): string {
  const r = new ByteReader(block);
  const parts: string[] = [];
  while (r.remaining >= 4) {
    const id = r.u8();
    r.u8(); // fragment version
    const length = r.u16();
    const data = r.bytes(Math.min(length, r.remaining));
    if (id === FRAGMENT_TEXT && data.length >= 4) {
      const fr = new ByteReader(data);
      const charset = fr.u16();
      fr.u16(); // charset subset
      parts.push(decodeText(charset, fr.rest()));
    }
  }
  return parts.join('');
}
