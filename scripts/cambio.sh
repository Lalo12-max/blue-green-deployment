#!/bin/bash
set -e

echo "🚀 GitHub Actions - Pipeline CI/CD Blue-Green"
echo "============================================="
date

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

#############################################
# FASE 0 - Verificación del entorno
#############################################
log "FASE 0: Verificación del entorno..."

if ! command -v docker >/dev/null 2>&1; then
    log "ERROR: Docker no está instalado"
    exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
    log "ERROR: docker compose (plugin) no está instalado"
    exit 1
fi

log "OK: docker y docker compose funcionan"

#############################################
# FASE 1 - Determinar versión activa
#############################################
if docker ps --format '{{.Names}}' | grep -q "app_green"; then
    ACTIVE="green"
    INACTIVE="blue"
else
    ACTIVE="blue"
    INACTIVE="green"
fi

log "Versión activa actual: $ACTIVE"
log "Versión inactiva que se va a desplegar: $INACTIVE"

#############################################
# FASE 1.1 - Definir puertos por entorno
#############################################
GREEN_PORT=3002
BLUE_PORT=3001

if [ "$INACTIVE" == "green" ]; then
    HEALTH_PORT=$GREEN_PORT
else
    HEALTH_PORT=$BLUE_PORT
fi

log "Puerto asignado a $INACTIVE: $HEALTH_PORT"

#############################################
# FASE 2 - Deploy a entorno inactivo
#############################################
TARGET_DIR="/srv/app/$INACTIVE"
log "FASE 2: Construyendo contenedores en $INACTIVE"

cd $TARGET_DIR

docker compose pull
docker compose build --no-cache
docker compose up -d

log "Esperando 10 segundos para que el servicio arranque..."
sleep 10

#############################################
# FASE 3 - Healthcheck dinámico
#############################################
log "FASE 3: Ejecutando healthcheck en puerto $HEALTH_PORT..."

if curl -fs http://localhost:$HEALTH_PORT/health >/dev/null; then
    log "Healthcheck OK en $INACTIVE (puerto $HEALTH_PORT)"
else
    log "ERROR: Healthcheck falló en $INACTIVE. Revirtiendo..."
    docker compose down || true
    exit 1
fi

#############################################
# FASE 4 - Nginx switch sin pedir password
#############################################
log "FASE 4: Cambiando tráfico a $INACTIVE"

# Se asume que deployer tiene NOPASSWD configurado para estos comandos
sudo ln -sf /srv/app/$INACTIVE/nginx.conf /etc/nginx/sites-enabled/app.conf
sudo nginx -t
sudo systemctl reload nginx

log "Tráfico redirigido a $INACTIVE correctamente"

#############################################
# FASE 5 - Apagar versión vieja
#############################################
log "FASE 5: Apagando versión $ACTIVE"

cd /srv/app/$ACTIVE
docker compose down || true

log "DEPLOY COMPLETADO CORRECTAMENTE 🚀"
exit 0
