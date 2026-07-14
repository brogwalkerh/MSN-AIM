import { EventEmitter } from 'node:events';

/**
 * Minimal typed wrapper over node's EventEmitter. Events map:
 * name -> listener signature.
 */
export type EventMap = Record<string, (...args: never[]) => void>;

export class TypedEmitter<E extends EventMap> {
  private readonly emitter = new EventEmitter();

  on<K extends keyof E & string>(event: K, listener: E[K]): this {
    this.emitter.on(event, listener as unknown as (...args: unknown[]) => void);
    return this;
  }

  once<K extends keyof E & string>(event: K, listener: E[K]): this {
    this.emitter.once(event, listener as unknown as (...args: unknown[]) => void);
    return this;
  }

  off<K extends keyof E & string>(event: K, listener: E[K]): this {
    this.emitter.off(event, listener as unknown as (...args: unknown[]) => void);
    return this;
  }

  removeAllListeners(): this {
    this.emitter.removeAllListeners();
    return this;
  }

  protected emit<K extends keyof E & string>(event: K, ...args: Parameters<E[K]>): boolean {
    return this.emitter.emit(event, ...args);
  }
}
