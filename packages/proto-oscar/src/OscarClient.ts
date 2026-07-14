import {
  ImError,
  ImProtocolClient,
  type Buddy,
  type BuddyGroup,
  type ImAccountConfig,
  type PresenceStatus,
  type ProtocolCapabilities,
  type TypingState
} from '@msn-aim/im-core';
import { createLogger } from '@msn-aim/shared';
import { BosSession } from './session/BosSession';
import { sanitizeAimHtml } from './codec/html';
import { UserClass } from './consts';
import type { UserInfo } from './codec/userinfo';
import type { GroupEntry } from './foodgroups/feedbag';

const log = createLogger('oscar:client');

const RECONNECT_MAX_ATTEMPTS = 5;
const AUTO_RESPONSE_COOLDOWN_MS = 10 * 60 * 1000;

/** AIM (OSCAR protocol) client. */
export class OscarClient extends ImProtocolClient {
  readonly protocol = 'oscar';

  readonly capabilities: ProtocolCapabilities = {
    typing: true,
    awayMessages: true,
    groups: true,
    serverSideList: true,
    offlineMessages: true,
    profiles: true
  };

  private session: BosSession | null = null;
  private config: ImAccountConfig | null = null;
  private groups: BuddyGroup[] = [];
  private readonly buddies = new Map<string, Buddy>();
  private status: PresenceStatus = 'online';
  private awayMessage = '';
  private explicitDisconnect = false;
  private reconnectAttempts = 0;
  private reconnectTimer: NodeJS.Timeout | null = null;
  private readonly lastAutoResponseAt = new Map<string, number>();

  normalizeId(id: string): string {
    return id.toLowerCase().replace(/\s+/g, '');
  }

  async connect(config: ImAccountConfig): Promise<void> {
    if (this.session) throw new ImError('protocol', 'Already connected');
    this.config = config;
    this.explicitDisconnect = false;
    this.reconnectAttempts = 0;
    await this.startSession();
  }

  private async startSession(): Promise<void> {
    const config = this.config;
    if (!config) throw new ImError('protocol', 'No account configured');
    const session = new BosSession({
      host: config.server.host,
      port: config.server.port,
      screenName: config.username,
      password: config.password
    });
    this.session = session;

    session.on('stage', (stage) => {
      switch (stage) {
        case 'auth-connect':
          this.emit('sessionState', 'connecting');
          break;
        case 'auth-key':
        case 'auth-login':
          this.emit('sessionState', 'authenticating');
          break;
        case 'bos-connect':
        case 'host-ready':
        case 'rate-sync':
        case 'feedbag-sync':
          this.emit('sessionState', 'syncing');
          break;
        case 'online':
          this.reconnectAttempts = 0;
          this.emit('sessionState', 'online');
          break;
        default:
          break;
      }
    });

    session.on('buddyList', (groups) => {
      this.groups = this.toBuddyGroups(groups);
      this.emit('buddyListReceived', this.groups);
    });

    session.on('presence', (info, online) => {
      const buddy = this.applyPresence(info, online);
      this.emit('buddyPresence', buddy);
    });

    session.on('message', (msg) => {
      const from = this.normalizeId(msg.userInfo.screenName);
      this.emit('messageReceived', {
        from,
        to: this.normalizeId(config.username),
        body: sanitizeAimHtml(msg.text),
        timestampEpochMs: Date.now(),
        autoResponse: msg.autoResponse
      });
      this.maybeSendAutoResponse(from);
    });

    session.on('typing', (from, event) => {
      this.emit('typing', this.normalizeId(from), event);
    });

    session.on('userInfo', (reply) => {
      this.emit('buddyInfo', {
        id: this.normalizeId(reply.userInfo.screenName),
        profile: reply.profile !== undefined ? sanitizeAimHtml(reply.profile) : undefined,
        awayMessage: reply.awayMessage !== undefined ? sanitizeAimHtml(reply.awayMessage) : undefined,
        onlineSinceEpochMs: reply.userInfo.onlineSinceEpochMs,
        idleMinutes: reply.userInfo.idleMinutes
      });
    });

    session.on('rateWarning', (classId, code) => {
      this.emit(
        'error',
        new ImError('rate-limited', `Sending too fast (rate class ${classId}, code ${code}) — slowing down`)
      );
    });

    session.on('closed', (err) => {
      this.session = null;
      if (err) this.emit('error', err);
      this.emit('sessionState', 'disconnected', err?.message);
      this.maybeReconnect(err);
    });

    await session.login();
  }

