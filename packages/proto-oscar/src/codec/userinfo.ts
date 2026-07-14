import { ByteReader } from '../wire/bytebuf';
import { TlvBag, readTlvs } from '../wire/tlv';
import { UserClass } from '../consts';

/**
 * The "userinfo block" appears in buddy arrival/departure, incoming ICBMs
 * and locate replies:
 *   screenname pString8, warning u16, tlvCount u16, tlvCount TLVs
 */
export interface UserInfo {
  screenName: string;
  warningLevel: number;
  userClass: number;
  away: boolean;
  idleMinutes?: number;
  onlineSinceEpochMs?: number;
  tlvs: TlvBag;
}

export function readUserInfo(r: ByteReader): UserInfo {
  const screenName = r.pString8();
  const warningLevel = r.u16();
  const tlvCount = r.u16();
  const tlvs = new TlvBag(readTlvs(r, tlvCount));
  const userClass = tlvs.u16(0x0001) ?? 0;
  const signonTime = tlvs.u32(0x0003);
  return {
    screenName,
    warningLevel,
    userClass,
    away: (userClass & UserClass.AWAY) !== 0,
    idleMinutes: tlvs.u16(0x0004),
    onlineSinceEpochMs: signonTime !== undefined ? signonTime * 1000 : undefined,
    tlvs
  };
}
