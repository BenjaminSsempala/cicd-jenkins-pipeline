# ---- base
FROM node:22-alpine AS base
WORKDIR /app
COPY package.json package-lock.json ./

# ---- deps: production dependencies only ----
FROM base AS deps
RUN npm ci --omit=dev

# ---- test: all dependencies + tests (build with --target test) 
FROM base AS test
RUN npm ci
COPY src/ src/
COPY tests/ tests/
RUN npm test

# ---- runtime: small final image with only what the app needs 
FROM node:22-alpine AS runtime
ENV NODE_ENV=production
# npm, corepack and yarn aren't needed to run the app and carry their own CVEs
RUN rm -rf /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/corepack /opt/yarn-* \
    /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack /usr/local/bin/yarn /usr/local/bin/yarnpkg
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY package.json ./
COPY src/ src/
USER node
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://localhost:3000/health || exit 1
CMD ["node", "src/server.js"]
