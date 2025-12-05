#!/bin/bash
set -euo pipefail

# Mostrar comando y línea cuando falle
trap 'echo "[ERROR] Falló en la línea $LINENO. Último comando: $BASH_COMMAND"' ERR

PASSWORD="${1:-}"

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

# Ejecutar comandos con sudo
sudo_with_pass() {
    printf '%s\n' "$PASSWORD" | sudo -S -p '' "$@" 2>/dev/null
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

command -v docker >/dev/null 2>&1 || error "Docker no está instalado"
command -v docker-compose >/dev/null 2>&1 || error "docker-compose no está instalado"
command -v rsync >/dev/null 2>&1 || error "rsync no está instalado"

# =====================================================
# FASE 2: Construcción Docker
# =====================================================
log "FASE 2: Preparando contexto y construcción Docker..."

if [ ! -d "$HOME/app" ]; then
    error "No existe el directorio $HOME/app"
fi

IMAGE_NAME="blue-green-app:latest"

cd "$HOME/app"

if docker build -t "$IMAGE_NAME" .; then
    log "✅ Imagen Docker construida correctamente"
else
    error "❌ Error al construir la imagen Docker"
fi

IMAGE_SIZE=""
if docker image inspect "$IMAGE_NAME" --format='{{.Size}}' >/dev/null 2>&1; then
    IMAGE_SIZE=$(docker image inspect "$IMAGE_NAME" --format='{{.Size}}' | numfmt --to=iec --format="%.2f") || true
fi

# =====================================================
# FASE 3: Detectar ambiente actual
# =====================================================
log "FASE 3: Detectando ambiente..."

ACTIVE_CONF="$(sudo_with_pass readlink -f /etc/nginx/sites-enabled/app_active.conf 2>/dev/null || true)"

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
    # Primer despliegue
    CURRENT_ENV="none"
    TARGET_ENV="blue"
    TARGET_PORT="3001"
    TARGET_CONF="app_blue.conf"
    CURRENT_PORT=""
fi

log "🌍 Ambiente actual: $CURRENT_ENV"
log "🎯 Ambiente destino: $TARGET_ENV"

# =====================================================
# FASE 4: Configurar Nginx
# =====================================================
log "FASE 4: Configurando Nginx..."

sudo_with_pass mkdir -p /etc/nginx/sites-available

if [ "$TARGET_ENV" = "blue" ]; then
sudo_with_pass tee /etc/nginx/sites-available/app_blue.conf >/dev/null <<'EOF'
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
sudo_with_pass tee /etc/nginx/sites-available/app_green.conf >/dev/null <<'EOF'
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

sudo_with_pass mkdir -p /srv/app/"$TARGET_ENV"/app

log "📦 Sincronizando código a /srv/app/$TARGET_ENV/app ..."
sudo_with_pass rsync -a --delete "$HOME/app"/ /srv/app/"$TARGET_ENV"/app/

cd /srv/app/"$TARGET_ENV"

# 🔥 Eliminar contenedores huérfanos
docker-compose down --remove-orphans || true
docker rm -f app_blue 2>/dev/null || true
docker rm -f app_green 2>/dev/null || true

# 🔧 Construir y levantar
docker-compose build --no-cache
docker-compose up -d

# =====================================================
# FASE 6: Health Check
# =====================================================
log "FASE 6: Verificando salud..."

ATTEMPT=1
MAX_ATTEMPTS=15
SLEEP_SECONDS=3

while [[ $ATTEMPT -le $MAX_ATTEMPTS ]]; do
    CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:"$TARGET_PORT"/health || echo "000")
    if [ "$CODE" = "200" ]; then
        log "✅ Ambiente saludable"
        break
    fi
    log "⏳ Esperando salud... intento $ATTEMPT/$MAX_ATTEMPTS (http code: $CODE)"
    sleep "$SLEEP_SECONDS"
    ((ATTEMPT++))
done

if [[ $ATTEMPT -gt $MAX_ATTEMPTS ]]; then
    error "❌ Health check falló después de $MAX_ATTEMPTS intentos"
fi

# =====================================================
# FASE 7: Switch Blue-Green
# =====================================================
log "FASE 7: Cambio Blue-Green..."

sudo_with_pass ln -sfn /etc/nginx/sites-available/"$TARGET_CONF" /etc/nginx/sites-enabled/app_active.conf
sudo_with_pass systemctl reload nginx || sudo_with_pass service nginx reload || error "No se pudo recargar nginx"

# =====================================================
# FASE 8: Limpieza
# =====================================================
log "FASE 8: Limpieza..."

if [ "$CURRENT_ENV" != "none" ]; then
    if [ -d /srv/app/"$CURRENT_ENV" ]; then
        pushd /srv/app/"$CURRENT_ENV" >/dev/null || true
        docker-compose down || true
        popd >/dev/null || true
    fi
fi

docker image prune -f || true

# =====================================================
# FIN
# =====================================================
log "🎉 Pipeline completado exitosamente"
