# queensbridge-nas

I have a network attached storage (NAS) device and I live in Queens so, it's
fitting that the naming conventions around this device reference the legendary
Nasir Jones AKA Nas!

![Nas album Illmatic cover](https://upload.wikimedia.org/wikipedia/en/2/27/IllmaticNas.jpg)

The repository contains configurations for Docker containers running on this
device. I'm primarily using it to backup my computer via Time Machine and as
a torrent powered Tivo device through Jellyfin. All access goes through
Tailscale.

## Services

All services are accessible with automatic HTTPS certificates via Tailscale:

- **QBittorrent** - `https://it-was-written.tail7aee2.ts.net:8444` - Torrent client with PIA VPN (Tailscale network only)
- **Jellyfin (Tailscale network)** - `https://it-was-written.tail7aee2.ts.net:8445` - Media server for movies, TV, and music
- **Jellyfin (Public via Funnel)** - `https://it-was-written.tail7aee2.ts.net:10000` - Public access (proxied through Caddy)
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

Jellyfin is exposed publicly on port 10000 via Tailscale Funnel. The Funnel
forwards to Caddy's Jellyfin site on `:8445` (not directly to Jellyfin), so
Caddy stays the single reverse-proxy source of truth:

```bash
# Run the helper (prompts for your NAS sudo password)
./setup-tailscale-funnel.sh

# ...or manually (one-time setup - configuration persists across reboots)
ssh nas
sudo /var/packages/Tailscale/target/bin/tailscale funnel --https=10000 --bg https+insecure://localhost:8445

# Verify Funnel status
tailscale funnel status
```

**Note:** Tailscale Funnel configuration is persistent and survives reboots. You only need to run this once, or after changing ports/backends.

### Jellyfin First-Run Setup

After deploying, open `https://it-was-written.tail7aee2.ts.net:8445` and:
1. Complete the setup wizard (create the admin user).
2. Add libraries pointing at the in-container paths: `/data/tv`, `/data/movies`, `/data/music`.
3. (Optional) Dashboard → Networking: confirm the **Published Server URL** is
   `https://it-was-written.tail7aee2.ts.net:10000` (also set via the
   `JELLYFIN_PublishedServerUrl` env var in `docker-compose.yml`).

## qBittorrent, the VPN kill-switch, and NAS DNS

**Background:** qBittorrent (`j4ym0/pia-qbittorrent`) ships a PIA VPN
**kill-switch**. It is designed to run in Docker **bridge mode**, and this repo
runs it that way — its WebUI is published on host port `8888` and Caddy proxies
`localhost:8888`. In bridge mode the kill-switch only affects the container, so a
VPN drop can **never** take down the NAS.

**Historical bug (now fixed):** it used to run `network_mode: host`, so the
kill-switch reprogrammed the **host's** iptables (default policies → `DROP`) and
`/etc/resolv.conf`. Any VPN failure firewalled the whole NAS off — DNS died, and
a failing qBittorrent couldn't resolve PIA to reconnect, so the outage stuck.
That was the root of the recurring "networking just breaks."

**Synology gotcha:** bridge port-publishing needs the nat `DOCKER` iptables
chain, which Synology sometimes drops after a reboot (symptom: qBittorrent's
WebUI on `:8444`/`:8888` returns nothing, and container start logs show
`iptables: No chain/target/match by that name`). Recreate it by restarting the
daemon: `ssh nas "sudo synopkg restart ContainerManager"`.

### Recovering broken DNS (legacy — only if host networking ever gets clobbered)

If the NAS ever loses DNS / all outbound networking (`nslookup` times out,
containers can't pull), reset the iptables default policies back to `ACCEPT`:

```bash
./deploy.sh --heal-dns          # from your machine (prompts for NAS sudo password)
```

or manually on the NAS:

```bash
ssh nas
sudo iptables -P INPUT ACCEPT
sudo iptables -P OUTPUT ACCEPT
sudo iptables -P FORWARD ACCEPT
# restore resolv.conf if it lost its nameservers:
grep -q '^nameserver' /etc/resolv.conf || \
  printf 'nameserver 1.1.1.1\nnameserver 1.0.0.1\n' | sudo tee /etc/resolv.conf
```

**Automatic recovery:** `nas-healthcheck.sh` (the 12-hour DSM Task Scheduler job)
detects `DROP` policies and resets them automatically as its first remediation
step, then notifies you via Synology notifications.

**Last resort:** if the iptables state is deeper-corrupted, a reboot fully resets
it (`sudo reboot`) — containers don't auto-start on boot, so DNS comes back clean.

## Health Checks & Monitoring

The stack is designed to self-heal:

- **Docker healthchecks** are defined for every service in `docker-compose.yml`,
  and `restart: unless-stopped` restarts any container that exits. (We do **not**
  run an `autoheal` sidecar — on this Synology its `docker restart` calls fail
  with exit 128 and it churned healthy containers, so it caused more outages than
  it fixed. Recovery is handled by Docker's own restart policy plus the
  `nas-healthcheck.sh` cron below.)
- **`healthcheck.sh`** (run from your machine) probes every service over its
  Tailscale URL *and* the public Funnel URL, so a green run proves the whole
  proxy + funnel path works. `deploy.sh` runs it automatically after each deploy.

  ```bash
  ./healthcheck.sh          # probe everything
  ./healthcheck.sh --fix    # on failure, SSH in and run remediation, then re-probe
  ```

- **`nas-healthcheck.sh`** runs *on the NAS* on a schedule. When the NAS
  networking wedges, it restarts the containers, then Tailscale, and notifies
  through Synology's own notification system (`synodsmnotify`). It is synced to
  `${DATA_DIR}/.scripts/nas-healthcheck.sh` by `deploy.sh`.

  Register it once in **DSM → Control Panel → Task Scheduler → Create →
  Scheduled Task → User-defined script**:
  - **User:** `root`
  - **Schedule:** every 12 hours
  - **Task Settings → Run command:** `bash /var/services/homes/eligundry/.scripts/nas-healthcheck.sh`
  - Enable **"Send run details by email"** and **"only when abnormal"** so a
    failed remediation also emails you (in addition to the DSM notification).
