#!/usr/bin/env bash
set -euo pipefail

CWD="/opt/telemt-docker"
PORT="9443"
TLS_DOMAIN="www.google.com"
USER_NAME="user1"
IMAGE="whn0thacked/telemt-docker:latest"
CONTAINER_NAME="telemt"

echo "🚀 Telemt One-Click Installer"

mkdir -p "$CWD"
cd "$CWD"

# Мини-проверки
command -v docker >/dev/null 2>&1 || { echo "❌ docker не найден"; exit 1; }
command -v openssl >/dev/null 2>&1 || { echo "❌ openssl не найден"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "❌ curl не найден"; exit 1; }

SECRET="$(openssl rand -hex 16)"
echo "🔑 Секрет: $SECRET"

# Конфиг telemt
cat > telemt.toml <<EOF
[general]
prefer_ipv6 = false
fast_mode = true

[general.modes]
classic = false
secure = false
tls = true

[server]
port = ${PORT}
listen_addr_ipv4 = "0.0.0.0"

[censorship]
tls_domain = "${TLS_DOMAIN}"
mask = true
mask_port = 443

[access.users]
${USER_NAME} = "${SECRET}"

show_link = ["${USER_NAME}"]
EOF

# docker-compose
cat > docker-compose.yml <<EOF
services:
  telemt:
    image: ${IMAGE}
    container_name: ${CONTAINER_NAME}
    restart: unless-stopped
    environment:
      RUST_LOG: "info"
    volumes:
      - ./telemt.toml:/etc/telemt.toml:ro
    ports:
      - "${PORT}:${PORT}/tcp"
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

echo "⏳ Запускаем Docker Compose..."
docker compose down --remove-orphans >/dev/null 2>&1 || true
docker compose up -d

# ВАЖНО: инициализация переменных для set -u
TG_LINE=""
PUBLIC_IP=""

# Публичный IPv4 (может не получиться — это не ошибка)
PUBLIC_IP="$(curl -4 -s --connect-timeout 5 ifconfig.me 2>/dev/null || true)"

# Ждём, пока telemt напечатает tg:// ссылку (до 60 сек)
echo -n "⏳ Ожидание логов... (макс 60 сек)"
for _ in $(seq 1 30); do
  # Не используем docker compose logs -f — только хвост логов контейнера
  TG_LINE="$(docker logs "${CONTAINER_NAME}" --tail 300 2>/dev/null | grep -o 'tg://proxy?[^ ]*' | tail -1 || true)"

  if [[ -n "${TG_LINE:-}" ]]; then
    break
  fi

  echo -n "."
  sleep 2
done
echo ""

if [[ -n "${TG_LINE:-}" ]]; then
  # Подставляем публичный IP (если получили)
  if [[ -n "${PUBLIC_IP:-}" ]]; then
    TG_LINE="$(echo "$TG_LINE" | sed "s/172\.19\.0\.2/${PUBLIC_IP}/g")"
  fi

  echo ""
  echo "🎉 ✅ TELEMT УСТАНОВЛЕН!"
  echo "📂 Директория: $CWD"
  echo ""
  echo "🔗 ГОТОВАЯ ССЫЛКА:"
  echo "$TG_LINE"
  echo ""
else
  echo ""
  echo "⚠️ Telemt запустился, но tg:// ссылка не появилась за 60 сек."
  echo "Попробуйте так:"
  echo "cd $CWD && docker compose restart && sleep 5"
  echo "docker logs ${CONTAINER_NAME} --tail 500 | grep -o 'tg://proxy?[^ ]*' | tail -1 | sed \"s/172\\.19\\.0\\.2/\$(curl -4 -s ifconfig.me)/\""
  echo ""
fi

echo "🔍 Управление:"
echo "cd $CWD"
echo "docker compose logs -f telemt"
echo "docker compose restart"
echo "docker compose down"
