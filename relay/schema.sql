CREATE SCHEMA IF NOT EXISTS slap_battle;

CREATE TABLE IF NOT EXISTS slap_battle.identities (
  token_hash TEXT PRIMARY KEY CHECK (token_hash ~ '^[0-9a-f]{64}$'),
  name TEXT NOT NULL UNIQUE
);
