# queensbridge-nas

I have a network attached storage (NAS) device and I live in Queens so, it's
fitting that the naming conventions around this device reference the legendary
Nasir Jones AKA Nas!

![Nas album Illmatic cover](https://upload.wikimedia.org/wikipedia/en/2/27/IllmaticNas.jpg)

The repository contains configurations for Docker containers running on this
device. I'm primarily using it to backup my computer via Time Machine and to
store the media library that feeds my torrent-powered Tivo. All access goes
through Tailscale.

Media playback is served by **Jellyfin, which runs on my MacBook** (not the
NAS) — the NAS's ARM Realtek SoC is too weak to transcode, so Jellyfin was moved
to the Apple Silicon Mac (VideoToolbox hardware transcoding) where it reads the
media from this NAS over SMB. See [Jellyfin (runs on the MacBook)](#jellyfin-runs-on-the-macbook).

## Services

All services are accessible with automatic HTTPS certificates via Tailscale:

- **QBittorrent** - `https://it-was-written.tail7aee2.ts.net:8444` - Torrent client with PIA VPN (Tailscale network only)
- **Synology DSM** - `https://it-was-written.tail7aee2.ts.net:8443` - NAS web interface
- **Jellyfin** - `https://macbook-of-eli.tail7aee2.ts.net:10000` - Media server for movies, TV, and music (**runs on the MacBook**, reads media from the NAS over SMB)

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

## Jellyfin (runs on the MacBook)

Jellyfin **does not run on the NAS**. The NAS's ARM Realtek RTD1619B has no
hardware video encoder, so any transcode pegged all four cores and stuttered.
Jellyfin now runs on the MacBook (`macbook-of-eli`, Apple Silicon) as a headless
`launchd` service. It reads the media from the NAS over SMB and, when a client
does need a transcode, uses **VideoToolbox** hardware acceleration. The media
still lives on the NAS under `${DATA_DIR}/{TV,Movies,Music}`.

The service files live in [`macbook-jellyfin/`](macbook-jellyfin/):

| File | Purpose |
|------|---------|
| `org.jellyfin.server.plist` | LaunchAgent (`~/Library/LaunchAgents/`), `RunAtLoad` + `KeepAlive` |
| `jellyfin-run.sh` | Wrapper: mounts the NAS, then runs the bundled Jellyfin server under `caffeinate` |
| `jellyfin-mount-nas.sh` | Mounts `smb://…/home` at `~/nas-media` (password from a `0600` file) |
| `rewrite_paths.py` | One-time migration tool that rewrote container paths (`/data/*`, `/config/data`) to the Mac paths in the migrated Jellyfin DB |

**Layout on the Mac:**
- App (server + `jellyfin-ffmpeg`): `/Applications/Jellyfin.app` (`brew install --cask jellyfin`)
- Data/config/cache/log: `~/.local/share/jellyfin/` (migrated from the NAS `.jellyfin/config`)
- Media mount: `~/nas-media` → `smb://eligundry@100.91.114.32/home`

**Full Disk Access is required.** macOS blocks background (`launchd`) processes
from *reading* network volumes unless granted Full Disk Access. Add
`/Applications/Jellyfin.app/Contents/MacOS/jellyfin` under **System Settings →
Privacy & Security → Full Disk Access**. Without it, Jellyfin starts and serves
the web UI but can't read any media.

**Manage the service:**
```bash
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/org.jellyfin.server.plist  # start/install
launchctl bootout   gui/$(id -u)/org.jellyfin.server                               # stop
launchctl kickstart -k gui/$(id -u)/org.jellyfin.server                            # restart
```

### Tailscale Funnel (One-Time, on the MacBook)

Jellyfin is exposed publicly on port 10000 via Tailscale Funnel, pointing
straight at the local Jellyfin HTTP port (`8096`) — "raw", no Caddy. Run this on
the MacBook (funnel config is persistent and survives reboots):

```bash
# helper
./setup-tailscale-funnel.sh

# ...or manually
tailscale funnel --bg --https=10000 http://127.0.0.1:8096

# verify
tailscale funnel status
```

Because the Funnel forwards to `localhost:8096` with no `X-Forwarded-For`,
Jellyfin sees Funnel clients as local — so they aren't hit by the "remote"
bitrate cap, which favors Direct Play over transcoding.

## qBittorrent + PIA VPN (via gluetun)

**How it works:** qBittorrent has **no built-in VPN**. It routes all traffic
through **[gluetun](https://github.com/qdm12/gluetun)** (`qmcgaw/gluetun`), a
dedicated PIA VPN gateway container, using `network_mode: service:gluetun`.
gluetun runs OpenVPN plus a kill-switch **entirely inside its own network
namespace** and never touches the host's iptables. If the tunnel drops, only the
containers sharing gluetun's namespace (qBittorrent) lose connectivity — the NAS
stays online. qBittorrent's WebUI is published on gluetun's port `8888`, and
Caddy proxies `localhost:8888` (with `FIREWALL_INPUT_PORTS=8888` opening it
through gluetun's kill-switch).

**Why not the old `j4ym0/pia-qbittorrent` image?** Its PIA kill-switch
reprogrammed the **host's** iptables (default policies → `DROP`) and took the
entire NAS offline on any restart or VPN drop — in **both** `network_mode: host`
**and** Docker bridge mode on this Synology. That was the root of the recurring
"networking just breaks" outages. gluetun's self-contained firewall fixes it.

**Config migration:** both images run `qbittorrent-nox --profile=/config`, so the
existing torrents/config under `${DATA_DIR}/.qbittorrent/config` should carry over
unchanged. Verify the torrent list on first boot.

### Recovering broken DNS (only if host networking ever gets clobbered)

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
