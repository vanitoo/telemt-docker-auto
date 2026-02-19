#!/bin/bash
set -euo pipefail

# 🌈 Telemt MTProxy One-Click Installer v2.0
# Порт 9443 | Docker | Авто IP | Надежная ссылка

echo "🚀 Telemt One-Click Installer"

CWD="/opt/telemt-docker"
mkdir -p "$CWD" && cd "$CWD"

# 🔑 Генерация секрета
SECRET=$(openssl rand -hex 16)
echo "🔑 Секрет: $SECRET"

# 📄 telemt.toml
cat > telemt.toml << EOF
[general]
prefer_ipv6 = false
fast_mode = true

[general.modes]
classic = false
secure = false
tls = true

[server]
port = 9443
listen_addr_ipv4 = "0.0.0.0"

[censorship]
tls_domain = "www.google.com"
mask = true
mask_port = 443
fake_cert_len = 2048

[access.users]
user1 = "$SECRET"

show_link = ["user1"]
EOF

# 🐳 docker-compose.yml
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
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
EOF

# 🚀 Запуск
echo "⏳ Запускаем Docker Compose..."
docker compose down 2>/dev/null || true
docker compose up -d

# ⏳ Надежное ожидание логов (до 60 сек)
echo "⏳ Ожидание логов... (макс 60 сек)"
MAX_WAIT=60
COUNTER=0

while [ $COUNTER -lt $MAX_WAIT ]; do
    if docker compose ps | grep -q "Up"; then
        sleep 3
        TG_LINE=$(docker compose logs telemt 2>/dev/null | grep -o 'tg://proxy?[^ ]*' | tail -1)
        if [[ "$TG_LINE" == tg://proxy?* ]]; then
            break
        fi
    fi
    COUNTER=$((COUNTER+3))
    echo -n "."
done

# 🌐 Получаем публичный IP
PUBLIC_IP=$(curl -4 -s --connect-timeout 5 ifconfig.me || curl -4 -s --connect-timeout 5 ipinfo.io/ip || echo "127.0.0.1")

# 🔗 Формируем финальную ссылку
if [[ "$TG_LINE" == tg://proxy?* ]]; then
    TG_LINK=$(echo "$TG_LINE" | sed "s/172\.19\.0\.2/$PUBLIC_IP/" | sed "s/localhost/$PUBLIC_IP/")
else
    TG_LINK="🔄 Логи не готовы. Выполните: cd $CWD && docker compose restart"
fi

# 🎉 Финальный вывод
cat << END

🎉 ✅ TELEMT УСТАНОВЛЕН v2.0!

📂 Директория: $CWD
🔗 ГОТОВАЯ ССЫЛКА:
$TG_LINK

🔍 СТАТУС:
$(docker compose ps)

📋 УПРАВЛЕНИЕ:
cd $CWD
docker compose logs -f         # 🔴 Логи в реальном времени
docker compose restart         # 🔄 Перезапуск
docker compose down            # 🛑 Остановка

🔗 НОВАЯ ССЫЛКА (если IP изменился):
docker compose logs telemt | grep -o 'tg://proxy?[^ ]*' | tail -1 | sed "s/172\\.19\\.0\\.2/$(curl -4 -s ifconfig.me)/"

END

# ✅ Проверка порта
if [[ "$PUBLIC_IP" != "127.0.0.1" ]]; then
    echo "🔍 Тест порта (выполните с другого хоста): nc -zv $PUBLIC_IP 9443"
fi
