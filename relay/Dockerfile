FROM oven/bun:1-alpine
WORKDIR /app
COPY package.json bun.lock ./
RUN bun install --frozen-lockfile --production
COPY server.ts names.ts identity-store.ts schema.sql ./
ENV PORT=8787
EXPOSE 8787
USER bun
CMD ["bun", "server.ts"]
