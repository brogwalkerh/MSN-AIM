# MSN Messenger (MSNP) Support — Design Plan

AIM/OSCAR is Papillon's first fully implemented protocol. MSN Messenger is the second,
designed here and stubbed in `packages/proto-msnp` (`MsnpClient` implements
`ImProtocolClient` and declares its capability manifest, so the UI already knows how to
treat MSN accounts).

## Target service & dialect

- **Server**: [Escargot](https://escargot.chat/) — the live MSN Messenger revival.
  Notification server `m1.escargot.chat`, TCP **1863** (already a preset in
  `packages/shared/src/config.ts`).
- **Protocol version**: **MSNP12** first. It predates the Passport/SSO ("Tweener"/RST)
  machinery of MSNP13+, uses the simpler MD5 challenge (`USR I`/`USR S` with MSNP2-style
  auth on Escargot), and covers everything our `ImProtocolClient` contract needs:
  presence, forward/allow/block lists with groups, switchboard IMs, typing.
- **Dialect authority**: Escargot's open-source server
  (`gitlab.com/escargot-chat/server`) — read its `msn` front-end handlers rather than
  trusting decade-old fan docs when behavior differs.

## Wire model (vs OSCAR)

MSNP is a line-based, TRID-tagged command stream, not binary FLAP/SNAC:

```
>>> VER 1 MSNP12 CVR0\r\n
<<< VER 1 MSNP12\r\n
>>> CVR 2 0x0409 winnt 5.1 i386 MSNMSGR 7.0.0777 msmsgs user@example.com\r\n
<<< CVR 2 ...\r\n
>>> USR 3 TWN I user@example.com          (Escargot: MD5/legacy auth variant)
<<< USR 3 TWN S <challenge>
>>> USR 4 TWN S <response>
<<< USR 4 OK user@example.com ...
```

Payload commands (`MSG`, `UBX`, …) carry a byte count and a MIME body — the parser needs
a "read N bytes after this line" mode, the moral equivalent of our FLAP frame
reassembly.

### Module skeleton (mirrors proto-oscar)

```
packages/proto-msnp/src/
├── wire/lines.ts         # TRID allocator + line/payload stream parser
├── session/NsSession.ts  # notification-server state machine
├── session/Switchboard.ts# one per conversation (XFR/ANS/CAL/JOI lifecycle)
├── codec/msg.ts          # MIME message bodies: text/plain, TypingUser control
└── MsnpClient.ts         # ImProtocolClient facade (exists today as a stub)
```

## Mapping onto `ImProtocolClient`

| Contract              | MSNP12 realization                                                    |
| --------------------- | --------------------------------------------------------------------- |
| `connect`             | VER → CVR → USR handshake; `SYN` to fetch lists; resolves on first `CHG` ack |
| buddy list + groups   | `SYN` reply: `LSG` groups, `LST` contacts with FL/AL/BL membership bits |
| `addBuddy/removeBuddy`| `ADC FL N=… C=<groupId>` / `REM FL <contact> <groupId>`                |
| presence events       | `ILN` (initial), `NLN` (online/status change), `FLN` (offline)         |
| own status            | `CHG <TRID> NLN|BSY|AWY|IDL|BRB|PHN|LUN [caps]`                        |
| `sendMessage`         | switchboard: `XFR SB` → connect+`USR`, `CAL` buddy, `MSG A` text/plain |
| incoming messages     | `RNG` invite → connect+`ANS`, then `MSG` events                        |
| `sendTyping`          | `MSG U` with `Content-Type: text/x-msmsgscontrol` + `TypingUser:` header |
| away message text     | not in MSNP12 (PSM arrives with MSNP11+ `UUX`); capability flag stays false |
| `offlineMessages`     | OIM is out of scope for milestone 1; capability false                  |

**The structural difference to plan for**: OSCAR has one BOS connection; MSNP spawns a
**switchboard TCP session per conversation**. `MsnpClient` must own a
`Map<conversationKey, Switchboard>` with idle timeouts, re-`XFR` on send-after-close, and
`RNG` acceptance — this lifecycle is the main new complexity, and it stays hidden behind
`sendMessage()/messageReceived` so the UI never sees it.

## Milestones

1. **N1** — wire codec + NS handshake against Escargot; `sessionState` events.
2. **N2** — `SYN` list sync mapped to `buddyListReceived`; ILN/NLN/FLN presence.
3. **N3** — switchboard send/receive + typing; chat windows work unchanged.
4. **N4** — list mutations (ADC/REM/ADG), status changes (CHG), block/allow.
5. **N5** — hardening: reconnect, Escargot quirks, integration tests against a
   self-hosted Escargot server in docker (their repo ships one).

## Risks

- **Escargot auth drift**: they patch clients; verify the exact `USR` variant Escargot
  accepts for MSNP12 from their server source before building auth.
- **Switchboard lifecycle leaks**: cap concurrent switchboards, close on window close.
- **Charset**: MSNP bodies are UTF-8 (unlike OSCAR!) — do not reuse the OSCAR codec.
- **Rate limiting**: Escargot enforces flood limits server-side; reuse the token-bucket
  shape from `proto-oscar/session/RateLimiter` with MSNP-appropriate constants.
