import { defineConfig, externalizeDepsPlugin } from 'electron-vite';
import react from '@vitejs/plugin-react';
import { resolve } from 'node:path';

const aliases = {
  '@msn-aim/shared': resolve(__dirname, 'packages/shared/src/index.ts'),
  '@msn-aim/im-core': resolve(__dirname, 'packages/im-core/src/index.ts'),
  '@msn-aim/proto-oscar': resolve(__dirname, 'packages/proto-oscar/src/index.ts'),
  '@msn-aim/proto-msnp': resolve(__dirname, 'packages/proto-msnp/src/index.ts')
};

export default defineConfig({
  main: {
    resolve: { alias: aliases },
    plugins: [externalizeDepsPlugin({ exclude: ['@msn-aim/shared', '@msn-aim/im-core', '@msn-aim/proto-oscar', '@msn-aim/proto-msnp'] })],
    build: {
      rollupOptions: {
        input: { index: resolve(__dirname, 'src/main/index.ts') }
      }
    }
  },
  preload: {
    resolve: { alias: aliases },
    plugins: [externalizeDepsPlugin()],
    build: {
      rollupOptions: {
        input: {
          shell: resolve(__dirname, 'src/preload/shell.ts'),
          chat: resolve(__dirname, 'src/preload/chat.ts')
        }
      }
    }
  },
  renderer: {
    resolve: { alias: aliases },
    plugins: [react()],
    build: {
      rollupOptions: {
        input: {
          shell: resolve(__dirname, 'src/renderer/shell/index.html'),
          chat: resolve(__dirname, 'src/renderer/chat/index.html')
        }
      }
    }
  }
});
