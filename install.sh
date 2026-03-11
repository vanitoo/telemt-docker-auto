#!/usr/bin/env bash
set -euo pipefail

# Fix args when script is executed via: bash <(curl ...)
if [[ $# -eq 0 && -n "${BASH_ARGV:-}" ]]; then
    set -- "${BASH_ARGV[@]}"
fi

CWD="/opt/telemt-docker"
CONFIG="$CWD/telemt.toml"

PORT="${PORT:-2053}"
TLS_DOMAIN="${TLS_DOMAIN:-ajax.cloudflare.com}"
USER_NAME="${USER_NAME:-user1}"

IMAGE="whn0thacked/telemt-docker:latest"
CONTAINER_NAME="telemt"

MODE="install"
NEW_USER=""

if [[ "${1:-}" == "--adduser" ]]; then
    MODE="adduser"
    NEW_USER="${2:-}"
fi

require_bin() {
    command -v "$1" >/dev/null 2>&1 || { echo "❌ $1 не найден"; exit 1; }
}

require_bin docker
require_bin openssl
require_bin curl
require_bin xxd

get_ip() {
    curl -4 -s --connect-timeout 5 https://api.ipify.org || echo "YOUR_PUBLIC_IP"
}

generate_secret() {
    openssl rand -hex 16
}

domain_hex() {
    printf '.%s' "$1" | xxd -p -c 9999 | tr -d '\n'
}

restart_container() {
    docker restart "$CONTAINER_NAME" >/dev/null
}

print_link() {

    local secret="$1"

    PUBLIC_IP="$(get_ip)"
    DOMAIN_HEX="$(domain_hex "$TLS_DOMAIN")"

    SECRET_EE_TLS="ee${secret}${DOMAIN_HEX}"

    echo ""
    echo "🔗 Telegram link:"
    echo "tg://proxy?server=${PUBLIC_IP}&port=${PORT}&secret=${SECRET_EE_TLS}"
    echo ""
}

add_user() {

    if [[ ! -f "$CONFIG" ]]; then
        echo "❌ telemt.toml не найден. Сначала выполните установку."
        exit 1
    fi

    cd "$CWD"

    if [[ -z "$NEW_USER" ]]; then

        LAST_USER=$(grep -o 'user[0-9]\+' "$CONFIG" | sed 's/user//' | sort -n | tail -n1)

        if [[ -z "$LAST_USER" ]]; then
            NEXT_ID=2
        else
            NEXT_ID=$((LAST_USER + 1))
        fi

        NEW_USER="user${NEXT_ID}"

    fi

    SECRET_BASE="$(generate_secret)"

    awk -v user="$NEW_USER" -v secret="$SECRET_BASE" '
    BEGIN{added=0}
    /^\[access.users\]/{
        print
        getline
        while ($0 !~ /^\[/ && !added) {
            print
            getline
        }
        print user " = \"" secret "\""
        added=1
    }
    {print}
    ' "$CONFIG" > telemt.tmp

    mv telemt.tmp "$CONFIG"

    restart_container

    echo "✅ Пользователь добавлен: $NEW_USER"

    print_link "$SECRET_BASE"

}

install_server() {

    echo "🚀 Telemt One-Click Installer"

    mkdir -p "$CWD"
    cd "$CWD"

    SECRET_BASE="$(generate_secret)"

    echo "🔑 Секрет: $SECRET_BASE"

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

    echo -n "⏳ Ожидание контейнера..."

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
        echo "❌ Контейнер не запущен (status=$STATUS)"
        docker logs "$CONTAINER_NAME" --tail 200 || true
        exit 1
    fi

    print_link "$SECRET_BASE"

}

if [[ "$MODE" == "adduser" ]]; then
    add_user
else
    install_server
fi
