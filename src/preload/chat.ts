import { contextBridge, ipcRenderer } from 'electron';
import type { IpcCommandKey, IpcEventKey, PapillonBridge } from '@msn-aim/shared';

/**
 * Chat windows get the same generic bridge shape as the shell; the main
 * process scopes what each chat window may learn via im:getChatContext.
 */
const bridge: PapillonBridge = {
  invoke: (channel: IpcCommandKey, args: unknown) =>
    ipcRenderer.invoke(channel, args) as never,
  on: (channel: IpcEventKey, listener: (payload: never) => void) => {
    const wrapped = (_event: unknown, payload: never) => listener(payload);
    ipcRenderer.on(channel, wrapped as never);
    return () => ipcRenderer.off(channel, wrapped as never);
  }
};

contextBridge.exposeInMainWorld('papillon', bridge);
