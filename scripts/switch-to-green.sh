#!/bin/bash
set -e

echo "🔄 Cambiando tráfico a GREEN..."

# Cambiar symlink
sudo ln -sfn /etc/nginx/sites-available/app_green.conf /etc/nginx/sites-enabled/app_active.conf

# Verificar configuración
sudo nginx -t

# Recargar Nginx
sudo systemctl reload nginx

echo "✅ Tráfico cambiado a GREEN"
