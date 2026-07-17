#!/bin/bash
# healthcheck.sh - Verify every NAS service is up and externally addressable.
#
# Runs from your local machine (needs Tailscale connectivity). Probes each
# service over its Tailscale HTTPS URL AND the public Tailscale Funnel URL, so a
# green run proves the whole reverse-proxy + funnel path is working end to end.
#
# Usage:
#   ./healthcheck.sh          # probe everything, exit non-zero if anything fails
#   ./healthcheck.sh --fix    # on failure, SSH to the NAS and run remediation
#                             # (restart containers, then Tailscale) then re-probe
#
# deploy.sh calls this at the end of every deploy.

set -uo pipefail

HOST="it-was-written.tail7aee2.ts.net"
NAS_HOST="nas"
TIMEOUT=15

FIX=false
[[ "${1:-}" == "--fix" ]] && FIX=true

# Color output
green() { echo -e "\033[0;32m$1\033[0m"; }
red()   { echo -e "\033[0;31m$1\033[0m"; }
info()  { echo -e "\033[0;34m[INFO]\033[0m $1"; }
warn()  { echo -e "\033[0;33m[WARN]\033[0m $1"; }

# name|url|expected_http_code  (expected code "2xx3xx" means any 200-399)
# Jellyfin runs on the MacBook now (macbook-of-eli), not the NAS — it reads the
# media from the NAS over SMB and serves via its own Tailscale Funnel on :10000.
SERVICES=(
  "qBittorrent|https://${HOST}:8444|2xx3xx"
  "Jellyfin (MacBook funnel)|https://macbook-of-eli.tail7aee2.ts.net:10000/health|200"
  "Synology DSM|https://${HOST}:8443|2xx3xx"
)

probe() {
  # $1 url  -> echoes HTTP status code (000 on connection failure)
  curl -sk -o /dev/null -m "$TIMEOUT" -w "%{http_code}" "$1" 2>/dev/null
}

code_ok() {
  # $1 code, $2 expected
  local code="$1" expected="$2"
  if [[ "$expected" == "2xx3xx" ]]; then
    [[ "$code" =~ ^[23][0-9][0-9]$ ]]
  else
    [[ "$code" == "$expected" ]]
  fi
}

run_checks() {
  local failed=0
  for entry in "${SERVICES[@]}"; do
    IFS='|' read -r name url expected <<< "$entry"
    local code
    code=$(probe "$url")
    if code_ok "$code" "$expected"; then
      green "  ✓ ${name} (${code})"
    else
      red   "  ✗ ${name} (${code}) -> ${url}"
      failed=$((failed + 1))
    fi
  done
  return $failed
}

remediate() {
  warn "Attempting remediation on ${NAS_HOST} (heal DNS, restart containers, then Tailscale)..."
  # -t so sudo can prompt for a password on your terminal.
  ssh -t "$NAS_HOST" 'sudo bash -s' <<'ENDSSH'
    DOCKER=/usr/local/bin/docker
    # 1. Heal networking: reset iptables policies left at DROP by the qBittorrent
    #    VPN kill-switch (the usual cause of total-blackout DNS failures).
    if iptables -S 2>/dev/null | grep -q '^-P \(INPUT\|OUTPUT\|FORWARD\) DROP'; then
      echo "[nas] Resetting DROP iptables policies (VPN kill-switch residue)..."
      iptables -P INPUT ACCEPT; iptables -P OUTPUT ACCEPT; iptables -P FORWARD ACCEPT
    fi
    grep -q '^nameserver' /etc/resolv.conf || printf 'nameserver 1.1.1.1\nnameserver 1.0.0.1\n' > /etc/resolv.conf
    # 2. Restart containers.
    echo "[nas] Restarting containers..."
    $DOCKER compose -f /volume1/docker/compose.yaml restart || \
      $DOCKER compose -f /volume1/docker/compose.yaml up -d
    sleep 10
    # 3. Restart Tailscale as a last resort.
    echo "[nas] Restarting Tailscale package..."
    /usr/syno/bin/synopkg restart Tailscale || true
    sleep 10
ENDSSH
}

echo ""
info "Health check for ${HOST}"
echo ""
run_checks
result=$?

if [[ $result -ne 0 && "$FIX" == true ]]; then
  echo ""
  remediate
  echo ""
  info "Re-checking after remediation..."
  echo ""
  run_checks
  result=$?
fi

echo ""
if [[ $result -eq 0 ]]; then
  green "All services healthy ✓"
  exit 0
else
  red "${result} service(s) unhealthy ✗"
  [[ "$FIX" == false ]] && warn "Re-run with --fix to attempt automatic remediation on the NAS."
  exit 1
fi
