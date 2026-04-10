# 🐳 telemt-docker

> **📢 Сборка образов перенесена в GitLab**
>
> Из-за перманентной блокировки GitHub Actions образы теперь собираются в
> **[GitLab CI](https://gitlab.com/An0nX/telemt-docker)**. GitHub-репозиторий
> продолжает существовать как зеркало GitLab.
>
> Подробности: [An0nX/telemt-docker#14](https://github.com/An0nX/telemt-docker/issues/14)

---

[![Docker Image Size](https://img.shields.io/docker/image-size/whn0thacked/telemt-docker/latest?style=flat-square&logo=docker&color=blue)](https://hub.docker.com/r/whn0thacked/telemt-docker)
[![Docker Pulls](https://img.shields.io/docker/pulls/whn0thacked/telemt-docker?style=flat-square&logo=docker)](https://hub.docker.com/r/whn0thacked/telemt-docker)
[![Architecture](https://img.shields.io/badge/arch-amd64%20%7C%20arm64-important?style=flat-square)](#)
[![Security: non-root](https://img.shields.io/badge/security-non--root-success?style=flat-square)](#)
[![Base Image](https://img.shields.io/badge/base-distroless%2Fstatic%3Anonroot-blue?style=flat-square)](https://github.com/GoogleContainerTools/distroless)
[![Upstream](https://img.shields.io/badge/upstream-telemt-orange?style=flat-square)](https://github.com/telemt/telemt)

A minimal, secure, and production-oriented Docker image for **Telemt** — a fast MTProto proxy server (MTProxy) written in **Rust + Tokio**.

Built as a **fully static** binary and shipped in a **distroless** runtime image, running as **non-root** by default.

---

## ✨ Features

- **🔐 Secure by default:** Distroless runtime + non-root user.
- **🏗 Multi-arch:** Supports `amd64` and `arm64`.
- **📦 Fully static binary:** Designed for `gcr.io/distroless/static:nonroot`.
- **🧾 Config-driven:** You mount a single configuration file directory and go.
- **📈 Metrics-ready:** Supports Telemt metrics port (`9090`) via config.
- **🧰 Build-time pinning:** Upstream repo/ref are configurable via build args.

---

## ⚠️ Important Notice

Telemt is a Telegram proxy (MTProto). Operating proxies may be restricted or monitored depending on your country/ISP and may carry legal/operational risks.

You are responsible for compliance with local laws and for safe deployment (firewalling, access control, logs, monitoring).

---

## 🚀 Quick Start (Docker Compose)

### 1. Generate a Secret
Telemt users require a **32-hex-char secret** (16 bytes):

```bash
openssl rand -hex 16
```

### 2. Create Configuration Directory

Refer to the upstream repository for the configuration format and examples:

👉 **https://github.com/telemt/telemt**

To allow the Telemt API to write configuration changes dynamically (e.g. creating users), you **must mount a directory**, not just the file. The API performs atomic saves by creating a temporary `.tmp` file in the same directory and renaming it. 

Create the directory, place your config inside, and ensure it is writable by the container:

```bash
mkdir ./telemt-config
# Create and edit your config inside
touch ./telemt-config/telemt.toml
# Grant write permissions so the container's non-root user can modify the config
chmod 777 ./telemt-config
chmod 666 ./telemt-config/telemt.toml
```

### 3. Create `docker-compose.yml`

> **⚠️ Network mode note:**
> This configuration uses `network_mode: host`, which means the container shares
> the host's network stack directly. **Published ports (`ports:` section) are
> discarded when using host network mode** — port exposure is controlled entirely
> by your `telemt.toml` configuration (i.e. whichever port Telemt listens on will
> be available on the host automatically).
>
> If you need Docker-managed port mapping (e.g. remapping ports, or binding only
> to `127.0.0.1`), remove `network_mode: host` to use the default **bridge** mode
> and uncomment the `ports` section below.

> **⚠️ Privileged Ports (443) Binding Note:**
> The base image uses a non-root user by default to minimize the attack vector. If your configuration binds Telemt to port `443` (or any port < 1024), you will encounter a `Permission denied (os error 13)` error. To fix this, you need to run the container as `root` by uncommenting `user: "root"` and commenting out the `security_opt: no-new-privileges:true` block in the example below.

```yaml
services:
  telemt:
    image: whn0thacked/telemt-docker:latest
    container_name: telemt
    restart: unless-stopped

    # ---------------------------------------------------------------
    # Root user requirement for binding privileged ports (<1024)
    # The default image runs as 'nonroot' to minimize attack vectors.
    # Uncomment the line below to run as root ONLY if you need to bind
    # to port 443 and encounter 'os error 13'.
    # ---------------------------------------------------------------
    # user: "root"

    # Telemt uses RUST_LOG for verbosity (optional)
    environment:
      RUST_LOG: "info"

    # ---------------------------------------------------------------
    # API Configuration writes (Atomic Config Save)
    # The API performs atomic writes (creates a .tmp file and renames it).
    # To allow the API to save changes to the config, we MUST mount the 
    # ENTIRE directory (not just the file) and ensure it is writable.
    # We override the default command to point to the mounted file.
    # ---------------------------------------------------------------
    command: ["/etc/telemt/telemt.toml"]
    volumes:
      - ./telemt-config:/etc/telemt

    # ---------------------------------------------------------------
    # Host network mode: the container uses the host's network stack
    # directly. The "ports" section is IGNORED in this mode — Telemt
    # binds to host ports as specified in telemt.toml.
    #
    # To use Docker-managed port mapping instead, comment out
    # "network_mode: host" and uncomment the "ports" section below.
    # ---------------------------------------------------------------
    network_mode: host

    # ports:
    #   - "443:443/tcp"
    #   # If you enable metrics_port=9090 in config:
    #   # - "127.0.0.1:9090:9090/tcp"

    # Hardening
    # ---------------------------------------------------------------
    # ⚠️ If you uncommented `user: "root"` above to bind to port 443,
    # you MUST comment out the two lines below, as they prevent
    # gaining the necessary privileges for binding restricted ports.
    # ---------------------------------------------------------------
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
    read_only: true
    tmpfs:
      - /tmp:rw,nosuid,nodev,noexec,size=16m

    # Resource limits (optional)
    deploy:
      resources:
        limits:
          cpus: "0.50"
          memory: 256M
        reservations:
          cpus: "0.25"
          memory: 128M

    # File descriptor limits (critical for a high-load server!)
    ulimits:
      nofile:
        soft: 65536
        hard: 65536

    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
```

### 4. Start

```bash
docker compose up -d
```

Logs:

```bash
docker compose logs -f
```

---

## ⚙️ Configuration

### Environment Variables

| Variable | Mandatory | Default | Description |
|---|:---:|---|---|
| `RUST_LOG` | No | — | Telemt log level (e.g. `info`, `debug`, `trace`). |

### Volumes

| Container Path | Purpose |
|---|---|
| **`/etc/telemt`** | Directory containing the `telemt.toml` config file. Mounted as a directory (without `:ro`) to allow the API to securely perform atomic writes. |

### Ports

| Port | Purpose |
|---:|---|
| `443/tcp` | Main MTProxy listener (commonly used for TLS-like traffic). |
| `9090/tcp` | Metrics port (only if enabled in `telemt.toml`). |
| `9091/tcp` | API port (only if enabled in `telemt.toml`). |

> **Note:** When using `network_mode: host`, Docker does not manage port mapping.
> Telemt binds directly to host interfaces/ports as configured in `telemt.toml`.
> The table above lists the default ports for reference only.

---

## 🧠 Container Behavior

- **ENTRYPOINT:** `telemt`
- **CMD:** Extracted from the `docker-compose.yml` (`["/etc/telemt/telemt.toml"]`)

So the container effectively runs:

```text
telemt /etc/telemt/telemt.toml
```

To run a raw docker command without Compose:

```bash
docker build -t telemt:local .
docker run --name telemt --restart unless-stopped \
  -p 443:443 \
  -e RUST_LOG=info \
  -v "$PWD/telemt-config:/etc/telemt" \
  --read-only \
  --cap-drop ALL --cap-add NET_BIND_SERVICE \
  --ulimit nofile=65536:65536 \
  telemt:local /etc/telemt/telemt.toml
```

---

## 🛠 Build

This Dockerfile supports pinning upstream Telemt source:

- `TELEMT_REPO` (default: `https://github.com/telemt/telemt.git`)
- `TELEMT_REF` (default: `main`)

### Multi-arch build (amd64 + arm64)

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t whn0thacked/telemt-docker:latest \
  --push .
```

### Build a specific upstream tag/branch/commit

```bash
docker buildx build \
  --build-arg TELEMT_REF=v1.1.0.0 \
  -t whn0thacked/telemt-docker:v1.1.0.0 \
  --push .
```

---

## 🔗 Useful Links

- **Telemt upstream:** https://github.com/telemt/telemt
- **MTProxy ad tag bot:** https://t.me/mtproxybot
- **Distroless images:** https://github.com/GoogleContainerTools/distroless
