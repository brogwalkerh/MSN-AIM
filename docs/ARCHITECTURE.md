# Architecture

Papillon recreates the MSN Explorer all-in-one shell (browser, IM, mail, media, portal
home page) as an Electron + TypeScript app, with AIM as the flagship IM protocol via a
from-scratch OSCAR implementation.

```
┌─────────────────────────── Electron main process ───────────────────────────┐
│  ImService ──────────► ImProtocolClient (im-core contract)                  │
│    │                     ├── OscarClient (proto-oscar: node:net → FLAP/SNAC)│
│    │                     └── MsnpClient  (proto-msnp: stub, planned)        │
│  MailService (imapflow/nodemailer)   MediaService (media:// protocol)       │
│  HomeService (RSS + open-meteo)      BrowserPaneController (WebContentsView)│
│  ChatWindowManager (BrowserWindow per conversation)                         │
└───────────────┬──────────────── typed IPC (shared/ipc-contract) ────────────┘
                │ invoke/handle + broadcast events
┌───────────────▼──────────────── sandboxed renderers ────────────────────────┐
│  shell/  — sign-in tiles, MSN chrome, Home/Browser/Mail/Chat/Media panes    │
│  chat/   — AIM-style conversation windows                                   │
└──────────────────────────────────────────────────────────────────────────────┘
```

## Rules that keep this sane

- **All sockets live in the main process.** `packages/*` are pure Node/TS with zero
  Electron imports — the protocol stack runs (and is tested) without Electron.
- **Renderers are sandboxed** (`contextIsolation`, `sandbox: true`, no node). The only
  bridge is `window.papillon` (generic typed `invoke`/`on`), and the contract lives in
  one file: `packages/shared/src/ipc-contract.ts`. Add a channel there and both sides
  type-check.
- **The embedded browser is a `WebContentsView`** owned by main (`<webview>` is
  deprecated). The renderer draws a placeholder div and streams its rect via
  `browser:setBounds`; anything that must overlay the browser hides it first via
  `browser:setVisible` — the view always composites above the renderer.
- **Chat windows are separate frameless `BrowserWindow`s** pooled by
  `accountId:buddyId`. Each window asks `im:getChatContext` who it is; contexts are
  keyed by `webContents.id` in main, so a window can never impersonate another
  conversation.
- **OSCAR text is not UTF-8.** Outgoing picks ASCII → ISO-8859-1 → UCS-2BE; incoming
  decodes by the charset word in the ICBM fragment. See
  `proto-oscar/src/codec/charset.ts` and its tests before touching message code.
- **Every outbound SNAC goes through the RateLimiter** (`BosSession.send`). Revival
  servers enforce the classic rate classes and will disconnect chatty clients.
- **Assets are original.** The butterfly, icons and skin are hand-drawn SVG/CSS in this
  repo evoking the era's style. Do not import Microsoft or AOL artwork, sounds, or
  binaries.

## Testing layers

1. `pnpm test` — codec round-trips + a scripted fake OSCAR server driving
   `OscarClient` end-to-end over loopback TCP (login, multi-frame Feedbag, ICBM echo,
   typing, mutations, auth failure).
2. `pnpm test:integration` — the same client against a **real Open OSCAR Server**
   (docker compose or `scripts/run-oscar-server.sh`): presence both ways, unicode IMs,
   typing, away round-trip, list mutations.
3. `pnpm build && pnpm exec playwright test` — boots the actual app (xvfb on CI),
   creates an account, signs on to the local server, switches panes, screenshots.
