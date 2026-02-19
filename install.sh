#!/bin/bash
set -euo pipefail

# 🌈 Telemt MTProxy One-Click Installer v2.1 (FIXED)
echo "🚀 Telemt One-Click v2.1"

CWD="/opt/telemt-docker"
mkdir -p "$CWD" && cd "$CWD"

# 🔑 Секрет
SECRET=$(openssl rand -hex 16)
echo "🔑 Секрет: $SECRET"

# 📄 telemt.toml
cat > telemt.toml << EOF
[general]
prefer_ipv6 = false
fast_mode = true

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
EOF

# 🚀 Запуск
echo "⏳ Docker Compose..."
docker compose down 2>/dev/null || true
docker compose up -d

# ⏳ Ожидание (60 сек)
echo -n "⏳ Ожидание логов... (60 сек)"
for i in {1..20}; do
    sleep 3
    echo -n "."
    
    # Проверяем логи
    if docker compose logs telemt 2>/dev/null | grep -q "tg://proxy"; then
        echo ""
        echo "✅ Логи найдены!"
        break
    fi
done
echo ""

# 🌐 IP
PUBLIC_IP=$(curl -4 -s --connect-timeout 10 ifconfig.me 2>/dev/null || curl -4 -s --connect-timeout 10 ipinfo.io/ip 2>/dev/null || echo "127.0.0.1")

# 🔗 Ссылка (✅ ИСПРАВЛЕНО)
TG_LINE=$(docker compose logs telemt 2>/dev/null | grep -o 'tg://proxy?[^ ]*' | tail -1 || echo "")
if [[ -n "$TG_LINE" && "$TG_LINE" == tg://proxy?* ]]; then
    TG_LINK=$(echo "$TG_LINE" | sed "s/172\.19\.0\.2/$PUBLIC_IP/g" | sed "s/localhost/$PUBLIC_IP/g")
else
    TG_LINK="🔄 Перезапустите: cd $CWD && docker compose restart"
fi

# 🎉 Вывод
cat << END

🎉 ✅ TELEMT v2.1 УСТАНОВЛЕН!

📂 $CWD
🔗 $TG_LINK

📊 СТАТУС:
$(docker compose ps | tail -n +3)

📋 КОМАНДЫ:
cd $CWD
docker compose logs -f      # Логи
docker compose restart      # 🔄 Ссылка
END

# Тест порта
if [[ "$PUBLIC_IP" != "127.0.0.1" ]]; then
    echo "🔍 nc -zv $PUBLIC_IP 9443"
fi
