# ============================================
# Dockerfile definitivo para SimStudio (2025)
# ============================================

FROM oven/bun:1.1-alpine AS base
WORKDIR /app

RUN apk add --no-cache git curl ca-certificates

FROM base AS deps
COPY package.json bun.lockb* ./
COPY packages/db/package.json ./packages/db/
COPY apps/sim/package.json ./apps/sim/
RUN bun install --frozen-lockfile

FROM base AS builder
COPY --from=deps /app/node_modules ./node_modules
COPY . .

ARG NEXT_PUBLIC_APP_URL
ENV NEXT_PUBLIC_APP_URL=${NEXT_PUBLIC_APP_URL}
ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1

RUN cd packages/db && bunx drizzle-kit generate || true

# ← ESTA LÍNEA ES LA QUE LO SALVA TODO
RUN --mount=type=cache,target=/root/.bun/install/cache \
    NEXT_PRIVATE_TURBOPACK=0 \
    NODE_OPTIONS="--max-old-space-size=4096" \
    bun run build --filter=sim

FROM oven/bun:1.1-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
ENV PORT=3000

RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs

COPY --from=builder --chown=nextjs:nodejs /app/apps/sim/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/apps/sim/.next/static ./apps/sim/.next/static
COPY --from=builder --chown=nextjs:nodejs /app/apps/sim/public ./apps/sim/public

USER nextjs
EXPOSE 3000
CMD ["bun", "server.js"]
