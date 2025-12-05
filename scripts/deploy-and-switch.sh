#!/bin/bash
set -e

echo "🔧 Script de despliegue y switching Blue-Green"
echo "==============================================="

# Verificar que estamos como deployer
if [ "$(whoami)" != "deployer" ]; then
    echo "❌ Este script debe ejecutarse como usuario 'deployer'"
    exit 1
fi

# Función para verificar salud
check_health() {
    local port=$1
    local service=$2
    local max_attempts=12
    local attempt=1
    
    echo "⏳ Verificando salud de $service (puerto $port)..."
    
    while [ $attempt -le $max_attempts ]; do
        if timeout 5 curl -s -f http://localhost:$port/health > /dev/null 2>&1; then
            echo "✅ $service está saludable (intento $attempt)"
            return 0
        fi
        echo "⏰ Intento $attempt/$max_attempts - $service no responde, esperando 5s..."
        sleep 5
        ((attempt++))
    done
    
    echo "❌ ERROR: $service no responde después de $max_attempts intentos"
    echo "💡 Revisa los logs: docker-compose logs"
    return 1
}

# Función para desplegar en un ambiente
deploy_environment() {
    local env=$1
    local port=$2
    
    echo ""
    echo "🚀 DESPLEGANDO EN AMBIENTE $env"
    echo "================================"
    
    cd /srv/app/$env
    
    # Parar si está corriendo
    echo "⏸️  Deteniendo $env si está activo..."
    docker-compose down 2>/dev/null || true
    
    # Limpiar imágenes viejas
    echo "🧹 Limpiando recursos Docker..."
    docker system prune -f 2>/dev/null || true
    
    # Construir nueva imagen
    echo "🏗️  Construyendo imagen para $env..."
    if ! docker-compose build --no-cache; then
        echo "❌ ERROR: Falló la construcción de $env"
        return 1
    fi
    
    # Iniciar contenedores
    echo "🚀 Iniciando $env..."
    if ! docker-compose up -d; then
        echo "❌ ERROR: Falló al iniciar $env"
        return 1
    fi
    
    # Verificar salud
    if check_health $port $env; then
        echo "🎉 $env desplegado exitosamente!"
        return 0
    else
        echo "❌ ERROR: $env no pasó el health check"
        cd /srv/app/$env
        docker-compose logs
        return 1
    fi
}

# Función para cambiar tráfico
switch_traffic() {
    local target_env=$1
    
    echo ""
    echo "🔄 CAMBIANDO TRÁFICO A $target_env"
    echo "=================================="
    
    local config_file="/etc/nginx/sites-available/app_${target_env}.conf"
    
    if [ ! -f "$config_file" ]; then
        echo "❌ ERROR: Archivo de configuración no encontrado: $config_file"
        return 1
    fi
    
    # Cambiar enlace simbólico
    echo "🔗 Configurando Nginx para $target_env..."
    sudo ln -sfn "$config_file" /etc/nginx/sites-enabled/app_active.conf
    
    # Verificar configuración
    echo "🔍 Verificando configuración Nginx..."
    if ! sudo nginx -t; then
        echo "❌ ERROR: Configuración Nginx inválida"
        return 1
    fi
    
    # Recargar Nginx
    echo "🔄 Recargando Nginx..."
    sudo systemctl reload nginx
    
    # Esperar un momento
    sleep 3
    
    # Verificar que el cambio funcionó
    echo "🔍 Verificando cambio..."
    for i in {1..5}; do
        if timeout 5 curl -s http://localhost/health 2>/dev/null | grep -q "$target_env"; then
            echo "✅ Tráfico cambiado exitosamente a $target_env"
            return 0
        fi
        echo "⏳ Esperando confirmación... ($i/5)"
        sleep 2
    done
    
    echo "⚠️  ADVERTENCIA: No se pudo confirmar el cambio automáticamente"
    echo "💡 Verifica manualmente con: curl http://localhost"
    return 0
}

