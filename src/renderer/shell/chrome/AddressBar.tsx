import { useEffect, useState } from 'react';
import type { BrowserNavState } from '@msn-aim/shared';
import { useUiStore } from '../../stores/uiStore';

export function AddressBar() {
  const setPane = useUiStore((s) => s.setPane);
  const [nav, setNav] = useState<BrowserNavState | null>(null);
  const [value, setValue] = useState('');
  const [editing, setEditing] = useState(false);

  useEffect(() => {
    return window.papillon.on('browser:navState', (state) => {
      setNav(state);
      if (!editing) setValue(state.url);
    });
  }, [editing]);

  const go = () => {
    if (!value.trim()) return;
    setPane('browser');
    void window.papillon.invoke('browser:navigate', { url: value.trim() });
    setEditing(false);
  };

  return (
    <div className="addressbar">
      <div className="addressbar__nav">
        <button
          className="addressbar__button"
          disabled={!nav?.canGoBack}
          onClick={() => void window.papillon.invoke('browser:back', {})}
        >
          ◀ Back
        </button>
        <button
          className="addressbar__button"
          disabled={!nav?.canGoForward}
          onClick={() => void window.papillon.invoke('browser:forward', {})}
        >
          ▶
        </button>
        <button
          className="addressbar__button"
          onClick={() =>
            void window.papillon.invoke(nav?.loading ? 'browser:stop' : 'browser:reload', {})
          }
        >
          {nav?.loading ? '✕' : '↻'}
        </button>
      </div>
      <span className="addressbar__label">Address</span>
      <input
        className="addressbar__input"
        value={value}
        placeholder="Type a web address and press Enter"
        onFocus={() => setEditing(true)}
        onBlur={() => setEditing(false)}
        onChange={(e) => setValue(e.target.value)}
        onKeyDown={(e) => e.key === 'Enter' && go()}
      />
      <button className="addressbar__go" onClick={go}>
        Go
      </button>
    </div>
  );
}
