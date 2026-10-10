import { WebSocketServer, WebSocket } from "ws";
import { randomName } from "./names";

type Mode = "private" | "crew" | "arena";
type OutMsg = Record<string, string | number | boolean | string[] | null>;
interface Peer {
  ws: WebSocket; name: string; mode: Mode; room: string | null;
  blocked: Set<string>; mutedUntil: number;
  lastSlap: Map<string, number>; hits: number[]; sentTimes: number[]; lastShuffle: number;
}

const peers = new Map<string, Peer>();
const taken = new Set<string>();
const rooms = new Map<string, Set<string>>();
const reportsAgainst = new Map<string, Set<string>>();
// Arena membership as array + index map: O(1) join/leave/random pick at any size.
const arena: string[] = [];
const arenaIdx = new Map<string, number>();

const PORT = Number(process.env.PORT ?? 8787);
const SEND_CD_MS = 1500;        // per sender->target cooldown
const INCOMING_CAP = 12;        // max incoming slaps/min per target
const SEND_CAP = 20;            // max outgoing slaps/min per sender
const AUTO_MUTE_MS = 60_000;
const ROOM_LIST_MAX = 50;
const SAMPLE_SIZE = 8;
const SHUFFLE_CD_MS = 400;
const COUNT_DEBOUNCE_MS = 1000;

const PRESET_SLAPS: Record<string, true> = { slap: true, bonk: true, splat: true, thwack: true };
const SLAP_KINDS = Object.keys(PRESET_SLAPS);

function send(p: Peer, msg: OutMsg): void {
  if (p.ws.readyState === WebSocket.OPEN) p.ws.send(JSON.stringify(msg));
}

// Single choke point for reading untrusted inbound fields: object key + typeof check.
function field(m: object, key: string): string | undefined {
  if (!(key in m)) return undefined;
  const v: unknown = (m as Record<string, unknown>)[key];
  return typeof v === "string" ? v : undefined;
}

let countTimer: NodeJS.Timeout | null = null;
/** Arena size changes are coalesced into at most one broadcast per second. */
function scheduleCount(): void {
  if (countTimer) return;
  countTimer = setTimeout(() => {
    countTimer = null;
    const msg = JSON.stringify({ t: "count", count: arena.length });
    for (const n of arena) {
      const p = peers.get(n);
      if (p?.ws.readyState === WebSocket.OPEN) p.ws.send(msg);
    }
  }, COUNT_DEBOUNCE_MS);
}

function arenaAdd(name: string): void {
  if (arenaIdx.has(name)) return;
  arenaIdx.set(name, arena.length);
  arena.push(name);
  scheduleCount();
}

function arenaRemove(name: string): void {
  const i = arenaIdx.get(name);
  if (i === undefined) return;
  const last = arena.pop() ?? name;
  if (last !== name) { arena[i] = last; arenaIdx.set(last, i); }
  arenaIdx.delete(name);
  scheduleCount();
}

function mutuallyVisible(a: Peer, b: Peer): boolean {
  return !a.blocked.has(b.name) && !b.blocked.has(a.name);
}

function sampleArena(self: Peer): string[] {
  const out = new Set<string>();
  const want = Math.min(SAMPLE_SIZE, arena.length - 1);
  for (let tries = 0; out.size < want && tries < want * 6; tries++) {
    const n = arena[(Math.random() * arena.length) | 0];
    const other = peers.get(n);
    if (!other || other === self || out.has(n) || !mutuallyVisible(self, other)) continue;
    out.add(n);
  }
  return [...out];
}

function roomList(self: Peer): string[] {
  const out: string[] = [];
  for (const n of rooms.get(self.room ?? "") ?? []) {
    const other = peers.get(n);
    if (!other || other === self || !mutuallyVisible(self, other)) continue;
    out.push(n);
    if (out.length >= ROOM_LIST_MAX) break;
  }
  return out;
}

/** Tells one peer who they can see. Arena: random sample; crew: the room; private: nobody. */
function sendPresence(p: Peer): void {
  const names = p.mode === "arena" ? sampleArena(p) : p.mode === "crew" ? roomList(p) : [];
  const count = p.mode === "arena" ? arena.length : p.mode === "crew" ? (rooms.get(p.room ?? "")?.size ?? 0) : 0;
  send(p, { t: "presence", names, you: p.name, mode: p.mode, room: p.room, count });
}

function notifyRoom(room: string | null): void {
  if (!room) return;
  for (const n of rooms.get(room) ?? []) {
    const p = peers.get(n);
    if (p) sendPresence(p);
  }
}

function leaveCurrent(p: Peer): string | null {
  arenaRemove(p.name);
  const old = p.room;
  if (old) {
    rooms.get(old)?.delete(p.name);
    if (rooms.get(old)?.size === 0) rooms.delete(old);
    p.room = null;
  }
  return old;
}

