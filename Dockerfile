# ============================================
# Stage 1: Base
# ============================================
FROM oven/bun:1.1.34-debian AS base
WORKDIR /app

# Instalar dependencias del sistema
RUN apt-get update && apt-get install -y \
    git \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# ============================================
# Stage 2: Dependencies
# ============================================
FROM base AS deps

# Clonar el repo
RUN git clone https://github.com/simstudioai/sim.git /tmp/sim && \
    cp -r /tmp/sim/* /app/ && \
    rm -rf /tmp/sim

# Instalar dependencias
RUN bun install --frozen-lockfile

# ============================================
# Stage 3: Builder
# ============================================
FROM base AS builder

# Copiar node_modules del stage anterior
COPY --from=deps /app /app

# Build args para variables de entorno de build-time
ARG NEXT_PUBLIC_APP_URL
ENV NEXT_PUBLIC_APP_URL=${NEXT_PUBLIC_APP_URL}

# Variables de build
ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1

# Generar Prisma client y hacer build
RUN cd packages/db && bunx drizzle-kit generate || true
RUN bun run build --filter=sim

# ============================================
# Stage 4: Runner
# ============================================
FROM oven/bun:1.1.34-debian AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1

# Crear usuario no-root
RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 nextjs && \
    mkdir -p /app/.next /app/uploads /app/.cache && \
    chown -R nextjs:nodejs /app

# Copiar archivos necesarios
COPY --from=builder --chown=nextjs:nodejs /app/apps/sim/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/apps/sim/.next/static ./apps/sim/.next/static
FROM oven/bun:1.1.34-debian AS base
WORKDIR /app

RUN apt-get update && apt-get install -y \
    git \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

FROM base AS deps

RUN git clone https://github.com/simstudioai/sim.git /tmp/sim && \
    cp -r /tmp/sim/* /app/ && \
    rm -rf /tmp/sim

RUN bun install --frozen-lockfile

FROM oven/bun:1.1.34-debian AS base
WORKDIR /app

RUN apt-get update && apt-get install -y \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

FROM base AS deps
WORKDIR /app

COPY package.json bun.lockb* ./
COPY packages/db/package.json ./packages/db/
COPY apps/sim/package.json ./apps/sim/

RUN bun install --frozen-lockfile || bun install

FROM base AS builder
WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY . .

ARG NEXT_PUBLIC_APP_URL
ENV NEXT_PUBLIC_APP_URL=${NEXT_PUBLIC_APP_URL}
ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1

RUN cd packages/db && bunx drizzle-kit generate || true
RUN bun run build --filter=sim || bun run build

FROM oven/bun:1.1.34-debian AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1

RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 nextjs

COPY --from=builder --chown=nextjs:nodejs /app/apps/sim/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/apps/sim/.next/static ./apps/sim/.next/static
COPY --from=builder --chown=nextjs:nodejs /app/apps/sim/public ./apps/sim/public
COPY --from=builder --chown=nextjs:nodejs /app/node_modules ./node_modules
COPY --from=builder --chown=nextjs:nodejs /app/package.json ./package.json

USER nextjs
EXPOSE 3000

ENV PORT=3000
ENV HOSTNAME="0.0.0.0"

CMD ["bun", "run", "start"]