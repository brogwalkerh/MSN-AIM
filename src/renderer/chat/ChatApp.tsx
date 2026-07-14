import { useEffect, useRef, useState } from 'react';
import type { ChatWindowContext } from '@msn-aim/shared';

interface ChatLine {
  from: 'me' | 'them' | 'system';
  senderName: string;
  html: string;
  at: number;
  auto?: boolean;
}

function escapeHtml(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

export function ChatApp() {
  const [context, setContext] = useState<ChatWindowContext | null>(null);
  const [lines, setLines] = useState<ChatLine[]>([]);
  const [text, setText] = useState('');
  const [typing, setTyping] = useState(false);
  const [buddyStatus, setBuddyStatus] = useState<string | null>(null);
  const [format, setFormat] = useState({ bold: false, italic: false, underline: false });
  const [error, setError] = useState<string | null>(null);
  const logRef = useRef<HTMLDivElement>(null);
  const typingSentRef = useRef<'typing' | 'stopped'>('stopped');
  const typingTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    void window.papillon.invoke('im:getChatContext', {}).then((ctx) => {
      setContext(ctx);
      if (ctx) document.title = `${ctx.buddyName} — Instant Message`;
    });
  }, []);

  useEffect(() => {
    if (!context) return;
    const offMessage = window.papillon.on('im:message', ({ accountId, message }) => {
      if (accountId !== context.accountId || message.from !== context.buddyId) return;
      setLines((l) => [
        ...l,
        {
          from: 'them',
          senderName: context.buddyName,
          html: message.body, // sanitized by the protocol layer
          at: message.timestampEpochMs,
          auto: message.autoResponse
        }
      ]);
      setTyping(false);
    });
    const offTyping = window.papillon.on('im:typing', ({ accountId, from, state }) => {
      if (accountId !== context.accountId || from !== context.buddyId) return;
      setTyping(state === 'typing');
    });
    const offPresence = window.papillon.on('im:buddyPresence', ({ accountId, buddy }) => {
      if (accountId !== context.accountId || buddy.id !== context.buddyId) return;
      setBuddyStatus(buddy.status);
      setLines((l) => [
        ...l,
        {
          from: 'system',
          senderName: '',
          html: `<i>${escapeHtml(buddy.displayName)} is now ${buddy.status}.</i>`,
          at: Date.now()
        }
      ]);
    });
    return () => {
      offMessage();
      offTyping();
      offPresence();
    };
  }, [context]);

  useEffect(() => {
    logRef.current?.scrollTo({ top: logRef.current.scrollHeight });
  }, [lines, typing]);

  const sendTypingState = (state: 'typing' | 'stopped') => {
    if (!context || typingSentRef.current === state) return;
    typingSentRef.current = state;
    void window.papillon
      .invoke('im:sendTyping', { accountId: context.accountId, to: context.buddyId, state })
      .catch(() => undefined);
  };

  const onInput = (value: string) => {
    setText(value);
    if (value.length > 0) {
      sendTypingState('typing');
      if (typingTimerRef.current) clearTimeout(typingTimerRef.current);
      typingTimerRef.current = setTimeout(() => sendTypingState('stopped'), 4000);
    } else {
      sendTypingState('stopped');
    }
  };

  const send = () => {
    if (!context || !text.trim()) return;
    let html = escapeHtml(text.trim());
    if (format.bold) html = `<b>${html}</b>`;
    if (format.italic) html = `<i>${html}</i>`;
    if (format.underline) html = `<u>${html}</u>`;
    setError(null);
    window.papillon
      .invoke('im:sendMessage', { accountId: context.accountId, to: context.buddyId, body: html })
      .then(() => {
        setLines((l) => [
          ...l,
          { from: 'me', senderName: context.ownScreenName, html, at: Date.now() }
        ]);
        setText('');
        sendTypingState('stopped');
      })
      .catch((err) => setError((err as Error).message));
  };

  if (!context) return null;

  return (
    <div className="chat">
      <header className="chat__titlebar">
        🗨 {context.buddyName}
        <div className="chat__titlebar-controls">
          <button onClick={() => void window.papillon.invoke('window:minimize', {})}>–</button>
          <button onClick={() => void window.papillon.invoke('window:close', {})}>✕</button>
        </div>
      </header>
      {buddyStatus && buddyStatus !== 'online' && (
        <div className="chat__status">{context.buddyName} is {buddyStatus}</div>
      )}
      <div className="chat__log" ref={logRef}>
        {lines.map((line, i) => (
          <div key={i} className="chat__line">
            <span className="chat__time">
              {new Date(line.at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
            </span>
            {line.from === 'system' ? (
              <span className="chat__auto" dangerouslySetInnerHTML={{ __html: line.html }} />
            ) : (
              <>
                <span className={`chat__sender chat__sender--${line.from}`}>
                  {line.senderName}:
                </span>{' '}
                {line.auto && <span className="chat__auto">(auto-response) </span>}
                <span dangerouslySetInnerHTML={{ __html: line.html }} />
              </>
            )}
          </div>
        ))}
      </div>
      <div className="chat__typing">{typing ? `${context.buddyName} is typing…` : ''}</div>
      {error && <div className="chat__status" style={{ color: '#c0392b' }}>{error}</div>}
      <div className="chat__format">
        <button
          className={format.bold ? 'active' : ''}
          onClick={() => setFormat((f) => ({ ...f, bold: !f.bold }))}
        >
          <b>B</b>
        </button>
        <button
          className={format.italic ? 'active' : ''}
          onClick={() => setFormat((f) => ({ ...f, italic: !f.italic }))}
        >
          <i>I</i>
        </button>
        <button
          className={format.underline ? 'active' : ''}
          onClick={() => setFormat((f) => ({ ...f, underline: !f.underline }))}
        >
          <u>U</u>
        </button>
      </div>
      <div className="chat__input-row">
        <textarea
          className="chat__input"
          autoFocus
          value={text}
          onChange={(e) => onInput(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter' && !e.shiftKey) {
              e.preventDefault();
              send();
            }
          }}
          placeholder="Type a message and press Enter"
        />
        <button className="chat__send" disabled={!text.trim()} onClick={send}>
          Send
        </button>
      </div>
    </div>
  );
}
