import { mkdirSync } from "node:fs";
import { join } from "node:path";
import { createHash, randomBytes } from "node:crypto";
import { Database, type Statement } from "bun:sqlite";
import { randomName } from "./names";

interface IdentityRow { name: string; }

export class IdentityStore {
  private readonly db: Database;
  private readonly findName: Statement<IdentityRow, [string]>;
  private readonly insertIdentity: Statement<unknown, [string, string]>;

  constructor(dataDir = process.env.DATA_DIR || join(import.meta.dir, "data")) {
    mkdirSync(dataDir, { recursive: true });
    this.db = new Database(join(dataDir, "identities.sqlite"));
    this.db.exec("PRAGMA journal_mode = WAL");
    this.db.exec("PRAGMA synchronous = FULL");
    this.db.exec("PRAGMA busy_timeout = 5000");
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS identities (
        token_hash TEXT PRIMARY KEY NOT NULL CHECK (length(token_hash) = 64),
        name TEXT NOT NULL UNIQUE
      ) WITHOUT ROWID
    `);
    this.findName = this.db.query<IdentityRow, [string]>("SELECT name FROM identities WHERE token_hash = ?");
    this.insertIdentity = this.db.query<unknown, [string, string]>("INSERT OR IGNORE INTO identities (token_hash, name) VALUES (?, ?)");
  }

  nameFor(token: string): string {
    const tokenHash = createHash("sha256").update(token, "utf8").digest("hex");
    const existing = this.findName.get(tokenHash);
    if (existing) return existing.name;

    while (true) {
      this.insertIdentity.run(tokenHash, randomName());
      const inserted = this.findName.get(tokenHash);
      if (inserted) return inserted.name;
    }
  }

  close(): void {
    this.db.close();
  }
}

export function newIdentityToken(): string {
  return randomBytes(32).toString("hex");
}
