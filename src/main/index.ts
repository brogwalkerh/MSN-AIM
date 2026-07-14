import { BrowserWindow, app } from 'electron';
import { createLogger } from '@msn-aim/shared';
import { handle } from './ipc/typed-ipc';
import { deleteAccount, listAccounts, upsertAccount } from './storage/accounts';
import { ImService } from './im/ImService';
import { MailService } from './mail/MailService';
import { MediaService } from './media/MediaService';
import { HomeService } from './home/HomeService';
import { BrowserPaneController } from './browser/BrowserPaneController';
import { createShellWindow } from './windows/ShellWindow';
import { ChatWindowManager } from './windows/ChatWindowManager';

const log = createLogger('main');

const gotLock = app.requestSingleInstanceLock();
if (!gotLock) {
  app.quit();
}

MediaService.registerScheme();

const imService = new ImService();
const mailService = new MailService();
const mediaService = new MediaService();
const homeService = new HomeService();
const browserPane = new BrowserPaneController();
const chatWindows = new ChatWindowManager();

let shellWindow: BrowserWindow | null = null;

const accountScreenNames = new Map<string, string>();

function openChat(accountId: string, buddyId: string, buddyName?: string, focus = true): void {
  chatWindows.open(
    {
      accountId,
      buddyId,
      buddyName: buddyName ?? buddyId,
      ownScreenName: accountScreenNames.get(accountId) ?? 'me'
    },
    focus
  );
}

function registerIpc(): void {
  handle('accounts:list', async () => listAccounts());
  handle('accounts:upsert', async (args) => {
    const summary = upsertAccount(args);
    accountScreenNames.set(summary.id, summary.username);
    return summary;
  });
  handle('accounts:delete', async ({ id }) => deleteAccount(id));

  handle('window:minimize', async (_args, event) => {
    BrowserWindow.fromWebContents(event.sender)?.minimize();
  });
  handle('window:maximize', async (_args, event) => {
    const win = BrowserWindow.fromWebContents(event.sender);
    if (win?.isMaximized()) win.unmaximize();
    else win?.maximize();
  });
  handle('window:close', async (_args, event) => {
    BrowserWindow.fromWebContents(event.sender)?.close();
  });

  imService.registerIpc();
  imService.onOpenChat(openChat);
  mailService.registerIpc();
  mediaService.registerIpc();
  homeService.registerIpc();
  browserPane.registerIpc();
  chatWindows.registerIpc();
}

void app.whenReady().then(() => {
  registerIpc();
  mediaService.attachProtocolHandler();
  shellWindow = createShellWindow();
  browserPane.attach(shellWindow);

  for (const account of listAccounts()) {
    accountScreenNames.set(account.id, account.username);
  }

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      shellWindow = createShellWindow();
      browserPane.attach(shellWindow);
    }
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});

app.on('before-quit', () => {
  void imService.disconnectAll();
});

process.on('uncaughtException', (err) => {
  log.error(`uncaught: ${err.stack ?? err.message}`);
});
