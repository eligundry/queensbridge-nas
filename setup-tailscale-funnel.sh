#!/bin/bash
# setup-tailscale-funnel.sh - Enable Tailscale Funnel for Jellyfin.
#
# Jellyfin now runs on THIS MacBook (macbook-of-eli) as a headless launchd
# service (see README "Jellyfin (runs on the MacBook)"), not on the NAS. So the
# Funnel is configured here, locally, and points straight at the local Jellyfin
# HTTP port (8096) — "raw", with no Caddy in between. Funnel terminates public
# TLS on :10000 and forwards to http://127.0.0.1:8096.
#
# Run this ON the MacBook (not the NAS). Tailscale Funnel configuration is
# persistent and survives reboots.
#
# Note: port 443 on this node is already used by another Funnel; Jellyfin uses
# :10000 (one of the three Funnel-eligible ports: 443, 8443, 10000).
#
# To disable:  tailscale funnel --https=10000 off

set -e

FUNNEL_PORT=10000
FUNNEL_TARGET="http://127.0.0.1:8096"

echo "Enabling Tailscale Funnel for Jellyfin on port ${FUNNEL_PORT} (local MacBook)..."
echo "  target: ${FUNNEL_TARGET}"
echo ""

tailscale funnel --bg --https=${FUNNEL_PORT} "${FUNNEL_TARGET}"

echo ""
echo "Verifying Funnel status..."
tailscale funnel status

echo ""
echo "✓ Tailscale Funnel is now enabled!"
echo "  Jellyfin is publicly accessible at: https://macbook-of-eli.tail7aee2.ts.net:${FUNNEL_PORT}"
echo ""
echo "Note: This configuration is persistent and will survive reboots."
