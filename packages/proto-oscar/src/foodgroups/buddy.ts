import { ByteReader } from '../wire/bytebuf';
import { readUserInfo, type UserInfo } from '../codec/userinfo';

/** Parse 03,0B buddy-arrived / 03,0C buddy-departed (same userinfo shape). */
export function parseBuddyEvent(body: Buffer): UserInfo {
  return readUserInfo(new ByteReader(body));
}
