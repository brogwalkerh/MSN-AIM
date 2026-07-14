import { Butterfly } from './Butterfly';

export function TitleBar({ title }: { title: string }) {
  const win = (action: 'window:minimize' | 'window:maximize' | 'window:close') =>
    void window.papillon.invoke(action, {});
  return (
    <header className="titlebar">
      <Butterfly className="titlebar__butterfly" />
      <div className="titlebar__title">{title}</div>
      <div className="titlebar__controls">
        <button className="titlebar__button" onClick={() => win('window:minimize')} aria-label="Minimize">
          –
        </button>
        <button className="titlebar__button" onClick={() => win('window:maximize')} aria-label="Maximize">
          ▢
        </button>
        <button
          className="titlebar__button titlebar__button--close"
          onClick={() => win('window:close')}
          aria-label="Close"
        >
          ✕
        </button>
      </div>
    </header>
  );
}
