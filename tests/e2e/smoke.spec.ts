import { expect, test, _electron as electron } from '@playwright/test';

/**
 * E2E smoke: the packaged app boots, shows the sign-in screen, and can
 * create an account + sign in against a local Open OSCAR Server (5190,
 * DISABLE_AUTH). Run `pnpm build` first; server must be listening unless
 * SKIP_OSCAR_INTEGRATION=1 (then only the shell render is checked).
 */
test('shell boots to sign-in and signs on to AIM', async () => {
  const app = await electron.launch({
    args: ['out/main/index.js', '--no-sandbox'],
    env: { ...process.env, PAPILLON_TEST_USER_DATA: '1' }
  });
  const win = await app.firstWindow();
  await win.waitForLoadState('domcontentloaded');

  // Sign-in screen renders with the butterfly branding.
  await expect(win.getByText('Welcome to papillon')).toBeVisible();
  await expect(win.getByText('Add new user')).toBeVisible();
  await win.screenshot({ path: 'tests/e2e/artifacts/signin.png' });

  if (process.env.SKIP_OSCAR_INTEGRATION !== '1') {
    // Create an account against the local test server and sign in.
    await win.getByText('Add new user').click();
    await win.getByLabel('Screen name').fill(`e2e${Date.now().toString(36).slice(-5)}`);
    await win.getByLabel('Password', { exact: true }).fill('hunter2');
    await win.getByRole('button', { name: /Create & Sign In/ }).click();

    // The shell chrome appears once we're online.
    await expect(win.getByRole('button', { name: 'Home' })).toBeVisible({ timeout: 20_000 });
    await expect(win.getByText('Online')).toBeVisible({ timeout: 20_000 });
    await win.screenshot({ path: 'tests/e2e/artifacts/shell.png' });

    // Pane switching works.
    await win.getByRole('button', { name: 'Music', exact: true }).click();
    await expect(win.getByText('MSN Music — no track loaded')).toBeVisible();

    // Chat pane: add a buddy to the server-side list…
    await win.getByRole('button', { name: 'Chat' }).click();
    await expect(win.getByText('My Status')).toBeVisible();
    await win.getByPlaceholder('Screen name').fill('chatpal');
    await win.getByRole('button', { name: 'Add Buddy' }).click();
    await expect(win.getByText('chatpal added.')).toBeVisible({ timeout: 10_000 });
    await win.screenshot({ path: 'tests/e2e/artifacts/chat-pane.png' });

    // …and double-click it to open an AIM-style chat window.
    const chatWindowPromise = app.waitForEvent('window');
    await win.getByRole('button', { name: /chatpal/ }).first().dblclick();
    const chatWin = await chatWindowPromise;
    await chatWin.waitForLoadState('domcontentloaded');
    await expect(chatWin.getByPlaceholder('Type a message and press Enter')).toBeVisible();
    await chatWin.getByPlaceholder('Type a message and press Enter').fill('hey — you around? 🙂');
    await chatWin.keyboard.press('Enter');
    // Our own line renders in the log (delivery is covered by integration tests).
    await expect(chatWin.getByText('hey — you around? 🙂')).toBeVisible();
    await chatWin.screenshot({ path: 'tests/e2e/artifacts/chat-window.png' });
  }

  await app.close();
});
