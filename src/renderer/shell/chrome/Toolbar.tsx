import { useImStore } from '../../stores/imStore';
import { useUiStore, type PaneId } from '../../stores/uiStore';
import { BrowserIcon, ChatIcon, HomeIcon, MailIcon, MediaIcon } from './icons';

const BUTTONS: { id: PaneId; label: string; icon: () => JSX.Element }[] = [
  { id: 'home', label: 'Home', icon: HomeIcon },
  { id: 'browser', label: 'Web', icon: BrowserIcon },
  { id: 'mail', label: 'E-mail', icon: MailIcon },
  { id: 'chat', label: 'Chat', icon: ChatIcon },
  { id: 'media', label: 'Music', icon: MediaIcon }
];

export function Toolbar() {
  const { activePane, setPane } = useUiStore();
  const accounts = useImStore((s) => s.accounts);
  const activeAccountId = useImStore((s) => s.activeAccountId);
  const account = accounts.find((a) => a.id === activeAccountId);

  return (
    <nav className="toolbar">
      {BUTTONS.map(({ id, label, icon: Icon }) => (
        <button
          key={id}
          className={`toolbar__button ${activePane === id ? 'toolbar__button--active' : ''}`}
          onClick={() => setPane(id)}
        >
          <Icon />
          {label}
        </button>
      ))}
      <div className="toolbar__spacer" />
      {account && (
        <div className="toolbar__user">
          <div className="toolbar__user-avatar">{account.avatar}</div>
          {account.username}
        </div>
      )}
    </nav>
  );
}
