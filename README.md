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

- **QBittorrent** - `qbittorrent.tail7aee2.ts.net` - Torrent client with PIA VPN
- **Plex** - `plex.tail7aee2.ts.net` - Media server for movies, TV, and music
- **Home Assistant** - `home-assistant.tail7aee2.ts.net` - Home automation platform
- **Synology DSM** - `nas.tail7aee2.ts.net` - NAS web interface (HTTP)
- **Synology DSM (Secure)** - `it-was-written.tail7aee2.ts.net` - NAS web interface (HTTPS)

## SSL/TLS Configuration

- **Caddy** reverse proxy handles all HTTPS termination
- **Tailscale certificates** are automatically obtained and renewed
- All services accessible only within the Tailscale network
- No manual certificate management required

To deploy: `docker-compose up -d`
