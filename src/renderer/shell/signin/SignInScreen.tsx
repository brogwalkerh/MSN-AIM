import { useEffect, useState } from 'react';
import { SERVER_PRESETS, type AccountSummary, type UpsertAccountArgs } from '@msn-aim/shared';
import { extractErrorMessage, useImStore } from '../../stores/imStore';
import { Butterfly } from '../chrome/Butterfly';

const AVATARS = ['🦋', '🌟', '🐱', '🚀', '🌈', '🎸', '⚽', '🌻'];

type Mode = { kind: 'tiles' } | { kind: 'password'; account: AccountSummary } | { kind: 'add' };

export function SignInScreen() {
  const { accounts, loadAccounts, upsertAccount, deleteAccount, signIn, lastError, clearError, session } =
    useImStore();
  const [mode, setMode] = useState<Mode>({ kind: 'tiles' });
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    void loadAccounts();
  }, [loadAccounts]);

  const attemptSignIn = async (accountId: string, password?: string) => {
    setBusy(true);
    try {
      await signIn(accountId, password);
    } catch {
      // error is surfaced via lastError
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="signin">
      <div className="signin__logo">
        <Butterfly />
        <span>
          Welcome to <em>papillon</em>
        </span>
      </div>

      {mode.kind === 'tiles' && (
        <>
          <div className="signin__hint">Click your name to sign in and start exploring.</div>
          <div className="signin__tiles">
            {accounts.map((account) => (
              <button
                key={account.id}
                className="signin__tile"
                disabled={busy}
                onClick={() => {
                  clearError();
                  if (account.rememberPassword) void attemptSignIn(account.id);
                  else setMode({ kind: 'password', account });
                }}
              >
                <div className="signin__tile-avatar">{account.avatar}</div>
                {account.username}
                <span className="signin__tile-sub">
                  {account.protocol === 'oscar' ? 'AIM' : 'MSN Messenger'} · {account.server.host}
                </span>
              </button>
            ))}
            <button className="signin__tile" onClick={() => setMode({ kind: 'add' })}>
              <div className="signin__tile-avatar">＋</div>
              Add new user
            </button>
          </div>
          {lastError && <div className="signin__error">{lastError}</div>}
          {busy && session !== 'online' && <div className="signin__hint">Signing in…</div>}
        </>
      )}

      {mode.kind === 'password' && (
        <PasswordCard
          account={mode.account}
          busy={busy}
          error={lastError}
          onCancel={() => {
            clearError();
            setMode({ kind: 'tiles' });
          }}
          onSubmit={(password, remember) => {
            void (async () => {
              if (remember) {
                await upsertAccount({
                  id: mode.account.id,
                  protocol: mode.account.protocol,
                  username: mode.account.username,
                  password,
                  rememberPassword: true,
                  server: mode.account.server,
                  avatar: mode.account.avatar
                });
              }
              await attemptSignIn(mode.account.id, password);
            })();
          }}
          onForget={() => {
            void deleteAccount(mode.account.id).then(() => setMode({ kind: 'tiles' }));
          }}
        />
      )}

      {mode.kind === 'add' && (
        <AddAccountCard
          busy={busy}
          error={lastError}
          onCancel={() => {
            clearError();
            setMode({ kind: 'tiles' });
          }}
          onSubmit={(args, password) => {
            void (async () => {
              setBusy(true);
              try {
                const account = await upsertAccount(args);
                await signIn(account.id, password);
              } catch (err) {
                useImStore.setState({ lastError: extractErrorMessage(err) });
              } finally {
                setBusy(false);
              }
            })();
          }}
        />
      )}
    </div>
  );
}

