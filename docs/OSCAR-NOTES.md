# OSCAR crib sheet

Working notes for `packages/proto-oscar`. Authoritative references:

- **NINA Wiki** — https://wiki.nina.chat/wiki/Protocols/OSCAR (the maintained spec,
  derived from AOL's 2008 docs; per-SNAC pages for every foodgroup)
- **iserverd docs mirror** — https://ox.github.io/iserverd-oscar-mirror/ (byte-level
  FLAP/SNAC/TLV layouts)
- **Open OSCAR Server source** — https://github.com/mk6i/open-oscar-server (executable
  ground truth; our default/test server)

## Framing

```
FLAP:  0x2A | channel u8 | sequence u16 | length u16 | payload
  ch1 = connection negotiation (hello u32=1, + TLV 0x06 cookie on BOS)
  ch2 = SNAC   ch4 = close (TLV 0x09 = error code)   ch5 = keepalive (60s)

SNAC:  foodgroup u16 | subtype u16 | flags u16 | requestId u32 | body
  flags & 0x0001 → another reply with same requestId follows (multi-frame 13,06!)
  flags & 0x8000 → u16-length block prepended to body — skip it

TLV:   type u16 | length u16 | value
```

## Sign-on sequence (what BosSession does)

```
auth conn:  hello → 17,06 (sn) → 17,07 (MD5 key) → 17,02 → 17,03
            TLV 0x05 = BOS host:port, 0x06 = cookie, 0x08 = error code
            hash = md5(key + password + "AOL Instant Messenger (SM)")   [TLV 0x25]
bos conn:   hello+cookie → 01,03 (host online) → 01,17/01,18 (versions)
            → 01,06/01,07/01,08 (rate params; feed the RateLimiter)
            → 02,02 / 03,02 / 04,04→04,05→04,02 (rights + ICBM params)
            → 13,05 → 13,06×N (Feedbag) → 13,07 (activate)
            → 02,04 (caps/profile) → 01,02 (client-online) → ONLINE
```

## Cheat table

| Thing              | SNAC / format                                                       |
| ------------------ | ------------------------------------------------------------------- |
| send IM            | 04,06: cookie8, channel u16=1, sn p8, TLV 0x02 (frag 5 caps + frag 1 charset/text), TLV 0x06 store-offline, TLV 0x04 auto-response |
| recv IM            | 04,07: cookie8, channel, **userinfo block**, then message TLVs      |
| typing (MTN)       | 04,14: cookie8, channel u16=1, sn p8, u16 (0 stop / 1 typed / 2 typing) |
| buddy arrived/left | 03,0B / 03,0C: userinfo block                                       |
| userinfo block     | sn p8, warning u16, tlvCount u16, TLVs (0x01 class — 0x20=away; 0x03 signon; 0x04 idle min) |
| away message       | set: 02,04 TLV 0x03 mime + 0x04 text ("" clears). fetch: 02,05 type 3 → 02,06 |
| idle               | 01,11 u32 seconds (0 clears)                                        |
| Feedbag item       | name p16, groupId u16, itemId u16, classId u16, tlvLen u16 + TLVs (0=buddy 1=group 2=permit 3=deny; 0x0131 alias, 0xC8 group children) |
| Feedbag mutate     | 13,11 begin → 13,08/09/0A → 13,0E acks (u16 per item, 0=ok) → 13,12 end |
| charsets           | 0x0000 ASCII · 0x0002 UCS-2BE · 0x0003 ISO-8859-1 — **never UTF-8** |

## Servers

- Local dev: Open OSCAR Server, everything on `127.0.0.1:5190`, REST API `:8080`
  (`POST /user` to create accounts when `DISABLE_AUTH=false`).
- Public: NINA — `login.oscar.nina.chat:5190` (sign-in preset in the app).
