import { create } from 'zustand';

export type PaneId = 'home' | 'browser' | 'mail' | 'chat' | 'media';

interface UiState {
  activePane: PaneId;
  statusText: string;
  setPane: (pane: PaneId) => void;
  setStatusText: (text: string) => void;
}

export const useUiStore = create<UiState>((set) => ({
  activePane: 'home',
  statusText: 'Welcome to MSN Explorer',
  setPane: (activePane) => set({ activePane }),
  setStatusText: (statusText) => set({ statusText })
}));
