# Backend image with the Flutter web app. Build context: the repository root
#   docker build -f backend/Dockerfile .

# --- Flutter web app
FROM ghcr.io/cirruslabs/flutter:stable AS web
WORKDIR /src/app
COPY app/pubspec.yaml app/pubspec.lock ./
RUN flutter pub get
COPY app/ ./
RUN flutter build web --release --no-web-resources-cdn --pwa-strategy=none

# --- Backend dependencies (native argon2 for linux)
FROM node:24-slim AS deps
WORKDIR /app
COPY backend/package.json backend/package-lock.json ./
RUN npm ci --omit=dev --no-audit --no-fund

# --- Runtime: TypeScript runs directly (type stripping of Node 24), no build step
FROM node:24-slim
ENV NODE_ENV=production WEB_ROOT=/app/web PORT=4000
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY backend/package.json ./
COPY backend/src ./src
COPY backend/migrations ./migrations
COPY backend/scripts ./scripts
COPY --from=web /src/app/build/web ./web
# Brotli / gzip copies of the web app, served as they are
RUN node scripts/compress-web.ts web
USER node
EXPOSE 4000
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s \
	CMD ["node", "-e", "fetch('http://127.0.0.1:4000/healthz').then(r => process.exit(r.ok ? 0 : 1), () => process.exit(1))"]
CMD ["node", "src/main.ts"]
