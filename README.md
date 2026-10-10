# Slap Battle 👏

Weekend build: slap your friends' Macs. Server assigns a random name; crew rooms or opt-in arena; preset slaps only.

## Run

```bash
# relay
cd relay && bun install && bun server.ts   # ws://localhost:8787

# mac client
cd mac && swift run
```

Relay test: `cd relay && bun test.ts` (needs server running).

## Protocol (relay <-> client)

- `hello` — assigned name, modes, preset slap kinds
- `set_mode {mode, room?}` — private | crew+room | arena (default private)
- `presence` — visible names (consent-filtered, max 50)
- `slap {to, kind}` / `slapped {from, kind}` — kind must be a preset
- `regen_name`, `mute`, `block {name}`, `report {name}`

Server rules: 1.5s per-target cooldown, 12 incoming/min cap, block list, 3 distinct reports = kick.

## Safety

- No custom text/audio. No accounts; relay hides IPs.
- FX never raises volume; PANIC button kills sound + banner.
- Auto-pause on screen share / full-screen is TODO — test with friends first.
