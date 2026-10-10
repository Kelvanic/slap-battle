import { WebSocketServer, WebSocket } from "ws";
import { randomName } from "./names";

type Mode = "private" | "crew" | "arena";
type OutMsg = Record<string, string | number | boolean | string[] | null>;
interface Peer {
  ws: WebSocket; name: string; mode: Mode; room: string | null;
  blocked: Set<string>; mutedUntil: number;
  lastSlap: Map<string, number>; hits: number[]; slapsSent: number; slapsTaken: number;
}
const peers = new Map<string, Peer>();
const taken = new Set<string>();
const rooms = new Map<string, Set<string>>();
const bans = new Set<string>();
const reportsAgainst = new Map<string, Set<string>>();

const PORT = Number(process.env.PORT ?? 8787);
const SEND_CD_MS = 1500;
const GLOBAL_CAP = 12;
const AUTO_MUTE_MS = 60_000;
const MAX_PRESENCE = 50;

const PRESET_SLAPS: Record<string, true> = { slap: true, bonk: true, splat: true, thwack: true };
const SLAP_KINDS = Object.keys(PRESET_SLAPS);

// Every outbound send must pass the readyState guard; single choke point.
function send(p: Peer, msg: OutMsg): void {
  if (p.ws.readyState === WebSocket.OPEN) p.ws.send(JSON.stringify(msg));
}

function pruneHits(p: Peer, now: number): void {
  p.hits = p.hits.filter((t) => now - t < 60_000);
}

function visiblePeers(self: Peer): string[] {
  const out: string[] = [];
  for (const [name, p] of peers) {
    if (p === self || p.blocked.has(self.name)) continue;
    if (self.mode === "arena" && p.mode === "arena") out.push(name);
    else if (self.mode === "crew" && p.mode === "crew" && self.room && self.room === p.room) out.push(name);
    if (out.length >= MAX_PRESENCE) break;
  }
  return out;
}

function broadcastPresence(): void {
  for (const p of peers.values()) {
    send(p, { t: "presence", names: visiblePeers(p), you: p.name, mode: p.mode, room: p.room });
  }
}

function leaveRoom(p: Peer): void {
  if (p.room) {
    rooms.get(p.room)?.delete(p.name);
    if (rooms.get(p.room)?.size === 0) rooms.delete(p.room);
    p.room = null;
  }
}

// Single choke point for reading untrusted inbound fields: object key + typeof check.
function field(m: object, key: string): string | undefined {
  if (!(key in m)) return undefined;
  const v: unknown = (m as Record<string, unknown>)[key];
  return typeof v === "string" ? v : undefined;
}

const wss = new WebSocketServer({ port: PORT });
wss.on("connection", (ws, req) => {
  const ip = req.socket.remoteAddress ?? "unknown";
  if (bans.has(ip)) { ws.close(4403, "banned"); return; }
  const name = randomName(taken);
  taken.add(name);
  const p: Peer = { ws, name, mode: "private", room: null, blocked: new Set(), mutedUntil: 0, lastSlap: new Map(), hits: [], slapsSent: 0, slapsTaken: 0 };
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
        if (mode === "private" || mode === "arena") { leaveRoom(p); p.mode = mode; }
        else {
          const room = field(m, "room");
          if (mode !== "crew" || !room || !/^[a-z0-9-]{1,32}$/i.test(room)) return;
          leaveRoom(p);
          p.mode = "crew"; p.room = room.toLowerCase();
          if (!rooms.has(p.room)) rooms.set(p.room, new Set());
          rooms.get(p.room)?.add(p.name);
        }
        broadcastPresence();
        break;
      }
      case "regen_name": {
        const next = randomName(taken);
        taken.delete(p.name); taken.add(next);
        if (p.room) { rooms.get(p.room)?.delete(p.name); rooms.get(p.room)?.add(next); }
        peers.delete(p.name); p.name = next; peers.set(next, p);
        broadcastPresence();
        break;
      }
      case "slap": {
        const target = peers.get(field(m, "to") ?? "");
        const kindRaw = field(m, "kind");
        const kind = kindRaw && PRESET_SLAPS[kindRaw] ? kindRaw : "slap";
        if (!target || target === p) return;
        const allowed = (p.mode === "arena" && target.mode === "arena") ||
          (p.mode === "crew" && target.mode === "crew" && p.room && p.room === target.room);
        if (!allowed || target.mutedUntil > now || target.blocked.has(p.name)) return;
        if (now - (p.lastSlap.get(target.name) ?? 0) < SEND_CD_MS) return;
        pruneHits(target, now);
        if (target.hits.length >= GLOBAL_CAP) return;
        p.lastSlap.set(target.name, now); target.hits.push(now);
        p.slapsSent++; target.slapsTaken++;
        send(target, { t: "slapped", from: p.name, kind, id: `${now}-${p.name}` });
        send(p, { t: "slap_ok", to: target.name, kind });
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
  ws.on("close", () => { leaveRoom(p); peers.delete(p.name); taken.delete(p.name); });
});

console.log(`slap-battle relay on ws://localhost:${PORT}`);
