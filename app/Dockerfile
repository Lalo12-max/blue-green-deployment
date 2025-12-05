# app/Dockerfile — usa CONTEXTO ./app
FROM node:18-alpine AS builder
WORKDIR /app

# Copiar package.json y package-lock para aprovechar cache
COPY package*.json ./

# Instalar dependencias (dev opcionalmente) — aquí instalamos todo para que funcione localmente
RUN npm install

# Copiar el resto de la aplicación desde el contexto (./app)
COPY . .

# Production stage
FROM node:18-alpine AS production
WORKDIR /app

RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001

# Copiar desde builder
COPY --from=builder --chown=nodejs:nodejs /app /app

USER nodejs

EXPOSE 3000

CMD ["node", "server.js"]
