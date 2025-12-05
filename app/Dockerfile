FROM node:18-alpine AS builder
WORKDIR /app

COPY app/package*.json ./app/
COPY app ./app/

RUN cd app && npm install --omit=dev

FROM node:18-alpine AS production
WORKDIR /app

RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001

COPY --from=builder --chown=nodejs:nodejs /app/app ./ 

USER nodejs

EXPOSE 3000
CMD ["node", "server.js"]
