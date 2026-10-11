import { createHash, randomBytes } from "node:crypto";
import { Pool } from "pg";
import { WebSocket, type RawData } from "ws";
import { z } from "zod";
import { IdentityStore, newIdentityToken } from "./identity-store";

let URL = "";
const DATABASE_URL = z.string().min(1).parse(process.env.DATABASE_URL);
const testTokenHashes = new Set<string>();
function trackTestToken(token: string): void {
  testTokenHashes.add(createHash("sha256").update(token, "utf8").digest("hex"));
}
const WAIT_MS = 10_000;
const MessageSchema = z.object({ t: z.string() }).passthrough();
type Msg = z.infer<typeof MessageSchema>;
interface Conn { ws: WebSocket; msgs: Msg[]; }
interface Closed { code: number; reason: string; }

function decode(raw: RawData): Msg | null {
  const text = Buffer.isBuffer(raw)
    ? raw.toString("utf8")
    : raw instanceof ArrayBuffer
      ? Buffer.from(raw).toString("utf8")
      : Buffer.concat(raw).toString("utf8");
  try {
    const value: unknown = JSON.parse(text);
    const parsed = MessageSchema.safeParse(value);
    return parsed.success ? parsed.data : null;
  } catch {
    return null;
  }
}

async function openSocket(url: string): Promise<WebSocket> {
  const pending = Promise.withResolvers<WebSocket>();
  const ws = new WebSocket(url);
  ws.once("open", () => pending.resolve(ws));
  ws.once("error", (error) => pending.reject(error));
  return pending.promise;
}

function track(ws: WebSocket): Conn {
  const conn: Conn = { ws, msgs: [] };
  ws.on("message", (raw) => {
    const message = decode(raw);
    if (message) conn.msgs.push(message);
  });
  return conn;
}

async function connect(token: string, url = URL): Promise<Conn> {
  const conn = track(await openSocket(url));
  trackTestToken(token);
  conn.ws.send(JSON.stringify({ t: "identify", token }));
  try {
    await waitFor(conn, (message) => message.t === "hello");
    return conn;
  } catch (error) {
    conn.ws.close();
    throw error;
  }
}

function waitFor(conn: Conn, matches: (message: Msg) => boolean, after = 0, timeoutMs = WAIT_MS): Promise<Msg> {
  for (const message of conn.msgs.slice(after)) {
    if (matches(message)) return Promise.resolve(message);
  }

  const pending = Promise.withResolvers<Msg>();
  let settled = false;
  const cleanup = () => {
    clearTimeout(timer);
    conn.ws.off("message", onMessage);
    conn.ws.off("close", onClose);
  };
  const onMessage = () => {
    const message = conn.msgs.slice(after).find(matches);
    if (!settled && message) {
      settled = true;
      cleanup();
      pending.resolve(message);
    }
  };
  const onClose = (code: number) => {
    if (!settled) {
      settled = true;
      cleanup();
      pending.reject(new Error(`connection closed (${code}) before expected message`));
    }
  };
  const timer = setTimeout(() => {
    if (!settled) {
      settled = true;
      cleanup();
      pending.reject(new Error("timed out waiting for relay message"));
    }
  }, timeoutMs);
  conn.ws.on("message", onMessage);
  conn.ws.once("close", onClose);
  return pending.promise;
}

function waitForClose(ws: WebSocket, timeoutMs = WAIT_MS): Promise<Closed> {
  const pending = Promise.withResolvers<Closed>();
  const timer = setTimeout(() => {
    ws.off("close", onClose);
    pending.reject(new Error("timed out waiting for websocket close"));
  }, timeoutMs);
  const onClose = (code: number, reason: Buffer) => {
    clearTimeout(timer);
    pending.resolve({ code, reason: reason.toString("utf8") });
  };
  ws.once("close", onClose);
  return pending.promise;
}

