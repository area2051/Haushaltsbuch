# Build context: repository root (see docker-compose.yml).

FROM node:22-slim AS web
WORKDIR /web
COPY web/package.json web/package-lock.json ./
RUN npm ci
COPY web ./
COPY server/openapi.json /server/openapi.json
RUN npm run build

FROM node:22-slim AS build
WORKDIR /app
COPY server/package.json server/package-lock.json ./
RUN npm ci
COPY server/tsconfig.json server/tsconfig.build.json ./
COPY server/src ./src
RUN npm run build

FROM node:22-slim
ENV NODE_ENV=production
WORKDIR /app
COPY server/package.json server/package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force
COPY --from=build /app/dist ./dist
COPY server/drizzle ./drizzle
COPY --from=web /web/dist ./web-dist
# Files copied from the host keep the host's mode bits. NAS shares (e.g. UGOS/Synology) grant
# access through ACLs, which COPY drops, so the files can end up unreadable for `node`.
# Make everything the app reads world-readable (directories traversable) before switching user.
RUN chmod -R a+rX package.json package-lock.json drizzle web-dist
USER node
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:'+(process.env.PORT||3000)+'/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
CMD ["node", "dist/main.js"]
