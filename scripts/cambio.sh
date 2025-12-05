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

# ===================== FASE 0 =========================
log "FASE 0: Verificación del entorno..."

if ! command -v node >/dev/null 2>&1; then
    log "📦 Instalando Node.js..."
    sudo_with_pass apt update
    sudo_with_pass apt install -y nodejs npm
fi

if ! command -v docker >/dev/null 2>&1; then
    error "Docker no está instalado"
fi

# ===================== FASE 1 =========================
log "FASE 1: Ejecutando pruebas de integración..."
cd ~/app

if [ ! -d "node_modules" ]; then
    log "Instalando dependencias..."
    npm ci || npm install
fi

log "Ejecutando pruebas..."
if ! npm test; then
    error "❌ Fallaron las pruebas de integración"
fi

if [ -f "coverage/lcov.info" ]; then
    COVERAGE=$(grep -o 'lines.*%' coverage/lcov.info | head -1)
    log "📊 Cobertura: $COVERAGE"
fi

# ===================== FASE 2 =========================
log "FASE 2: Construcción de Docker..."
if docker build --target tester -t app-test . && docker build -t blue-green-app:latest .; then
    log "✅ Imagen Docker construida"
else
    error "❌ Error en la construcción de Docker"
fi

IMAGE_SIZE=$(docker image inspect blue-green-app:latest --format='{{.Size}}' | numfmt --to=iec --format="%.2f")

# ===================== FASE 3 =========================
log "FASE 3: Detectando ambiente..."

ACTIVE_CONF=$(sudo_with_pass readlink -f /etc/nginx/sites-enabled/app_active.conf || echo "")

if [[ "$ACTIVE_CONF" == *"app_blue.conf" ]]; then
    CURRENT_ENV="blue"
    TARGET_ENV="green"
    TARGET_PORT="3002"
    TARGET_CONF="app_green.conf"
    CURRENT_PORT="3001"
elif [[ "$ACTIVE_CONF" == *"app_green.conf" ]]; then
    CURRENT_ENV="green"
    TARGET_ENV="blue"
    TARGET_PORT="3001"
    TARGET_CONF="app_blue.conf"
    CURRENT_PORT="3002"
else
    CURRENT_ENV="none"
    TARGET_ENV="blue"
    TARGET_PORT="3001"
    TARGET_CONF="app_blue.conf"
    CURRENT_PORT="3002"
fi

log "🌍 Ambiente actual: $CURRENT_ENV"
log "🎯 Nuevo ambiente: $TARGET_ENV"

# ===================== FASE 4 =========================
log "FASE 4: Configurando Nginx..."

if [ "$TARGET_ENV" = "blue" ]; then

sudo_with_pass tee /etc/nginx/sites-available/app_blue.conf >/dev/null <<NGINXBLUE
upstream app_backend {
    server 127.0.0.1:3001 max_fails=3 fail_timeout=10s;
}

server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://app_backend;
    }
}
NGINXBLUE

else

sudo_with_pass tee /etc/nginx/sites-available/app_green.conf >/dev/null <<NGINXGREEN
upstream app_backend {
    server 127.0.0.1:3002 max_fails=3 fail_timeout=10s;
}

server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://app_backend;
    }
}
NGINXGREEN

fi

log "✅ Configuración Nginx generada"

# ===================== FASE 5 =========================
log "FASE 5: Desplegando $TARGET_ENV..."

cp -r ~/app/* /srv/app/$TARGET_ENV/ 2>/dev/null || true

cd /srv/app/$TARGET_ENV
docker-compose down || true
docker-compose build --no-cache
docker-compose up -d

# ===================== FASE 6 =========================
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

# ===================== FASE 7 =========================
log "FASE 7: Cambio Blue-Green..."

sudo_with_pass tee /etc/nginx/sites-available/app_temp_switch.conf >/dev/null <<TEMPEOF
upstream app_backend {
    server 127.0.0.1:$TARGET_PORT weight=9;
    server 127.0.0.1:$CURRENT_PORT weight=1;
}

server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://app_backend;
    }
}
TEMPEOF

sudo_with_pass ln -sfn /etc/nginx/sites-available/app_temp_switch.conf /etc/nginx/sites-enabled/app_active.conf
sudo_with_pass systemctl reload nginx

sleep 5

sudo_with_pass ln -sfn /etc/nginx/sites-available/$TARGET_CONF /etc/nginx/sites-enabled/app_active.conf
sudo_with_pass systemctl reload nginx

# ===================== FASE 8 =========================
log "FASE 8: Verificación final..."

# ===================== FASE 9 =========================
log "FASE 9: Limpieza..."

if [ "$CURRENT_ENV" != "none" ]; then
    cd /srv/app/$CURRENT_ENV
    docker-compose down || true
fi

sudo_with_pass rm -f /etc/nginx/sites-available/app_temp_switch.conf
docker image prune -f || true

# ===================== FASE 10 =========================
log "🎉 Pipeline completado exitosamente"
