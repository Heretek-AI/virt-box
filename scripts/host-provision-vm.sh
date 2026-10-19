#!/usr/bin/env bash
# Provision the virt-box KVM guest on any Linux libvirt/QEMU/KVM host.
# 1. Builds (or reuses) the UEFI qcow2 via `nixos-rebuild build-image`.
# 2. Resizes the OS disk, creates the dedicated backup disk (serial virt-box-backup).
# 3. Defines the guest with virt-install (q35, UEFI, TPM 2.0, virtio, guest agent).
set -euo pipefail

# Load .env when present (same keys as .env.example).
if [ -f .env ]; then set -a; . ./.env; set +a; fi

VM_NAME="${VM_NAME:-virt-box}"
VM_RAM_MB="${VM_RAM_MB:-16384}"
VM_VCPUS="${VM_VCPUS:-8}"
VM_OS_DISK_SIZE="${VM_OS_DISK_SIZE:-100G}"
VM_OS_DISK_DIR="${VM_OS_DISK_DIR:-/var/lib/libvirt/images}"
VM_BACKUP_DISK_SIZE="${VM_BACKUP_DISK_SIZE:-100G}"
VM_BACKUP_DISK_DIR="${VM_BACKUP_DISK_DIR:-/var/lib/libvirt/images}"
VM_LIBVIRT_NETWORK="${VM_LIBVIRT_NETWORK:-default}"
FLAKE_ATTR="${FLAKE_ATTR:-virt-box}"

OS_QCOW2="${VM_OS_DISK_DIR}/${VM_NAME}-os.qcow2"
BACKUP_QCOW2="${VM_BACKUP_DISK_DIR}/${VM_NAME}-backup.qcow2"

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing required command: $1" >&2; exit 1; }; }
need virsh; need virt-install; need qemu-img

if virsh dominfo "$VM_NAME" >/dev/null 2>&1; then
  echo "domain $VM_NAME already exists — refusing to recreate (virsh undefine $VM_NAME to start over)"
  exit 1
fi

# 1. Build the image if result/ is missing or stale.
if [ ! -d result ] || [ -z "$(ls result/*.qcow2 2>/dev/null || true)" ]; then
  echo "==> building UEFI qcow2 image (nixos-rebuild build-image --image-variant qcow-efi --flake .#${FLAKE_ATTR})"
  need nixos-rebuild
  nixos-rebuild build-image --image-variant qcow-efi --flake ".#${FLAKE_ATTR}"
fi
BUILT_QCOW2="$(ls -t result/*.qcow2 | head -n1)"
echo "==> source image: $BUILT_QCOW2"

# 2. Install + resize OS disk.
echo "==> installing OS disk at $OS_QCOW2 ($VM_OS_DISK_SIZE)"
sudo install -o qemu -g qemu -m 0600 -D "$BUILT_QCOW2" "$OS_QCOW2"
sudo qemu-img resize "$OS_QCOW2" "$VM_OS_DISK_SIZE"
[ -n "${SELINUX:-}" ] && sudo restorecon -v "$OS_QCOW2" || sudo restorecon -v "$OS_QCOW2" || true

# 3. Create the dedicated backup disk (qcow2, serial virt-box-backup so the
#    guest finds it at /dev/disk/by-id/virtio-virt-box-backup).
if [ ! -f "$BACKUP_QCOW2" ]; then
  echo "==> creating backup disk at $BACKUP_QCOW2 ($VM_BACKUP_DISK_SIZE)"
  sudo qemu-img create -f qcow2 "$BACKUP_QCOW2" "$VM_BACKUP_DISK_SIZE"
  sudo chown qemu:qemu "$BACKUP_QCOW2"
  sudo restorecon -v "$BACKUP_QCOW2" || true
else
  echo "==> reusing existing backup disk $BACKUP_QCOW2"
fi
mkdir -p "${VM_BACKUP_DISK_DIR}" 2>/dev/null || sudo mkdir -p "${VM_BACKUP_DISK_DIR}"

# 4. Define the guest.
echo "==> defining libvirt domain $VM_NAME (${VM_RAM_MB}MB RAM, ${VM_VCPUS} vCPUs)"
sudo virt-install \
  --name "$VM_NAME" \
  --os-variant nixos-unstable \
  --memory "$VM_RAM_MB" \
  --vcpus "$VM_VCPUS",topology.sockets=1,cores=4,threads=2 \
  --cpu host-passthrough \
  --machine q35 \
  --boot uefi,loader_secure=yes \
  --features smm.state=on,acpi=on,apic=on \
  --tpm backend.type=emulator,backend.version=2.0,model=tpm-tis \
  --disk "path=${OS_QCOW2},format=qcow2,bus=virtio,cache=writeback,discard=unmap,serial=virt-box-os" \
  --disk "path=${BACKUP_QCOW2},format=qcow2,bus=virtio,cache=writeback,discard=unmap,serial=virt-box-backup" \
  --controller virtio-scsi \
  --network "network=${VM_LIBVIRT_NETWORK},model=virtio" \
  --channel unix,target.type=virtio,name=org.qemu.guest_agent.0 \
  --graphics spice,gl.enable=yes \
  --video virtio,accel.accel3d=yes \
  --sound none \
  --rng /dev/urandom,model=virtio \
  --memballoon virtio \
  --import \
  --noautoconsole

echo "==> $VM_NAME defined. Useful next steps:"
echo "    virsh list --all"
echo "    virsh domifaddr $VM_NAME"
echo "    just deploy"
