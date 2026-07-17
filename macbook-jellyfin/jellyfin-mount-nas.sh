#!/bin/bash
# Mounts the NAS home share (contains TV/Movies/Music) that Jellyfin serves.
# Password is read from the login keychain at runtime (never stored on disk).
# Idempotent: exits 0 if already mounted and readable.
set -u

MP="/Users/eligundry/nas-media"
HOST="100.91.114.32"          # NAS Tailscale IP (SMB reachable on the tailnet)
SHARE="home"                   # Synology per-user home share -> /var/services/homes/eligundry
SMBUSER="eligundry"
PWFILE="/Users/eligundry/.config/jellyfin-nas/smb.pass"  # 0600 file (mode-protected)

mkdir -p "$MP"

# Already mounted? Treat presence as good. We intentionally do NOT read the
# volume to health-check it: macOS TCC blocks background (launchd) processes from
# *reading* network volumes, so an `ls` here would false-negative and flap the
# mount. Establishing the mount does not require the read grant; the Jellyfin
# server process (granted Full Disk Access) performs the actual media reads.
if mount | grep -q " on $MP (smbfs"; then
  exit 0
fi

# Read the SMB password from the mode-protected file. We deliberately avoid
# `security find-internet-password -w` here: under launchd it blocks on a
# keychain ACL/partition authorization that has no GUI to answer it.
PW=$(< "$PWFILE")
if [ -z "$PW" ]; then
  echo "jellyfin-mount-nas: no password in $PWFILE" >&2
  exit 1
fi
ENC=$(/usr/bin/python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "$PW")
unset PW

/sbin/mount_smbfs -N "//${SMBUSER}:${ENC}@${HOST}/${SHARE}" "$MP"
rc=$?
unset ENC
if [ $rc -ne 0 ]; then
  echo "jellyfin-mount-nas: mount_smbfs failed (exit $rc)" >&2
  exit $rc
fi
exit 0
