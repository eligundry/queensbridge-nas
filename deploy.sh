#!/bin/bash
# deploy.sh - Deploy NAS Docker configurations

set -e  # Exit on error

# Configuration
NAS_HOST="nas"
NAS_DOCKER_DIR="/volume1/docker"
NAS_DATA_DIR="/var/services/homes/eligundry"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color output functions
info() { echo -e "\033[0;34m[INFO]\033[0m $1"; }
success() { echo -e "\033[0;32m[SUCCESS]\033[0m $1"; }
error() { echo -e "\033[0;31m[ERROR]\033[0m $1"; exit 1; }
warn() { echo -e "\033[0;33m[WARN]\033[0m $1"; }

# Step 1: Validate prerequisites
validate_prerequisites() {
  info "Validating prerequisites..."

  # Check if .env exists
  if [[ ! -f "$SCRIPT_DIR/.env" ]]; then
    error ".env file not found. Copy .env.template to .env and configure it."
  fi

  # Check SSH connection
  if ! ssh -q "$NAS_HOST" exit; then
    error "Cannot connect to $NAS_HOST via SSH"
  fi

  success "Prerequisites validated"
}

# Step 2: Download missing configs from NAS (first-time setup)
download_configs() {
  info "Checking for missing configuration files..."

  # Create config directories if they don't exist
  mkdir -p "$SCRIPT_DIR/config/qbittorrent"

  # Download QBittorrent config if missing
  if [[ ! -f "$SCRIPT_DIR/config/qbittorrent/qBittorrent.conf" ]]; then
    info "Downloading QBittorrent configuration..."
    ssh "$NAS_HOST" "cat $NAS_DATA_DIR/.qbittorrent/config/qBittorrent/config/qBittorrent.conf" \
        > "$SCRIPT_DIR/config/qbittorrent/qBittorrent.conf" || warn "Failed to download QBittorrent config"
  fi

  success "Configuration files ready"
}

# Step 3: Sync files to NAS
sync_files() {
  info "Syncing files to NAS..."

  # Sync docker-compose.yml to Container Manager location
  info "Syncing docker-compose.yml..."
  ssh "$NAS_HOST" "cat > $NAS_DOCKER_DIR/compose.yaml" < "$SCRIPT_DIR/docker-compose.yml"

  # Sync .env file
  info "Syncing .env..."
  ssh "$NAS_HOST" "cat > $NAS_DOCKER_DIR/.env" < "$SCRIPT_DIR/.env"

  # Sync Caddyfile
  info "Syncing Caddyfile..."
  ssh "$NAS_HOST" "mkdir -p $NAS_DATA_DIR/.caddy"
  ssh "$NAS_HOST" "cat > $NAS_DATA_DIR/.caddy/Caddyfile" < "$SCRIPT_DIR/Caddyfile"

  # Sync host-side healthcheck script (run by DSM Task Scheduler on a cron)
  info "Syncing nas-healthcheck.sh..."
  ssh "$NAS_HOST" "mkdir -p $NAS_DATA_DIR/.scripts"
  ssh "$NAS_HOST" "cat > $NAS_DATA_DIR/.scripts/nas-healthcheck.sh" < "$SCRIPT_DIR/nas-healthcheck.sh"
  ssh "$NAS_HOST" "chmod +x $NAS_DATA_DIR/.scripts/nas-healthcheck.sh"

  # Sync QBittorrent config
  if [[ -f "$SCRIPT_DIR/config/qbittorrent/qBittorrent.conf" ]]; then
    info "Syncing QBittorrent configuration..."
    ssh "$NAS_HOST" "mkdir -p $NAS_DATA_DIR/.qbittorrent/config/qBittorrent/config"
    ssh "$NAS_HOST" "cat > $NAS_DATA_DIR/.qbittorrent/config/qBittorrent/config/qBittorrent.conf" \
        < "$SCRIPT_DIR/config/qbittorrent/qBittorrent.conf"
  fi

  success "Files synced successfully"
}

