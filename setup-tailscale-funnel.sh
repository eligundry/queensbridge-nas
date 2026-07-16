#!/bin/bash
# setup-tailscale-funnel.sh - Enable Tailscale Funnel for Jellyfin
#
# This script should only need to be run once. Tailscale Funnel configuration
# is persistent and will survive reboots automatically.
#
# The Funnel terminates public TLS on :10000 and forwards directly to Jellyfin's
# HTTP port (8096). We tried routing the Funnel through Caddy (:8445) but Funnel
# sends SNI "localhost", which doesn't match Caddy's Tailscale-hostname site, so
# the TLS handshake fails with a 502. Pointing straight at Jellyfin is the
# proven, stable approach (Jellyfin handles direct exposure fine; the tailnet
# path on :8445 still goes through Caddy). JELLYFIN_PublishedServerUrl in
# docker-compose.yml tells Jellyfin its public URL.
#
# If you ever need to re-enable it (e.g., after changing the port or backend):
#   ssh nas
#   sudo /var/packages/Tailscale/target/bin/tailscale funnel --https=10000 --bg http://localhost:8096

set -e

FUNNEL_TARGET="http://localhost:8096"

echo "Enabling Tailscale Funnel for Jellyfin on port 10000..."
echo ""
echo "Running on NAS: sudo tailscale funnel --https=10000 --bg $FUNNEL_TARGET"
echo ""

# -t forces a TTY so the sudo password prompt works over SSH.
ssh -t nas "sudo /var/packages/Tailscale/target/bin/tailscale funnel --https=10000 --bg $FUNNEL_TARGET"

echo ""
echo "Verifying Funnel status..."
ssh nas "/var/packages/Tailscale/target/bin/tailscale funnel status"

echo ""
echo "✓ Tailscale Funnel is now enabled!"
echo "  Jellyfin is publicly accessible at: https://it-was-written.tail7aee2.ts.net:10000"
echo ""
echo "Note: This configuration is persistent and will survive NAS reboots."
