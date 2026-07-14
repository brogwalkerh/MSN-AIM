import { createHash } from 'node:crypto';
import { AIM_MD5_STRING } from '../consts';

function md5(...parts: (Buffer | string)[]): Buffer {
  const h = createHash('md5');
  for (const p of parts) h.update(typeof p === 'string' ? Buffer.from(p, 'latin1') : p);
  return h.digest();
}

/**
 * Classic BUCP password hash (TLV 0x25 in SNAC 17,02):
 *   md5(authKey + password + "AOL Instant Messenger (SM)")
 */
export function bucpPasswordHash(authKey: Buffer, password: string): Buffer {
  return md5(authKey, password, AIM_MD5_STRING);
}

/**
 * "MD5 of password" variant, signalled by an empty TLV 0x4C:
 *   md5(authKey + md5(password) + "AOL Instant Messenger (SM)")
 */
export function bucpPasswordHashMd5(authKey: Buffer, password: string): Buffer {
  return md5(authKey, md5(password), AIM_MD5_STRING);
}
