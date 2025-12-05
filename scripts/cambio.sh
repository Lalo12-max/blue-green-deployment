#!/bin/bash
set -e

PASSWORD="$1"

if [ -z "$PASSWORD" ]; then
    echo "❌ Error: Se requiere contraseña como parámetro"
    echo "Uso: $0 <password>"
    exit 1
fi

echo "🚀 GitHub Actions - Pipeline CI/CD Blue-Green"
echo "============================================="
date
echo ""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

sudo_with_pass() {
    echo "$PASSWORD" | sudo -S "$@" 2>/dev/null
}

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
    exit 1
}

# =====================================================
# FASE 0: Verificación del servidor
# =====================================================
log "FASE 0: Verificación del entorno..."

if ! command -v docker >/dev/null 2>&1; then
    error "Docker no está instalado"
fi

# =====================================================
# FASE 1: (ELIMINADA)  — ya no ejecutamos pruebas aquí
# =====================================================

# =====================================================
# FASE 2: Construcción Docker
# =====================================================
log "FASE 2: Construcción Docker..."

cd ~/app

if docker build -t blue-green-app:latest .; then
    log "✅ Imagen Docker construida correctamente"
else
    error "❌ Error al construir la imagen Docker"
fi

IMAGE_SIZE=$(docker image inspect blue-green-app:latest --format='{{.Size}}' | numfmt --to=iec --format="%.2f")

# =====================================================
# FASE 3: Detectar ambiente actual
# =====================================================
log "FASE 3: Detectando ambiente..."

ACTIVE_CONF=$(sudo_with_pass readlink -f /etc/nginx/sites-enabled/app_active.conf || echo "")

if [[ "$ACTIVE_CONF" == *"app_blue.conf" ]]; then
    CURRENT_ENV="blue"
    TARGET_ENV="green"
    TARGET_PORT="3002"
    TARGET_CONF="app_green.conf"
    CURRENT_PORT="3001"
else
    CURRENT_ENV="green"
    TARGET_ENV="blue"
    TARGET_PORT="3001"
    TARGET_CONF="app_blue.conf"
    CURRENT_PORT="3002"
fi

log "🌍 Ambiente actual: $CURRENT_ENV"
log "🎯 Ambiente destino: $TARGET_ENV"

# =====================================================
# FASE 4: Configurar Nginx
# =====================================================
log "FASE 4: Configurando Nginx..."

if [ "$TARGET_ENV" = "blue" ]; then

sudo_with_pass tee /etc/nginx/sites-available/app_blue.conf >/dev/null <<EOF
upstream app_backend {
    server 127.0.0.1:3001;
}

server {
    listen 80;
    location / {
        proxy_pass http://app_backend;
    }
}
EOF

else

sudo_with_pass tee /etc/nginx/sites-available/app_green.conf >/dev/null <<EOF
upstream app_backend {
    server 127.0.0.1:3002;
}

server {
    listen 80;
    location / {
        proxy_pass http://app_backend;
    }
}
EOF

fi

log "✅ Configuración Nginx lista"

# =====================================================
# FASE 5: Despliegue nuevo ambiente
# =====================================================
log "FASE 5: Desplegando $TARGET_ENV..."

cp -r ~/app/* /srv/app/$TARGET_ENV/ || true

cd /srv/app/$TARGET_ENV
docker-compose down || true
docker-compose build --no-cache
docker-compose up -d

# =====================================================
# FASE 6: Health Check
# =====================================================
log "FASE 6: Verificando salud..."

ATTEMPT=1
while [[ $ATTEMPT -le 15 ]]; do
    CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$TARGET_PORT/health || echo "000")
    if [ "$CODE" = "200" ]; then
        log "✅ Ambiente saludable"
        break
    fi
    sleep 3
    ((ATTEMPT++))
done

# =====================================================
# FASE 7: Switch Blue-Green
# =====================================================
log "FASE 7: Cambio Blue-Green..."

sudo_with_pass ln -sfn /etc/nginx/sites-available/$TARGET_CONF /etc/nginx/sites-enabled/app_active.conf
sudo_with_pass systemctl reload nginx

# =====================================================
# FASE 8: Limpieza
# =====================================================
log "FASE 8: Limpieza..."

if [ "$CURRENT_ENV" != "none" ]; then
    cd /srv/app/$CURRENT_ENV
    docker-compose down || true
fi

docker image prune -f || true

# =====================================================
# FIN
# =====================================================
log "🎉 Pipeline completado exitosamente"
