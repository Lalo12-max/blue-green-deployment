# Build stage
FROM node:18-alpine AS builder
WORKDIR /app

# Copiar archivos de dependencias
COPY package*.json ./
COPY server.js ./
COPY app.js ./

# Instalar dependencias (solo producción)
RUN npm install --omit=dev

# Production stage
FROM node:18-alpine AS production
WORKDIR /app

# Crear usuario seguro
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001

# Copiar node_modules y código
COPY --from=builder --chown=nodejs:nodejs /app/node_modules ./node_modules
COPY --chown=nodejs:nodejs . .

# Cambiar usuario
USER nodejs

EXPOSE 3000

CMD ["node", "server.js"]
