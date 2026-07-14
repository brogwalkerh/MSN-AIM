export type PresenceStatus = 'online' | 'away' | 'idle' | 'offline';

export type ProtocolId = 'oscar' | 'msnp';

export interface Buddy {
  /** Normalized id (protocol-specific: AIM lowercases and strips spaces). */
  id: string;
  /** Formatted screen name / friendly name as the network reports it. */
  displayName: string;
  group: string;
  status: PresenceStatus;
  awayMessage?: string;
  idleMinutes?: number;
  onlineSinceEpochMs?: number;
}

export interface BuddyGroup {
  name: string;
  buddies: Buddy[];
}

export interface ImMessage {
  from: string;
  to: string;
  /** Sanitized HTML subset (b/i/u/font/a); plain text is valid HTML. */
  body: string;
  timestampEpochMs: number;
  /** True for away-message auto-replies. */
  autoResponse: boolean;
  /** True when delivered from server offline-message storage. */
  offline?: boolean;
}

export type TypingState = 'typing' | 'typed' | 'stopped';

export type SessionState =
  | 'disconnected'
  | 'connecting'
  | 'authenticating'
  | 'syncing'
  | 'online';

export type ImErrorKind =
  | 'auth-failed'
  | 'rate-limited'
  | 'network'
  | 'protocol'
  | 'not-supported';

export class ImError extends Error {
  constructor(
    public readonly kind: ImErrorKind,
    message: string,
    public readonly fatal = false
  ) {
    super(message);
    this.name = 'ImError';
  }
}

export interface ImServerConfig {
  host: string;
  port: number;
}

export interface ImAccountConfig {
  protocol: ProtocolId;
  username: string;
  password: string;
  server: ImServerConfig;
}

/** What a protocol implementation can do; UI greys out the rest. */
export interface ProtocolCapabilities {
  typing: boolean;
  awayMessages: boolean;
  groups: boolean;
  serverSideList: boolean;
  offlineMessages: boolean;
  profiles: boolean;
}

export interface BuddyInfo {
  id: string;
  profile?: string;
  awayMessage?: string;
  onlineSinceEpochMs?: number;
  idleMinutes?: number;
}
