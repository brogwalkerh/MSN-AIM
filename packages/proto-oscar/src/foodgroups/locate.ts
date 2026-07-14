import { ByteReader, ByteWriter } from '../wire/bytebuf';
import { TlvBag, readTlvs, writeTlv } from '../wire/tlv';
import { readUserInfo, type UserInfo } from '../codec/userinfo';

const PROFILE_MIME = 'text/aolrtf; charset="us-ascii"';

export const LOCATE_TYPE_PROFILE = 0x0001;
export const LOCATE_TYPE_AWAY = 0x0003;

/**
 * Build 02,04 set-info body. Pass `undefined` to leave a field unchanged;
 * pass an empty string for awayMessage to clear away status (return from away).
 */
export function encodeSetInfo(opts: {
  profile?: string;
  awayMessage?: string;
  capabilities?: Buffer;
}): Buffer {
  const w = new ByteWriter();
  if (opts.profile !== undefined) {
    w.bytes(writeTlv(0x0001, PROFILE_MIME));
    w.bytes(writeTlv(0x0002, opts.profile));
  }
  if (opts.awayMessage !== undefined) {
    w.bytes(writeTlv(0x0003, PROFILE_MIME));
    w.bytes(writeTlv(0x0004, opts.awayMessage));
  }
  if (opts.capabilities !== undefined) {
    w.bytes(writeTlv(0x0005, opts.capabilities));
  }
  return w.build();
}

/** Build 02,05 user-info query body: type u16 + screenname pString8. */
export function encodeUserInfoQuery(type: number, screenName: string): Buffer {
  return new ByteWriter().u16(type).pString8(screenName).build();
}

export interface LocateUserInfoReply {
  userInfo: UserInfo;
  profile?: string;
  awayMessage?: string;
}

/** Parse 02,06 user-info reply: userinfo block + info TLVs. */
export function parseUserInfoReply(body: Buffer): LocateUserInfoReply {
  const r = new ByteReader(body);
  const userInfo = readUserInfo(r);
  const tlvs = new TlvBag(readTlvs(r));
  return {
    userInfo,
    profile: tlvs.string(0x0002),
    awayMessage: tlvs.string(0x0004)
  };
}
