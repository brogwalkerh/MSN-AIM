/**
 * Legacy FLAP channel-1 password "roasting" — XOR with a fixed table.
 * Only used by the oldest clients; kept for compatibility testing.
 */
const ROAST_TABLE = [
  0xf3, 0x26, 0x81, 0xc4, 0x39, 0x86, 0xdb, 0x92, 0x71, 0xa3, 0xb9, 0xe6, 0x53, 0x7a, 0x95, 0x7c
];

export function roastPassword(password: string): Buffer {
  const bytes = Buffer.from(password, 'latin1');
  const out = Buffer.allocUnsafe(bytes.length);
  for (let i = 0; i < bytes.length; i++) {
    out[i] = (bytes[i] ?? 0) ^ (ROAST_TABLE[i % ROAST_TABLE.length] ?? 0);
  }
  return out;
}