async function closeConnection(conn: Conn): Promise<void> {
  if (conn.ws.readyState === WebSocket.CLOSED) return;
  const closed = waitForClose(conn.ws);
  conn.ws.close();
  await closed;
}

function send(conn: Conn, message: object): void {
  conn.ws.send(JSON.stringify(message));
}


let pass = 0;
let fail = 0;
function check(name: string, ok: boolean): void {
  console.log(ok ? `ok - ${name}` : `FAIL - ${name}`);
  if (ok) pass++; else fail++;
}

async function startIsolatedRelay(): Promise<{ url: string; stop: () => Promise<void> }> {
  const child = Bun.spawn([process.execPath, "server.ts"], {
    cwd: import.meta.dir,
    env: { ...process.env, PORT: "0" },
    stdout: "pipe",
    stderr: "pipe",
  });
  const pending = Promise.withResolvers<string>();
  const timer = setTimeout(() => pending.reject(new Error("isolated relay did not start")), WAIT_MS);
  const output = child.stdout;
  if (!output) {
    clearTimeout(timer);
    child.kill();
    await child.exited;
    throw new Error("isolated relay has no startup output");
  }
  void (async () => {
    const reader = output.getReader();
    const decoder = new TextDecoder();
    let text = "";
    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) throw new Error("isolated relay exited before listening");
        text += decoder.decode(value, { stream: true });
        const port = /slap-battle relay on ws:\/\/localhost:(\d+)/.exec(text)?.[1];
        if (port) {
          pending.resolve(`ws://localhost:${port}`);
          return;
        }
      }
    } catch (error) {
      pending.reject(error);
    }
  })();
  try {
    const url = await pending.promise;
    clearTimeout(timer);
    return {
      url,
      stop: async () => {
        child.kill();
        await child.exited;
      },
    };
  } catch (error) {
    clearTimeout(timer);
    child.kill();
    await child.exited;
    throw error;
  }
}

