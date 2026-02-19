#!/bin/bash
set -euo pipefail

# 🌈 Telemt MTProxy One-Click Installer
# Порт 9443 | Docker | Авто IP | Готовая ссылка

echo "🚀 Устанавливаем Telemt MTProxy..."

# 1. Создаем директорию
mkdir -p /opt/telemt-docker
cd /opt/telemt-docker

# 2. Генерируем секрет
SECRET=$(openssl rand -hex 16)
echo "🔑 Секрет: $SECRET"

# 3. Создаем telemt.toml
cat > telemt.toml << EOF
[general]
prefer_ipv6 = false

[general.modes]
tls = true

[server]
port = 9443
listen_addr_ipv4 = "0.0.0.0"

[censorship]
tls_domain = "www.google.com"
mask = true
mask_port = 443

[access.users]
user1 = "$SECRET"

show_link = ["user1"]
EOF

# 4. Docker Compose
cat > docker-compose.yml << 'EOF'
services:
  telemt:
    image: whn0thacked/telemt-docker:latest
    container_name: telemt
    restart: unless-stopped
    environment:
      RUST_LOG: "info"
    volumes:
      - ./telemt.toml:/etc/telemt.toml:ro
    ports:
      - "9443:9443/tcp"
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
    read_only: true
    tmpfs:
      - /tmp:rw,nosuid,nodev,noexec,size=16m
EOF

# 5. Запуск
echo "⏳ Запускаем..."
docker compose up -d

# 6. Ждем готовности (секрет в логах)
echo "⏳ Ждем логи..."
sleep 10

# 7. Получаем публичную ссылку
PUBLIC_IP=$(curl -4 -s ifconfig.me)
sleep 2
TG_LINK=$(docker compose logs telemt 2>/dev/null | grep -o 'tg://proxy?[^ ]*' | tail -1 | sed "s/172\.19\.0\.2/$PUBLIC_IP/" 2>/dev/null || echo "🔄 Перезапустите: cd /opt/telemt-docker && docker compose restart && bash <(curl ...)")

echo ""
echo "🎉 ✅ TELEMT УСТАНОВЛЕН!"
echo "📂 Директория: /opt/telemt-docker"
echo ""
echo "🔗 ГОТОВАЯ ССЫЛКА:"
echo "$TG_LINK"
echo ""
echo "🔍 Управление:"
echo "cd /opt/telemt-docker"
echo "docker compose logs -f    # Логи"
echo "docker compose restart    # Перезапуск"
echo "docker compose down       # Остановка"
