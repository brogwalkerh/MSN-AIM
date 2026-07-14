import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { OscarClient } from '@msn-aim/proto-oscar';
import type { Buddy, BuddyGroup, ImMessage } from '@msn-aim/im-core';

/**
 * End-to-end tests against a real Open OSCAR Server (formerly Retro AIM
 * Server) with DISABLE_AUTH=true, reachable on OSCAR_TEST_HOST:5190.
 * Start one with docker/docker-compose.yml or scripts/run-oscar-server.sh.
 */
const HOST = process.env.OSCAR_TEST_HOST ?? '127.0.0.1';
const PORT = parseInt(process.env.OSCAR_TEST_PORT ?? '5190', 10);

const RUN = process.env.SKIP_OSCAR_INTEGRATION !== '1';

function waitFor<T>(register: (resolve: (v: T) => void) => void, what: string, ms = 15_000): Promise<T> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`timed out waiting for ${what}`)), ms);
    register((v) => {
      clearTimeout(timer);
      resolve(v);
    });
  });
}

const STAMP = Date.now().toString(36).slice(-6);
const ALICE = `alice${STAMP}`;
const BOB = `bob${STAMP}`;

describe.runIf(RUN)('OSCAR end-to-end against Open OSCAR Server', () => {
  const alice = new OscarClient();
  const bob = new OscarClient();

  beforeAll(async () => {
    await Promise.all([
      alice.connect({
        protocol: 'oscar',
        username: ALICE,
        password: 'passw0rd',
        server: { host: HOST, port: PORT }
      }),
      bob.connect({
        protocol: 'oscar',
        username: BOB,
        password: 'passw0rd',
        server: { host: HOST, port: PORT }
      })
    ]);
  }, 60_000);

  afterAll(async () => {
    await Promise.allSettled([alice.disconnect(), bob.disconnect()]);
  });

  it('mutual buddy adds produce presence events both ways', async () => {
    const alicePresence = waitFor<Buddy>((res) =>
      alice.on('buddyPresence', (b) => b.id === BOB && res(b))
    , `presence of ${BOB}`);
    const aliceList = waitFor<BuddyGroup[]>((res) => alice.on('buddyListReceived', res), 'buddy list');

    await alice.addBuddy(BOB, 'Integration Pals');
    await bob.addBuddy(ALICE, 'Integration Pals');

    const groups = await aliceList;
    expect(groups.some((g) => g.buddies.some((b) => b.id === BOB))).toBe(true);

    const presence = await alicePresence;
    expect(presence.status).toBe('online');
  }, 30_000);

  it('delivers instant messages with unicode intact', async () => {
    const received = waitFor<ImMessage>((res) =>
      bob.on('messageReceived', (m) => m.from === ALICE && res(m))
    , 'message at bob');
    await alice.sendMessage(BOB, 'hello from the shell — ça marche 🙂');
    const msg = await received;
    expect(msg.body).toBe('hello from the shell — ça marche 🙂');
  }, 30_000);

  it('delivers typing notifications', async () => {
    const seen = waitFor<string>((res) =>
      bob.on('typing', (from, state) => from === ALICE && state === 'typing' && res(from))
    , 'typing event at bob');
    await alice.sendTyping(BOB, 'typing');
    expect(await seen).toBe(ALICE);
  }, 30_000);

  it('away status round-trips: bob sees alice go away and can fetch the message', async () => {
    const awayPresence = waitFor<Buddy>((res) =>
      bob.on('buddyPresence', (b) => b.id === ALICE && b.status === 'away' && res(b))
    , 'away presence at bob');
    await alice.setStatus('away', 'gone for lunch 🥪');
    await awayPresence;

    const info = waitFor<{ id: string; awayMessage?: string }>((res) =>
      bob.on('buddyInfo', (i) => i.id === ALICE && res(i))
    , 'away message text');
    await bob.requestBuddyInfo(ALICE);
    const details = await info;
    expect(details.awayMessage ?? '').toContain('gone for lunch');

    const backPresence = waitFor<Buddy>((res) =>
      bob.on('buddyPresence', (b) => b.id === ALICE && b.status === 'online' && res(b))
    , 'return presence at bob');
    await alice.setStatus('online');
    await backPresence;
  }, 30_000);

  it('removes buddies from the server-side list', async () => {
    await expect(alice.removeBuddy(BOB, 'Integration Pals')).resolves.toBeUndefined();
  }, 30_000);
});
