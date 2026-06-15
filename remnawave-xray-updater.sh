#!/usr/bin/env bash
set -Eeuo pipefail

# =====================================================
# Remnawave Xray Safe Updater (Production Hardened)
# Fixes Hysteria 2 online/traffic bug (Issue #5868)
# =====================================================

XRAY_VERSION="${1:-26.6.1}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

log()  { echo -e "${CYAN}[INFO]${NC} $1"; }
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1"; }

# -----------------------------
# 1. FIND CONTAINER (robust)
# -----------------------------
CONTAINER=$(docker ps -q --filter "label=com.docker.compose.service=remnanode" | head -n1 || true)

if [ -z "$CONTAINER" ]; then
    CONTAINER=$(docker ps -q --filter "name=remnanode" | head -n1 || true)
fi

if [ -z "$CONTAINER" ]; then
    err "Remnawave container not found"
    exit 1
fi

COMPOSE_DIR=$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' "$CONTAINER" 2>/dev/null || true)
SERVICE=$(docker inspect -f '{{index .Config.Labels "com.docker.compose.service"}}' "$CONTAINER" 2>/dev/null || true)

if [ -z "$COMPOSE_DIR" ] || [ ! -d "$COMPOSE_DIR" ]; then
    err "Cannot detect compose directory"
    exit 1
fi

[ -z "$SERVICE" ] && SERVICE="remnanode"

XRAY_DIR="${COMPOSE_DIR}/custom-xray"
XRAY_BIN="${XRAY_DIR}/xray"
OVERRIDE_FILE="${COMPOSE_DIR}/docker-compose.override.yml"
TMP_DIR="$(mktemp -d)"

# -----------------------------
# TRAP FOR SAFE ROLLBACK INSTRUCTIONS
# -----------------------------
ROLLBACK_CMD="rm -f $OVERRIDE_FILE && cd $COMPOSE_DIR && docker compose up -d --force-recreate $SERVICE"
cleanup_and_err() {
    rm -rf "$TMP_DIR"
    err "Script failed! To rollback manually, run:"
    echo -e "${YELLOW}$ROLLBACK_CMD${NC}"
    exit 1
}
trap cleanup_and_err ERR

# -----------------------------
# 2. ARCH DETECTION
# -----------------------------
ARCH=$(uname -m)
case "$ARCH" in
    x86_64) ARCH="64" ;;
    aarch64|arm64) ARCH="arm64-v8a" ;;
    *) err "Unsupported arch: $ARCH"; exit 1 ;;
esac

log "Container: $CONTAINER"
log "Compose  : $COMPOSE_DIR"
log "Service  : $SERVICE"
log "Version  : $XRAY_VERSION"

# -----------------------------
# 3. SAFETY CHECK (no override overwrite)
# -----------------------------
if [ -f "$OVERRIDE_FILE" ]; then
    warn "override.yml already exists"
    warn "Skipping automatic changes to avoid breaking user config"
    echo "Add manually:"
    echo "  - ${XRAY_BIN}:/usr/local/bin/xray:ro"
    # Штатный выход. trap ERR здесь НЕ сработает, так как код завершения 0.
    exit 0
fi

# -----------------------------
# 4. DOWNLOAD + VERIFY
# -----------------------------
mkdir -p "$XRAY_DIR"

log "Downloading Xray..."
wget -q --show-progress -O "$TMP_DIR/xray.zip" \
"https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/Xray-linux-${ARCH}.zip"

unzip -q "$TMP_DIR/xray.zip" -d "$TMP_DIR"
chmod +x "$TMP_DIR/xray"

DOWN_VER=$("$TMP_DIR/xray" version | head -n1)

if ! echo "$DOWN_VER" | grep -q "Xray ${XRAY_VERSION}"; then
    err "Version mismatch: $DOWN_VER"
    exit 1
fi

# IMPORTANT: file must exist BEFORE docker restart
install -m 755 "$TMP_DIR/xray" "$XRAY_BIN"
ok "Binary installed: $XRAY_BIN"

# -----------------------------
# 5. APPLY OVERRIDE
# -----------------------------
cat > "$OVERRIDE_FILE" <<EOF
services:
  ${SERVICE}:
    volumes:
      - ${XRAY_BIN}:/usr/local/bin/xray:ro
EOF

ok "Override applied"

# -----------------------------
# 6. RESTART ONLY TARGET SERVICE
# -----------------------------
log "Restarting service..."
cd "$COMPOSE_DIR"

# Вывод Docker Compose оставлен намеренно. 
# Если в override.yml будет ошибка или Docker не сможет запустить контейнер,
# пользователь увидит лог, а set -e моментально перехватит ошибку и вызовет trap.
docker compose up -d --force-recreate "$SERVICE"

# -----------------------------
# 7. REAL HEALTH CHECK
# -----------------------------
log "Waiting for stability..."

SUCCESS=0

for i in $(seq 1 12); do
    sleep 5

    STATUS=$(docker inspect -f '{{.State.Status}}' "$CONTAINER" 2>/dev/null || echo "unknown")
    RESTARTS=$(docker inspect -f '{{.RestartCount}}' "$CONTAINER" 2>/dev/null || echo "0")

    if [ "$STATUS" = "running" ] && [ "$RESTARTS" -eq 0 ]; then
        if docker exec "$CONTAINER" /usr/local/bin/xray version >/dev/null 2>&1; then
            SUCCESS=1
            break
        fi
    fi

    warn "check $i/12: status=$STATUS restarts=$RESTARTS"
done

# -----------------------------
# 8. RESULT
# -----------------------------
if [ "$SUCCESS" -eq 1 ]; then
    echo
    echo "=================================="
    echo " SUCCESS: Xray updated"
    echo " version: $XRAY_VERSION"
    echo "=================================="
    echo "rollback:"
    echo "$ROLLBACK_CMD"
    echo "=================================="
else
    err "Service unstable after update"
    err "Rollback required manually"
    exit 1
fi

rm -rf "$TMP_DIR"
trap - ERR