  private maybeReconnect(err?: ImError): void {
    if (this.explicitDisconnect || err?.kind === 'auth-failed' || err?.fatal) return;
    if (!this.config || this.reconnectAttempts >= RECONNECT_MAX_ATTEMPTS) return;
    const delay = Math.min(60_000, 2000 * 2 ** this.reconnectAttempts);
    this.reconnectAttempts += 1;
    log.info(`reconnecting in ${delay}ms (attempt ${this.reconnectAttempts})`);
    this.reconnectTimer = setTimeout(() => {
      this.startSession().catch((e) => {
        this.emit('error', e instanceof ImError ? e : new ImError('network', String(e)));
      });
    }, delay);
    this.reconnectTimer.unref?.();
  }

  private toBuddyGroups(groups: GroupEntry[]): BuddyGroup[] {
    return groups.map((g) => ({
      name: g.name,
      buddies: g.buddies.map((b) => {
        const id = this.normalizeId(b.name);
        const existing = this.buddies.get(id);
        const buddy: Buddy = {
          id,
          displayName: b.alias || b.name,
          group: g.name,
          status: existing?.status ?? 'offline',
          awayMessage: existing?.awayMessage,
          idleMinutes: existing?.idleMinutes,
          onlineSinceEpochMs: existing?.onlineSinceEpochMs
        };
        this.buddies.set(id, buddy);
        return buddy;
      })
    }));
  }

  private applyPresence(info: UserInfo, online: boolean): Buddy {
    const id = this.normalizeId(info.screenName);
    const existing = this.buddies.get(id);
    const status: PresenceStatus = !online
      ? 'offline'
      : (info.userClass & UserClass.AWAY) !== 0
        ? 'away'
        : info.idleMinutes && info.idleMinutes > 0
          ? 'idle'
          : 'online';
    const buddy: Buddy = {
      id,
      displayName: info.screenName,
      group: existing?.group ?? 'Buddies',
      status,
      awayMessage: status === 'away' ? existing?.awayMessage : undefined,
      idleMinutes: online ? info.idleMinutes : undefined,
      onlineSinceEpochMs: online ? info.onlineSinceEpochMs : undefined
    };
    this.buddies.set(id, buddy);
    // Away text isn't in the arrival event; fetch it lazily.
    if (status === 'away') this.session?.requestUserInfo(info.screenName, true);
    return buddy;
  }

  private maybeSendAutoResponse(to: string): void {
    if (this.status !== 'away' || !this.awayMessage || !this.session) return;
    const last = this.lastAutoResponseAt.get(to) ?? 0;
    if (Date.now() - last < AUTO_RESPONSE_COOLDOWN_MS) return;
    this.lastAutoResponseAt.set(to, Date.now());
    try {
      this.session.sendIM(to, this.awayMessage, { autoResponse: true });
    } catch (err) {
      log.warn(`auto-response failed: ${(err as Error).message}`);
    }
  }

  async disconnect(): Promise<void> {
    this.explicitDisconnect = true;
    if (this.reconnectTimer) clearTimeout(this.reconnectTimer);
    this.session?.disconnect();
    this.session = null;
    this.emit('sessionState', 'disconnected');
  }

  private requireSession(): BosSession {
    if (!this.session || this.session.currentStage !== 'online') {
      throw new ImError('network', 'Not signed on');
    }
    return this.session;
  }

  async sendMessage(to: string, htmlBody: string): Promise<void> {
    this.requireSession().sendIM(to, htmlBody);
  }

  async sendTyping(to: string, state: TypingState): Promise<void> {
    this.requireSession().sendTyping(to, state);
  }

  async setStatus(status: PresenceStatus, awayMessage?: string): Promise<void> {
    const session = this.requireSession();
    this.status = status;
    switch (status) {
      case 'away':
        this.awayMessage = awayMessage || 'I am away from my computer right now.';
        this.lastAutoResponseAt.clear();
        session.setAwayMessage(this.awayMessage);
        break;
      case 'idle':
        session.setIdle(600);
        break;
      case 'online':
        this.awayMessage = '';
        session.setAwayMessage('');
        session.setIdle(0);
        break;
      case 'offline':
        await this.disconnect();
        break;
    }
  }

  async setIdleTime(seconds: number): Promise<void> {
    this.requireSession().setIdle(seconds);
  }

  async setProfile(html: string): Promise<void> {
    this.requireSession().setProfile(html);
  }

  async requestBuddyInfo(id: string): Promise<void> {
    // Away query returns profile + away text together on most servers.
    this.requireSession().requestUserInfo(id, true);
  }

  async addBuddy(id: string, group: string): Promise<void> {
    await this.requireSession().addBuddy(id, group);
  }

  async removeBuddy(id: string, group: string): Promise<void> {
    await this.requireSession().removeBuddy(id, group);
  }

  async addGroup(name: string): Promise<void> {
    await this.requireSession().addGroup(name);
  }

  async renameGroup(oldName: string, newName: string): Promise<void> {
    await this.requireSession().renameGroup(oldName, newName);
  }
}
