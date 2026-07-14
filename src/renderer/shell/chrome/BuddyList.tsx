import { useState } from 'react';
import type { Buddy } from '@msn-aim/im-core';
import { useImStore } from '../../stores/imStore';

function BuddyRow({ buddy }: { buddy: Buddy }) {
  const openChat = useImStore((s) => s.openChat);
  const title =
    buddy.status === 'away' && buddy.awayMessage
      ? buddy.awayMessage.replace(/<[^>]+>/g, '')
      : buddy.status;
  return (
    <button
      className={`buddy buddy--${buddy.status}`}
      title={title}
      onDoubleClick={() => openChat(buddy.id, buddy.displayName)}
    >
      <span className={`buddy__dot buddy__dot--${buddy.status}`} />
      <span className="buddy__name">{buddy.displayName}</span>
      {buddy.status === 'idle' && buddy.idleMinutes ? (
        <span className="buddy__meta">{buddy.idleMinutes}m</span>
      ) : null}
    </button>
  );
}

export function BuddyList() {
  const groups = useImStore((s) => s.groups);
  const presence = useImStore((s) => s.presence);
  const [collapsed, setCollapsed] = useState<Record<string, boolean>>({});

  if (groups.length === 0) {
    return <div className="empty-note">Your contact list is empty.<br />Add a buddy from the Chat page.</div>;
  }

  return (
    <div>
      {groups.map((group) => {
        const buddies = group.buddies.map((b) => presence[b.id] ?? b);
        const online = buddies.filter((b) => b.status !== 'offline').length;
        const isCollapsed = collapsed[group.name] ?? false;
        return (
          <div className="buddy-group" key={group.name}>
            <button
              className="buddy-group__header"
              onClick={() => setCollapsed((c) => ({ ...c, [group.name]: !isCollapsed }))}
            >
              <span>{isCollapsed ? '▸' : '▾'}</span>
              {group.name} ({online}/{buddies.length})
            </button>
            {!isCollapsed &&
              [...buddies]
                .sort((a, b) => {
                  const rank = (s: string) => (s === 'offline' ? 1 : 0);
                  return rank(a.status) - rank(b.status) || a.displayName.localeCompare(b.displayName);
                })
                .map((buddy) => <BuddyRow key={buddy.id} buddy={buddy} />)}
          </div>
        );
      })}
    </div>
  );
}
