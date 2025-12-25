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

- **QBittorrent** - `https://it-was-written.tail7aee2.ts.net:8444` - Torrent client with PIA VPN
- **Plex** - `https://it-was-written.tail7aee2.ts.net:8445` - Media server for movies, TV, and music
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

To deploy: `docker-compose up -d`
