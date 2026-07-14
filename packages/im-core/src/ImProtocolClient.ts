import { TypedEmitter } from './events';
import type {
  Buddy,
  BuddyGroup,
  BuddyInfo,
  ImAccountConfig,
  ImError,
  ImMessage,
  PresenceStatus,
  ProtocolCapabilities,
  SessionState,
  TypingState
} from './types';

export interface ImClientEvents {
  sessionState: (state: SessionState, detail?: string) => void;
  error: (err: ImError) => void;
  buddyListReceived: (groups: BuddyGroup[]) => void;
  buddyPresence: (buddy: Buddy) => void;
  messageReceived: (msg: ImMessage) => void;
  typing: (from: string, state: TypingState) => void;
  buddyInfo: (info: BuddyInfo) => void;
  [key: string]: (...args: never[]) => void;
}

/**
 * The protocol-agnostic IM client contract. OSCAR (AIM) implements this
 * today; MSNP (MSN Messenger via Escargot) slots in behind the same
 * interface — see docs/MSNP-PLANNING.md.
 */
export abstract class ImProtocolClient extends TypedEmitter<ImClientEvents> {
  abstract readonly protocol: string;
  abstract readonly capabilities: ProtocolCapabilities;

  /** Protocol-specific identity normalization for comparisons/keys. */
  abstract normalizeId(id: string): string;

  /** Resolves once the session reaches 'online'. */
  abstract connect(config: ImAccountConfig): Promise<void>;
  abstract disconnect(): Promise<void>;

  abstract sendMessage(to: string, htmlBody: string): Promise<void>;
  abstract sendTyping(to: string, state: TypingState): Promise<void>;

  abstract setStatus(status: PresenceStatus, awayMessage?: string): Promise<void>;
  abstract setIdleTime(seconds: number): Promise<void>;
  abstract setProfile(html: string): Promise<void>;
  /** Async result arrives via the 'buddyInfo' event. */
  abstract requestBuddyInfo(id: string): Promise<void>;

  abstract addBuddy(id: string, group: string): Promise<void>;
  abstract removeBuddy(id: string, group: string): Promise<void>;
  abstract addGroup(name: string): Promise<void>;
  abstract renameGroup(oldName: string, newName: string): Promise<void>;
}
