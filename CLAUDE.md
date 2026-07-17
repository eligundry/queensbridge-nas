# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Docker-based NAS configuration for hosting media services. All services are accessed via Tailscale network with automatic HTTPS certificates provided by Caddy reverse proxy.

## Architecture

### Service Stack
- **Caddy** - Reverse proxy handling HTTPS termination with Tailscale certificates
- **gluetun** - PIA VPN gateway (image: qmcgaw/gluetun); qBittorrent routes through it
- **QBittorrent** - Torrent client (image: lscr.io/linuxserver/qbittorrent), no built-in VPN — uses `network_mode: service:gluetun`
- **Jellyfin** - Media server for TV, movies, and music (image: lscr.io/linuxserver/jellyfin)

### Network Configuration
Caddy and Jellyfin use `network_mode: host`. gluetun runs in Docker bridge mode
and qBittorrent shares gluetun's network namespace (`network_mode: service:gluetun`);
see the VPN section below. Services are accessible within the Tailscale network at
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

### qBittorrent + VPN (via gluetun — do NOT use the old j4ym0 image)
qBittorrent has **no built-in VPN**. It routes all traffic through **gluetun**
(`qmcgaw/gluetun`), a dedicated PIA VPN gateway container, via
`network_mode: service:gluetun`. gluetun runs OpenVPN + its kill-switch entirely
inside its own network namespace and **never touches the host's iptables**. A VPN
drop can only cut off the containers sharing gluetun's netns (qBittorrent) — the
host stays online.
- The WebUI is published on gluetun's port `8888` (qBittorrent shares that netns),
  so Caddy proxies `localhost:8888` exactly as before. `FIREWALL_INPUT_PORTS=8888`
  opens the WebUI through gluetun's kill-switch.
- PIA credentials are passed as `OPENVPN_USER`/`OPENVPN_PASSWORD` (`${PIA_USERNAME}`
  / `${PIA_PASSWORD}`); region via `SERVER_REGIONS=US East`.
- gluetun auto-creates `/dev/net/tun` (needs `cap_add: NET_ADMIN`), so no device
  mapping is required.

**Why we abandoned `j4ym0/pia-qbittorrent`:** its PIA kill-switch clobbered the
**host's** iptables (INPUT policy → `DROP`) and took the whole NAS offline on any
restart/VPN drop — in **both** host mode AND Docker bridge mode on this Synology
(the bridge-mode isolation we assumed did not hold). This was the root of the
recurring "networking just breaks" outages. gluetun's self-contained firewall is
the fix.

**Config migration note:** both images run `qbittorrent-nox --profile=/config`, so
the profile layout (`/config/qBittorrent/config/qBittorrent.conf`,
`/config/qBittorrent/data/BT_backup/`) should carry over and preserve the existing
torrents when switching to `lscr.io/linuxserver/qbittorrent`. Verify on first boot;
if the linuxserver image looks for a flat `/config/qBittorrent/qBittorrent.conf`,
move the old files into the layout it expects before trusting the torrent list.

DNS recovery (if the host firewall ever gets clobbered again — e.g. by the old
image before this migration): `./deploy.sh --heal-dns` resets iptables policies to
`ACCEPT` + restores resolv.conf; `nas-healthcheck.sh` does this automatically as
its first remediation step. **This requires host access** — if the NAS is already
inbound-firewalled, SSH won't get in; recover via LAN/DSM terminal or a reboot.
