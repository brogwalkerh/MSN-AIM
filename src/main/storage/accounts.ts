import { randomUUID } from 'node:crypto';
import { safeStorage } from 'electron';
import type { AccountSummary, UpsertAccountArgs } from '@msn-aim/shared';
import { JsonStore } from './JsonStore';

interface StoredAccount extends AccountSummary {
  /** base64 of safeStorage-encrypted password (only when rememberPassword). */
  encryptedPassword?: string;
}

let store: JsonStore<{ accounts: StoredAccount[] }> | null = null;

function accountsStore(): JsonStore<{ accounts: StoredAccount[] }> {
  store ??= new JsonStore('accounts', { accounts: [] });
  return store;
}

function toSummary(account: StoredAccount): AccountSummary {
  const { encryptedPassword: _omitted, ...summary } = account;
  return summary;
}

export function listAccounts(): AccountSummary[] {
  return accountsStore().get('accounts').map(toSummary);
}

export function upsertAccount(args: UpsertAccountArgs): AccountSummary {
  const accounts = [...accountsStore().get('accounts')];
  const id = args.id ?? randomUUID();
  const existing = accounts.find((a) => a.id === id);
  const next: StoredAccount = {
    id,
    protocol: args.protocol,
    username: args.username,
    server: args.server,
    avatar: args.avatar,
    rememberPassword: args.rememberPassword,
    encryptedPassword: existing?.encryptedPassword
  };
  if (!args.rememberPassword) {
    delete next.encryptedPassword;
  } else if (args.password) {
    next.encryptedPassword = safeStorage.isEncryptionAvailable()
      ? safeStorage.encryptString(args.password).toString('base64')
      : Buffer.from(args.password, 'utf8').toString('base64');
  }
  const idx = accounts.findIndex((a) => a.id === id);
  if (idx >= 0) accounts[idx] = next;
  else accounts.push(next);
  accountsStore().set('accounts', accounts);
  return toSummary(next);
}

export function deleteAccount(id: string): void {
  accountsStore().set(
    'accounts',
    accountsStore().get('accounts').filter((a) => a.id !== id)
  );
}

export function getAccountWithPassword(
  id: string
): (AccountSummary & { password?: string }) | null {
  const account = accountsStore().get('accounts').find((a) => a.id === id);
  if (!account) return null;
  let password: string | undefined;
  if (account.encryptedPassword) {
    const raw = Buffer.from(account.encryptedPassword, 'base64');
    try {
      password = safeStorage.isEncryptionAvailable()
        ? safeStorage.decryptString(raw)
        : raw.toString('utf8');
    } catch {
      password = undefined;
    }
  }
  return { ...toSummary(account), password };
}
