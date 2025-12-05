# Build stage
FROM node:18-alpine AS builder
WORKDIR /app

# Copiar archivos de dependencias
COPY package*.json ./
COPY server.js ./

# Instalar dependencias de producción y desarrollo
RUN npm ci --only=production && \
    npm ci --only=development

# Test stage
FROM builder AS tester
WORKDIR /app
COPY . .
RUN npm test

# Production stage
FROM node:18-alpine AS production
WORKDIR /app

# Crear usuario no-root para seguridad
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001

# Copiar node_modules desde builder
COPY --from=builder --chown=nodejs:nodejs /app/node_modules ./node_modules
COPY --from=builder --chown=nodejs:nodejs /app/package*.json ./
COPY --chown=nodejs:nodejs . .

# Cambiar a usuario no-root
USER nodejs

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD node -e "require('http').get('http://localhost:3000/health', (r) => {process.exit(r.statusCode === 200 ? 0 : 1)})"

EXPOSE 3000
CMD ["npm", "start"]
