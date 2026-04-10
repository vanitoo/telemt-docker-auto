# syntax=docker/dockerfile:1.7

ARG TELEMT_VERSION=

FROM --platform=$TARGETPLATFORM alpine:latest AS fetch

ARG TELEMT_VERSION
ARG TARGETARCH

# ── Cache-buster: передайте при сборке, например:
#    docker build --build-arg CACHEBUST="$(date +%s)" ...
# Если TELEMT_VERSION задан явно, кеш-бастер не нужен,
# но и не помешает — слой и так инвалидируется при смене версии.
ARG CACHEBUST=

RUN --mount=type=cache,target=/var/cache/apk \
    apk add --no-cache \
      ca-certificates \
      curl \
      tar \
      binutils \
      upx \
    && update-ca-certificates

# ↓↓↓  Используем CACHEBUST внутри RUN, чтобы Docker не мог
#       считать слой неизменным при пустом TELEMT_VERSION
RUN set -eux; \
    echo "cache-bust: ${CACHEBUST}"; \
    \
    case "${TARGETARCH}" in \
      amd64)  ARCH=x86_64  ;; \
      arm64)  ARCH=aarch64 ;; \
      *) echo "unsupported arch: ${TARGETARCH}"; exit 1 ;; \
    esac; \
    \
    if [ -n "${TELEMT_VERSION}" ]; then \
      VERSION="${TELEMT_VERSION}"; \
    else \
      VERSION="$(curl -fsSLI -o /dev/null -w '%{url_effective}' \
        https://github.com/telemt/telemt/releases/latest | sed 's#.*/##')"; \
    fi; \
    \
    BASE_URL="https://github.com/telemt/telemt/releases/download/${VERSION}"; \
    TARBALL="telemt-${ARCH}-linux-musl.tar.gz"; \
    \
    echo "=== Using release ${VERSION} ==="; \
    echo "=== Downloading ${TARBALL} ==="; \
    curl -fsSL -o "/tmp/${TARBALL}" "${BASE_URL}/${TARBALL}"; \
    curl -fsSL -o "/tmp/${TARBALL}.sha256" "${BASE_URL}/${TARBALL}.sha256"; \
    \
    echo "=== Verifying checksum ==="; \
    cd /tmp && sha256sum -c "${TARBALL}.sha256"; \
    \
    echo "=== Extracting ==="; \
    mkdir -p /out; \
    tar -xzf "/tmp/${TARBALL}" -C /out; \
    chmod 755 /out/telemt; \
    \
    echo "=== Verifying static linkage ==="; \
    if readelf -lW /out/telemt 2>/dev/null | grep -q "Requesting program interpreter"; then \
      echo "ERROR: telemt is dynamically linked -> cannot run in distroless/static"; \
      exit 1; \
    fi

RUN set -eux; \
    echo "=== Before UPX ===" && ls -lh /out/telemt; \
    if upx --ultra-brute --preserve-build-id /out/telemt; then \
      echo "=== After UPX ===" && ls -lh /out/telemt; \
      echo "=== Integrity check ===" && upx -t /out/telemt; \
    else \
      echo "=== UPX failed on ${TARGETARCH}, skipping compression ==="; \
      ls -lh /out/telemt; \
    fi

FROM gcr.io/distroless/static:nonroot AS runtime

STOPSIGNAL SIGINT

COPY --from=fetch /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=fetch /out/telemt /usr/local/bin/telemt

WORKDIR /tmp

EXPOSE 443/tcp 9090/tcp

USER nonroot:nonroot
ENTRYPOINT ["/usr/local/bin/telemt"]
CMD ["/etc/telemt.toml"]
