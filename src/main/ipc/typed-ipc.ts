import { BrowserWindow, ipcMain, type IpcMainInvokeEvent } from 'electron';
import type {
  IpcCommandArgs,
  IpcCommandKey,
  IpcCommandResult,
  IpcEventKey,
  IpcEvents
} from '@msn-aim/shared';

/** Register a typed invoke handler. One handler per channel. */
export function handle<K extends IpcCommandKey>(
  channel: K,
  handler: (args: IpcCommandArgs<K>, event: IpcMainInvokeEvent) => IpcCommandResult<K>
): void {
  ipcMain.handle(channel, (event, args) => handler(args as IpcCommandArgs<K>, event));
}

/** Push a typed event to every open window. */
export function broadcast<K extends IpcEventKey>(channel: K, payload: IpcEvents[K]): void {
  for (const win of BrowserWindow.getAllWindows()) {
    if (!win.isDestroyed()) win.webContents.send(channel, payload);
  }
}
