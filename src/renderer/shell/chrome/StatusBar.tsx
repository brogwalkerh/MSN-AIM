import { useImStore } from '../../stores/imStore';
import { useUiStore } from '../../stores/uiStore';
import { Butterfly } from './Butterfly';

const SESSION_LABELS: Record<string, string> = {
  disconnected: 'Not signed in',
  connecting: 'Connecting…',
  authenticating: 'Signing in…',
  syncing: 'Loading your buddy list…',
  online: 'Online'
};

export function StatusBar() {
  const statusText = useUiStore((s) => s.statusText);
  const session = useImStore((s) => s.session);
  const ownStatus = useImStore((s) => s.ownStatus);

  const connection =
    session === 'online' && ownStatus !== 'online'
      ? `Online (${ownStatus})`
      : SESSION_LABELS[session] ?? session;

  return (
    <footer className="statusbar">
      <Butterfly className="statusbar__butterfly" />
      <span>{statusText}</span>
      <span className="statusbar__conn">
        <span
          className={`buddy__dot buddy__dot--${session === 'online' ? (ownStatus === 'away' ? 'away' : 'online') : 'offline'}`}
        />
        {connection}
      </span>
    </footer>
  );
}
