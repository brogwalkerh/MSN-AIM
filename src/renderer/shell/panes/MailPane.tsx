import { useCallback, useEffect, useState } from 'react';
import type {
  ComposeMailArgs,
  MailAccountConfig,
  MailBody,
  MailEnvelope,
  MailboxSummary
} from '@msn-aim/shared';

type View =
  | { kind: 'loading' }
  | { kind: 'setup' }
  | { kind: 'browse' }
  | { kind: 'compose'; draft?: Partial<ComposeMailArgs> };

export function MailPane() {
  const [view, setView] = useState<View>({ kind: 'loading' });
  const [account, setAccount] = useState<MailAccountConfig | null>(null);
  const [mailboxes, setMailboxes] = useState<MailboxSummary[]>([]);
  const [mailbox, setMailbox] = useState('INBOX');
  const [messages, setMessages] = useState<MailEnvelope[]>([]);
  const [selected, setSelected] = useState<MailBody | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loadingList, setLoadingList] = useState(false);

  useEffect(() => {
    void window.papillon.invoke('mail:getAccount', {}).then((acct) => {
      setAccount(acct);
      setView(acct ? { kind: 'browse' } : { kind: 'setup' });
    });
  }, []);

  const refresh = useCallback(
    async (box = mailbox) => {
      setLoadingList(true);
      setError(null);
      try {
        const [boxes, envelopes] = await Promise.all([
          window.papillon.invoke('mail:listMailboxes', {}),
          window.papillon.invoke('mail:listMessages', { mailbox: box })
        ]);
        setMailboxes(boxes);
        setMessages(envelopes);
      } catch (err) {
        setError((err as Error).message);
      } finally {
        setLoadingList(false);
      }
    },
    [mailbox]
  );

  useEffect(() => {
    if (view.kind === 'browse' && account) void refresh();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [view.kind, account]);

  if (view.kind === 'loading') return <div className="empty-note">Opening your mailbox…</div>;

  if (view.kind === 'setup') {
    return (
      <MailSetup
        initial={account}
        onSaved={(acct) => {
          setAccount(acct);
          setView({ kind: 'browse' });
        }}
      />
    );
  }

  if (view.kind === 'compose') {
    return (
      <MailCompose
        draft={view.draft}
        onDone={() => setView({ kind: 'browse' })}
      />
    );
  }

  return (
    <div className="mail" style={{ flexDirection: 'column' }}>
      <div className="mail__toolbar">
        <button className="btn btn--primary" onClick={() => setView({ kind: 'compose' })}>
          ✏️ New Message
        </button>
        <button className="btn" onClick={() => void refresh()} disabled={loadingList}>
          ↻ Check Mail
        </button>
        {selected && (
          <button
            className="btn"
            onClick={() =>
              setView({
                kind: 'compose',
                draft: {
                  to: messages.find((m) => m.uid === selected.uid)?.fromAddress ?? '',
                  subject: `Re: ${messages.find((m) => m.uid === selected.uid)?.subject ?? ''}`,
                  inReplyTo: { mailbox, uid: selected.uid }
                }
              })
            }
          >
            ↩ Reply
          </button>
        )}
        <button className="btn" style={{ marginLeft: 'auto' }} onClick={() => setView({ kind: 'setup' })}>
          ⚙ Account
        </button>
      </div>
      {error && <div className="signin__error">{error}</div>}
      <div className="mail" style={{ flex: 1, minHeight: 0 }}>
        <div className="mail__folders">
          {mailboxes.map((box) => (
            <button
              key={box.path}
              className={`mail__folder ${box.path === mailbox ? 'mail__folder--active' : ''}`}
              onClick={() => {
                setMailbox(box.path);
                setSelected(null);
                void refresh(box.path);
              }}
            >
              {box.name}
            </button>
          ))}
        </div>
        <div className="mail__list">
          {loadingList ? (
            <div className="empty-note">Checking for new mail…</div>
          ) : messages.length === 0 ? (
            <div className="empty-note">No messages in this folder.</div>
          ) : (
            messages.map((msg) => (
              <button
                key={msg.uid}
                className={`mail__item ${!msg.seen ? 'mail__item--unseen' : ''} ${
                  selected?.uid === msg.uid ? 'mail__item--active' : ''
                }`}
                onClick={() => {
                  void window.papillon
                    .invoke('mail:getMessage', { mailbox, uid: msg.uid })
                    .then(setSelected)
                    .catch((err) => setError((err as Error).message));
                }}
              >
                <div className="mail__item-from">{msg.from}</div>
                <div className="mail__item-subject">{msg.subject}</div>
                <div className="mail__item-date">
                  {msg.dateEpochMs ? new Date(msg.dateEpochMs).toLocaleString() : ''}
                </div>
              </button>
            ))
          )}
        </div>
        <div className="mail__reader">
          {selected ? (
            <>
              <div className="mail__reader-head">
                <strong>{messages.find((m) => m.uid === selected.uid)?.subject}</strong>
                <div className="mail__item-date">
                  From {messages.find((m) => m.uid === selected.uid)?.from}
                  {selected.attachments.length > 0 &&
                    ` · ${selected.attachments.length} attachment(s)`}
                </div>
              </div>
              <MailBodyView body={selected} />
            </>
          ) : (
            <div className="empty-note">Select a message to read it.</div>
          )}
        </div>
      </div>
    </div>
  );
}

function MailBodyView({ body }: { body: MailBody }) {
  // Render in a sandboxed iframe: no scripts, no top-navigation, and a CSP
  // that blocks remote loads (privacy: no tracking pixels).
  const html = body.html
    ? `<!doctype html><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'">` +
      `<base target="_blank">${body.html}`
    : `<!doctype html><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'">` +
      `<pre style="font-family:Verdana,sans-serif;font-size:12px;white-space:pre-wrap">${escapeHtml(
        body.text ?? ''
      )}</pre>`;
  return <iframe className="mail__reader-body" sandbox="" srcDoc={html} title="Message" />;
}

