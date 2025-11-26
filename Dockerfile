FROM oven/bun:1.1-alpine AS base
WORKDIR /app

RUN apk add --no-cache git curl ca-certificates

# ------------------------------------------------------------------
# Stage 2: Dependencies
# ------------------------------------------------------------------
FROM base AS deps
WORKDIR /app

COPY package.json bun.lockb* ./
COPY packages/db/package.json ./packages/db/
COPY apps/sim/package.json ./apps/sim/

# Instalar sin frozen-lockfile para permitir resolución de deps
RUN bun install || bun install --no-save

# Instalar lodash explícitamente si no está
RUN bun add lodash || true

# ------------------------------------------------------------------
# Stage 3: Builder  
# ------------------------------------------------------------------
FROM base AS builder
WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY . .

ARG NEXT_PUBLIC_APP_URL
ENV NEXT_PUBLIC_APP_URL=${NEXT_PUBLIC_APP_URL}
ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
ENV SKIP_ENV_VALIDATION=true

# Generar schema + build
RUN cd packages/db && bunx drizzle-kit generate || true
RUN bun run build --filter=sim

# ------------------------------------------------------------------
# Stage 4: Runner
# ------------------------------------------------------------------
FROM oven/bun:1.1-alpine AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1

RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 nextjs

# Copiar archivos built
COPY --from=builder --chown=nextjs:nodejs /app/apps/sim/.next ./apps/sim/.next
COPY --from=builder --chown=nextjs:nodejs /app/apps/sim/public ./apps/sim/public
COPY --from=builder --chown=nextjs:nodejs /app/node_modules ./node_modules
COPY --from=builder --chown=nextjs:nodejs /app/package.json ./package.json
COPY --from=builder --chown=nextjs:nodejs /app/apps ./apps
COPY --from=builder --chown=nextjs:nodejs /app/packages ./packages

USER nextjs
EXPOSE 3000

ENV PORT=3000
ENV HOSTNAME="0.0.0.0"

WORKDIR /app/apps/sim
CMD ["bun", "run", "start"]