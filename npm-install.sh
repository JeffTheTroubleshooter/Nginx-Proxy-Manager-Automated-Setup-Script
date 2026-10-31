#!/usr/bin/env bash
#
# Nginx Proxy Manager installer / uninstaller (Docker Compose)
# Detects distro, ensures Docker, writes compose file, starts the stack.
#
# Usage:
#   bash npm-install.sh            # install
#   bash npm-install.sh uninstall  # stop and optionally remove data
#

set -euo pipefail

START_TIME=$(date +%s)
DEFAULT_DIR="/opt/nginx-proxy-manager"
DEFAULT_HTTP=80
DEFAULT_HTTPS=443
DEFAULT_ADMIN=81

# ── helpers (logs to stderr) ───────────────────────────────────────────────
die() { echo -e "\n\033[1;31mError:\033[0m $*" >&2; exit 1; }
info() { echo -e "\033[1;34m==>\033[0m $*" >&2; }
ok() { echo -e "\033[1;32m==>\033[0m $*" >&2; }
warn() { echo -e "\033[1;33m==>\033[0m $*" >&2; }
prompt() { local var="$1" msg="$2" default="$3"; read -rp "$msg [$default]: " input; printf -v "$var" '%s' "${input:-$default}"; }
ask_yn() { local msg="$1" default="${2:-n}"; local ans; read -rp "$msg [y/N]: " ans; ans="${ans:-$default}"; [[ "$ans" =~ ^[Yy] ]]; }

elapsed() {
  local end=$(date +%s)
  local secs=$((end - START_TIME))
  printf '%dm %ds' $((secs/60)) $((secs%60))
}

# ── distro detection ───────────────────────────────────────────────────────
detect_distro() {
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    ID="${ID:-}"
    ID_LIKE="${ID_LIKE:-}"
  else
    die "Cannot detect distro (/etc/os-release missing)."
  fi

  case "$ID" in
    debian|ubuntu|linuxmint|pop|elementary|zorin) PKG="apt" ;;
    fedora|rhel|rocky|almalinux|centos|ol)         PKG="dnf" ;;
    arch|manjaro|endeavouros|garuda)               PKG="pacman" ;;
    opensuse*|sles)                                PKG="zypper" ;;
    alpine)                                        PKG="apk" ;;
    *)
      case "$ID_LIKE" in
        *debian*|*ubuntu*) PKG="apt" ;;
        *rhel*|*fedora*)   PKG="dnf" ;;
        *arch*)            PKG="pacman" ;;
        *suse*)            PKG="zypper" ;;
        *) die "Unsupported distro: $ID (ID_LIKE=$ID_LIKE). Supported: Debian/Ubuntu, Fedora/RHEL, Arch, openSUSE, Alpine." ;;
      esac
      ;;
  esac
  info "Detected: $ID ($PKG)"
}

# ── docker ─────────────────────────────────────────────────────────────────
ensure_docker() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    ok "Docker and Compose already installed"
    return 0
  fi
  info "Installing Docker..."
  case "$PKG" in
    apt)
      sudo apt-get update -qq
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl
      sudo install -m 0755 -d /etc/apt/keyrings
      curl -fsSL https://download.docker.com/linux/$ID/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
      sudo chmod a+r /etc/apt/keyrings/docker.gpg
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$ID $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
      sudo apt-get update -qq
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      ;;
    dnf)
      sudo dnf install -y dnf-plugins-core
      sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo || \
        sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
      sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      ;;
    pacman)
      sudo pacman -Sy --noconfirm docker docker-compose
      ;;
    zypper)
      sudo zypper --non-interactive install docker docker-compose
      ;;
    apk)
      sudo apk add --no-cache docker docker-cli-compose
      ;;
  esac
  sudo systemctl enable --now docker 2>/dev/null || sudo rc-service docker start 2>/dev/null || true
  ok "Docker ready."
}

# ── compose ────────────────────────────────────────────────────────────────
write_compose() {
  info "Writing docker-compose.yml..."
  sudo mkdir -p "$INSTALL_DIR/data" "$INSTALL_DIR/letsencrypt"
  sudo tee "$INSTALL_DIR/docker-compose.yml" >/dev/null <<YAML
services:
  app:
    image: 'jc21/nginx-proxy-manager:latest'
    restart: unless-stopped
    ports:
      - '${HTTP_PORT}:80'
      - '${HTTPS_PORT}:443'
      - '${ADMIN_PORT}:81'
    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt
YAML
  sudo chown -R "$USER:$USER" "$INSTALL_DIR" 2>/dev/null || true
  ok "Compose file written."
}

