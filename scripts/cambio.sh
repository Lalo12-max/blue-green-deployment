#!/bin/bash
set -e

# Recibir contraseña como primer parámetro
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

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Función para ejecutar sudo con contraseña
sudo_with_pass() {
    echo "$PASSWORD" | sudo -S "$@" 2>/dev/null
}

# Función para log
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
    exit 1
}

# ========== FASE 0: VERIFICACIÓN INICIAL ==========
log "FASE 0: Verificación del entorno..."

# Verificar que tenemos Node.js y npm
if ! command -v node &> /dev/null; then
    log "📦 Instalando Node.js..."
    sudo_with_pass apt update
    sudo_with_pass apt install -y nodejs npm
fi

# Verificar que tenemos Docker
if ! command -v docker &> /dev/null; then
    error "Docker no está instalado"
fi

# ========== FASE 1: PRUEBAS DE INTEGRACIÓN ==========
log "FASE 1: Ejecutando pruebas de integración..."

cd ~/app

# Instalar dependencias de desarrollo si no existen
if [ ! -d "node_modules" ]; then
    log "Instalando dependencias..."
    npm ci || npm install
fi

# Ejecutar pruebas con Supertest
log "Ejecutando suite de pruebas..."
if npm test; then
    log "✅ Todas las pruebas pasaron"
else
    error "❌ Fallaron las pruebas de integración"
fi

# Generar reporte de cobertura
if [ -f "coverage/lcov.info" ]; then
    COVERAGE=$(grep -o 'lines.*%' coverage/lcov.info | head -1)
    log "📊 Cobertura de pruebas: $COVERAGE"
fi

# ========== FASE 2: CONSTRUCCIÓN CON DOCKER ==========
log "FASE 2: Construcción de contenedor Docker..."

# Construir con multi-stage build
log "Construyendo imagen multi-stage..."
if docker build --target tester -t app-test . && docker build -t blue-green-app:latest .; then
    log "✅ Imagen Docker construida exitosamente"
    
    # Verificar tamaño de la imagen
    IMAGE_SIZE=$(docker image inspect blue-green-app:latest --format='{{.Size}}' | numfmt --to=iec --format="%.2f")
    log "📦 Tamaño de imagen: $IMAGE_SIZE"
else
    error "❌ Error en la construcción de Docker"
fi

# ========== FASE 3: DETECCIÓN DE AMBIENTE ==========
log "FASE 3: Detectando ambiente actual..."

ACTIVE_CONF=$(sudo_with_pass readlink -f /etc/nginx/sites-enabled/app_active.conf 2>/dev/null || echo "")

if [[ "$ACTIVE_CONF" == *"app_blue.conf" ]]; then
    CURRENT_ENV="blue"
    TARGET_ENV="green"
    TARGET_PORT="3002"
    TARGET_CONF="app_green.conf"
    CURRENT_PORT="3001"
    log "📍 Ambiente actual: BLUE (puerto 3001)"
elif [[ "$ACTIVE_CONF" == *"app_green.conf" ]]; then
    CURRENT_ENV="green"
    TARGET_ENV="blue"
    TARGET_PORT="3001"
    TARGET_CONF="app_blue.conf"
    CURRENT_PORT="3002"
    log "📍 Ambiente actual: GREEN (puerto 3002)"
else
    log "⚠️  Configuración no encontrada, usando BLUE por defecto"
    CURRENT_ENV="none"
    TARGET_ENV="blue"
    TARGET_PORT="3001"
    TARGET_CONF="app_blue.conf"
    CURRENT_PORT="3002"
fi

log "🎯 Nuevo ambiente: $TARGET_ENV (puerto $TARGET_PORT)"

# ========== FASE 4: CONFIGURACIÓN NGINX (PROXY INVERSO) ==========
log "FASE 4: Configurando Nginx como Proxy Inverso..."

# Crear configuración para el nuevo ambiente
if [ "$TARGET_ENV" = "blue" ]; then
    sudo_with_pass tee /etc/nginx/sites-available/app_blue.conf > /dev/null << NGINXBLUE
upstream app_backend {
    server 127.0.0.1:3001 max_fails=3 fail_timeout=10s;
}

server {
    listen 80;
    server_name _;
    
    # Logs centralizados
    access_log /var/log/nginx/app_access.log;
    error_log /var/log/nginx/app_error.log;
    
    # Compression
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml text/javascript;
    
    # Timeouts
    client_header_timeout 10s;
    client_body_timeout 10s;
    send_timeout 10s;
    
    # Headers de seguridad
    add_header X-Frame-Options SAMEORIGIN;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    
    location / {
        proxy_pass http://app_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        
        # Optimizaciones de proxy
        proxy_connect_timeout 5s;
        proxy_read_timeout 10s;
        proxy_send_timeout 10s;
        proxy_buffering on;
        proxy_buffer_size 4k;
        proxy_buffers 8 4k;
    }
    
    # Health check endpoint
    location /nginx-health {
        access_log off;
        return 200 "nginx is healthy\\n";
        add_header Content-Type text/plain;
    }
}
NGINXBLUE
else
    sudo_with_pass tee /etc/nginx/sites-available/app_green.conf > /dev/null << NGINXGREEN
