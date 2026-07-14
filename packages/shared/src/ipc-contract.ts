import type {
  Buddy,
  BuddyGroup,
  BuddyInfo,
  ImErrorKind,
  ImMessage,
  PresenceStatus,
  ProtocolId,
  SessionState,
  TypingState
} from '@msn-aim/im-core';

/** A stored account as exposed to renderers (no password). */
export interface AccountSummary {
  id: string;
  protocol: ProtocolId;
  username: string;
  server: { host: string; port: number };
  avatar: string;
  rememberPassword: boolean;
}

export interface UpsertAccountArgs {
  id?: string;
  protocol: ProtocolId;
  username: string;
  password?: string;
  rememberPassword: boolean;
  server: { host: string; port: number };
  avatar: string;
}

export interface Rect {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface BrowserNavState {
  url: string;
  title: string;
  canGoBack: boolean;
  canGoForward: boolean;
  loading: boolean;
}

export interface MailAccountConfig {
  email: string;
  displayName: string;
  imap: { host: string; port: number; secure: boolean };
  smtp: { host: string; port: number; secure: boolean };
  user: string;
  password?: string;
}

export interface MailboxSummary {
  path: string;
  name: string;
  specialUse?: string;
  unseen?: number;
}

export interface MailEnvelope {
  uid: number;
  mailbox: string;
  from: string;
  fromAddress: string;
  subject: string;
  dateEpochMs: number;
  seen: boolean;
}

export interface MailBody {
  uid: number;
  mailbox: string;
  /** Sanitizable HTML (renderer sandboxes + sanitizes before display). */
  html?: string;
  text?: string;
  attachments: { filename: string; size: number }[];
}

export interface ComposeMailArgs {
  to: string;
  cc?: string;
  subject: string;
  text: string;
  inReplyTo?: { mailbox: string; uid: number };
}

export interface TrackInfo {
  id: string;
  title: string;
  artist: string;
  album: string;
  durationSec: number;
  /** media:// URL playable inside the sandboxed renderer. */
  url: string;
}

export interface ChannelItem {
  title: string;
  link: string;
  source: string;
  publishedEpochMs?: number;
}

export interface WeatherReport {
  location: string;
  temperatureC: number;
  weatherCode: number;
  description: string;
  highC: number;
  lowC: number;
}

export interface ChatWindowContext {
  accountId: string;
  buddyId: string;
  buddyName: string;
  ownScreenName: string;
}

/**
 * Renderer -> main request/response channels (ipcRenderer.invoke).
 * Single source of truth; main registers a handler per key and the
 * preload exposes a generic typed invoke.
 */
export interface IpcCommands {
  // accounts / sign-in
  'accounts:list': (args: Record<string, never>) => Promise<AccountSummary[]>;
  'accounts:upsert': (args: UpsertAccountArgs) => Promise<AccountSummary>;
  'accounts:delete': (args: { id: string }) => Promise<void>;

  // IM session
  'im:connect': (args: { accountId: string; password?: string }) => Promise<void>;
  'im:disconnect': (args: { accountId: string }) => Promise<void>;
  'im:sendMessage': (args: { accountId: string; to: string; body: string }) => Promise<void>;
  'im:sendTyping': (args: { accountId: string; to: string; state: TypingState }) => Promise<void>;
  'im:setStatus': (args: {
    accountId: string;
    status: PresenceStatus;
    awayMessage?: string;
  }) => Promise<void>;
  'im:setProfile': (args: { accountId: string; html: string }) => Promise<void>;
  'im:requestBuddyInfo': (args: { accountId: string; buddyId: string }) => Promise<void>;
  'im:addBuddy': (args: { accountId: string; buddyId: string; group: string }) => Promise<void>;
  'im:removeBuddy': (args: { accountId: string; buddyId: string; group: string }) => Promise<void>;
  'im:addGroup': (args: { accountId: string; name: string }) => Promise<void>;
  'im:openChat': (args: {
    accountId: string;
    buddyId: string;
    buddyName?: string;
    /** false = open without stealing focus (incoming-message auto-open). */
    focus?: boolean;
  }) => Promise<void>;
  'im:getChatContext': (args: Record<string, never>) => Promise<ChatWindowContext | null>;

  // embedded browser pane
  'browser:navigate': (args: { url: string }) => Promise<void>;
  'browser:back': (args: Record<string, never>) => Promise<void>;
  'browser:forward': (args: Record<string, never>) => Promise<void>;
  'browser:stop': (args: Record<string, never>) => Promise<void>;
  'browser:reload': (args: Record<string, never>) => Promise<void>;
  'browser:setBounds': (args: { bounds: Rect }) => Promise<void>;
  'browser:setVisible': (args: { visible: boolean }) => Promise<void>;

  // mail
  'mail:getAccount': (args: Record<string, never>) => Promise<MailAccountConfig | null>;
  'mail:setAccount': (args: MailAccountConfig) => Promise<void>;
  'mail:listMailboxes': (args: Record<string, never>) => Promise<MailboxSummary[]>;
  'mail:listMessages': (args: {
    mailbox: string;
    offset?: number;
  }) => Promise<MailEnvelope[]>;
  'mail:getMessage': (args: { mailbox: string; uid: number }) => Promise<MailBody>;
  'mail:send': (args: ComposeMailArgs) => Promise<void>;

  // media
  'media:openFiles': (args: Record<string, never>) => Promise<TrackInfo[]>;
  'media:addStream': (args: { url: string }) => Promise<TrackInfo>;

  // home channels
  'home:getNews': (args: Record<string, never>) => Promise<ChannelItem[]>;
  'home:getWeather': (args: { location?: string }) => Promise<WeatherReport | null>;

  // window chrome (frameless windows draw their own controls)
  'window:minimize': (args: Record<string, never>) => Promise<void>;
  'window:maximize': (args: Record<string, never>) => Promise<void>;
  'window:close': (args: Record<string, never>) => Promise<void>;
}

/** Main -> renderer push events (webContents.send). */
export interface IpcEvents {
  'im:sessionState': { accountId: string; state: SessionState; detail?: string };
  'im:error': { accountId: string; kind: ImErrorKind; message: string; fatal: boolean };
  'im:buddyList': { accountId: string; groups: BuddyGroup[] };
  'im:buddyPresence': { accountId: string; buddy: Buddy };
  'im:message': { accountId: string; message: ImMessage };
  'im:typing': { accountId: string; from: string; state: TypingState };
  'im:buddyInfo': { accountId: string; info: BuddyInfo };
  'browser:navState': BrowserNavState;
}

export type IpcCommandKey = keyof IpcCommands;
export type IpcEventKey = keyof IpcEvents;

export type IpcCommandArgs<K extends IpcCommandKey> = Parameters<IpcCommands[K]>[0];
export type IpcCommandResult<K extends IpcCommandKey> = ReturnType<IpcCommands[K]>;

/** Shape of the API each preload exposes on window.papillon. */
export interface PapillonBridge {
  invoke<K extends IpcCommandKey>(channel: K, args: IpcCommandArgs<K>): IpcCommandResult<K>;
  on<K extends IpcEventKey>(channel: K, listener: (payload: IpcEvents[K]) => void): () => void;
}
