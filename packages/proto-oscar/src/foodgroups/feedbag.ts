import { ByteReader, ByteWriter } from '../wire/bytebuf';
import { TlvBag, readTlvs, writeTlv } from '../wire/tlv';
import { FeedbagClass } from '../consts';

/**
 * Feedbag (SSI, foodgroup 0x0013) — the server-side buddy list.
 * Item wire format:
 *   name pString16, groupId u16, itemId u16, classId u16,
 *   tlvBlockLen u16, TLVs
 */
export interface FeedbagItem {
  name: string;
  groupId: number;
  itemId: number;
  classId: number;
  tlvs: TlvBag;
  rawTlvBlock: Buffer;
}

const TLV_GROUP_CHILDREN = 0x00c8;
const TLV_BUDDY_ALIAS = 0x0131;

export function encodeItem(item: {
  name: string;
  groupId: number;
  itemId: number;
  classId: number;
  tlvBlock?: Buffer;
}): Buffer {
  const tlvBlock = item.tlvBlock ?? Buffer.alloc(0);
  return new ByteWriter()
    .pString16(item.name)
    .u16(item.groupId)
    .u16(item.itemId)
    .u16(item.classId)
    .u16(tlvBlock.length)
    .bytes(tlvBlock)
    .build();
}

export function readItem(r: ByteReader): FeedbagItem {
  const name = r.pString16();
  const groupId = r.u16();
  const itemId = r.u16();
  const classId = r.u16();
  const rawTlvBlock = Buffer.from(r.bytes(r.u16()));
  return {
    name,
    groupId,
    itemId,
    classId,
    tlvs: TlvBag.parse(rawTlvBlock),
    rawTlvBlock
  };
}

export interface FeedbagReplyFrame {
  version: number;
  items: FeedbagItem[];
  lastUpdateEpochSec: number;
}

/** Parse one 13,06 reply frame (large lists span several frames). */
export function parseReplyFrame(body: Buffer): FeedbagReplyFrame {
  const r = new ByteReader(body);
  const version = r.u8();
  const count = r.u16();
  const items: FeedbagItem[] = [];
  for (let i = 0; i < count; i++) items.push(readItem(r));
  const lastUpdateEpochSec = r.remaining >= 4 ? r.u32() : 0;
  return { version, items, lastUpdateEpochSec };
}

/** Build 13,05 query-if-modified body (timestamp 0 + count 0 = send everything). */
export function encodeQuery(): Buffer {
  return new ByteWriter().u32(0).u16(0).build();
}

export interface BuddyEntry {
  name: string;
  alias?: string;
  groupId: number;
  itemId: number;
}

export interface GroupEntry {
  name: string;
  groupId: number;
  buddies: BuddyEntry[];
}

/** Assemble the group/buddy tree from raw items. */
export function buildTree(items: FeedbagItem[]): GroupEntry[] {
  const groups = new Map<number, GroupEntry>();
  const orphans: BuddyEntry[] = [];
  for (const item of items) {
    if (item.classId === FeedbagClass.GROUP && item.groupId !== 0) {
      groups.set(item.groupId, {
        name: item.name,
        groupId: item.groupId,
        buddies: groups.get(item.groupId)?.buddies ?? []
      });
    }
  }
  for (const item of items) {
    if (item.classId !== FeedbagClass.BUDDY) continue;
    const entry: BuddyEntry = {
      name: item.name,
      alias: item.tlvs.string(TLV_BUDDY_ALIAS),
      groupId: item.groupId,
      itemId: item.itemId
    };
    const group = groups.get(item.groupId);
    if (group) group.buddies.push(entry);
    else orphans.push(entry);
  }
  const result = [...groups.values()];
  if (orphans.length > 0) {
    result.push({ name: 'Buddies', groupId: 0, buddies: orphans });
  }
  return result;
}

/** Parse 13,0E status ack: one u16 result code per submitted item (0 = ok). */
export function parseStatus(body: Buffer): number[] {
  const r = new ByteReader(body);
  const codes: number[] = [];
  while (r.remaining >= 2) codes.push(r.u16());
  return codes;
}

export const FEEDBAG_STATUS_MESSAGES: Record<number, string> = {
  0x0000: 'success',
  0x0002: 'item not found',
  0x0003: 'item already exists',
  0x000a: 'invalid item',
  0x000c: 'limit exceeded',
  0x000d: 'attempt to add ICQ contact to AIM list',
  0x000e: 'requires authorization'
};

/** Allocate an item id not used by any existing item in the group. */
export function allocateItemId(items: FeedbagItem[], groupId: number): number {
  const used = new Set(
    items.filter((i) => i.groupId === groupId || i.classId !== FeedbagClass.BUDDY).map((i) => i.itemId)
  );
  let id = Math.floor(Math.random() * 0x7fff) + 1;
  while (used.has(id)) id = Math.floor(Math.random() * 0x7fff) + 1;
  return id;
}

/** Allocate a group id not used by any existing group. */
export function allocateGroupId(items: FeedbagItem[]): number {
  const used = new Set(items.filter((i) => i.classId === FeedbagClass.GROUP).map((i) => i.groupId));
  let id = Math.floor(Math.random() * 0x7fff) + 1;
  while (used.has(id)) id = Math.floor(Math.random() * 0x7fff) + 1;
  return id;
}

/** Build the TLV block for a group item listing its child buddy item ids. */
export function encodeGroupChildrenTlv(childItemIds: number[]): Buffer {
  const w = new ByteWriter();
  for (const id of childItemIds) w.u16(id);
  return writeTlv(TLV_GROUP_CHILDREN, w.build());
}
