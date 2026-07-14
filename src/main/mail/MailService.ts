import { ImapFlow } from 'imapflow';
import { simpleParser } from 'mailparser';
import { createTransport } from 'nodemailer';
import { safeStorage } from 'electron';
import { createLogger, type MailAccountConfig, type MailEnvelope } from '@msn-aim/shared';
import { handle } from '../ipc/typed-ipc';
import { JsonStore } from '../storage/JsonStore';

const log = createLogger('mail');
const PAGE_SIZE = 50;

interface StoredMail extends Omit<MailAccountConfig, 'password'> {
  encryptedPassword?: string;
}

/** IMAP/SMTP mail — main-process only; renderers get plain DTOs. */
export class MailService {
  private store = new JsonStore<{ account: StoredMail | null }>('mail', { account: null });

  private getCredentials(): (MailAccountConfig & { password: string }) | null {
    const account = this.store.get('account');
    if (!account?.encryptedPassword) return null;
    const raw = Buffer.from(account.encryptedPassword, 'base64');
    const password = safeStorage.isEncryptionAvailable()
      ? safeStorage.decryptString(raw)
      : raw.toString('utf8');
    const { encryptedPassword: _omit, ...rest } = account;
    return { ...rest, password };
  }

  private async withImap<T>(fn: (client: ImapFlow) => Promise<T>): Promise<T> {
    const creds = this.getCredentials();
    if (!creds) throw new Error('No mail account configured');
    const client = new ImapFlow({
      host: creds.imap.host,
      port: creds.imap.port,
      secure: creds.imap.secure,
      auth: { user: creds.user, pass: creds.password },
      logger: false
    });
    await client.connect();
    try {
      return await fn(client);
    } finally {
      await client.logout().catch(() => client.close());
    }
  }

  registerIpc(): void {
    handle('mail:getAccount', async () => {
      const account = this.store.get('account');
      if (!account) return null;
      const { encryptedPassword: _omit, ...rest } = account;
      return rest;
    });

    handle('mail:setAccount', async (config) => {
      const { password, ...rest } = config;
      const previous = this.store.get('account');
      const stored: StoredMail = { ...rest };
      if (password) {
        stored.encryptedPassword = safeStorage.isEncryptionAvailable()
          ? safeStorage.encryptString(password).toString('base64')
          : Buffer.from(password, 'utf8').toString('base64');
      } else if (previous?.encryptedPassword) {
        stored.encryptedPassword = previous.encryptedPassword;
      }
      this.store.set('account', stored);
    });

    handle('mail:listMailboxes', async () => {
      return await this.withImap(async (client) => {
        const boxes = await client.list();
        return boxes
          .filter((b) => !b.flags?.has('\\Noselect'))
          .map((b) => ({
            path: b.path,
            name: b.name,
            specialUse: b.specialUse
          }));
      });
    });

    handle('mail:listMessages', async ({ mailbox, offset = 0 }) => {
      return await this.withImap(async (client) => {
        const lock = await client.getMailboxLock(mailbox);
        try {
          const status = client.mailbox;
          const total = typeof status === 'object' ? status.exists : 0;
          if (!total) return [];
          const end = total - offset;
          const start = Math.max(1, end - PAGE_SIZE + 1);
          if (end < 1) return [];
          const envelopes: MailEnvelope[] = [];
          for await (const msg of client.fetch(`${start}:${end}`, {
            uid: true,
            envelope: true,
            flags: true
          })) {
            const from = msg.envelope?.from?.[0];
            envelopes.push({
              uid: msg.uid,
              mailbox,
              from: from?.name || from?.address || '(unknown)',
              fromAddress: from?.address ?? '',
              subject: msg.envelope?.subject ?? '(no subject)',
              dateEpochMs: msg.envelope?.date ? new Date(msg.envelope.date).getTime() : 0,
              seen: msg.flags?.has('\\Seen') ?? false
            });
          }
          return envelopes.reverse();
        } finally {
          lock.release();
        }
      });
    });

    handle('mail:getMessage', async ({ mailbox, uid }) => {
      return await this.withImap(async (client) => {
        const lock = await client.getMailboxLock(mailbox);
        try {
          const raw = await client.download(String(uid), undefined, { uid: true });
          if (!raw?.content) throw new Error('Message not found');
          const parsed = await simpleParser(raw.content);
          await client.messageFlagsAdd(String(uid), ['\\Seen'], { uid: true });
          return {
            uid,
            mailbox,
            html: typeof parsed.html === 'string' ? parsed.html : undefined,
            text: parsed.text ?? undefined,
            attachments: parsed.attachments.map((a) => ({
              filename: a.filename ?? 'attachment',
              size: a.size
            }))
          };
        } finally {
          lock.release();
        }
      });
    });

    handle('mail:send', async (args) => {
      const creds = this.getCredentials();
      if (!creds) throw new Error('No mail account configured');
      const transport = createTransport({
        host: creds.smtp.host,
        port: creds.smtp.port,
        secure: creds.smtp.secure,
        auth: { user: creds.user, pass: creds.password }
      });
      await transport.sendMail({
        from: creds.displayName ? `"${creds.displayName}" <${creds.email}>` : creds.email,
        to: args.to,
        cc: args.cc || undefined,
        subject: args.subject,
        text: args.text
      });
      log.info(`sent mail to ${args.to}`);
    });
  }
}