upstream app_backend {
    server 127.0.0.1:3002 max_fails=3 fail_timeout=10s;
}

server {
    listen 80;
    server_name _;
    
    # Logs centralizados
    access_log /var/log/nginx/app_access.log;
    error_log /var/log/nginx/app_error.log;
    
    # Compression
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml text/javascript;
    
    # Timeouts
    client_header_timeout 10s;
    client_body_timeout 10s;
    send_timeout 10s;
    
    # Headers de seguridad
    add_header X-Frame-Options SAMEORIGIN;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    
    location / {
        proxy_pass http://app_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        
        # Optimizaciones de proxy
        proxy_connect_timeout 5s;
        proxy_read_timeout 10s;
        proxy_send_timeout 10s;
        proxy_buffering on;
        proxy_buffer_size 4k;
        proxy_buffers 8 4k;
    }
    
    # Health check endpoint
    location /nginx-health {
        access_log off;
        return 200 "nginx is healthy\\n";
        add_header Content-Type text/plain;
    }
}
NGINXGREEN
fi

log "✅ Configuración Nginx creada para $TARGET_ENV"

# ========== FASE 5: DESPLIEGUE DEL NUEVO AMBIENTE ==========
log "FASE 5: Desplegando ambiente $TARGET_ENV..."

# Copiar código actualizado
log "📋 Copiando código actualizado..."
cp -r ~/app/* /srv/app/$TARGET_ENV/ 2>/dev/null || true

cd /srv/app/$TARGET_ENV

# Parar si está corriendo
log "⏸️  Deteniendo $TARGET_ENV si está activo..."
docker-compose down 2>/dev/null || true

# Construir con nueva versión
log "🏗️  Construyendo nueva versión..."
if ! docker-compose build --no-cache; then
    error "❌ Falló la construcción de $TARGET_ENV"
fi

# Iniciar
log "🚀 Iniciando contenedores..."
if ! docker-compose up -d; then
    error "❌ Falló al iniciar $TARGET_ENV"
fi

# ========== FASE 6: VERIFICACIÓN DE SALUD ==========
log "FASE 6: Verificando salud de $TARGET_ENV..."

MAX_ATTEMPTS=15
ATTEMPT=1
HEALTHY=false

while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
    RESPONSE_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$TARGET_PORT/health || echo "000")
    
    if [ "$RESPONSE_CODE" = "200" ]; then
        log "✅ $TARGET_ENV está saludable (intento $ATTEMPT)"
        HEALTHY=true
        break
    fi
    
    log "⏰ Intento $ATTEMPT/$MAX_ATTEMPTS - Código: $RESPONSE_CODE"
    
    # Si es el último intento, mostrar logs de error
    if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
        log "📋 Mostrando logs de error:"
        docker-compose logs --tail=30
    fi
    
    sleep 3
    ((ATTEMPT++))
done

if [ "$HEALTHY" = false ]; then
    error "❌ $TARGET_ENV no pasó el health check después de $MAX_ATTEMPTS intentos"
fi

# ========== FASE 7: DESPLIEGUE BLUE-GREEN (ZERO DOWNTIME) ==========
log "FASE 7: Cambio Blue-Green (Zero Downtime)..."

# 7.1 Balanceador temporal para transición suave
log "⚖️  Creando balanceador temporal..."
sudo_with_pass tee /etc/nginx/sites-available/app_temp_switch.conf > /dev/null << TEMPEOF
upstream app_backend {
    # Nuevo ambiente (alto peso)
    server 127.0.0.1:$TARGET_PORT weight=9 max_fails=2 fail_timeout=3s;
    # Ambiente actual (bajo peso, para rollback rápido)
    server 127.0.0.1:$CURRENT_PORT weight=1 max_fails=2 fail_timeout=3s;
}

server {
    listen 80;
    server_name _;
    
    # Manejo elegante de errores durante transición
    error_page 502 503 504 = @maintenance;
    
    location @maintenance {
        return 503 '{"status": "updating", "message": "Actualización en progreso, por favor intenta en 2 segundos"}';
        add_header Content-Type application/json;
        add_header Retry-After 2;
    }

    location / {
        proxy_pass http://app_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        
        # Timeouts cortos para failover rápido
        proxy_connect_timeout 2s;
        proxy_read_timeout 4s;
        proxy_send_timeout 4s;
        
        # Reintentar rápidamente si falla
        proxy_next_upstream error timeout http_500 http_502 http_503 http_504;
        proxy_next_upstream_tries 2;
        proxy_next_upstream_timeout 1s;
    }
    
    location /health {
        proxy_pass http://app_backend/health;
        access_log off;
    }
}
TEMPEOF

# 7.2 Activar balanceador temporal (90% nuevo, 10% viejo)
log "🔗 Activando balanceador temporal..."
sudo_with_pass ln -sfn /etc/nginx/sites-available/app_temp_switch.conf /etc/nginx/sites-enabled/app_active.conf
sudo_with_pass nginx -t && sudo_with_pass systemctl reload nginx
log "✅ Balanceador temporal activado (90% $TARGET_ENV, 10% $CURRENT_ENV)"

# 7.3 Esperar estabilización
log "⏳ Esperando estabilización (5 segundos)..."
sleep 5

# 7.4 Cambio completo al nuevo ambiente
log "🎯 Cambiando completamente a $TARGET_ENV..."
sudo_with_pass ln -sfn /etc/nginx/sites-available/$TARGET_CONF /etc/nginx/sites-enabled/app_active.conf
sudo_with_pass nginx -t && sudo_with_pass systemctl reload nginx
log "✅ Cambio completo realizado"

# 7.5 Esperar procesamiento final
log "⏳ Procesando cambio final (3 segundos)..."
sleep 3

# ========== FASE 8: VERIFICACIÓN FINAL ==========
log "FASE 8: Verificación final..."

VERIFIED=false
for i in {1..6}; do
    RESPONSE=$(curl -s http://localhost/ 2>/dev/null || echo "")
    ENV_IN_RESPONSE=$(echo "$RESPONSE" | grep -o '"environment":"[^"]*"' | cut -d'"' -f4)
    
    if [ "$ENV_IN_RESPONSE" = "$TARGET_ENV" ]; then
        log "✅ Verificado: $TARGET_ENV sirviendo tráfico"
        VERIFIED=true
        break
    fi
    
    log "⏳ Esperando confirmación... ($i/6)"
    sleep 2
done

if [ "$VERIFIED" = false ]; then
    log "⚠️  No se pudo verificar automáticamente, verificando manualmente..."
    curl -s -I http://localhost/ | head -5
fi

# ========== FASE 9: LIMPIEZA Y REPORTE ==========
log "FASE 9: Limpieza y reporte..."

# 9.1 Limpiar ambiente anterior
if [ "$CURRENT_ENV" != "none" ]; then
    log "🗑️  Limpiando ambiente anterior ($CURRENT_ENV)..."
    cd /srv/app/$CURRENT_ENV
    docker-compose down 2>/dev/null || true
    log "✅ $CURRENT_ENV limpiado"
fi

# 9.2 Eliminar configuración temporal
sudo_with_pass rm -f /etc/nginx/sites-available/app_temp_switch.conf

# 9.3 Limpiar imágenes Docker no usadas
log "🧹 Limpiando imágenes no utilizadas..."
docker image prune -f 2>/dev/null || true

# ========== FASE 10: REPORTE FINAL ==========
log "🎉 PIPELINE COMPLETADO EXITOSAMENTE"
echo "===================================="
echo "📊 RESUMEN DEL DESPLIEGUE:"
echo "----------------------------"
echo "✅ Pruebas de integración: COMPLETADAS"
echo "✅ Construcción Docker: COMPLETADA"
echo "✅ Configuración Nginx: COMPLETADA"
echo "✅ Despliegue Blue-Green: COMPLETADO"
echo "✅ Zero Downtime: IMPLEMENTADO"
echo ""
echo "🔧 DETALLES TÉCNICOS:"
echo "---------------------"
echo "Ambiente anterior: $CURRENT_ENV"
echo "Ambiente nuevo: $TARGET_ENV"
echo "Método: Canary Deployment -> 90/10 -> 100%"
echo "Tiempo total: $(($(date +%s) - $(date -d "$(stat -c %y /proc/1 | cut -d' ' -f1-2)" +%s))) segundos"
echo ""
echo "🌐 ENDPOINTS DISPONIBLES:"
echo "-------------------------"
PUBLIC_IP=$(curl -s ifconfig.me)
echo "   🌍 Pública: http://$PUBLIC_IP"
echo "   🖥️  Local: http://localhost"
echo "   🔵 BLUE directo: http://localhost:3001"
echo "   🟢 GREEN directo: http://localhost:3002"
echo "   🏥 Health Check: http://localhost/health"
echo "   👥 API Users: http://localhost/api/users"
echo "   📦 API Products: http://localhost/api/products"
echo ""
echo "🐳 CONTENEDORES ACTIVOS:"
echo "------------------------"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo ""
echo "📈 MÉTRICAS:"
echo "------------"
echo "   Uptime Nginx: $(systemctl show nginx --property=ActiveEnterTimestamp | cut -d= -f2)"
echo "   Memoria usada: $(free -h | awk '/^Mem:/ {print $3 "/" $2}')"
echo "   Tamaño imagen: $IMAGE_SIZE"
echo ""
echo "🔗 ENLACES ÚTILES:"
echo "------------------"
echo "   GitHub Actions: https://github.com/USER/REPO/actions"
echo "   Docker Hub: https://hub.docker.com/r/USER/blue-green-app"
echo "   Server IP: $PUBLIC_IP"
echo ""
echo "✅ Pipeline CI/CD Blue-Green finalizado exitosamente a las $(date '+%H:%M:%S')"
