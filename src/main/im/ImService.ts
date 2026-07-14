import {
  ImError,
  createProtocolClient,
  registerProtocol,
  type ImProtocolClient
} from '@msn-aim/im-core';
import { OscarClient } from '@msn-aim/proto-oscar';
import { MsnpClient } from '@msn-aim/proto-msnp';
import { createLogger } from '@msn-aim/shared';
import { broadcast, handle } from '../ipc/typed-ipc';
import { getAccountWithPassword } from '../storage/accounts';

const log = createLogger('im-service');

/**
 * Owns one protocol client per signed-on account in the main process and
 * bridges client events onto typed IPC broadcasts.
 */
export class ImService {
  private readonly clients = new Map<string, ImProtocolClient>();
  private openChatRequested:
    | ((accountId: string, buddyId: string, buddyName?: string, focus?: boolean) => void)
    | null = null;

  constructor() {
    registerProtocol('oscar', () => new OscarClient());
    registerProtocol('msnp', () => new MsnpClient());
  }

  onOpenChat(
    fn: (accountId: string, buddyId: string, buddyName?: string, focus?: boolean) => void
  ): void {
    this.openChatRequested = fn;
  }

  client(accountId: string): ImProtocolClient {
    const client = this.clients.get(accountId);
    if (!client) throw new ImError('network', 'Not signed on');
    return client;
  }

  registerIpc(): void {
    handle('im:connect', async ({ accountId, password }) => {
      const account = getAccountWithPassword(accountId);
      if (!account) throw new Error('Unknown account');
      const effectivePassword = password || account.password;
      if (!effectivePassword) throw new Error('Password required');

      await this.clients.get(accountId)?.disconnect().catch(() => undefined);
      const client = createProtocolClient(account.protocol);
      this.clients.set(accountId, client);

      client.on('sessionState', (state, detail) =>
        broadcast('im:sessionState', { accountId, state, detail })
      );
      client.on('error', (err) =>
        broadcast('im:error', { accountId, kind: err.kind, message: err.message, fatal: err.fatal })
      );
      client.on('buddyListReceived', (groups) => broadcast('im:buddyList', { accountId, groups }));
      client.on('buddyPresence', (buddy) => broadcast('im:buddyPresence', { accountId, buddy }));
      client.on('messageReceived', (message) => broadcast('im:message', { accountId, message }));
      client.on('typing', (from, state) => broadcast('im:typing', { accountId, from, state }));
      client.on('buddyInfo', (info) => broadcast('im:buddyInfo', { accountId, info }));

      log.info(`connecting account ${account.username} (${account.protocol})`);
      await client.connect({
        protocol: account.protocol,
        username: account.username,
        password: effectivePassword,
        server: account.server
      });
    });

    handle('im:disconnect', async ({ accountId }) => {
      await this.clients.get(accountId)?.disconnect();
      this.clients.delete(accountId);
    });

    handle('im:sendMessage', async ({ accountId, to, body }) => {
      await this.client(accountId).sendMessage(to, body);
    });
    handle('im:sendTyping', async ({ accountId, to, state }) => {
      await this.client(accountId).sendTyping(to, state);
    });
    handle('im:setStatus', async ({ accountId, status, awayMessage }) => {
      await this.client(accountId).setStatus(status, awayMessage);
    });
    handle('im:setProfile', async ({ accountId, html }) => {
      await this.client(accountId).setProfile(html);
    });
    handle('im:requestBuddyInfo', async ({ accountId, buddyId }) => {
      await this.client(accountId).requestBuddyInfo(buddyId);
    });
    handle('im:addBuddy', async ({ accountId, buddyId, group }) => {
      await this.client(accountId).addBuddy(buddyId, group);
    });
    handle('im:removeBuddy', async ({ accountId, buddyId, group }) => {
      await this.client(accountId).removeBuddy(buddyId, group);
    });
    handle('im:addGroup', async ({ accountId, name }) => {
      await this.client(accountId).addGroup(name);
    });
    handle('im:openChat', async ({ accountId, buddyId, buddyName, focus }) => {
      this.openChatRequested?.(accountId, buddyId, buddyName, focus);
    });
  }

  async disconnectAll(): Promise<void> {
    await Promise.allSettled([...this.clients.values()].map((c) => c.disconnect()));
    this.clients.clear();
  }
}
