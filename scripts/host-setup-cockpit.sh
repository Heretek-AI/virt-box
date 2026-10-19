#!/usr/bin/env bash
# Install Cockpit + cockpit-machines on the KVM host (apt/dnf/pacman) bound to
# 127.0.0.1:9090 and expose it tailnet-only via `tailscale serve`, so VM
# start/stop/reboot/console/snapshots work from any browser or phone.
set -euo pipefail

COCKPIT_PORT="${COCKPIT_PORT:-9090}"

if command -v apt-get >/dev/null 2>&1; then
  sudo apt-get update
  sudo apt-get install -y cockpit cockpit-machines
elif command -v dnf >/dev/null 2>&1; then
  sudo dnf install -y cockpit cockpit-machines
elif command -v pacman >/dev/null 2>&1; then
  sudo pacman -Sy --noconfirm cockpit cockpit-machines
else
  echo "unsupported distro: install cockpit + cockpit-machines manually" >&2
  exit 1
fi

sudo systemctl enable --now cockpit.socket libvirtd
# Bind Cockpit to loopback only; remote access goes through Tailscale Serve.
sudo mkdir -p /etc/systemd/system/cockpit.socket.d
sudo tee /etc/systemd/system/cockpit.socket.d/listen.conf >/dev/null <<EOF
[Socket]
ListenStream=
ListenStream=127.0.0.1:${COCKPIT_PORT}
EOF
sudo systemctl daemon-reload
sudo systemctl restart cockpit.socket

if ! command -v tailscale >/dev/null 2>&1; then
  echo "tailscale CLI not found — install tailscale and run 'tailscale up' first" >&2
  exit 1
fi

tailscale serve --bg --https="${COCKPIT_PORT}" "https+insecure://127.0.0.1:${COCKPIT_PORT}"
echo "==> Cockpit available tailnet-only at https://$(hostname).<tailnet>.ts.net:${COCKPIT_PORT}"
tailscale serve status || true