# Step 4: Reload Container Manager
reload_containers() {
  info "Reloading Container Manager..."
  warn "The NAS Docker socket is root-owned, so this step uses sudo."
  warn "You will be prompted for your NAS sudo password."

  # -t forces a TTY so sudo can prompt for a password. Pull latest images,
  # then recreate containers.
  ssh -t "$NAS_HOST" "cd /volume1/docker && \
    echo 'Pulling latest images...' && \
    sudo /usr/local/bin/docker compose pull && \
    sudo /usr/local/bin/docker compose down --remove-orphans && \
    sudo /usr/local/bin/docker compose up -d --force-recreate"

  success "Container Manager reloaded"
}

# Step 5: Verify services
verify_services() {
  info "Verifying services..."

  # Give containers time to start and pass their healthchecks
  sleep 15

  # Check container status (sudo: root-owned Docker socket)
  ssh -t "$NAS_HOST" "sudo /usr/local/bin/docker compose -f /volume1/docker/compose.yaml ps"

  # End-to-end reachability over Tailscale + Funnel
  echo ""
  info "Running end-to-end health check..."
  if [[ -x "$SCRIPT_DIR/healthcheck.sh" ]]; then
    "$SCRIPT_DIR/healthcheck.sh" || warn "Some services failed the health check — see above."
  else
    warn "healthcheck.sh not found or not executable; skipping end-to-end check."
  fi

  success "Deployment complete!"
}

# Heal broken NAS DNS / networking.
#
# Root cause (historical): the old j4ym0/pia-qbittorrent container ran a VPN
# kill-switch that set the HOST's iptables default policies to DROP and rewrote
# /etc/resolv.conf, firewalling the whole NAS off whenever the VPN dropped — in
# both host AND bridge mode on this Synology. That image has been replaced by
# gluetun (self-contained firewall, never touches the host), so this should no
# longer trigger; kept as a recovery tool in case the host firewall is ever
# clobbered again. NOTE: needs host access — if the NAS is already inbound-
# firewalled, SSH can't get in; recover via LAN/DSM terminal or a reboot.
#
# This resets the default policies back to ACCEPT and restores resolv.conf.
# Requires sudo on the NAS (iptables is not in the passwordless sudo scope), so
# you'll be prompted for your NAS password.
heal_dns() {
  info "Healing NAS DNS/networking (resetting iptables policies + resolv.conf)..."
  ssh -t "$NAS_HOST" 'sudo bash -s' <<'ENDSSH'
    echo "Current default policies:"; iptables -S | grep '^-P'
    iptables -P INPUT ACCEPT
    iptables -P OUTPUT ACCEPT
    iptables -P FORWARD ACCEPT
    echo "Reset to:"; iptables -S | grep '^-P'
    if ! grep -q '^nameserver' /etc/resolv.conf; then
      printf 'nameserver 1.1.1.1\nnameserver 1.0.0.1\n' > /etc/resolv.conf
      echo "resolv.conf restored to 1.1.1.1 / 1.0.0.1"
    fi
    if nslookup google.com >/dev/null 2>&1; then
      echo "DNS OK ✓"
    else
      echo "DNS still failing — the iptables state may be deeper-corrupted; a reboot will fully reset it."
    fi
ENDSSH
  success "DNS heal complete"
}

# Main execution
main() {
  echo ""
  echo "========================================"
  echo "  NAS Docker Deployment Script"
  echo "========================================"
  echo ""

  validate_prerequisites
  download_configs
  sync_files
  reload_containers
  verify_services

  echo ""
  info "Services should be accessible at:"
  echo "  - QBittorrent:          https://it-was-written.tail7aee2.ts.net:8444"
  echo "  - Synology DSM:         https://it-was-written.tail7aee2.ts.net:8443"
  echo ""
  info "Jellyfin runs on the MacBook now (not the NAS):"
  echo "  - Jellyfin (public):    https://macbook-of-eli.tail7aee2.ts.net:10000"
  echo "    Managed by the launchd service on macbook-of-eli; it reads media from"
  echo "    this NAS over SMB. See README \"Jellyfin (runs on the MacBook)\"."
  echo ""
}

# Handle script arguments
case "${1:-}" in
  --download-only)
    download_configs
    exit 0
    ;;
  --sync-only)
    validate_prerequisites
    sync_files
    exit 0
    ;;
  --heal-dns)
    heal_dns
    exit 0
    ;;
  *)
    main
    ;;
esac
