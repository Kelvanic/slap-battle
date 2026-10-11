# Slap Battle

A Mac menu-bar game with preset slap effects, private crew rooms, and an opt-in arena.

## Run locally

```bash
cd relay
bun install
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

The first connection assigns a unique random username. The Mac generates a 32-byte secret and stores it under the fixed `Kelvanic SlapBattle v1` service in the current user's non-synchronizing, device-only Keychain. It is sent only in the first WebSocket message, never in a URL or log. The relay stores the credential's SHA-256 hash and permanent username in SQLite, not the raw credential.

Deleting the app or its normal application data does not delete the Keychain item. Reinstalling a consistently signed build in the same macOS account recovers the credential and username. Names cannot be rerolled. Opening a second copy replaces the earlier connection; the earlier client pauses rather than endlessly reconnecting.

This is a local credential, not hardware fingerprinting. No serial number or MAC address is collected. A different macOS account gets another identity. Deleting/resetting the Keychain, erasing the Mac, or losing the relay database can lose the identity; reinstall alone does not. A copied credential can impersonate its owner, so do not share it. Current session counters and activity are not persisted.

## Relay storage and deployment

The relay's SQLite registry lives in its `DATA_DIR`. The Docker image uses `/data`; Coolify must mount the named `slap-identities` volume there and run one replica. Keep that volume and its database backed up. Container replacement does not erase a correctly mounted registry; deleting the volume does. WAL and SHM files belong with the database during operation—use a SQLite-consistent backup rather than blindly copying a live DB file.

## Panel

Native light/dark surfaces, desaturated avatars, and one adaptive slate accent replace neon gradients. Counters, weapon selection, and slap effects retain their motion. The panel stays clipped to its rounded edges.

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

`cd relay && bun test.ts` exercises identity reconnect/recovery and gameplay on an isolated local relay. Tests use their own temporary credentials and database fixtures. Do not run capacity tests against the shared live arena. Public names and counts show attention/presence, not real-world personal identity.
