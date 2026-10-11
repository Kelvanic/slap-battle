# Slap Battle

A Mac menu-bar game with preset slap effects, private crew rooms, and an opt-in arena.

<img src="mac/Assets/AppIcon.png" width="128" alt="Slap Battle app icon: an illustrated high-five hand on a slate tile">

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

Keep the bundle identifier `com.kelvanic.slapbattle` and signing identity consistent between releases so macOS can authorize the same Keychain item. Without `SLAP_SIGN_IDENTITY`, packaging uses an ad-hoc signature for development only. Release artifacts are Developer ID-signed; notarization status must be checked in the release notes.

### App artwork

The original illustrated app icon is bundled as `Contents/Resources/SlapBattle.icns`
before signing. It is referenced by `CFBundleIconFile` for Finder and app packages.
To regenerate all native sizes from the code-owned vector drawing:

```bash
cd mac
swift Tools/GenerateIcon.swift Assets
iconutil -c icns Assets/SlapBattle.iconset -o Assets/SlapBattle.icns
```

The menu-bar status icon remains a monochrome system symbol for readability.
The published v1.0.0 download assets are immutable and do not include this later
artwork; build from current source or use the next release for the illustrated icon.

## CI, releases, and deployment

Source and downloads are public at [Kelvanic/slap-battle](https://github.com/Kelvanic/slap-battle).
Official distribution packages appear in [GitHub Releases](https://github.com/Kelvanic/slap-battle/releases).
Notarization is required by default. The owner explicitly approved **v1.0.0 as
Developer ID-signed but not notarized** while Apple credentials are unavailable.
This release has not been checked by Apple's notarization service.

- `CI`: pull requests, main pushes, and version tags run strict relay typechecks,
  Docker build, 22 protocol checks against an isolated TLS PostgreSQL container,
  and debug/release builds on Apple Silicon and Intel macOS runners. No production
  database credentials are required. Run `./relay/ci-check.sh` locally with Bun,
  Docker, and OpenSSL.
- `Deploy relay`: successful main-push CI triggers Coolify deployment. Direct
  push deployments in Coolify are disabled. The workflow refuses a stale checked
  commit when main has moved. Manual deployments also require successful CI.
- `Release`: push an existing release commit as `vMAJOR.MINOR.PATCH` (for example
  `git tag v0.1.0 && git push origin v0.1.0`) or manually select an existing tag.
  Successful CI for that exact commit is required. Both architectures must produce
  accepted Apple notarizations and stapled packages before the automated workflow publishes.

Each release contains `SlapBattle-VERSION-macos-arm64.dmg`, an app ZIP,
the corresponding `x86_64` DMG/ZIP, and `SHA256SUMS`. Choose arm64 for Apple Silicon,
x86_64 for Intel. These are separate architecture packages, not a universal binary.
The app checks the public GitHub latest-release endpoint at launch and every six
hours while running. It offers only a newer stable version with an uploaded DMG
for the running architecture; drafts, prereleases, and equal/older versions are
not offered. The panel shows a new-version card with release notes and a download
link. App options include **Check for updates** and **Enable update notifications**.
System notifications are opt-in; a successful notification is remembered locally
and isn't repeated for that version. If permission is denied, the update card
still works. Automatic checks do not prompt for notification permission.

Updates are manual: the buttons open GitHub in the browser, and the user reviews
the notes and installs the package. No executable is automatically downloaded or
replaced. GitHub receives ordinary network requests including your IP address and
app version; device credentials and usernames are never included. No GitHub login
or API token is needed. Notification preferences/deduplication are stored in the
app's UserDefaults, separate from the permanent identity in Keychain.

The original v1.0.0 assets do not contain update notifications or the later app
icon. These features are in current source and the next packaged release.

### Installing the signed-only v1.0.0 release

Download the package for your Mac, open the DMG, and drag SlapBattle to Applications.
Gatekeeper may block first launch because **v1.0.0 is not notarized**. Only if you
trust the source and have verified the download, attempt to open the installed
app, then choose System Settings → Privacy & Security → Open Anyway and confirm
Open. This approves only Slap Battle; do not disable Gatekeeper or SIP, remove
quarantine recursively, or override malware/damaged-app warnings.
[Apple's guidance](https://support.apple.com/en-us/102445) explains this exception
and notes that managed Macs may prohibit it. Notarization is still the preferred
distribution path.

Local signed-only packaging requires explicit `SLAP_ALLOW_UNNOTARIZED=1` alongside
the version, build number, architecture, and Developer ID signing identity. It
does not skip code signing and must never be described as notarized. The v1.0.0
tag is excluded from automatic packaging because it is released manually under
this exception. All other automatic tag releases still require notarization.

### Required GitHub configuration

Deployment secrets/variables: `COOLIFY_TOKEN`, `COOLIFY_URL`, `COOLIFY_APP_UUID`.
Store deployment credentials only in GitHub secrets; use a narrowly scoped Coolify
deploy token when available. Configure the `production` environment as appropriate.

Configure the `release` environment with:

| Secret | Value |
| --- | --- |
| `APPLE_CERTIFICATE_P12` | Base64 Developer ID certificate **and private key** export |
| `APPLE_CERTIFICATE_PASSWORD` | Password protecting that export |
| `APPLE_SIGNING_IDENTITY` | Exact Developer ID Application signing identity |
| `APPLE_NOTARY_KEY_ID` | App Store Connect API key ID |
| `APPLE_NOTARY_ISSUER_ID` | App Store Connect issuer ID |
| `APPLE_NOTARY_PRIVATE_KEY` | Corresponding `.p8` private key contents |

Do not commit these values. Hosted runners need the P12; the local Keychain is not
uploaded automatically. Release tooling deletes its temporary keychain and private
key files after use. Missing signing/notarization credentials fail the release.
For local releases, use `SLAP_NOTARY_PROFILE` instead of the three API-key secrets.
Set `SLAP_VERSION`, `SLAP_BUILD_NUMBER`, and `SLAP_ARCH`, then run `mac/release.sh`.

Require pull requests and successful `Relay checks` plus both `Mac build` checks
on main. Do not use production `DATABASE_URL` in CI. Never publish an unsigned
package as a substitute for a failed notarized release.

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

Cutover on 2026-10-11 imported all nine source identity mappings unchanged. A
consistent additional snapshot is retained on the VM at
`/var/lib/docker/volumes/lprjtzxw20a1qwtnx4yamduu-slap-identities/_data/identities-before-neon-20261011.sqlite`
with owner-only permissions. This snapshot is recovery data, not an active fallback.
An isolated Neon branch verified repeated imports, transactional rollback on
conflicts, and 22 identity/gameplay checks. The deployed relay recovered a
pre-migration credential's original username, and all nine Postgres mappings were
compared exactly with the frozen source before temporary test data was removed.

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
