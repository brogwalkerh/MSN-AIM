import {
  ImError,
  ImProtocolClient,
  type ImAccountConfig,
  type PresenceStatus,
  type ProtocolCapabilities,
  type TypingState
} from '@msn-aim/im-core';

/**
 * MSN Messenger (MSNP) protocol client — v1 stub.
 *
 * MSNP support targets the Escargot revival service (m1.escargot.chat:1863,
 * MSNP12). The full design — TRID command stream, VER/CVR/USR handshake,
 * switchboard sessions, presence and list mapping onto ImProtocolClient —
 * lives in docs/MSNP-PLANNING.md. This stub proves the multi-protocol
 * abstraction compiles against a second protocol and lets the UI expose
 * MSN as "coming soon".
 */
export class MsnpClient extends ImProtocolClient {
  readonly protocol = 'msnp';

  readonly capabilities: ProtocolCapabilities = {
    typing: true, // TypingUser MIME control message
    awayMessages: false, // MSNP has status codes (BSY/AWY...) but no away text pre-MSNP11 PSM
    groups: true, // FL groups via ADG/ADC
    serverSideList: true, // FL/AL/BL server lists
    offlineMessages: false, // OIM is out of scope for the first MSNP milestone
    profiles: false
  };

  normalizeId(id: string): string {
    // MSNP identities are email addresses; compare case-insensitively.
    return id.trim().toLowerCase();
  }

  private notImplemented(): never {
    throw new ImError(
      'not-supported',
      'MSN Messenger (MSNP) support is planned but not implemented yet — see docs/MSNP-PLANNING.md',
      true
    );
  }

  connect(_config: ImAccountConfig): Promise<void> {
    this.notImplemented();
  }
  disconnect(): Promise<void> {
    return Promise.resolve();
  }
  sendMessage(_to: string, _htmlBody: string): Promise<void> {
    this.notImplemented();
  }
  sendTyping(_to: string, _state: TypingState): Promise<void> {
    this.notImplemented();
  }
  setStatus(_status: PresenceStatus, _awayMessage?: string): Promise<void> {
    this.notImplemented();
  }
  setIdleTime(_seconds: number): Promise<void> {
    this.notImplemented();
  }
  setProfile(_html: string): Promise<void> {
    this.notImplemented();
  }
  requestBuddyInfo(_id: string): Promise<void> {
    this.notImplemented();
  }
  addBuddy(_id: string, _group: string): Promise<void> {
    this.notImplemented();
  }
  removeBuddy(_id: string, _group: string): Promise<void> {
    this.notImplemented();
  }
  addGroup(_name: string): Promise<void> {
    this.notImplemented();
  }
  renameGroup(_oldName: string, _newName: string): Promise<void> {
    this.notImplemented();
  }
}
