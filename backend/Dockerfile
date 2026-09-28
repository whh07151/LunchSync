# syntax=docker/dockerfile:1
FROM node:24.11.1-bookworm-slim AS dependencies

WORKDIR /app
COPY package.json package-lock.json .npmrc ./
RUN npm ci

FROM dependencies AS build

COPY . .
RUN npm run build

FROM node:24.11.1-bookworm-slim AS runtime

ENV NODE_ENV=production \
    PORT=3000

WORKDIR /app
RUN groupadd --gid 10001 lunchsync \
    && useradd --uid 10001 --gid 10001 --no-create-home \
        --home-dir /app --shell /usr/sbin/nologin lunchsync

COPY package.json package-lock.json .npmrc ./
RUN npm ci --omit=dev \
    && npm cache clean --force

COPY --from=build --chown=lunchsync:lunchsync /app/dist ./dist
COPY --from=build --chown=lunchsync:lunchsync /app/public ./public

USER 10001:10001
EXPOSE 3000
STOPSIGNAL SIGTERM
HEALTHCHECK --interval=30s --timeout=3s --start-period=20s --retries=3 \
    CMD ["node", "-e", "fetch('http://127.0.0.1:3000/api/ready').then((response) => process.exit(response.ok ? 0 : 1)).catch(() => process.exit(1))"]

CMD ["node", "dist/main"]
