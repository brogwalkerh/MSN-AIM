import { useImStore } from '../../stores/imStore';
import { useUiStore } from '../../stores/uiStore';
import { BuddyList } from './BuddyList';

export function Sidebar() {
  const session = useImStore((s) => s.session);
  const setPane = useUiStore((s) => s.setPane);

  return (
    <aside className="sidebar">
      <div className="sidebar__section">
        <div className="sidebar__section-title">My Buddies</div>
        <div className="sidebar__section-body">
          {session === 'online' ? (
            <BuddyList />
          ) : (
            <div className="empty-note">Not signed in to chat.</div>
          )}
        </div>
      </div>
      <div className="sidebar__section">
        <div className="sidebar__section-title">My Stuff</div>
        <div className="sidebar__section-body">
          <button className="buddy" onClick={() => setPane('mail')}>
            📧 <span className="buddy__name">E-mail</span>
          </button>
          <button className="buddy" onClick={() => setPane('media')}>
            🎵 <span className="buddy__name">My Music</span>
          </button>
          <button className="buddy" onClick={() => setPane('home')}>
            📰 <span className="buddy__name">News &amp; Weather</span>
          </button>
        </div>
      </div>
    </aside>
  );
}
