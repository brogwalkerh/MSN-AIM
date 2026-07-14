import { BrowserWindow, shell } from 'electron';
import { join } from 'node:path';
import type { ChatWindowContext } from '@msn-aim/shared';
import { handle } from '../ipc/typed-ipc';

/**
 * One frameless BrowserWindow per conversation (classic AIM UX), pooled by
 * accountId+buddyId. Each window learns who it is via im:getChatContext.
 */
export class ChatWindowManager {
  private readonly windows = new Map<string, BrowserWindow>();
  private readonly contexts = new Map<number, ChatWindowContext>();

  registerIpc(): void {
    handle('im:getChatContext', async (_args, event) => {
      return this.contexts.get(event.sender.id) ?? null;
    });
  }

  open(context: ChatWindowContext, focus = true): void {
    const key = `${context.accountId}:${context.buddyId}`;
    const existing = this.windows.get(key);
    if (existing && !existing.isDestroyed()) {
      if (focus) existing.focus();
      return;
    }

    const win = new BrowserWindow({
      width: 540,
      height: 480,
      minWidth: 380,
      minHeight: 320,
      frame: false,
      backgroundColor: '#dbe8f5',
      show: false,
      webPreferences: {
        preload: join(__dirname, '../preload/chat.js'),
        contextIsolation: true,
        nodeIntegration: false,
        sandbox: true
      }
    });
    this.windows.set(key, win);
    this.contexts.set(win.webContents.id, context);
    win.once('ready-to-show', () => win.show());
    win.on('closed', () => {
      this.windows.delete(key);
    });
    win.webContents.setWindowOpenHandler(({ url }) => {
      void shell.openExternal(url);
      return { action: 'deny' };
    });
    win.webContents.on('will-navigate', (event) => event.preventDefault());
    win.webContents.on('destroyed', () => this.contexts.delete(win.webContents.id));

    if (process.env['ELECTRON_RENDERER_URL']) {
      void win.loadURL(`${process.env['ELECTRON_RENDERER_URL']}/chat/index.html`);
    } else {
      void win.loadFile(join(__dirname, '../renderer/chat/index.html'));
    }
  }

  /** Focus (or open) the window for an incoming message. */
  ensureOpenFor(context: ChatWindowContext): void {
    this.open(context);
  }
}
