# virt-box host task runner. Loads .env when present.
set dotenv-load

default:
    @just --list

# Evaluate the flake without building (fast syntax/type check).
check:
    nix flake check --no-build
    nix eval .#nixosConfigurations.virt-box.config.system.build.toplevel.drvPath

# Validate shell scripts, seeded profile JSON, and OpenRig RigSpec YAML.
validate:
    bash -n scripts/host-provision-vm.sh
    bash -n scripts/host-setup-cockpit.sh
    jq empty profiles/pi/*/*.json profiles/opencode/*.json
    if command -v rig >/dev/null 2>&1; then rig spec validate profiles/openrig/pi-squad.yaml; elif [ -x "$HOME/.npm-global/bin/rig" ]; then "$HOME/.npm-global/bin/rig" spec validate profiles/openrig/pi-squad.yaml; fi
    @echo "validation OK"

# Build the UEFI qcow2 image (result/*.qcow2).
build-image:
    #!/usr/bin/env bash
    set -euo pipefail
    attr="${FLAKE_ATTR:-virt-box}"
    nixos-rebuild build-image --image-variant qcow-efi --flake ".#${attr}"

# Provision the KVM guest (builds image if needed, creates disks, virt-install).
create-vm:
    #!/usr/bin/env bash
    set -euo pipefail
    ./scripts/host-provision-vm.sh

# Rebuild + activate on the running VM over SSH (fast update loop).
deploy ip="":
    #!/usr/bin/env bash
    set -euo pipefail
    attr="${FLAKE_ATTR:-virt-box}"
    vm_ip="{{ip}}"
    if [ -z "$vm_ip" ]; then
      vm_ip=$(virsh domifaddr "${VM_NAME:-virt-box}" 2>/dev/null | awk '/ipv4/ {print $4}' | cut -d/ -f1 | head -n1 || true)
    fi
    if [ -z "$vm_ip" ]; then echo "usage: just deploy <vm-ip> (could not auto-detect)"; exit 1; fi
    echo "deploying .#${attr} to root@${vm_ip} ..."
    nixos-rebuild switch --flake ".#${attr}" --target-host "root@${vm_ip}"

# Install Cockpit + cockpit-machines on the host and expose via Tailscale Serve.
setup-host-cockpit:
    ./scripts/host-setup-cockpit.sh

# Take a libvirt snapshot of the VM.
snapshot name="manual":
    #!/usr/bin/env bash
    set -euo pipefail
    virsh snapshot-create-as "${VM_NAME:-virt-box}" "{{name}}" --description "virt-box {{name}} $(date -u +%FT%TZ)" --atomic

# Trigger an immediate Restic backup inside the guest.
backup-now ip="":
    #!/usr/bin/env bash
    set -euo pipefail
    vm_ip="{{ip}}"
    if [ -z "$vm_ip" ]; then
      vm_ip=$(virsh domifaddr "${VM_NAME:-virt-box}" 2>/dev/null | awk '/ipv4/ {print $4}' | cut -d/ -f1 | head -n1 || true)
    fi
    if [ -z "$vm_ip" ]; then echo "usage: just backup-now <vm-ip>"; exit 1; fi
    ssh "root@${vm_ip}" "systemctl start restic-backups-virtbox-local.service && restic-virtbox-local snapshots"

# Print the Tailscale URLs + mobile pairing hints.
pair-mobile:
    #!/usr/bin/env bash
    set -euo pipefail
    name=$(tailscale status --json 2>/dev/null | jq -r '.Self.DNSName // empty' || true)
    echo "Guest Tailscale URLs (replace <tailnet> with your tailnet):"
    echo "  Paseo (WebUI + sh.paseo app):  https://virt-box.<tailnet>.ts.net/"
    echo "  pi-web-ui:                     https://virt-box.<tailnet>.ts.net:8443"
    echo "  pi-web:                        https://virt-box.<tailnet>.ts.net:8504"
    echo "  OpenChamber:                   https://virt-box.<tailnet>.ts.net:3000"
    echo "  OpenCode (app.getopencode):    https://virt-box.<tailnet>.ts.net:4096"
    echo "  OpenRig TUI (ttyd + tmux):     https://virt-box.<tailnet>.ts.net:7681"
    echo "  OpenRig daemon UI:             https://virt-box.<tailnet>.ts.net:7433"
    echo "Pair OpenCode Mobile with: opencode pair --url https://virt-box.<tailnet>.ts.net:4096"
    echo "Boot the Pi squad with: rig up ~/.openrig/specs/pi-squad.yaml --cwd ."
