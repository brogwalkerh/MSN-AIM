import { defineConfig } from 'vitest/config';
import { resolve } from 'node:path';

export default defineConfig({
  resolve: {
    alias: {
      '@msn-aim/shared': resolve(__dirname, 'packages/shared/src/index.ts'),
      '@msn-aim/im-core': resolve(__dirname, 'packages/im-core/src/index.ts'),
      '@msn-aim/proto-oscar': resolve(__dirname, 'packages/proto-oscar/src/index.ts'),
      '@msn-aim/proto-msnp': resolve(__dirname, 'packages/proto-msnp/src/index.ts')
    }
  },
  test: {
    include: ['packages/*/src/**/*.test.ts', 'tests/unit/**/*.test.ts'],
    environment: 'node'
  }
});
