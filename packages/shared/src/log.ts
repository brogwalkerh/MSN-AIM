export type LogLevel = 'debug' | 'info' | 'warn' | 'error';

const levelOrder: Record<LogLevel, number> = { debug: 0, info: 1, warn: 2, error: 3 };

let minLevel: LogLevel =
  typeof process !== 'undefined' && process.env?.PAPILLON_DEBUG ? 'debug' : 'info';

export function setLogLevel(level: LogLevel): void {
  minLevel = level;
}

export interface Logger {
  debug(msg: string, ...args: unknown[]): void;
  info(msg: string, ...args: unknown[]): void;
  warn(msg: string, ...args: unknown[]): void;
  error(msg: string, ...args: unknown[]): void;
}

export function createLogger(scope: string): Logger {
  const log =
    (level: LogLevel) =>
    (msg: string, ...args: unknown[]) => {
      if (levelOrder[level] < levelOrder[minLevel]) return;
      // eslint-disable-next-line no-console
      console[level === 'debug' ? 'log' : level](`[${scope}] ${msg}`, ...args);
    };
  return { debug: log('debug'), info: log('info'), warn: log('warn'), error: log('error') };
}
