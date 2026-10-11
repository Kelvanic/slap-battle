import { createHash, randomBytes } from "node:crypto";
import { readFile } from "node:fs/promises";
import { Pool } from "pg";
import { randomName } from "./names";

interface IdentityRow { name: string; }

export class IdentityStore {
  private constructor(private readonly pool: Pool) {}

  static async open(databaseUrl = process.env.DATABASE_URL): Promise<IdentityStore> {
    if (!databaseUrl) throw new Error("DATABASE_URL is required");

    let pool: Pool | null = null;
    try {
      const schema = await readFile(new URL("./schema.sql", import.meta.url), "utf8");
      const connectionUrl = new URL(databaseUrl);
      for (const key of ["sslmode", "sslrootcert", "sslcert", "sslkey", "sslpassword"]) {
        connectionUrl.searchParams.delete(key);
      }
      pool = new Pool({
        connectionString: connectionUrl.toString(),
        ssl: { rejectUnauthorized: true },
        connectionTimeoutMillis: 10_000,
        query_timeout: 10_000,
      });
      pool.on("error", () => {
        console.error("identity database connection failed");
      });
      await pool.query(schema);
      return new IdentityStore(pool);
    } catch {
      if (pool) await pool.end().catch(() => undefined);
      throw new Error("identity database initialization failed");
    }
  }

  async nameFor(token: string): Promise<string> {
    const tokenHash = createHash("sha256").update(token, "utf8").digest("hex");
    try {
      const current = await this.pool.query<IdentityRow>(
        "SELECT name FROM slap_battle.identities WHERE token_hash = $1",
        [tokenHash],
      );
      const currentName = current.rows[0]?.name;
      if (currentName) return currentName;
      while (true) {
        const inserted = await this.pool.query<IdentityRow>(
          "INSERT INTO slap_battle.identities (token_hash, name) VALUES ($1, $2) ON CONFLICT DO NOTHING RETURNING name",
          [tokenHash, randomName()],
        );
        const insertedName = inserted.rows[0]?.name;
        if (insertedName) return insertedName;

        const existing = await this.pool.query<IdentityRow>(
          "SELECT name FROM slap_battle.identities WHERE token_hash = $1",
          [tokenHash],
        );
        const existingName = existing.rows[0]?.name;
        if (existingName) return existingName;
      }
    } catch {
      throw new Error("identity database unavailable");
    }
  }

  async close(): Promise<void> {
    await this.pool.end();
  }
}

export function newIdentityToken(): string {
  return randomBytes(32).toString("hex");
}