/** Returns null if delivered, otherwise a miss reason. */
function deliverSlap(p: Peer, target: Peer, kind: string, now: number): string | null {
  if (target === p) return "self";
  const together = (p.mode === "arena" && target.mode === "arena") ||
    (p.mode === "crew" && target.mode === "crew" && p.room !== null && p.room === target.room);
  if (!together) return "gone";
  if (!mutuallyVisible(p, target) || target.mutedUntil > now) return "blocked";
  if (now - (p.lastSlap.get(target.name) ?? 0) < SEND_CD_MS) return "cooldown";
  target.hits = target.hits.filter((t) => now - t < 60_000);
  if (target.hits.length >= INCOMING_CAP) return "busy";

  p.lastSlap.set(target.name, now);
  if (p.lastSlap.size > 200) {
    for (const [n, t] of p.lastSlap) if (now - t >= SEND_CD_MS) p.lastSlap.delete(n);
  }
  p.sentTimes.push(now);
  target.hits.push(now);
  send(target, { t: "slapped", from: p.name, kind, id: `${now}-${p.name}` });
  send(p, { t: "slap_ok", to: target.name, kind });
  return null;
}

const wss = new WebSocketServer({ port: PORT });
wss.on("connection", (ws) => {
  const name = randomName(taken);
  taken.add(name);
  const p: Peer = {
    ws, name, mode: "private", room: null, blocked: new Set(), mutedUntil: 0,
    lastSlap: new Map(), hits: [], sentTimes: [], lastShuffle: 0,
  };
  peers.set(name, p);
  send(p, { t: "hello", you: name, modes: ["private", "crew", "arena"], slaps: SLAP_KINDS });

  ws.on("message", (raw) => {
    let m: unknown;
    try { m = JSON.parse(String(raw)) as unknown; } catch { return; }
    if (typeof m !== "object" || m === null) return;
    const now = Date.now();

    switch (field(m, "t")) {
      case "set_mode": {
        const mode = field(m, "mode");
        const room = field(m, "room");
        if (mode === "crew" && (!room || !/^[a-z0-9-]{1,32}$/i.test(room))) return;
        if (mode !== "private" && mode !== "arena" && mode !== "crew") return;
        const oldRoom = leaveCurrent(p);
        p.mode = mode;
        if (mode === "arena") arenaAdd(p.name);
        if (mode === "crew" && room) {
          p.room = room.toLowerCase();
          if (!rooms.has(p.room)) rooms.set(p.room, new Set());
          rooms.get(p.room)?.add(p.name);
        }
        sendPresence(p);
        notifyRoom(oldRoom);
        if (p.room !== oldRoom) notifyRoom(p.room);
        break;
      }
      case "regen_name": {
        const old = p.name;
        const next = randomName(taken);
        taken.delete(old); taken.add(next);
        const i = arenaIdx.get(old);
        if (i !== undefined) { arena[i] = next; arenaIdx.delete(old); arenaIdx.set(next, i); }
        if (p.room) { rooms.get(p.room)?.delete(old); rooms.get(p.room)?.add(next); }
        peers.delete(old); p.name = next; peers.set(next, p);
        sendPresence(p);
        notifyRoom(p.room);
        break;
      }
      case "shuffle": {
        if (now - p.lastShuffle < SHUFFLE_CD_MS) return;
        p.lastShuffle = now;
        sendPresence(p);
        break;
      }
      case "slap":
      case "slap_random": {
        const kindRaw = field(m, "kind");
        const kind = kindRaw && PRESET_SLAPS[kindRaw] ? kindRaw : "slap";
        p.sentTimes = p.sentTimes.filter((t) => now - t < 60_000);
        if (p.sentTimes.length >= SEND_CAP) { send(p, { t: "slap_miss", to: field(m, "to") ?? "", reason: "slow_down" }); return; }

        if (field(m, "t") === "slap") {
          const to = field(m, "to") ?? "";
          const target = peers.get(to);
          const reason = target ? deliverSlap(p, target, kind, now) : "gone";
          if (reason) send(p, { t: "slap_miss", to, reason });
          return;
        }
        if (p.mode !== "arena") return;
        for (let tries = 0; tries < 12; tries++) {
          const target = peers.get(arena[(Math.random() * arena.length) | 0]);
          if (target && deliverSlap(p, target, kind, now) === null) return;
        }
        send(p, { t: "slap_miss", to: "", reason: "nobody" });
        break;
      }
      case "mute": {
        p.mutedUntil = now + AUTO_MUTE_MS;
        send(p, { t: "muted", until: p.mutedUntil });
        break;
      }
      case "block": {
        const target = field(m, "name");
        if (!target) return;
        p.blocked.add(target);
        send(p, { t: "blocked", name: target });
        break;
      }
      case "report": {
        const target = field(m, "name");
        if (!target || !peers.has(target)) return;
        if (!reportsAgainst.has(target)) reportsAgainst.set(target, new Set());
        reportsAgainst.get(target)?.add(p.name);
        if ((reportsAgainst.get(target)?.size ?? 0) >= 3) peers.get(target)?.ws.close(4403, "reported");
        send(p, { t: "report_ok", name: target });
        break;
      }
    }
  });

  ws.on("close", () => {
    const oldRoom = leaveCurrent(p);
    peers.delete(p.name);
    taken.delete(p.name);
    reportsAgainst.delete(p.name);
    notifyRoom(oldRoom);
  });
});

console.log(`slap-battle relay on ws://localhost:${PORT}`);
