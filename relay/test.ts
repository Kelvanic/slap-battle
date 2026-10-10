import { WebSocket } from "ws";

const URL = process.env.RELAY_URL ?? "ws://localhost:8787";
// Remote relays need longer settle time between steps.
const DELAY_SCALE = Number(process.env.DELAY_SCALE ?? 1);
type Msg = Record<string, unknown>;
interface Conn { ws: WebSocket; msgs: Msg[]; }

function delay(ms: number): Promise<void> {
  const { promise, resolve } = Promise.withResolvers<void>();
  setTimeout(resolve, ms * DELAY_SCALE);
  return promise;
}

function connect(): Promise<Conn> {
  const { promise, resolve, reject } = Promise.withResolvers<Conn>();
  const ws = new WebSocket(URL);
  const msgs: Msg[] = [];
  ws.on("message", (d) => {
    try {
      const v: unknown = JSON.parse(String(d));
      if (typeof v === "object" && v !== null) msgs.push(v as Msg);
    } catch { /* ignore malformed */ }
  });
  ws.on("open", () => resolve({ ws, msgs }));
  ws.on("error", reject);
  return promise;
}

let pass = 0;
let fail = 0;
function check(name: string, ok: boolean): void {
  console.log(ok ? `ok - ${name}` : `FAIL - ${name}`);
  if (ok) pass++; else fail++;
}
const send = (c: Conn, o: object) => c.ws.send(JSON.stringify(o));
const last = (c: Conn, t: string) => [...c.msgs].reverse().find((m) => m.t === t);
const slapsTo = (c: Conn) => c.msgs.filter((m) => m.t === "slapped").length;

const a = await connect();
const b = await connect();
await delay(200);
const nameA = String(a.msgs.find((m) => m.t === "hello")?.you ?? "");
const nameB = String(b.msgs.find((m) => m.t === "hello")?.you ?? "");
check("both get random names", nameA !== "" && nameB !== "" && nameA !== nameB);
check("preset slaps listed", Array.isArray(a.msgs[0]?.slaps) && (a.msgs[0].slaps as unknown[]).includes("slap"));

send(a, { t: "slap", to: nameB, kind: "slap" });
await delay(200);
check("private mode blocks slap", slapsTo(b) === 0 && last(a, "slap_miss")?.reason === "gone");

send(a, { t: "set_mode", mode: "arena" });
send(b, { t: "set_mode", mode: "arena" });
await delay(300);
send(a, { t: "shuffle" });
await delay(300);
const sample = last(a, "presence");
const names = Array.isArray(sample?.names) ? (sample.names as unknown[]) : [];
check("arena sample includes other player", names.includes(nameB));
check("arena sample excludes self", !names.includes(nameA));
await delay(1100);
check("debounced arena count", last(a, "count")?.count === 2);

send(a, { t: "slap", to: nameB, kind: "bonk" });
await delay(200);
const hit = last(b, "slapped");
check("arena slap delivered with sender", hit?.from === nameA && hit?.kind === "bonk");

const n0 = slapsTo(b);
send(a, { t: "slap", to: nameB });
await delay(200);
check("per-target cooldown enforced", slapsTo(b) === n0 && last(a, "slap_miss")?.reason === "cooldown");

await delay(1600);
send(a, { t: "slap_random", kind: "splat" });
await delay(300);
check("random slap finds a stranger", slapsTo(b) === n0 + 1 && last(b, "slapped")?.kind === "splat");

send(b, { t: "block", name: nameA });
await delay(1700);
const n1 = slapsTo(b);
send(a, { t: "slap", to: nameB });
await delay(300);
check("block stops slap", slapsTo(b) === n1);

send(b, { t: "regen_name" });
await delay(300);
const newB = String(last(b, "presence")?.you ?? "");
check("regen rotates name", newB !== "" && newB !== nameB);

send(a, { t: "slap", to: nameB });
await delay(300);
check("stale name reports gone", last(a, "slap_miss")?.reason === "gone");

a.ws.close();
b.ws.close();
await delay(200);
console.log(`\n${pass} pass, ${fail} fail`);
process.exit(fail ? 1 : 0);
