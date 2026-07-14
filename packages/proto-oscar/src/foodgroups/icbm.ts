import { randomBytes } from 'node:crypto';
import { ByteReader, ByteWriter } from '../wire/bytebuf';
import { TlvBag, readTlvs, writeTlv } from '../wire/tlv';
import { decodeMessageBlock, encodeMessageBlock } from '../codec/icbm-message';
import { readUserInfo, type UserInfo } from '../codec/userinfo';

export const ICBM_CHANNEL_IM = 0x0001;

/**
 * ICBM parameter flags (04,02): channel messages allowed, missed-call
 * notifications, host acks and typing (MTN) events.
 */
const ICBM_FLAG_CHANNEL_MSGS = 0x00000001;
const ICBM_FLAG_MISSED_CALLS = 0x00000002;
const ICBM_FLAG_TYPING_EVENTS = 0x00000008;

export function encodeParamsSet(maxMessageSize = 8000): Buffer {
  return new ByteWriter()
    .u16(0x0000) // channel 0 = apply to all channels
    .u32(ICBM_FLAG_CHANNEL_MSGS | ICBM_FLAG_MISSED_CALLS | ICBM_FLAG_TYPING_EVENTS)
    .u16(maxMessageSize)
    .u16(999) // max sender warning level
    .u16(999) // max receiver warning level
    .u32(0) // minimum message interval ms
    .build();
}

export interface OutgoingMessageOptions {
  /** Ask the server to store the message if the buddy is offline. */
  storeOffline?: boolean;
  /** Mark as an auto-response (away-message reply). */
  autoResponse?: boolean;
}

/** Build 04,06 channel-1 send body. */
export function encodeSendMessage(
  to: string,
  text: string,
  opts: OutgoingMessageOptions = {}
): Buffer {
  const w = new ByteWriter()
    .bytes(randomBytes(8)) // ICBM cookie
    .u16(ICBM_CHANNEL_IM)
    .pString8(to)
    .bytes(writeTlv(0x0002, encodeMessageBlock(text)));
  if (opts.autoResponse) w.bytes(writeTlv(0x0004, Buffer.alloc(0)));
  else if (opts.storeOffline) w.bytes(writeTlv(0x0006, Buffer.alloc(0)));
  return w.build();
}

export interface IncomingMessage {
  cookie: Buffer;
  channel: number;
  userInfo: UserInfo;
  text: string;
  autoResponse: boolean;
}

/** Parse 04,07 channel-msg-to-client. Returns null for non-IM channels. */
export function parseIncomingMessage(body: Buffer): IncomingMessage | null {
  const r = new ByteReader(body);
  const cookie = Buffer.from(r.bytes(8));
  const channel = r.u16();
  const userInfo = readUserInfo(r);
  if (channel !== ICBM_CHANNEL_IM) return null; // rendezvous etc. out of scope
  const tlvs = new TlvBag(readTlvs(r));
  const block = tlvs.raw(0x0002);
  return {
    cookie,
    channel,
    userInfo,
    text: block ? decodeMessageBlock(block) : '',
    autoResponse: tlvs.has(0x0004)
  };
}

export type MtnEvent = 'stopped' | 'typed' | 'typing';

const MTN_CODES: Record<MtnEvent, number> = { stopped: 0x0000, typed: 0x0001, typing: 0x0002 };

/** Build 04,14 typing-notification body. */
export function encodeTyping(to: string, event: MtnEvent): Buffer {
  return new ByteWriter()
    .bytes(Buffer.alloc(8))
    .u16(ICBM_CHANNEL_IM)
    .pString8(to)
    .u16(MTN_CODES[event])
    .build();
}

/** Parse 04,14 typing notification. */
export function parseTyping(body: Buffer): { from: string; event: MtnEvent } {
  const r = new ByteReader(body);
  r.bytes(8); // cookie
  r.u16(); // channel
  const from = r.pString8();
  const code = r.u16();
  const event: MtnEvent = code === 0x0002 ? 'typing' : code === 0x0001 ? 'typed' : 'stopped';
  return { from, event };
}
