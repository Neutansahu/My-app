# syntax=docker/dockerfile:1

# Stage 1: install production dependencies (cached unless package*.json changes)
FROM node:20-alpine AS deps
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev

# Stage 2: minimal runtime image
FROM node:20-alpine
WORKDIR /app
ENV NODE_ENV=production \
    PORT=8080
COPY --from=deps /app/node_modules ./node_modules
COPY package*.json server.js ./

# Run as the unprivileged "node" user that ships with the image
USER node
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/health || exit 1

CMD ["node", "server.js"]
