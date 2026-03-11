#!/usr/bin/env bash
set -euo pipefail

CWD="/opt/telemt-docker"
PORT="${PORT:-2053}"
TLS_DOMAIN="${TLS_DOMAIN:-ajax.cloudflare.com}"
USER_NAME="${USER_NAME:-user1}"
IMAGE="whn0thacked/telemt-docker:latest"
CONTAINER_NAME="telemt"

echo "🚀 Telemt One-Click Installer"

mkdir -p "$CWD"
cd "$CWD"

command -v docker >/dev/null 2>&1 || { echo "❌ docker не найден"; exit 1; }
command -v openssl >/dev/null 2>&1 || { echo "❌ openssl не найден"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "❌ curl не найден"; exit 1; }
command -v xxd >/dev/null 2>&1 || { echo "❌ xxd не найден (обычно пакет vim-common)"; exit 1; }

SECRET_BASE="$(openssl rand -hex 16)"
echo "🔑 Секрет (base): $SECRET_BASE"

# telemt.toml — ВАЖНО: show_link не используем (ломает запуск на вашей версии)
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
${USER_NAME} = "${SECRET_BASE}"
EOF

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

echo -n "⏳ Ожидание контейнера... (до 30 сек)"
for _ in $(seq 1 30); do
  STATUS="$(docker inspect -f '{{.State.Status}}' "${CONTAINER_NAME}" 2>/dev/null || true)"
  if [[ "$STATUS" == "running" ]]; then
    break
  fi
  echo -n "."
  sleep 1
done
echo ""

STATUS="$(docker inspect -f '{{.State.Status}}' "${CONTAINER_NAME}" 2>/dev/null || true)"
if [[ "$STATUS" != "running" ]]; then
  echo "❌ Контейнер не запущен (status=$STATUS). Логи:"
  docker logs "${CONTAINER_NAME}" --tail 200 || true
  exit 1
fi

PUBLIC_IP="$(curl -4 -s --connect-timeout 5 ifconfig.me 2>/dev/null || true)"
if [[ -z "${PUBLIC_IP:-}" ]]; then
  PUBLIC_IP="YOUR_PUBLIC_IP"
fi

DOMAIN_HEX="$(printf '.%s' "$TLS_DOMAIN" | xxd -p -c 9999 | tr -d '\n')"
SECRET_EE_TLS="ee${SECRET_BASE}${DOMAIN_HEX}"

# Чистая строка (как вы просили)
echo "tg://proxy?server=${PUBLIC_IP}&port=${PORT}&secret=${SECRET_EE_TLS}"
