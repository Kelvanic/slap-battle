#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

command -v bun >/dev/null 2>&1 || { echo "bun is required" >&2; exit 1; }
command -v docker >/dev/null 2>&1 || { echo "docker is required" >&2; exit 1; }
command -v openssl >/dev/null 2>&1 || { echo "openssl is required" >&2; exit 1; }

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/slap-battle-ci.XXXXXX")"
container_name="slap-battle-ci-$$"
image_name="slap-battle-relay-ci:$$"
container_started=0
image_built=0
cleanup() {
  if [[ "$container_started" == 1 ]]; then
    docker rm --force "$container_name" >/dev/null 2>&1 || true
  fi
  if [[ "$image_built" == 1 ]]; then
    docker image rm "$image_name" >/dev/null 2>&1 || true
  fi
  rm -rf "$work_dir"
}
trap cleanup EXIT

bun install --frozen-lockfile
bunx tsc --noEmit --strict --target ESNext --module Preserve --moduleResolution bundler --types bun ./*.ts
docker build --tag "$image_name" .
image_built=1

mkdir -p "$work_dir/tls"
openssl genrsa -out "$work_dir/tls/ca.key" 2048 >/dev/null 2>&1
openssl req -x509 -new -nodes -key "$work_dir/tls/ca.key" -sha256 -days 2 \
  -subj "/CN=Slap Battle CI temporary CA" -out "$work_dir/tls/ca.crt" >/dev/null 2>&1
openssl genrsa -out "$work_dir/tls/server.key" 2048 >/dev/null 2>&1
openssl req -new -key "$work_dir/tls/server.key" \
  -subj "/CN=localhost" -out "$work_dir/tls/server.csr" >/dev/null 2>&1
printf 'subjectAltName=DNS:localhost,IP:127.0.0.1\nextendedKeyUsage=serverAuth\n' > "$work_dir/tls/server.ext"
openssl x509 -req -in "$work_dir/tls/server.csr" -CA "$work_dir/tls/ca.crt" \
  -CAkey "$work_dir/tls/ca.key" -CAcreateserial -out "$work_dir/tls/server.crt" \
  -days 2 -sha256 -extfile "$work_dir/tls/server.ext" >/dev/null 2>&1
chmod 600 "$work_dir/tls/server.key"

# Runtime credentials are random per invocation and are never printed.
db_password="$(openssl rand -hex 24)"
docker run --detach --name "$container_name" \
  --publish 127.0.0.1::5432 \
  --mount "type=bind,src=$work_dir/tls/server.crt,dst=/ci-tls/server.crt,readonly" \
  --mount "type=bind,src=$work_dir/tls/server.key,dst=/ci-tls/server.key,readonly" \
  --mount "type=bind,src=$work_dir/tls/ca.crt,dst=/ci-tls/ca.crt,readonly" \
  --env POSTGRES_USER=postgres \
  --env "POSTGRES_PASSWORD=$db_password" \
  --env POSTGRES_DB=postgres \
  --entrypoint /bin/sh \
  postgres:17-alpine \
  -c 'mkdir -p /pg-tls && cp /ci-tls/server.key /pg-tls/server.key && cp /ci-tls/server.crt /pg-tls/server.crt && chown postgres:postgres /pg-tls/server.key && chmod 600 /pg-tls/server.key && exec docker-entrypoint.sh postgres -c ssl=on -c ssl_cert_file=/pg-tls/server.crt -c ssl_key_file=/pg-tls/server.key -c ssl_ca_file=/ci-tls/ca.crt' >/dev/null
container_started=1

db_port="$(docker port "$container_name" 5432/tcp | cut -d: -f2)"
for attempt in $(seq 1 60); do
  if docker exec "$container_name" pg_isready --username=postgres --dbname=postgres >/dev/null 2>&1; then
    break
  fi
  if [[ "$attempt" == 60 ]]; then
    echo "temporary PostgreSQL did not become ready" >&2
    docker logs "$container_name" >&2
    exit 1
  fi
  sleep 1
done

export NODE_EXTRA_CA_CERTS="$work_dir/tls/ca.crt"
export DATABASE_URL="postgresql://postgres:${db_password}@127.0.0.1:${db_port}/postgres"
bun -e 'import { Pool } from "pg"; const pool = new Pool({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: true }, connectionTimeoutMillis: 3000 }); try { await pool.query("SELECT 1"); } finally { await pool.end(); }'
bun test.ts
