# ============================================
# Dockerfile definitivo para SimStudio (2025)
# ============================================

FROM oven/bun:1.1-alpine AS base
WORKDIR /app

# ------------------------------------------------------------------
# 1. Dependencias del sistema (solo lo necesario)
# ------------------------------------------------------------------
RUN apk add --no-cache git curl ca-certificates

# ------------------------------------------------------------------
# 2. Instalación de dependencias (con lockfile)
# ------------------------------------------------------------------
FROM base AS deps
COPY package.json bun.lockb* ./
COPY packages/db/package.json ./packages/db/
COPY apps/sim/package.json ./apps/sim/
RUN bun install --frozen-lockfile

# ------------------------------------------------------------------
# 3. Build de la app
# ------------------------------------------------------------------
FROM base AS builder
COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Variables de entorno de build
ARG NEXT_PUBLIC_APP_URL
ENV NEXT_PUBLIC_APP_URL=${NEXT_PUBLIC_APP_URL}
ENV NODE_ENV=production
ENV NEXT_TELEMETERY_DISABLED=1

# Generar schema + build
RUN cd packages/db && bunx drizzle-kit generate || true
RUN bun run build --filter=sim

# ------------------------------------------------------------------
# 4. Imagen final ultra-ligera (solo runtime)
# ------------------------------------------------------------------
FROM oven/bun:1.1-alpine AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
ENV PORT=3000

# Usuario no-root
RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs

# Copiar solo lo necesario del standalone build
COPY --from=builder --chown=nextjs:nodejs /app/apps/sim/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/apps/sim/.next/static ./apps/sim/.next/static
COPY --from=builder --chown=nextjs:nodejs /app/apps/sim/public ./apps/sim/public

USER nextjs
EXPOSE 3000

CMD ["bun", "server.js"]