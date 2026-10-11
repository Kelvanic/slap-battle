import { createHash } from "node:crypto";
import { Database } from "bun:sqlite";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { Pool } from "pg";
import { z } from "zod";

const IdentityRowSchema = z.object({
  token_hash: z.string().regex(/^[0-9a-f]{64}$/),
  name: z.string().min(1),
}).strict();
type IdentityRow = z.infer<typeof IdentityRowSchema>;

function digestRows(rows: readonly IdentityRow[]): string {
  const hash = createHash("sha256");
  const ordered = [...rows].sort((a, b) => a.token_hash < b.token_hash ? -1 : a.token_hash > b.token_hash ? 1 : a.name < b.name ? -1 : a.name > b.name ? 1 : 0);
  const length = Buffer.alloc(8);
  for (const row of ordered) {
    for (const value of [row.token_hash, row.name]) {
      const bytes = Buffer.from(value, "utf8");
      length.writeBigUInt64BE(BigInt(bytes.byteLength));
      hash.update(length);
      hash.update(bytes);
    }
  }
  return hash.digest("hex");
}

function readSource(sourcePath: string): IdentityRow[] {
  const db = new Database(sourcePath, { readonly: true, create: false });
  try {
    const columns = db.query<{ name: string; type: string }, []>("PRAGMA table_info(identities)").all();
    const tokenHashColumn = columns.find((column) => column.name === "token_hash");
    const nameColumn = columns.find((column) => column.name === "name");
    if (!tokenHashColumn || !nameColumn || tokenHashColumn.type.toUpperCase() !== "TEXT" || nameColumn.type.toUpperCase() !== "TEXT") {
      throw new Error("invalid source schema");
    }
    const rawRows: unknown[] = db.query("SELECT token_hash, name FROM identities").all();
    const rows = rawRows.map((row) => IdentityRowSchema.parse(row));
    const hashes = new Set<string>();
    const names = new Set<string>();
    for (const row of rows) {
      if (hashes.has(row.token_hash) || names.has(row.name)) throw new Error("duplicate source identity");
      hashes.add(row.token_hash);
      names.add(row.name);
    }
    return rows;
  } finally {
    db.close();
  }
}

async function migrate(sourcePath: string, databaseUrl: string): Promise<{ input: number; imported: number; verified: number; digest: string }> {
  const rows = readSource(sourcePath);
  const schema = await readFile(join(import.meta.dir, "schema.sql"), "utf8");
  if (schema.trim().length === 0) throw new Error("missing target schema");

  const connection = new URL(databaseUrl);
  if (!["postgres:", "postgresql:"].includes(connection.protocol) || connection.hostname.includes("-pooler")) {
    throw new Error("a direct Postgres connection is required for migration");
  }
  connection.searchParams.delete("sslmode");
  connection.searchParams.delete("sslrootcert");
  const pool = new Pool({
    connectionString: connection.toString(),
    ssl: { rejectUnauthorized: true },
    connectionTimeoutMillis: 10_000,
    query_timeout: 10_000,
    max: 1,
  });
  try {
    const client = await pool.connect();
    try {
      await client.query("BEGIN");
      await client.query(schema);
      let imported = 0;
      for (const row of rows) {
        const result = await client.query(
          "INSERT INTO slap_battle.identities (token_hash, name) VALUES ($1, $2) ON CONFLICT DO NOTHING",
          [row.token_hash, row.name],
        );
        imported += result.rowCount ?? 0;
      }

      let verified = 0;
      for (const row of rows) {
        const result = await client.query<{ token_hash: string; name: string }>(
          "SELECT token_hash, name FROM slap_battle.identities WHERE token_hash = $1 OR name = $2",
          [row.token_hash, row.name],
        );
        if (result.rows.length !== 1 || result.rows[0]?.token_hash !== row.token_hash || result.rows[0]?.name !== row.name) {
          throw new Error("target identity conflict");
        }
        verified += 1;
      }
      await client.query("COMMIT");
      return { input: rows.length, imported, verified, digest: digestRows(rows) };
    } catch (error) {
      try {
        await client.query("ROLLBACK");
      } catch {
        // The transaction may already have been aborted by the server.
      }
      throw error;
    } finally {
      client.release();
    }
  } finally {
    await pool.end();
  }
}

const sourcePath = process.argv[2];
const databaseUrl = process.env.MIGRATION_DATABASE_URL;
if (!sourcePath || process.argv.length !== 3 || !databaseUrl) {
  console.error("Migration failed.");
  process.exitCode = 1;
} else {
  try {
    const result = await migrate(sourcePath, databaseUrl);
    console.log(JSON.stringify(result));
  } catch {
    console.error("Migration failed.");
    process.exitCode = 1;
  }
}
