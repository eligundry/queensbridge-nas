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
  mkdir -p "$SCRIPT_DIR/config/home-assistant"

  # Download QBittorrent config if missing
  if [[ ! -f "$SCRIPT_DIR/config/qbittorrent/qBittorrent.conf" ]]; then
    info "Downloading QBittorrent configuration..."
    ssh "$NAS_HOST" "cat $NAS_DATA_DIR/.qbittorrent/config/qBittorrent/config/qBittorrent.conf" \
        > "$SCRIPT_DIR/config/qbittorrent/qBittorrent.conf" || warn "Failed to download QBittorrent config"
  fi

  # Download Home Assistant configs if missing
  for file in configuration.yaml automations.yaml scripts.yaml; do
    if [[ ! -f "$SCRIPT_DIR/config/home-assistant/$file" ]]; then
      info "Downloading Home Assistant $file..."
      ssh "$NAS_HOST" "cat $NAS_DATA_DIR/.home-assistant/$file" \
          > "$SCRIPT_DIR/config/home-assistant/$file" || warn "Failed to download $file"
    fi
  done

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

  # Sync QBittorrent config
  if [[ -f "$SCRIPT_DIR/config/qbittorrent/qBittorrent.conf" ]]; then
    info "Syncing QBittorrent configuration..."
    ssh "$NAS_HOST" "mkdir -p $NAS_DATA_DIR/.qbittorrent/config/qBittorrent/config"
    ssh "$NAS_HOST" "cat > $NAS_DATA_DIR/.qbittorrent/config/qBittorrent/config/qBittorrent.conf" \
        < "$SCRIPT_DIR/config/qbittorrent/qBittorrent.conf"
  fi

  # Sync Home Assistant configs (skip if permission denied)
  if [[ -d "$SCRIPT_DIR/config/home-assistant" ]]; then
    info "Syncing Home Assistant configurations..."
    ssh "$NAS_HOST" "mkdir -p $NAS_DATA_DIR/.home-assistant" || true
    for file in "$SCRIPT_DIR/config/home-assistant"/*.yaml; do
      if [[ -f "$file" ]]; then
        filename=$(basename "$file")
        ssh "$NAS_HOST" "cat > $NAS_DATA_DIR/.home-assistant/$filename" < "$file" 2>/dev/null || \
          warn "Skipping $filename (permission denied - Home Assistant manages this file)"
      fi
    done
  fi

  success "Files synced successfully"
}

# Step 4: Reload Container Manager
reload_containers() {
  info "Reloading Container Manager..."

  # Navigate to docker directory and restart services
  ssh "$NAS_HOST" << 'ENDSSH'
    cd /volume1/docker
    # Pull latest images
    echo "Pulling latest images..."
    /usr/local/bin/docker compose pull
    # Stop and remove containers, then recreate them (use full path for docker)
    /usr/local/bin/docker compose down --remove-orphans
    /usr/local/bin/docker compose up -d --force-recreate
ENDSSH

  success "Container Manager reloaded"
}

# Step 5: Verify services
verify_services() {
  info "Verifying services..."

  # Wait a few seconds for containers to start
  sleep 5

  # Check container status
  ssh "$NAS_HOST" "/usr/local/bin/docker compose -f /volume1/docker/compose.yaml ps"

  success "Deployment complete!"
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
  echo "  - QBittorrent: https://it-was-written.tail7aee2.ts.net:8444"
  echo "  - Plex: https://it-was-written.tail7aee2.ts.net:8445"
  echo "  - Home Assistant: https://it-was-written.tail7aee2.ts.net:8446"
  echo ""
  warn "IMPORTANT: Configure Plex manually:"
  echo "  1. Go to Plex Settings → Network"
  echo "  2. Add custom server access URL: https://it-was-written.tail7aee2.ts.net:8445"
  echo "  3. Set secure connections to 'Preferred'"
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
  *)
    main
    ;;
esac
