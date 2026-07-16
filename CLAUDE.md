# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Docker-based NAS configuration for hosting media services. All services are accessed via Tailscale network with automatic HTTPS certificates provided by Caddy reverse proxy.

## Architecture

### Service Stack
- **Caddy** - Reverse proxy handling HTTPS termination with Tailscale certificates
- **QBittorrent** - Torrent client with PIA VPN integration (image: j4ym0/pia-qbittorrent)
- **Jellyfin** - Media server for TV, movies, and music (image: lscr.io/linuxserver/jellyfin)

### Network Configuration
All app services use `network_mode: host` (qBittorrent is the exception — it runs
in bridge mode; see below) and are accessible within the Tailscale network at
`it-was-written.tail7aee2.ts.net` with different ports:
- 8444 - QBittorrent
- 8445 - Jellyfin (tailnet)
- 10000 - Jellyfin (public, via Tailscale Funnel → Caddy :8445)
- 8443 - Synology DSM

### Volume Management
All service data is stored under `${DATA_DIR}` with the following structure:
- `.caddy/` - Caddy configuration and certificates
- `.qbittorrent/config/` - QBittorrent configuration
- `Torrents/` - QBittorrent downloads
- `.jellyfin/config/` - Jellyfin configuration (and cache)
- `TV/`, `Movies/`, `Music/` - Jellyfin media libraries (mounted at `/data/tv`, `/data/movies`, `/data/music`)
- `.scripts/nas-healthcheck.sh` - Host-side healthcheck run by DSM Task Scheduler

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
- Jellyfin: 8096
- Synology DSM: 5001 (HTTPS)
- Caddy admin API: 2019 (used for healthchecks)

### Tailscale Funnel
Public access to Jellyfin uses Tailscale Funnel on port 10000, which forwards to
Caddy's Jellyfin site (`https+insecure://localhost:8445`) rather than directly
to Jellyfin. Enable it once with `./setup-tailscale-funnel.sh`.

### Health Checks
Every service defines a Docker `healthcheck` (for visibility in `docker ps`) and
uses `restart: unless-stopped` so Docker restarts anything that exits. There is
**no** `autoheal` sidecar — on this Synology its `docker restart` calls failed
(exit 128) and it churned healthy containers, causing more outages than it fixed.
`healthcheck.sh` verifies all services (including the public Funnel URL) from a
client machine and is run by `deploy.sh`. `nas-healthcheck.sh` runs on the NAS
via DSM Task Scheduler to self-heal networking and notify via `synodsmnotify`.

### NAS Deployment Notes
The Docker socket on the NAS is `root`-owned, so `docker`/`docker compose`
commands require `sudo`. A scoped passwordless-sudo drop-in
(`/etc/sudoers.d/eligundry-nas`) allows `docker`, `tailscale`, and `synopkg`
without a password; other commands (e.g. `iptables`, `reboot`) still prompt.
`deploy.sh` uses `ssh -t` + `sudo` for the container reload. File syncing
(compose, Caddyfile, configs) does not need sudo.

### qBittorrent + VPN (bridge mode — do NOT use host networking)
qBittorrent runs the `j4ym0/pia-qbittorrent` image, which includes a PIA VPN
**kill-switch**. It MUST run in **bridge mode** (the upstream design), never
`network_mode: host`:
- **Bridge mode:** the kill-switch programs iptables inside the container's own
  network namespace. A VPN failure only firewalls the container — the host is
  untouched. The WebUI is published on host port `8888` (DNAT) so Caddy can proxy
  `localhost:8888`. Requires `ALLOW_LOCAL_SUBNET_TRAFFIC=true` for LAN/Caddy
  access through the kill-switch.
- **Host mode (the old bug):** the kill-switch clobbered the **host's** iptables
  (default policies → `DROP`) and `/etc/resolv.conf`, so any VPN drop took the
  whole NAS offline (DNS dead) and it couldn't self-recover. This was the root of
  the recurring "networking just breaks" problem. Fixed by moving to bridge mode.

Synology gotcha: Docker bridge port-publishing needs the nat `DOCKER` iptables
chain, which Synology sometimes drops (symptom: `iptables: No chain/target/match
by that name` / `unable to find chain 'DOCKER'`, and published ports return 000).
Recreate it by restarting the daemon: `sudo synopkg restart ContainerManager`.

Legacy DNS recovery (only needed if host networking ever gets clobbered again):
`./deploy.sh --heal-dns` resets iptables policies to `ACCEPT` + restores
resolv.conf; `nas-healthcheck.sh` does this automatically as its first
remediation step.
