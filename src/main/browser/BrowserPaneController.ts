import { WebContentsView, type BrowserWindow } from 'electron';
import type { BrowserNavState } from '@msn-aim/shared';
import { broadcast, handle } from '../ipc/typed-ipc';

const HOME_URL = 'https://www.msn.com/';

/**
 * Owns the WebContentsView that renders real web content inside the shell.
 * The renderer draws an empty placeholder and streams its rect here; the
 * view composites above the renderer, so overlays ask us to hide it.
 */
export class BrowserPaneController {
  private view: WebContentsView | null = null;
  private win: BrowserWindow | null = null;
  private bounds = { x: 0, y: 0, width: 0, height: 0 };
  private visible = false;

  attach(win: BrowserWindow): void {
    this.win = win;
    const view = new WebContentsView({
      webPreferences: {
        contextIsolation: true,
        nodeIntegration: false,
        sandbox: true
      }
    });
    this.view = view;
    view.setBounds({ x: 0, y: 0, width: 0, height: 0 });

    const wc = view.webContents;
    const pushState = () => {
      const state: BrowserNavState = {
        url: wc.getURL(),
        title: wc.getTitle(),
        canGoBack: wc.navigationHistory.canGoBack(),
        canGoForward: wc.navigationHistory.canGoForward(),
        loading: wc.isLoading()
      };
      broadcast('browser:navState', state);
    };
    wc.on('did-navigate', pushState);
    wc.on('did-navigate-in-page', pushState);
    wc.on('did-start-loading', pushState);
    wc.on('did-stop-loading', pushState);
    wc.on('page-title-updated', pushState);
    wc.setWindowOpenHandler(({ url }) => {
      void wc.loadURL(url); // open popups in the same pane, MSN Explorer style
      return { action: 'deny' };
    });

    void wc.loadURL(HOME_URL);
  }

  private applyBounds(): void {
    if (!this.view || !this.win) return;
    if (this.visible) {
      this.win.contentView.addChildView(this.view);
      this.view.setBounds(this.bounds);
    } else {
      this.win.contentView.removeChildView(this.view);
    }
  }

  registerIpc(): void {
    handle('browser:navigate', async ({ url }) => {
      const target = /^[a-z]+:\/\//i.test(url) ? url : `https://${url}`;
      await this.view?.webContents.loadURL(target).catch(() => undefined);
    });
    handle('browser:back', async () => {
      this.view?.webContents.navigationHistory.goBack();
    });
    handle('browser:forward', async () => {
      this.view?.webContents.navigationHistory.goForward();
    });
    handle('browser:stop', async () => {
      this.view?.webContents.stop();
    });
    handle('browser:reload', async () => {
      this.view?.webContents.reload();
    });
    handle('browser:setBounds', async ({ bounds }) => {
      this.bounds = {
        x: Math.round(bounds.x),
        y: Math.round(bounds.y),
        width: Math.round(bounds.width),
        height: Math.round(bounds.height)
      };
      this.applyBounds();
    });
    handle('browser:setVisible', async ({ visible }) => {
      this.visible = visible;
      this.applyBounds();
    });
  }
}