start_stack() {
  info "Starting Nginx Proxy Manager..."
  (cd "$INSTALL_DIR" && sudo docker compose up -d) || die "docker compose up failed"
  sleep 3
  if sudo docker compose -f "$INSTALL_DIR/docker-compose.yml" ps | grep -q "Up"; then
    ok "Container is running."
  else
    warn "Container may still be starting. Check: sudo docker compose -f $INSTALL_DIR/docker-compose.yml logs"
  fi

  if systemctl is-active --quiet firewalld 2>/dev/null; then
    info "Opening firewall ports ${HTTP_PORT}/tcp, ${HTTPS_PORT}/tcp, ${ADMIN_PORT}/tcp..."
    sudo firewall-cmd --permanent --add-port="${HTTP_PORT}/tcp" || true
    sudo firewall-cmd --permanent --add-port="${HTTPS_PORT}/tcp" || true
    sudo firewall-cmd --permanent --add-port="${ADMIN_PORT}/tcp" || true
    sudo firewall-cmd --reload || true
    ok "Firewall updated."
  fi
}

# ── uninstall ──────────────────────────────────────────────────────────────
uninstall() {
  echo "Nginx Proxy Manager uninstaller"
  echo "================================"
  detect_distro

  prompt INSTALL_DIR "Install directory" "$DEFAULT_DIR"
  if [[ -f "$INSTALL_DIR/docker-compose.yml" ]]; then
    info "Stopping containers..."
    (cd "$INSTALL_DIR" && sudo docker compose down) || true
    ok "Containers stopped."
  fi

  if [[ -d "$INSTALL_DIR" ]]; then
    if ask_yn "Remove install directory $INSTALL_DIR (includes config and certificates)?"; then
      sudo rm -rf "$INSTALL_DIR"
      ok "Directory removed."
    else
      info "Kept $INSTALL_DIR"
    fi
  else
    warn "Install directory $INSTALL_DIR not found."
  fi

  echo
  ok "Uninstall finished in $(elapsed)"
}

# ── main ───────────────────────────────────────────────────────────────────
main() {
  local mode="${1:-install}"

  case "$mode" in
    uninstall|remove|--uninstall|-u)
      uninstall
      ;;
    install|"")
      echo "Nginx Proxy Manager installer (Docker Compose)"
      echo "=============================================="
      detect_distro
      ensure_docker

      echo
      prompt INSTALL_DIR "Install directory" "$DEFAULT_DIR"
      prompt HTTP_PORT "HTTP port" "$DEFAULT_HTTP"
      prompt HTTPS_PORT "HTTPS port" "$DEFAULT_HTTPS"
      prompt ADMIN_PORT "Admin UI port" "$DEFAULT_ADMIN"

      [[ "$HTTP_PORT" =~ ^[0-9]+$ && "$HTTPS_PORT" =~ ^[0-9]+$ && "$ADMIN_PORT" =~ ^[0-9]+$ ]] || die "Ports must be numbers."

      write_compose
      start_stack

      local ip
      ip=$(hostname -I 2>/dev/null | awk '{print $1}') || ip="localhost"

      echo
      ok "Done in $(elapsed)"
      echo
      echo "  Admin:  http://${ip:-localhost}:${ADMIN_PORT}"
      echo "  Files:  $INSTALL_DIR"
      echo
      echo "Default login:"
      echo "  Email:    admin@example.com"
      echo "  Password: changeme"
      echo "Change these on first login."
      echo
      echo "Proxy ports: HTTP ${HTTP_PORT}, HTTPS ${HTTPS_PORT}"
      echo
      echo "Service commands:"
      echo "  sudo docker compose -f $INSTALL_DIR/docker-compose.yml logs"
      echo "  sudo docker compose -f $INSTALL_DIR/docker-compose.yml restart"
      echo
      echo "To uninstall later: bash $0 uninstall"
      ;;
    *)
      die "Unknown option: $mode. Use: $0 [install|uninstall]"
      ;;
  esac
}

main "$@"
