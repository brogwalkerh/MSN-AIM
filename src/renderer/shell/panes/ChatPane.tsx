import { useState } from 'react';
import { useImStore } from '../../stores/imStore';
import { BuddyList } from '../chrome/BuddyList';

export function ChatPane() {
  const session = useImStore((s) => s.session);
  const ownStatus = useImStore((s) => s.ownStatus);
  const setStatus = useImStore((s) => s.setStatus);
  const addBuddy = useImStore((s) => s.addBuddy);
  const [awayText, setAwayText] = useState('I am away from my computer right now.');
  const [newBuddy, setNewBuddy] = useState('');
  const [newGroup, setNewGroup] = useState('Buddies');
  const [note, setNote] = useState<string | null>(null);

  if (session !== 'online') {
    return <div className="empty-note">Sign in to see your buddies and start chatting.</div>;
  }

  return (
    <div className="chat-pane">
      <div className="chat-pane__list channel-cell">
        <div className="channel-cell__title">Buddy List — double-click a name to chat</div>
        <div className="channel-cell__body">
          <BuddyList />
        </div>
      </div>
      <div className="chat-pane__side">
        <div className="channel-cell">
          <div className="channel-cell__title">My Status</div>
          <div className="status-picker">
            <label className="signin__check">
              <input
                type="radio"
                name="status"
                checked={ownStatus === 'online'}
                onChange={() => void setStatus('online')}
              />
              🟢 Available
            </label>
            <label className="signin__check">
              <input
                type="radio"
                name="status"
                checked={ownStatus === 'away'}
                onChange={() => void setStatus('away', awayText)}
              />
              🌙 Away
            </label>
            <textarea
              value={awayText}
              onChange={(e) => setAwayText(e.target.value)}
              onBlur={() => ownStatus === 'away' && void setStatus('away', awayText)}
              placeholder="Away message"
            />
          </div>
        </div>
        <div className="channel-cell">
          <div className="channel-cell__title">Add a Buddy</div>
          <div className="add-buddy">
            <input
              placeholder="Screen name"
              value={newBuddy}
              onChange={(e) => setNewBuddy(e.target.value)}
            />
            <input
              placeholder="Group"
              value={newGroup}
              onChange={(e) => setNewGroup(e.target.value)}
            />
            <button
              className="btn btn--primary"
              disabled={!newBuddy.trim()}
              onClick={() => {
                setNote(null);
                addBuddy(newBuddy.trim(), newGroup.trim() || 'Buddies')
                  .then(() => {
                    setNote(`${newBuddy.trim()} added.`);
                    setNewBuddy('');
                  })
                  .catch((err) => setNote((err as Error).message));
              }}
            >
              Add Buddy
            </button>
            {note && <div className="signin__hint" style={{ color: 'var(--msn-grey)' }}>{note}</div>}
          </div>
        </div>
      </div>
    </div>
  );
}
