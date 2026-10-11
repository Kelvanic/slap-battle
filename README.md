# Slap Battle

A Mac menu-bar game with preset slap effects, private crew rooms, and an opt-in arena.

## Run locally

```bash
cd relay
bun install
export DATABASE_URL='your pooled Neon Postgres connection string'
bun server.ts
```

In another terminal:

```bash
cd mac
SLAP_RELAY_URL=ws://localhost:8787 swift run
```

The Mac app defaults to the deployed `wss://lprjtzxw20a1qwtnx4yamduu.167.233.108.153.sslip.io` relay. Unencrypted WebSockets are allowed only for literal localhost/loopback development targets; remote connections require WSS.

## Build an installable Mac app

```bash
cd mac
SLAP_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' ./build-app.sh
open .build/SlapBattle.app
```

Keep the bundle identifier `com.kelvanic.slapbattle` and signing identity consistent between releases so macOS can authorize the same Keychain item. Without `SLAP_SIGN_IDENTITY`, packaging uses an ad-hoc signature for development only. Developer ID signing is supported here; notarization and public distribution are separate steps and have not been completed.

## Persistent names

The first connection assigns a unique random username. The Mac generates a 32-byte secret and stores it under the fixed `Kelvanic SlapBattle v1` service in the current user's non-synchronizing, device-only Keychain. It is sent only in the first WebSocket message, never in a URL or log. The relay stores the credential's SHA-256 hash and permanent username in Neon Postgres, not the raw credential.

Deleting the app or its normal application data does not delete the Keychain item. Reinstalling a consistently signed build in the same macOS account recovers the credential and username. Names cannot be rerolled. Opening a second copy replaces the earlier connection; the earlier client pauses rather than endlessly reconnecting.

This is a local credential, not hardware fingerprinting. No serial number or MAC address is collected. A different macOS account gets another identity. Deleting/resetting the Keychain, erasing the Mac, or losing the relay database can lose the identity; reinstall alone does not. A copied credential can impersonate its owner, so do not share it. Current session counters and activity are not persisted.

## Relay storage and deployment

The live registry is `slap_battle.identities` in Neon project `round-leaf-55541591`
(`slapbattle`), branch `production`. Set `DATABASE_URL` as a runtime-only Coolify
secret using the pooled connection. The relay verifies TLS and fails closed if
Postgres is unavailable; it never silently falls back to SQLite or assigns a
replacement name on a database error. The managed Neon Auth configuration is
separate from the game's device-credential protocol.

The original SQLite volume `lprjtzxw20a1qwtnx4yamduu-slap-identities` remains mounted
at `/data` on the Coolify VM as a frozen recovery copy. The new relay does not
write to it. It covers mappings present at cutover, not names created afterward.
Keep Neon recovery/history and database backups configured for ongoing protection.

### SQLite import

Take a SQLite-consistent snapshot including any WAL data and pause the old writer
for the final snapshot before switching backends. Use a direct, non-pooled Neon
connection for the importer:

A serialized standalone SQLite copy may retain its WAL-mode header. Normalize
only the private snapshot copy with `sqlite3 snapshot.sqlite 'PRAGMA journal_mode=DELETE;'`
before importing; do not change the live source database or discard its WAL.

```bash
cd relay
MIGRATION_DATABASE_URL='your direct Neon connection' bun migrate-sqlite.ts /private/path/identities.sqlite
```

The importer validates every source row, imports in a single transaction, checks
every hash/name pair, and prints only counts and a digest. Rerunning an identical
snapshot is idempotent. A conflicting hash or username aborts rather than
renaming anybody. Never commit database URLs, Keychain credentials, or snapshots.
`schema.sql` is the code-owned, idempotent schema used by the relay and importer.

## Panel

Native light/dark surfaces, desaturated avatars, and one adaptive slate accent keep
the panel restrained. A compact identity header and mode selector lead to one
primary action. Player rows stay lightweight; activity is collapsed by default,
and acknowledged sent/received counts live in the footer. Pause effects stays
immediately accessible. The bounded player list measures its content directly
so a small list does not collapse or leave a large empty viewport.

The menu-bar button opens an AppKit transient popover whose size follows the SwiftUI
content. This avoids the oversized translucent top/bottom regions of the previous
menu-window container. Opening the installed app again also opens the panel.

Reference layouts inspected through Mobbin:
- [Discord online friends](https://mobbin.com/screens/1bbbfcde-0540-4270-b7cb-1cfe2dd6baad) — compact avatar rows and trailing actions.
- [Slack profile panel](https://mobbin.com/screens/85e7842e-17c6-4dca-92eb-af34f54250af) — grouped identity and status.
- [Navattic command menu](https://mobbin.com/screens/c65971cf-c4ea-45e9-99a5-555930cb5d73) — quiet section grouping and secondary chrome.

## Protocol

- First message: `identify {token}`. No gameplay before authentication.
- `hello`: permanent username, modes, and preset slap kinds.
- `set_mode {mode, room?}`: private, crew with room code, or arena. Each connection starts private.
- `presence`: an arena sample of at most eight peers, or up to fifty crew peers; includes total count.
- `count`: coalesced arena count updates, independent of the sample size.
- `shuffle`: refresh the sample.
- `slap {to, kind}` or `slap_random {kind}`; `slapped`, `slap_ok`, or `slap_miss` result.
- `mute`, `block {name}`, `report {name}`.

The server enforces a 1.5-second sender-to-target cooldown, twelve incoming slaps per minute per target, twenty outgoing per minute per sender, and a three-distinct-reporter kick. Identity persists; blocks/reports/cooldowns are currently session state, not a durable moderation system.

## Safety

Only preset effects; no custom messages, images, or audio. Solo mode accepts no slaps. Panic hides effects; it does not disconnect the session. Screen-sharing/Focus auto-pause is not implemented: use Solo or Panic before presenting. TLS is necessary to protect the device credential in transit. This is an early private test game, not a production moderation guarantee.

## Verification

Run `DATABASE_URL='your isolated test-branch connection' bun test.ts` from `relay/`.
The suite starts its own local relays and deletes only the randomly generated test
identities it created. Use a disposable Neon branch, not production. It exercises
concurrent identity claims, persistence across store reopen, database failure,
private/crew/arena behavior, and duplicate-socket replacement. Migration validation
should also prove idempotency and full rollback on conflicting mappings.
Do not run capacity tests against the shared live arena. Public names and counts
show presence, not real-world personal identity.
