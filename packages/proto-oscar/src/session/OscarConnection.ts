import { Socket, connect } from 'node:net';
import { TypedEmitter } from '@msn-aim/im-core';
import { createLogger } from '@msn-aim/shared';
import { FlapChannel, FlapParser, encodeFlap, type FlapFrame } from '../wire/flap';
import { decodeSnac, encodeSnac, type Snac } from '../wire/snac';

const log = createLogger('oscar:conn');

const KEEPALIVE_INTERVAL_MS = 60_000;
const CONNECT_TIMEOUT_MS = 15_000;

export interface OscarConnectionEvents {
  signOn: (payload: Buffer) => void;
  snac: (snac: Snac) => void;
  closeFrame: (payload: Buffer) => void;
  close: (hadError: boolean) => void;
  error: (err: Error) => void;
  [key: string]: (...args: never[]) => void;
}

/**
 * One OSCAR TCP connection: FLAP framing, outbound sequence numbers,
 * channel routing and channel-5 keepalive. Auth and BOS sessions each
 * use one of these.
 */
export class OscarConnection extends TypedEmitter<OscarConnectionEvents> {
  private socket: Socket | null = null;
  private readonly parser = new FlapParser();
  private sequence = Math.floor(Math.random() * 0x8000);
  private keepaliveTimer: NodeJS.Timeout | null = null;
  private closed = false;

  /** Optional frame recorder for capturing test fixtures (dev only). */
  onFrame?: (direction: 'in' | 'out', channel: number, payload: Buffer) => void;

  async connect(host: string, port: number): Promise<void> {
    await new Promise<void>((resolve, reject) => {
      const socket = connect({ host, port });
      this.socket = socket;
      const failEarly = (err: Error) => reject(err);
      socket.setTimeout(CONNECT_TIMEOUT_MS, () => {
        socket.destroy(new Error(`connect timeout to ${host}:${port}`));
      });
      socket.once('error', failEarly);
      socket.once('connect', () => {
        socket.setTimeout(0);
        socket.setNoDelay(true);
        socket.off('error', failEarly);
        socket.on('error', (err) => {
          log.warn(`socket error: ${err.message}`);
          this.emit('error', err);
        });
        socket.on('close', (hadError) => {
          this.stopKeepalive();
          this.emit('close', hadError);
        });
        socket.on('data', (chunk) => this.onData(chunk));
        resolve();
      });
    });
  }

  private onData(chunk: Buffer): void {
    let frames: FlapFrame[];
    try {
      frames = this.parser.push(chunk);
    } catch (err) {
      this.emit('error', err as Error);
      this.destroy();
      return;
    }
    for (const frame of frames) {
      this.onFrame?.('in', frame.channel, frame.payload);
      switch (frame.channel) {
        case FlapChannel.SignOn:
          this.emit('signOn', frame.payload);
          break;
        case FlapChannel.Snac: {
          try {
            this.emit('snac', decodeSnac(frame.payload));
          } catch (err) {
            log.warn(`bad SNAC frame: ${(err as Error).message}`);
          }
          break;
        }
        case FlapChannel.SignOff:
          this.emit('closeFrame', frame.payload);
          break;
        case FlapChannel.KeepAlive:
          break;
        default:
          log.debug(`ignoring FLAP channel ${frame.channel}`);
      }
    }
  }

  sendFlap(channel: number, payload: Buffer): void {
    if (!this.socket || this.socket.destroyed) return;
    this.sequence = (this.sequence + 1) & 0xffff;
    this.onFrame?.('out', channel, payload);
    this.socket.write(encodeFlap(channel, this.sequence, payload));
  }

  sendSnac(snac: Snac): void {
    this.sendFlap(FlapChannel.Snac, encodeSnac(snac));
  }

  startKeepalive(): void {
    this.stopKeepalive();
    this.keepaliveTimer = setInterval(() => {
      this.sendFlap(FlapChannel.KeepAlive, Buffer.alloc(0));
    }, KEEPALIVE_INTERVAL_MS);
    this.keepaliveTimer.unref?.();
  }

  private stopKeepalive(): void {
    if (this.keepaliveTimer) {
      clearInterval(this.keepaliveTimer);
      this.keepaliveTimer = null;
    }
  }

  /** Graceful sign-off: send a channel-4 frame then close. */
  signOff(): void {
    if (this.closed) return;
    this.closed = true;
    this.stopKeepalive();
    try {
      this.sendFlap(FlapChannel.SignOff, Buffer.alloc(0));
    } finally {
      this.socket?.end();
    }
  }

  destroy(): void {
    this.closed = true;
    this.stopKeepalive();
    this.socket?.destroy();
  }
}
