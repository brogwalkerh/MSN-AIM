import { describe, expect, it } from 'vitest';
import { ByteReader, ByteWriter } from '../wire/bytebuf';
import { writeTlv } from '../wire/tlv';
import {
  allocateGroupId,
  allocateItemId,
  buildTree,
  encodeItem,
  parseReplyFrame,
  parseStatus,
  readItem
} from './feedbag';
import { FeedbagClass } from '../consts';

function makeReplyFrame(items: Buffer[], version = 0, timestamp = 12345): Buffer {
  const w = new ByteWriter().u8(version).u16(items.length);
  for (const i of items) w.bytes(i);
  w.u32(timestamp);
  return w.build();
}

describe('feedbag items', () => {
  it('round-trips an item with a TLV block', () => {
    const encoded = encodeItem({
      name: 'CoolBuddy99',
      groupId: 5,
      itemId: 77,
      classId: FeedbagClass.BUDDY,
      tlvBlock: writeTlv(0x0131, 'My Friend')
    });
    const item = readItem(new ByteReader(encoded));
    expect(item.name).toBe('CoolBuddy99');
    expect(item.groupId).toBe(5);
    expect(item.itemId).toBe(77);
    expect(item.classId).toBe(FeedbagClass.BUDDY);
    expect(item.tlvs.string(0x0131)).toBe('My Friend');
  });

  it('parses a reply frame with trailing timestamp', () => {
    const frame = parseReplyFrame(
      makeReplyFrame([
        encodeItem({ name: 'Friends', groupId: 1, itemId: 0, classId: FeedbagClass.GROUP }),
        encodeItem({ name: 'buddy one', groupId: 1, itemId: 10, classId: FeedbagClass.BUDDY })
      ])
    );
    expect(frame.items).toHaveLength(2);
    expect(frame.lastUpdateEpochSec).toBe(12345);
  });

  it('builds a group tree, attaching orphans to a default group', () => {
    const items = [
      readItem(
        new ByteReader(
          encodeItem({ name: 'Work', groupId: 2, itemId: 0, classId: FeedbagClass.GROUP })
        )
      ),
      readItem(
        new ByteReader(
          encodeItem({ name: 'colleague', groupId: 2, itemId: 3, classId: FeedbagClass.BUDDY })
        )
      ),
      readItem(
        new ByteReader(
          encodeItem({ name: 'stray', groupId: 99, itemId: 4, classId: FeedbagClass.BUDDY })
        )
      ),
      // Permit/deny items must not show up in the tree.
      readItem(
        new ByteReader(encodeItem({ name: 'blocked', groupId: 0, itemId: 5, classId: FeedbagClass.DENY }))
      )
    ];
    const tree = buildTree(items);
    expect(tree.map((g) => g.name).sort()).toEqual(['Buddies', 'Work']);
    expect(tree.find((g) => g.name === 'Work')!.buddies.map((b) => b.name)).toEqual(['colleague']);
    expect(tree.find((g) => g.name === 'Buddies')!.buddies.map((b) => b.name)).toEqual(['stray']);
  });

  it('parses status acks', () => {
    expect(parseStatus(Buffer.from([0x00, 0x00, 0x00, 0x0c]))).toEqual([0, 0x0c]);
  });

  it('allocates unused ids', () => {
    const items = [
      readItem(
        new ByteReader(encodeItem({ name: 'G', groupId: 7, itemId: 0, classId: FeedbagClass.GROUP }))
      )
    ];
    expect(allocateGroupId(items)).not.toBe(7);
    const id = allocateItemId(items, 7);
    expect(id).toBeGreaterThan(0);
    expect(id).toBeLessThanOrEqual(0x8000);
  });
});