function escapeHtml(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

function MailSetup(props: { initial: MailAccountConfig | null; onSaved: (a: MailAccountConfig) => void }) {
  const [email, setEmail] = useState(props.initial?.email ?? '');
  const [displayName, setDisplayName] = useState(props.initial?.displayName ?? '');
  const [user, setUser] = useState(props.initial?.user ?? '');
  const [password, setPassword] = useState('');
  const [imapHost, setImapHost] = useState(props.initial?.imap.host ?? 'imap.gmail.com');
  const [imapPort, setImapPort] = useState(props.initial?.imap.port ?? 993);
  const [smtpHost, setSmtpHost] = useState(props.initial?.smtp.host ?? 'smtp.gmail.com');
  const [smtpPort, setSmtpPort] = useState(props.initial?.smtp.port ?? 465);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const applyPreset = (preset: 'gmail' | 'outlook' | 'fastmail') => {
    const presets = {
      gmail: { imap: 'imap.gmail.com', smtp: 'smtp.gmail.com' },
      outlook: { imap: 'outlook.office365.com', smtp: 'smtp-mail.outlook.com' },
      fastmail: { imap: 'imap.fastmail.com', smtp: 'smtp.fastmail.com' }
    } as const;
    setImapHost(presets[preset].imap);
    setSmtpHost(presets[preset].smtp);
    setImapPort(993);
    setSmtpPort(465);
  };

  return (
    <div className="mail__setup">
      <h2 style={{ color: 'var(--msn-blue-darkest)', fontSize: 14 }}>Set up your e-mail</h2>
      <div className="signin__hint" style={{ color: 'var(--msn-grey)' }}>
        Works with any IMAP provider. Gmail/Outlook require an app password.
      </div>
      <div className="signin__row">
        <button className="btn" onClick={() => applyPreset('gmail')}>Gmail</button>
        <button className="btn" onClick={() => applyPreset('outlook')}>Outlook</button>
        <button className="btn" onClick={() => applyPreset('fastmail')}>Fastmail</button>
      </div>
      <label>
        E-mail address
        <input value={email} onChange={(e) => { setEmail(e.target.value); if (!user) setUser(e.target.value); }} />
      </label>
      <label>
        Display name
        <input value={displayName} onChange={(e) => setDisplayName(e.target.value)} />
      </label>
      <label>
        Username
        <input value={user} onChange={(e) => setUser(e.target.value)} />
      </label>
      <label>
        Password / app password
        <input type="password" value={password} onChange={(e) => setPassword(e.target.value)} />
      </label>
      <div className="signin__row">
        <label>
          IMAP host
          <input value={imapHost} onChange={(e) => setImapHost(e.target.value)} />
        </label>
        <label>
          Port
          <input
            type="number"
            value={imapPort}
            onChange={(e) => setImapPort(parseInt(e.target.value, 10) || 993)}
          />
        </label>
      </div>
      <div className="signin__row">
        <label>
          SMTP host
          <input value={smtpHost} onChange={(e) => setSmtpHost(e.target.value)} />
        </label>
        <label>
          Port
          <input
            type="number"
            value={smtpPort}
            onChange={(e) => setSmtpPort(parseInt(e.target.value, 10) || 465)}
          />
        </label>
      </div>
      {error && <div className="signin__error">{error}</div>}
      <div className="signin__actions">
        <button
          className="btn btn--primary"
          disabled={saving || !email || !user}
          onClick={() => {
            const config: MailAccountConfig = {
              email,
              displayName,
              user,
              password: password || undefined,
              imap: { host: imapHost, port: imapPort, secure: imapPort === 993 },
              smtp: { host: smtpHost, port: smtpPort, secure: smtpPort === 465 }
            };
            setSaving(true);
            setError(null);
            window.papillon
              .invoke('mail:setAccount', config)
              .then(() => props.onSaved(config))
              .catch((err) => setError((err as Error).message))
              .finally(() => setSaving(false));
          }}
        >
          Save
        </button>
      </div>
    </div>
  );
}

function MailCompose(props: { draft?: Partial<ComposeMailArgs>; onDone: () => void }) {
  const [to, setTo] = useState(props.draft?.to ?? '');
  const [subject, setSubject] = useState(props.draft?.subject ?? '');
  const [text, setText] = useState('');
  const [sending, setSending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  return (
    <div className="mail__compose">
      <h2 style={{ color: 'var(--msn-blue-darkest)', fontSize: 14 }}>New message</h2>
      <label>
        To
        <input autoFocus value={to} onChange={(e) => setTo(e.target.value)} />
      </label>
      <label>
        Subject
        <input value={subject} onChange={(e) => setSubject(e.target.value)} />
      </label>
      <label>
        Message
        <textarea value={text} onChange={(e) => setText(e.target.value)} />
      </label>
      {error && <div className="signin__error">{error}</div>}
      <div className="signin__actions">
        <button className="btn" onClick={props.onDone}>
          Cancel
        </button>
        <button
          className="btn btn--primary"
          disabled={sending || !to || !subject}
          onClick={() => {
            setSending(true);
            setError(null);
            window.papillon
              .invoke('mail:send', { to, subject, text, inReplyTo: props.draft?.inReplyTo })
              .then(props.onDone)
              .catch((err) => setError((err as Error).message))
              .finally(() => setSending(false));
          }}
        >
          📨 Send
        </button>
      </div>
    </div>
  );
}
