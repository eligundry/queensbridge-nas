#!/bin/bash
# Headless Jellyfin server launcher for the LaunchAgent.
# Ensures the NAS media mount, then runs the bundled Jellyfin server apphost
# under caffeinate so macOS won't idle-sleep while it's serving.
set -u

JF="/Users/eligundry/.local/share/jellyfin"
APP="/Applications/Jellyfin.app/Contents"
BIN="$APP/MacOS/jellyfin"                 # server apphost (NOT the "Jellyfin Server" GUI wrapper)
WEB="$APP/Resources/jellyfin-web"
FFMPEG="$APP/MacOS/ffmpeg"                 # bundled jellyfin-ffmpeg (VideoToolbox capable)
PUBURL="https://macbook-of-eli.tail7aee2.ts.net:10000"

mkdir -p "$JF/log"

# Block startup until the NAS media is mounted (KeepAlive will retry on failure).
if ! /Users/eligundry/.local/bin/jellyfin-mount-nas.sh; then
  echo "jellyfin-run: NAS mount failed; not starting Jellyfin" >&2
  exit 1
fi

exec /usr/bin/caffeinate -i "$BIN" \
  --datadir   "$JF/data" \
  --configdir "$JF" \
  --cachedir  "$JF/cache" \
  --logdir    "$JF/log" \
  --webdir    "$WEB" \
  --ffmpeg    "$FFMPEG" \
  --published-server-url "$PUBURL"
