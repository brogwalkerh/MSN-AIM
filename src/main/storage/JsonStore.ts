import { mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { app } from 'electron';

/** Tiny synchronous JSON-file store (atomic writes) under userData. */
export class JsonStore<T extends object> {
  private readonly file: string;
  private data: T;

  constructor(name: string, defaults: T) {
    this.file = join(app.getPath('userData'), `${name}.json`);
    this.data = defaults;
    try {
      this.data = { ...defaults, ...JSON.parse(readFileSync(this.file, 'utf8')) };
    } catch {
      // first run or corrupt file — keep defaults
    }
  }

  get<K extends keyof T>(key: K): T[K] {
    return this.data[key];
  }

  set<K extends keyof T>(key: K, value: T[K]): void {
    this.data[key] = value;
    this.flush();
  }

  private flush(): void {
    mkdirSync(dirname(this.file), { recursive: true });
    const tmp = `${this.file}.tmp`;
    writeFileSync(tmp, JSON.stringify(this.data, null, 2));
    renameSync(tmp, this.file);
  }
}
