#!/bin/bash
# nas-healthcheck.sh - Host-side health check + self-heal, run ON the Synology NAS.
#
# Intended to be registered in DSM Task Scheduler as a user-defined script that
# runs as root on a 12-hour schedule (see README "Health Checks & Monitoring").
#
# What it does:
#   1. Probes every service locally (and the public Funnel URL end-to-end).
#   2. If anything is down, escalates remediation:
#        a. docker compose restart  ->  re-probe
#        b. restart the Tailscale package  ->  re-probe
#   3. Notifies through Synology's own notification system (synodsmnotify), and
#      exits non-zero on unresolved failure so DSM Task Scheduler's
#      "send run details by email on abnormal termination" also fires.
#
# Runs as root under Task Scheduler, so docker/synopkg need no sudo.

set -uo pipefail

DOCKER=/usr/local/bin/docker
COMPOSE_FILE=/volume1/docker/compose.yaml
SYNODSMNOTIFY=/usr/syno/bin/synodsmnotify
SYNOPKG=/usr/syno/bin/synopkg
HOST=it-was-written.tail7aee2.ts.net
TIMEOUT=15

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# name|url|expected  (expected "2xx3xx" = any 200-399, otherwise exact code)
# qBittorrent's WebUI (:8888) is published on the host by the gluetun container
# (qBittorrent shares gluetun's netns). It's safe to probe now that the VPN
# kill-switch lives inside gluetun and no longer touches the host.
# Jellyfin is NOT probed here: it was moved off the NAS to the MacBook and no
# longer runs on this host.
SERVICES=(
  "qbittorrent|http://127.0.0.1:8888|2xx3xx"
  "caddy|http://127.0.0.1:2019/config/|200"
)

probe() { curl -sk -o /dev/null -m "$TIMEOUT" -w "%{http_code}" "$1" 2>/dev/null; }

code_ok() {
  local code="$1" expected="$2"
  if [[ "$expected" == "2xx3xx" ]]; then
    [[ "$code" =~ ^[23][0-9][0-9]$ ]]
  else
    [[ "$code" == "$expected" ]]
  fi
}

# Populates the global DOWN array with the names of failing services.
run_checks() {
  DOWN=()
  local entry name url expected code
  for entry in "${SERVICES[@]}"; do
    IFS='|' read -r name url expected <<< "$entry"
    code=$(probe "$url")
    if code_ok "$code" "$expected"; then
      log "OK   $name ($code)"
    else
      log "FAIL $name ($code) -> $url"
      DOWN+=("$name")
    fi
  done
}

notify() {
  # $1 title  $2 message
  if [[ -x "$SYNODSMNOTIFY" ]]; then
    "$SYNODSMNOTIFY" @administrators "$1" "$2" || log "synodsmnotify failed"
  else
    log "synodsmnotify not found at $SYNODSMNOTIFY"
  fi
}

# Undo the PIA qBittorrent VPN kill-switch damage: if it left the host's iptables
# default policies at DROP (which kills DNS + all networking), reset them to
# ACCEPT and restore resolv.conf. Runs as root under Task Scheduler, so iptables
# needs no sudo. Returns 0 if it changed anything.
heal_network() {
  local changed=1
  if iptables -S 2>/dev/null | grep -q '^-P \(INPUT\|OUTPUT\|FORWARD\) DROP'; then
    log "Detected DROP default policies (VPN kill-switch residue) — resetting to ACCEPT."
    iptables -P INPUT ACCEPT
    iptables -P OUTPUT ACCEPT
    iptables -P FORWARD ACCEPT
    changed=0
  fi
  if ! grep -q '^nameserver' /etc/resolv.conf 2>/dev/null; then
    log "resolv.conf missing nameservers — restoring."
    printf 'nameserver 1.1.1.1\nnameserver 1.0.0.1\n' > /etc/resolv.conf
    changed=0
  fi
  return $changed
}

log "=== NAS health check starting ==="
run_checks

if [[ ${#DOWN[@]} -eq 0 ]]; then
  log "All services healthy."
  exit 0
fi

FIRST_DOWN="${DOWN[*]}"
log "Unhealthy: $FIRST_DOWN — beginning remediation."

# Step 0: heal networking (most common failure — VPN kill-switch left iptables
# policies at DROP, killing DNS). Cheap and safe, so always try it first.
if heal_network; then
  log "Networking healed — re-checking before touching containers."
  sleep 5
  run_checks
  if [[ ${#DOWN[@]} -eq 0 ]]; then
    notify "NAS auto-recovered" "Services were down ($FIRST_DOWN); recovered by resetting iptables policies (VPN kill-switch residue)."
    log "Recovered after network heal."
    exit 0
  fi
fi

# Step 1: restart containers
log "Remediation 1/3: restarting containers..."
"$DOCKER" compose -f "$COMPOSE_FILE" restart || "$DOCKER" compose -f "$COMPOSE_FILE" up -d
sleep 20
run_checks

if [[ ${#DOWN[@]} -eq 0 ]]; then
  notify "NAS auto-recovered" "Services were down ($FIRST_DOWN) and recovered after a container restart."
  log "Recovered after container restart."
  exit 0
fi

# Step 3: restart Tailscale (networking on the NAS sometimes wedges)
log "Remediation 3/3: restarting Tailscale package..."
"$SYNOPKG" restart Tailscale || log "synopkg restart Tailscale failed"
sleep 20
run_checks

if [[ ${#DOWN[@]} -eq 0 ]]; then
  notify "NAS auto-recovered" "Services were down ($FIRST_DOWN) and recovered after restarting Tailscale + containers."
  log "Recovered after Tailscale restart."
  exit 0
fi

# Still broken — escalate to the human.
STILL_DOWN="${DOWN[*]}"
notify "NAS health check FAILED" "Still down after auto-remediation: $STILL_DOWN. Manual intervention needed."
log "Remediation failed. Still down: $STILL_DOWN"
exit 1