# Función para detectar ambiente actual
detect_current_env() {
    echo "🔍 Detectando ambiente actual..."
    
    # Intentar detectar por Nginx
    local active_conf=$(sudo readlink -f /etc/nginx/sites-enabled/app_active.conf 2>/dev/null || echo "")
    if [[ "$active_conf" == *"app_blue.conf" ]]; then
        echo "blue"
        return 0
    elif [[ "$active_conf" == *"app_green.conf" ]]; then
        echo "green"
        return 0
    fi
    
    # Intentar detectar por respuesta HTTP
    for i in {1..3}; do
        local response=$(timeout 5 curl -s http://localhost/ 2>/dev/null || echo "")
        if echo "$response" | grep -q '"environment":"blue"'; then
            echo "blue"
            return 0
        elif echo "$response" | grep -q '"environment":"green"'; then
            echo "green"
            return 0
        fi
        sleep 1
    done
    
    echo "unknown"
    return 1
}

# --- MAIN SCRIPT ---

# Detectar ambiente actual
CURRENT_ENV=$(detect_current_env)
echo "📍 Ambiente actual detectado: $CURRENT_ENV"

# Determinar ambiente objetivo
if [ "$CURRENT_ENV" = "blue" ]; then
    TARGET_ENV="green"
    TARGET_PORT="3002"
    CURRENT_PORT="3001"
elif [ "$CURRENT_ENV" = "green" ]; then
    TARGET_ENV="blue"
    TARGET_PORT="3001"
    CURRENT_PORT="3002"
else
    # Por defecto, usar blue
    echo "⚠️  No se detectó ambiente activo, usando BLUE por defecto"
    TARGET_ENV="blue"
    TARGET_PORT="3001"
    CURRENT_ENV="green" # Asumir que green necesita ser desplegado
fi

echo ""
echo "📋 PLAN DE ACCIÓN:"
echo "   - Ambiente actual: $CURRENT_ENV (puerto $CURRENT_PORT)"
echo "   - Nuevo ambiente: $TARGET_ENV (puerto $TARGET_PORT)"
echo ""

# Preguntar confirmación
read -p "¿Continuar con el despliegue? (s/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Ss]$ ]]; then
    echo "❌ Despliegue cancelado"
    exit 0
fi

# 1. Desplegar en el ambiente objetivo
if ! deploy_environment "$TARGET_ENV" "$TARGET_PORT"; then
    echo "❌ ERROR CRÍTICO: Falló el despliegue en $TARGET_ENV"
    echo "💡 El ambiente $CURRENT_ENV sigue activo"
    exit 1
fi

# 2. Cambiar tráfico
if ! switch_traffic "$TARGET_ENV"; then
    echo "❌ ERROR: Falló el cambio de tráfico"
    echo "💡 $TARGET_ENV está desplegado pero el tráfico sigue en $CURRENT_ENV"
    exit 1
fi

# 3. Mostrar resumen
echo ""
echo "🎉 DESPLIEGUE COMPLETADO EXITOSAMENTE"
echo "======================================"
echo "✅ Ambiente anterior: $CURRENT_ENV"
echo "✅ Ambiente nuevo: $TARGET_ENV"
echo "✅ Puerto: $TARGET_PORT"
echo ""
echo "🔍 Verificación final:"
curl -s http://localhost/ | grep -o '"message":"[^"]*"'

# Opcional: Preguntar si limpiar el ambiente anterior
echo ""
read -p "¿Deseas limpiar el ambiente anterior ($CURRENT_ENV)? (s/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Ss]$ ]]; then
    echo "🧹 Limpiando $CURRENT_ENV..."
    cd /srv/app/$CURRENT_ENV
    docker-compose down
    echo "✅ $CURRENT_ENV limpiado"
fi

echo ""
echo "📊 ESTADO FINAL:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