async function cleanupTestIdentities(): Promise<void> {
  const connectionUrl = new globalThis.URL(DATABASE_URL);
  for (const key of ["sslmode", "sslrootcert", "sslcert", "sslkey", "sslpassword"]) {
    connectionUrl.searchParams.delete(key);
  }
  const pool = new Pool({
    connectionString: connectionUrl.toString(),
    ssl: { rejectUnauthorized: true },
  });
  try {
    if (testTokenHashes.size > 0) {
      await pool.query(
        "DELETE FROM slap_battle.identities WHERE token_hash = ANY($1::text[])",
        [[...testTokenHashes]],
      );
    }
  } finally {
    await pool.end();
  }
}
async function runTests(): Promise<void> {
  const primaryRelay = await startIsolatedRelay();
  URL = primaryRelay.url;
  try {

const durableToken = newIdentityToken();
trackTestToken(durableToken);
const registry = await IdentityStore.open(DATABASE_URL);
const originalName = await registry.nameFor(durableToken);
const concurrentToken = newIdentityToken();
trackTestToken(concurrentToken);
const concurrentNames = await Promise.all(Array.from({ length: 8 }, () => registry.nameFor(concurrentToken)));
const concurrentName = concurrentNames[0] ?? "";
const differentToken = newIdentityToken();
trackTestToken(differentToken);
const differentName = await registry.nameFor(differentToken);
await registry.close();
check("same-token concurrent claims resolve to one name", concurrentName !== "" && concurrentNames.every((name) => name === concurrentName));
check("different credentials receive unique names", differentName !== originalName);

const reopenedRegistry = await IdentityStore.open(DATABASE_URL);
const reopenedName = await reopenedRegistry.nameFor(durableToken);
await reopenedRegistry.close();
check("name survives PostgreSQL store close and reopen", reopenedName === originalName);

const unavailableStore = await IdentityStore.open(DATABASE_URL);
await unavailableStore.close();
let unavailableRejected = false;
try {
  await unavailableStore.nameFor(newIdentityToken());
} catch {
  unavailableRejected = true;
}
check("database failure rejects instead of generating an identity", unavailableRejected);

const malformed = await openSocket(URL);
const malformedClose = waitForClose(malformed);
malformed.send(JSON.stringify({ t: "identify", token: "not-a-token" }));
const malformedResult = await malformedClose;
check("malformed identity is rejected with policy close", malformedResult.code === 1008);
const timed = await openSocket(URL);
const timeoutResult = await waitForClose(timed, 7_000);
check("missing identify times out with policy close", timeoutResult.code === 1008);

const firstIdentifyToken = newIdentityToken();
const ignoredIdentifyToken = newIdentityToken();
trackTestToken(firstIdentifyToken);
trackTestToken(ignoredIdentifyToken);
const pendingIdentify = track(await openSocket(URL));
pendingIdentify.ws.send(JSON.stringify({ t: "identify", token: firstIdentifyToken }));
pendingIdentify.ws.send(JSON.stringify({ t: "identify", token: ignoredIdentifyToken }));
pendingIdentify.ws.send(JSON.stringify({ t: "set_mode", mode: "arena" }));
const pendingHello = await waitFor(pendingIdentify, (message) => message.t === "hello");
const verificationStore = await IdentityStore.open(DATABASE_URL);
const firstIdentifyName = await verificationStore.nameFor(firstIdentifyToken);
await verificationStore.close();
check("only the first identify token is accepted while lookup is pending", pendingHello.you === firstIdentifyName);
await closeConnection(pendingIdentify);

const tokenA = newIdentityToken();
const tokenB = newIdentityToken();
const a = await connect(tokenA);
const b = await connect(tokenB);
const nameA = String(a.msgs.find((message) => message.t === "hello")?.you ?? "");
const nameB = String(b.msgs.find((message) => message.t === "hello")?.you ?? "");
check("different live credentials receive distinct stable names", nameA !== "" && nameB !== "" && nameA !== nameB);
check("hello marks the assigned name stable", a.msgs.find((message) => message.t === "hello")?.stable === true);
check("preset slaps listed", Array.isArray(a.msgs.find((message) => message.t === "hello")?.slaps) && (a.msgs.find((message) => message.t === "hello")?.slaps as unknown[]).includes("slap"));

let cursor = a.msgs.length;
send(a, { t: "slap", to: nameB, kind: "slap" });
const privateMiss = await waitFor(a, (message) => message.t === "slap_miss", cursor);
check("private mode blocks slap", privateMiss.reason === "gone");

const room = `test-${randomBytes(8).toString("hex")}`;
cursor = a.msgs.length;
send(a, { t: "set_mode", mode: "crew", room });
await waitFor(a, (message) => message.t === "presence" && message.mode === "crew" && message.room === room, cursor);
const beforeBJoin = a.msgs.length;
cursor = b.msgs.length;
send(b, { t: "set_mode", mode: "crew", room });
const roomPresence = await waitFor(a, (message) => message.t === "presence" && Array.isArray(message.names) && message.names.includes(nameB), beforeBJoin);
await waitFor(b, (message) => message.t === "presence" && Array.isArray(message.names) && message.names.includes(nameA), cursor);
check("random private crew exposes only its joined peer", roomPresence.room === room);

cursor = b.msgs.length;
send(a, { t: "slap", to: nameB, kind: "bonk" });
const crewHit = await waitFor(b, (message) => message.t === "slapped", cursor);
await waitFor(a, (message) => message.t === "slap_ok");
check("crew slap is delivered with sender and kind", crewHit.from === nameA && crewHit.kind === "bonk");
cursor = a.msgs.length;
send(a, { t: "slap", to: nameB });
const cooldownMiss = await waitFor(a, (message) => message.t === "slap_miss", cursor);
check("per-target cooldown enforced", cooldownMiss.reason === "cooldown");
const cooldown = Promise.withResolvers<void>();
setTimeout(cooldown.resolve, 1_600);
await cooldown.promise;
cursor = b.msgs.length;
send(b, { t: "block", name: nameA });
await waitFor(b, (message) => message.t === "blocked", b.msgs.length);
send(a, { t: "slap", to: nameB });
const blockedMiss = await waitFor(a, (message) => message.t === "slap_miss", a.msgs.length);
check("block stops slap", blockedMiss.reason === "blocked");

await closeConnection(b);
const reconnectedB = await connect(tokenB);
const reconnectName = String(reconnectedB.msgs.find((message) => message.t === "hello")?.you ?? "");
check("same credential reconnect reuses its permanent name", reconnectName === nameB);
cursor = a.msgs.length;
send(a, { t: "slap", to: reconnectName });
const resetModeMiss = await waitFor(a, (message) => message.t === "slap_miss", cursor);
check("reconnected identity resets to private mode", resetModeMiss.reason === "gone");

const repeatedToken = newIdentityToken();
const previous = await connect(repeatedToken);
const repeatedName = String(previous.msgs.find((message) => message.t === "hello")?.you ?? "");
const previousClosed = waitForClose(previous.ws);
const replacement = await connect(repeatedToken);
const replacementClose = await previousClosed;
check("simultaneous duplicate identity replaces prior connection", replacementClose.code === 4409 && replacementClose.reason === "identity_in_use");
check("replacement connection retains its identity name", replacement.msgs.find((message) => message.t === "hello")?.you === repeatedName);

const duplicateRoom = `duplicate-${randomBytes(8).toString("hex")}`;
cursor = replacement.msgs.length;
send(replacement, { t: "set_mode", mode: "crew", room: duplicateRoom });
await waitFor(replacement, (message) => message.t === "presence" && message.mode === "crew", cursor);
const helper = await connect(newIdentityToken());
cursor = helper.msgs.length;
send(helper, { t: "set_mode", mode: "crew", room: duplicateRoom });
await waitFor(helper, (message) => message.t === "presence" && Array.isArray(message.names) && message.names.includes(repeatedName), cursor);
cursor = replacement.msgs.length;
send(helper, { t: "slap", to: repeatedName });
const replacementHit = await waitFor(replacement, (message) => message.t === "slapped", cursor);
check("old connection close cannot remove replacement identity", replacementHit.from === String(helper.msgs.find((message) => message.t === "hello")?.you ?? ""));

const isolated = await startIsolatedRelay();
const arenaPeers: Conn[] = [];
try {
  arenaPeers.push(await connect(newIdentityToken(), isolated.url));
  arenaPeers.push(await connect(newIdentityToken(), isolated.url));
  for (const conn of arenaPeers) send(conn, { t: "set_mode", mode: "arena" });
  const arenaCounts = await Promise.all(arenaPeers.map((conn) => waitFor(conn, (message) => message.t === "count" && message.count === 2)));
  check("isolated arena count is broadcast after debounce", arenaCounts.length === 2);
  const arenaNames = arenaPeers.map((conn) => String(conn.msgs.find((message) => message.t === "hello")?.you ?? ""));
  cursor = arenaPeers[0]!.msgs.length;
  send(arenaPeers[0]!, { t: "shuffle" });
  const sample = await waitFor(arenaPeers[0]!, (message) => message.t === "presence" && message.mode === "arena", cursor);
  const sampleNames = Array.isArray(sample.names) ? sample.names : [];
  check("arena sample includes its other player and excludes self", sampleNames.includes(arenaNames[1]) && !sampleNames.includes(arenaNames[0]) && sampleNames.length <= 8);
} finally {
  await Promise.all(arenaPeers.map(closeConnection));
  await isolated.stop();
}

await Promise.all([closeConnection(a), closeConnection(reconnectedB), closeConnection(replacement), closeConnection(helper)]);
console.log(`\n${pass} pass, ${fail} fail`);
process.exitCode = fail ? 1 : 0;
  } finally {
    try {
      await primaryRelay.stop();
    } finally {
      await cleanupTestIdentities();
    }
  }
}

await runTests();
