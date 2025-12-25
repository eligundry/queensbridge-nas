# queensbridge-nas

I have a network attached storage (NAS) device and I live in Queens so, it's
fitting that the naming conventions around this device reference the legendary
Nasir Jones AKA Nas!

![Nas album Illmatic cover](https://upload.wikimedia.org/wikipedia/en/2/27/IllmaticNas.jpg)

The repository contains configurations for Docker containers running on this
device. I'm primarily using it to backup my computer via Time Machine and as
a torrent powered Tivo device through Plex. All access goes through Tailscale.

## Services

All services are accessible with automatic HTTPS certificates via Tailscale:

- **QBittorrent** - `https://it-was-written.tail7aee2.ts.net:8444` - Torrent client with PIA VPN (Tailscale network only)
- **Plex (Tailscale network)** - `https://it-was-written.tail7aee2.ts.net:8445` - Media server for movies, TV, and music
- **Plex (Public via Funnel)** - `https://it-was-written.tail7aee2.ts.net:10000` - Public access for app.plex.tv
- **Home Assistant** - `https://it-was-written.tail7aee2.ts.net:8446` - Home automation platform
- **Synology DSM** - `https://it-was-written.tail7aee2.ts.net:8443` - NAS web interface

## SSL/TLS Configuration

- **Caddy** reverse proxy handles all HTTPS termination
- **Tailscale certificates** are automatically obtained and renewed
- All services accessible only within the Tailscale network
- No manual certificate management required

## Service Configuration

**QBittorrent** requires reverse proxy configuration:
```ini
[Preferences]
WebUI\CSRFProtection=false
WebUI\HostHeaderValidation=false
```

## SSH Access

SSH configuration for proper terminal support is in `~/.ssh/config`:

```ssh-config
Host nas
  HostName 100.91.114.32
  SetEnv TERM=xterm-256color
  RequestTTY yes
```

Connect using: `ssh nas`

## Deployment

### Automated Deployment

Use the deployment script to sync configurations and restart services:

```bash
# Full deployment (sync files + restart containers)
./deploy.sh

# Just sync files without restarting
./deploy.sh --sync-only

# Download configs from NAS (first-time setup)
./deploy.sh --download-only
```

The deploy script automatically:
- Syncs docker-compose.yml, Caddyfile, .env, and service configs to the NAS
- Updates Container Manager's compose file at `/volume1/docker/compose.yaml`
- Restarts all containers with the new configuration

### Manual Deployment

If needed, you can manually deploy via SSH:

```bash
ssh nas "cd /volume1/docker && docker compose up -d"
```

## Tailscale Funnel Setup (One-Time)

Plex requires Tailscale Funnel on port 10000 for public access (allows app.plex.tv to connect):

```bash
# Enable Funnel (one-time setup - configuration persists across reboots)
ssh nas
sudo /var/packages/Tailscale/target/bin/tailscale funnel --https=10000 --bg localhost:32400

# Verify Funnel status
tailscale funnel status
```

**Note:** Tailscale Funnel configuration is persistent and survives reboots. You only need to run this once, or after changing ports/backends.

### Plex Network Configuration

After enabling Funnel, configure Plex:
1. Go to Plex Settings → Network
2. Add custom server access URL: `https://it-was-written.tail7aee2.ts.net:10000`
3. Set "Secure connections" to "Preferred"