function PasswordCard(props: {
  account: AccountSummary;
  busy: boolean;
  error: string | null;
  onSubmit: (password: string, remember: boolean) => void;
  onCancel: () => void;
  onForget: () => void;
}) {
  const [password, setPassword] = useState('');
  const [remember, setRemember] = useState(false);
  return (
    <div className="signin__card">
      <h2>Sign in as {props.account.username}</h2>
      <label>
        Password
        <input
          type="password"
          autoFocus
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          onKeyDown={(e) => e.key === 'Enter' && props.onSubmit(password, remember)}
        />
      </label>
      <label className="signin__check">
        <input type="checkbox" checked={remember} onChange={(e) => setRemember(e.target.checked)} />
        Remember my password
      </label>
      {props.error && <div className="signin__error">{props.error}</div>}
      <div className="signin__actions">
        <button className="btn--link btn" onClick={props.onForget}>
          Remove account
        </button>
        <button className="btn" onClick={props.onCancel}>
          Cancel
        </button>
        <button
          className="btn btn--primary"
          disabled={props.busy || !password}
          onClick={() => props.onSubmit(password, remember)}
        >
          Sign In
        </button>
      </div>
    </div>
  );
}

function AddAccountCard(props: {
  busy: boolean;
  error: string | null;
  onSubmit: (args: UpsertAccountArgs, password: string) => void;
  onCancel: () => void;
}) {
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [remember, setRemember] = useState(true);
  const [presetId, setPresetId] = useState('local-oscar');
  const [host, setHost] = useState('127.0.0.1');
  const [port, setPort] = useState(5190);
  const [avatar, setAvatar] = useState(AVATARS[0]!);

  const preset = SERVER_PRESETS.find((p) => p.id === presetId);
  const isCustom = presetId === 'custom';
  const protocol = preset?.protocol ?? 'oscar';
  const effectiveHost = isCustom ? host : preset?.host ?? host;
  const effectivePort = isCustom ? port : preset?.port ?? port;
  const msnp = protocol === 'msnp';

  return (
    <div className="signin__card">
      <h2>Add a new user</h2>
      <label>
        Screen name
        <input type="text" autoFocus value={username} onChange={(e) => setUsername(e.target.value)} />
      </label>
      <label>
        Password
        <input type="password" value={password} onChange={(e) => setPassword(e.target.value)} />
      </label>
      <label>
        Service
        <select value={presetId} onChange={(e) => setPresetId(e.target.value)}>
          {SERVER_PRESETS.map((p) => (
            <option key={p.id} value={p.id}>
              {p.label}
            </option>
          ))}
          <option value="custom">Custom OSCAR server…</option>
        </select>
      </label>
      {isCustom && (
        <div className="signin__row">
          <label>
            Host
            <input type="text" value={host} onChange={(e) => setHost(e.target.value)} />
          </label>
          <label>
            Port
            <input
              type="number"
              value={port}
              onChange={(e) => setPort(parseInt(e.target.value, 10) || 5190)}
            />
          </label>
        </div>
      )}
      <label>
        Picture
        <select value={avatar} onChange={(e) => setAvatar(e.target.value)}>
          {AVATARS.map((a) => (
            <option key={a} value={a}>
              {a}
            </option>
          ))}
        </select>
      </label>
      <label className="signin__check">
        <input type="checkbox" checked={remember} onChange={(e) => setRemember(e.target.checked)} />
        Remember my password
      </label>
      {msnp && (
        <div className="signin__error">
          MSN Messenger (Escargot) support is planned — AIM works today. See docs/MSNP-PLANNING.md.
        </div>
      )}
      {props.error && <div className="signin__error">{props.error}</div>}
      <div className="signin__actions">
        <button className="btn" onClick={props.onCancel}>
          Cancel
        </button>
        <button
          className="btn btn--primary"
          disabled={props.busy || !username || !password || msnp}
          onClick={() =>
            props.onSubmit(
              {
                protocol,
                username,
                password: remember ? password : undefined,
                rememberPassword: remember,
                server: { host: effectiveHost, port: effectivePort },
                avatar
              },
              password
            )
          }
        >
          Create &amp; Sign In
        </button>
      </div>
    </div>
  );
}
