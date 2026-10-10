import { WebSocket } from "ws";

const URL = process.env.RELAY_URL ?? "ws://localhost:8787";
type Msg = Record<string, unknown>;
interface Conn { ws: WebSocket; msgs: Msg[]; }

function delay(ms: number): Promise<void> {
  const { promise, resolve } = Promise.withResolvers<void>();
  setTimeout(resolve, ms);
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

const a = await connect();
const b = await connect();
await delay(200);
const ha = a.msgs.find((m) => m.t === "hello");
const hb = b.msgs.find((m) => m.t === "hello");
const nameA = typeof ha?.you === "string" ? ha.you : "";
const nameB = typeof hb?.you === "string" ? hb.you : "";
check("both get random names", nameA !== "" && nameB !== "" && nameA !== nameB);
check("preset slaps listed", Array.isArray(ha?.slaps) && ha.slaps.includes("slap"));

// private -> no slap delivery
a.ws.send(JSON.stringify({ t: "slap", to: nameB, kind: "slap" }));
await delay(200);
check("private mode blocks slap", !b.msgs.some((m) => m.t === "slapped"));

// arena -> delivered
a.ws.send(JSON.stringify({ t: "set_mode", mode: "arena" }));
b.ws.send(JSON.stringify({ t: "set_mode", mode: "arena" }));
await delay(200);
a.ws.send(JSON.stringify({ t: "slap", to: nameB, kind: "bonk" }));
await delay(200);
const hit = b.msgs.find((m) => m.t === "slapped");
check("arena slap delivered with sender", hit?.from === nameA && hit?.kind === "bonk");

// cooldown: immediate second slap to same target dropped
const n0 = b.msgs.filter((m) => m.t === "slapped").length;
a.ws.send(JSON.stringify({ t: "slap", to: nameB }));
await delay(200);
check("per-target cooldown enforced", b.msgs.filter((m) => m.t === "slapped").length === n0);

// block
b.ws.send(JSON.stringify({ t: "block", name: nameA }));
await delay(300);
a.ws.send(JSON.stringify({ t: "slap", to: nameB }));
await delay(300);
check("block stops slap", b.msgs.filter((m) => m.t === "slapped").length === n0);

// regen name
b.ws.send(JSON.stringify({ t: "regen_name" }));
await delay(200);
const pres = [...a.msgs].reverse().find((m) => m.t === "presence");
const names = Array.isArray(pres?.names) ? (pres.names as unknown[]) : [];
check("regen rotates name", !names.includes(nameB));

a.ws.close();
b.ws.close();
await delay(200);
console.log(`\n${pass} pass, ${fail} fail`);
process.exit(fail ? 1 : 0);
