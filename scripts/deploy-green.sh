#!/bin/bash
set -e

echo "🚀 Desplegando en ambiente GREEN..."

cd /srv/app/green

# Construir y levantar contenedores
docker-compose build
docker-compose up -d

# Esperar a que el servicio esté listo
sleep 10

# Verificar health check
HEALTH_CHECK=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3002/health || true)

if [ "$HEALTH_CHECK" = "200" ]; then
    echo "✅ GREEN está saludable"
else
    echo "❌ GREEN no está respondiendo correctamente"
    exit 1
fi
