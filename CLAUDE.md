# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Docker-based NAS configuration for hosting media and home automation services. All services are accessed via Tailscale network with automatic HTTPS certificates provided by Caddy reverse proxy.

## Architecture

### Service Stack
- **Caddy** - Reverse proxy handling HTTPS termination with Tailscale certificates
- **QBittorrent** - Torrent client with PIA VPN integration (image: j4ym0/pia-qbittorrent)
- **Plex** - Media server for TV, movies, and music
- **Home Assistant** - Home automation platform

### Network Configuration
All services use `network_mode: host` and are accessible only within the Tailscale network at `it-was-written.tail7aee2.ts.net` with different ports:
- 8444 - QBittorrent
- 8445 - Plex
- 8446 - Home Assistant
- 8443 - Synology DSM

### Volume Management
All service data is stored under `${DATA_DIR}` with the following structure:
- `.caddy/` - Caddy configuration and certificates
- `.qbittorrent/config/` - QBittorrent configuration
- `Torrents/` - QBittorrent downloads
- `.plex/config/` and `.plex/transcode/` - Plex configuration
- `TV/`, `Movies/`, `Music/` - Plex media libraries
- `.home-assistant/` - Home Assistant configuration

### Tailscale Integration
Caddy accesses Tailscale through mounted volumes:
- `/var/packages/Tailscale/var:/var/lib/tailscale:ro`
- `/var/packages/Tailscale/var:/var/run/tailscale:ro`

TLS certificates are obtained via `get_certificate tailscale` in Caddyfile.

## Common Commands

### Deployment
```bash
docker-compose up -d
```

### Service Management
```bash
# View logs
docker-compose logs -f [service_name]

# Restart specific service
docker-compose restart [service_name]

# Stop all services
docker-compose down
```

### Environment Setup
Copy `.env.template` to `.env` and configure:
- `PIA_USERNAME` - Private Internet Access username
- `PIA_PASSWORD` - Private Internet Access password
- `DATA_DIR` - Base directory for all service data

## Important Configuration Notes

### QBittorrent Reverse Proxy
QBittorrent requires the following settings in Web UI preferences for reverse proxy compatibility:
```ini
[Preferences]
WebUI\CSRFProtection=false
WebUI\HostHeaderValidation=false
```

### Caddy Configuration
The Caddyfile at `/Users/eligundry/Code/queensbridge-nas/Caddyfile` must be synced to `${DATA_DIR}/.caddy/Caddyfile` since Caddy mounts the latter path.

### Service Ports
Internal service ports (before Caddy reverse proxy):
- QBittorrent: 8888
- Plex: 8080
- Home Assistant: 8123
- Synology DSM: 5001 (HTTPS)
