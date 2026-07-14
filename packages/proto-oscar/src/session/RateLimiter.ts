import { ByteReader } from '../wire/bytebuf';
import { createLogger } from '@msn-aim/shared';

const log = createLogger('oscar:rate');

export interface RateClass {
  id: number;
  windowSize: number;
  clearLevel: number;
  alertLevel: number;
  limitLevel: number;
  disconnectLevel: number;
  currentLevel: number;
  maxLevel: number;
}

/**
 * OSCAR rate limiting (OSERVICE 01,07). Servers compute a rolling average
 * of inter-send intervals per rate class:
 *   newLevel = (oldLevel * (window - 1) + msSinceLastSend) / window
 * and disconnect clients whose level sinks below disconnectLevel. All
 * outbound SNACs flow through waitForSend(), which delays just enough to
 * stay above the alert level. Revival servers really do enforce this.
 */
export class RateLimiter {
  private classes = new Map<number, RateClass>();
  private classBySnac = new Map<number, number>(); // (foodgroup<<16|subtype) -> classId
  private lastSendAt = new Map<number, number>();
  private levels = new Map<number, number>();
  private pauseUntil = new Map<number, number>();
  /** Safety margin above the alert level, in level units. */
  private static readonly MARGIN = 100;

  /** Parse the 01,07 rate params reply body. */
  parseRateParams(body: Buffer): void {
    const r = new ByteReader(body);
    const count = r.u16();
    const classes: RateClass[] = [];
    for (let i = 0; i < count; i++) {
      const id = r.u16();
      const windowSize = r.u32();
      const clearLevel = r.u32();
      const alertLevel = r.u32();
      const limitLevel = r.u32();
      const disconnectLevel = r.u32();
      const currentLevel = r.u32();
      const maxLevel = r.u32();
      // Protocol v3+ appends lastTime u32 + currentState u8.
      if (r.remaining >= 5) {
        r.u32();
        r.u8();
      }
      classes.push({
        id,
        windowSize,
        clearLevel,
        alertLevel,
        limitLevel,
        disconnectLevel,
        currentLevel,
        maxLevel
      });
    }
    for (const c of classes) {
      this.classes.set(c.id, c);
      this.levels.set(c.id, c.currentLevel);
    }
    // Rate groups: classId u16, pairCount u16, then (foodgroup u16, subtype u16) pairs.
    while (r.remaining >= 4) {
      const classId = r.u16();
      const pairCount = r.u16();
      for (let i = 0; i < pairCount && r.remaining >= 4; i++) {
        const foodgroup = r.u16();
        const subtype = r.u16();
        this.classBySnac.set(((foodgroup << 16) | subtype) >>> 0, classId);
      }
    }
    log.debug(`rate params: ${classes.length} classes, ${this.classBySnac.size} snac mappings`);
  }

  classIds(): number[] {
    return [...this.classes.keys()];
  }

  /** Called on 01,10 rate warnings: pause the class until it recovers. */
  noteWarning(classId: number, code: number): void {
    const cls = this.classes.get(classId);
    if (!cls) return;
    // code 2 = limit reached, 3 = limit + disconnect imminent
    const backoffMs = code >= 3 ? cls.windowSize * 50 : cls.windowSize * 25;
    this.pauseUntil.set(classId, Date.now() + backoffMs);
    log.warn(`rate warning class=${classId} code=${code}; pausing sends ${backoffMs}ms`);
  }

  /**
   * Compute how long to wait before sending the given SNAC, and account
   * for the send. Returns delay in ms (0 = go now).
   */
  reserveSend(foodgroup: number, subtype: number, now = Date.now()): number {
    const classId = this.classBySnac.get(((foodgroup << 16) | subtype) >>> 0);
    if (classId === undefined) return 0;
    const cls = this.classes.get(classId);
    if (!cls || cls.windowSize === 0) return 0;

    let sendAt = now;
    const pausedUntil = this.pauseUntil.get(classId) ?? 0;
    if (pausedUntil > sendAt) sendAt = pausedUntil;

    const last = this.lastSendAt.get(classId);
    const level = this.levels.get(classId) ?? cls.maxLevel;
    if (last !== undefined) {
      const threshold = cls.alertLevel + RateLimiter.MARGIN;
      // Find the earliest send time keeping newLevel >= threshold.
      const gap = sendAt - last;
      const projected = this.projectLevel(cls, level, gap);
      if (projected < threshold) {
        const requiredGap = threshold * cls.windowSize - level * (cls.windowSize - 1);
        sendAt = last + Math.max(requiredGap, gap);
      }
      const newLevel = this.projectLevel(cls, level, sendAt - last);
      this.levels.set(classId, Math.min(newLevel, cls.maxLevel));
    }
    this.lastSendAt.set(classId, sendAt);
    return Math.max(0, sendAt - now);
  }

  private projectLevel(cls: RateClass, oldLevel: number, gapMs: number): number {
    return Math.floor((oldLevel * (cls.windowSize - 1) + gapMs) / cls.windowSize);
  }
}
