FROM oven/bun:1-alpine
WORKDIR /app
COPY package.json bun.lock ./
RUN bun install --frozen-lockfile --production
COPY server.ts names.ts identity-store.ts ./
RUN mkdir -p /data && chown bun:bun /data
ENV PORT=8787 DATA_DIR=/data
EXPOSE 8787
USER bun
CMD ["bun", "server.ts"]
