import type { PapillonBridge } from '@msn-aim/shared';

declare global {
  interface Window {
    papillon: PapillonBridge;
  }
}

export {};
