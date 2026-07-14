import { create } from 'zustand';
import type { Buddy, BuddyGroup, BuddyInfo, PresenceStatus, SessionState, TypingState } from '@msn-aim/im-core';
import type { AccountSummary, UpsertAccountArgs } from '@msn-aim/shared';

export interface ImStoreState {
  accounts: AccountSummary[];
  activeAccountId: string | null;
  session: SessionState;
  sessionDetail?: string;
  ownStatus: PresenceStatus;
  groups: BuddyGroup[];
  presence: Record<string, Buddy>;
  buddyInfo: Record<string, BuddyInfo>;
  lastError: string | null;

  loadAccounts: () => Promise<void>;
  upsertAccount: (args: UpsertAccountArgs) => Promise<AccountSummary>;
  deleteAccount: (id: string) => Promise<void>;
  signIn: (accountId: string, password?: string) => Promise<void>;
  signOut: () => Promise<void>;
  setStatus: (status: PresenceStatus, awayMessage?: string) => Promise<void>;
  openChat: (buddyId: string, buddyName?: string, focus?: boolean) => void;
  addBuddy: (buddyId: string, group: string) => Promise<void>;
  removeBuddy: (buddyId: string, group: string) => Promise<void>;
  clearError: () => void;
}

export const useImStore = create<ImStoreState>((set, get) => ({
  accounts: [],
  activeAccountId: null,
  session: 'disconnected',
  ownStatus: 'online',
  groups: [],
  presence: {},
  buddyInfo: {},
  lastError: null,

  loadAccounts: async () => {
    const accounts = await window.papillon.invoke('accounts:list', {});
    set({ accounts });
  },

  upsertAccount: async (args) => {
    const account = await window.papillon.invoke('accounts:upsert', args);
    await get().loadAccounts();
    return account;
  },

  deleteAccount: async (id) => {
    await window.papillon.invoke('accounts:delete', { id });
    await get().loadAccounts();
  },

  signIn: async (accountId, password) => {
    set({ activeAccountId: accountId, lastError: null, session: 'connecting' });
    try {
      await window.papillon.invoke('im:connect', { accountId, password });
      set({ ownStatus: 'online' });
    } catch (err) {
      set({
        session: 'disconnected',
        lastError: extractErrorMessage(err)
      });
      throw err;
    }
  },

  signOut: async () => {
    const { activeAccountId } = get();
    if (activeAccountId) {
      await window.papillon.invoke('im:disconnect', { accountId: activeAccountId });
    }
    set({ session: 'disconnected', groups: [], presence: {}, activeAccountId: null });
  },

  setStatus: async (status, awayMessage) => {
    const { activeAccountId } = get();
    if (!activeAccountId) return;
    await window.papillon.invoke('im:setStatus', { accountId: activeAccountId, status, awayMessage });
    set({ ownStatus: status });
  },

  openChat: (buddyId, buddyName, focus = true) => {
    const { activeAccountId, presence } = get();
    if (!activeAccountId) return;
    void window.papillon.invoke('im:openChat', {
      accountId: activeAccountId,
      buddyId,
      buddyName: buddyName ?? presence[buddyId]?.displayName ?? buddyId,
      focus
    });
  },

  addBuddy: async (buddyId, group) => {
    const { activeAccountId } = get();
    if (!activeAccountId) return;
    await window.papillon.invoke('im:addBuddy', { accountId: activeAccountId, buddyId, group });
  },

  removeBuddy: async (buddyId, group) => {
    const { activeAccountId } = get();
    if (!activeAccountId) return;
    await window.papillon.invoke('im:removeBuddy', { accountId: activeAccountId, buddyId, group });
  },

  clearError: () => set({ lastError: null })
}));

export function extractErrorMessage(err: unknown): string {
  const raw = err instanceof Error ? err.message : String(err);
  // Electron prefixes invoke rejections with "Error invoking remote method '...': Error:"
  const idx = raw.lastIndexOf('Error: ');
  return idx >= 0 ? raw.slice(idx + 'Error: '.length) : raw;
}

/** Wire main-process IM events into the store. Call once at startup. */
export function initImEvents(): void {
  const active = () => useImStore.getState().activeAccountId;

  window.papillon.on('im:sessionState', ({ accountId, state, detail }) => {
    if (accountId !== active()) return;
    useImStore.setState({ session: state, sessionDetail: detail });
  });

  window.papillon.on('im:error', ({ accountId, message }) => {
    if (accountId !== active()) return;
    useImStore.setState({ lastError: message });
  });

  window.papillon.on('im:buddyList', ({ accountId, groups }) => {
    if (accountId !== active()) return;
    useImStore.setState((s) => {
      const presence = { ...s.presence };
      for (const g of groups) {
        for (const b of g.buddies) {
          presence[b.id] = { ...b, status: presence[b.id]?.status ?? b.status };
        }
      }
      return { groups, presence };
    });
  });

  window.papillon.on('im:buddyPresence', ({ accountId, buddy }) => {
    if (accountId !== active()) return;
    useImStore.setState((s) => ({ presence: { ...s.presence, [buddy.id]: { ...s.presence[buddy.id], ...buddy } } }));
  });

  window.papillon.on('im:buddyInfo', ({ accountId, info }) => {
    if (accountId !== active()) return;
    useImStore.setState((s) => ({
      buddyInfo: { ...s.buddyInfo, [info.id]: info },
      presence: info.awayMessage
        ? {
            ...s.presence,
            [info.id]: s.presence[info.id]
              ? { ...s.presence[info.id]!, awayMessage: info.awayMessage }
              : s.presence[info.id]!
          }
        : s.presence
    }));
  });

  // Auto-open a chat window (without stealing focus) on incoming messages.
  window.papillon.on('im:message', ({ accountId, message }) => {
    if (accountId !== active()) return;
    const { presence } = useImStore.getState();
    void window.papillon.invoke('im:openChat', {
      accountId,
      buddyId: message.from,
      buddyName: presence[message.from]?.displayName ?? message.from,
      focus: false
    });
  });
}
