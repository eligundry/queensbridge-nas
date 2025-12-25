#!/bin/bash
# setup-tailscale-funnel.sh - Enable Tailscale Funnel for Plex
#
# This script should only need to be run once. Tailscale Funnel configuration
# is persistent and will survive reboots automatically.
#
# If you ever need to re-enable it (e.g., after changing the port or backend):
#   ssh nas
#   sudo /var/packages/Tailscale/target/bin/tailscale funnel --https=10000 --bg localhost:32400

set -e

echo "Enabling Tailscale Funnel for Plex on port 10000..."
echo ""
echo "Running on NAS: sudo tailscale funnel --https=10000 --bg localhost:32400"
echo ""

ssh nas "sudo /var/packages/Tailscale/target/bin/tailscale funnel --https=10000 --bg localhost:32400"

echo ""
echo "Verifying Funnel status..."
ssh nas "/var/packages/Tailscale/target/bin/tailscale funnel status"

echo ""
echo "✓ Tailscale Funnel is now enabled!"
echo "  Plex is publicly accessible at: https://it-was-written.tail7aee2.ts.net:10000"
echo ""
echo "Note: This configuration is persistent and will survive NAS reboots."
