# virt-box NixOS guest configuration.
#
# Build a bootable UEFI qcow2 with:
#   nixos-rebuild build-image --image-variant qcow-efi --flake .#virt-box
#   nix build .#nixosConfigurations.virt-box.config.system.build.images.qcow-efi
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    ./modules/dev-environment.nix
    ./modules/secrets.nix
    ./modules/agents.nix
    ./modules/webuis.nix
    ./modules/backups.nix
  ];

  nixpkgs.hostPlatform = "x86_64-linux";
  system.stateVersion = "25.11";

  networking.hostName = "virt-box";

  # --- Boot: UEFI systemd-boot for qcow-efi image + libvirt q35/OVMF ---
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.timeout = 5;

  boot.initrd.availableKernelModules = [
    "virtio_pci"
    "virtio_blk"
    "virtio_scsi"
    "virtio_net"
    "virtio_balloon"
    "qemu_fw_cfg"
  ];

  fileSystems."/".options = [ "discard" "noatime" ];

  # --- Kernel tuning for compilation-heavy agent workloads in a KVM guest ---
  boot.kernel.sysctl = {
    "vm.swappiness" = 10;
    "vm.dirty_ratio" = 40;
    "vm.dirty_background_ratio" = 10;
    "fs.inotify.max_user_watches" = 524288;
  };

  # --- Guest integration ---
  services.qemuGuest.enable = true;
  services.spice-vdagentd.enable = true;
  services.fstrim.enable = true;
  services.irqbalance.enable = true;

  # Serial console for `virsh console virt-box` / Cockpit terminal access.
  boot.kernelParams = [ "console=ttyS0,115200n8" "console=tty1" ];
  systemd.services."serial-getty@ttyS0".enable = true;

  # QEMU guest agent channel is declared on the host XML (see
  # scripts/host-provision-vm.sh); the in-guest service above is all the
  # guest side needs.

  # --- Networking / SSH / Tailscale ---
  networking.firewall.enable = true;
  # All WebUIs bind to 127.0.0.1 and are exposed via Tailscale Serve only.
  # No public ports are opened here.

  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  services.tailscale = {
    enable = true;
    useRoutingFeatures = "client";
    openFirewall = true;
  };

  programs.mosh.enable = true;

  # --- Nix ---
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.trusted-users = [ "root" "@wheel" "agent" ];
  nix.settings.max-jobs = "auto";
  nix.settings.cores = 0;
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };
  nix.optimise.automatic = true;
  nixpkgs.config.allowUnfree = true;

  # --- The single interactive tenant. Agents run as this user. ---
  users.users.agent = {
    isNormalUser = true;
    description = "virt-box agent user (Pi + OpenCode)";
    extraGroups = [ "wheel" "podman" ];
    linger = true;
    subUidRanges = [{ startUid = 100000; count = 65536; }];
    subGidRanges = [{ startGid = 100000; count = 65536; }];
    openssh.authorizedKeys.keys = [
      # NOTE: replaced at deploy time via `just deploy` / sops template or
      # by adding your key here before building the image.
      # "ssh-ed25519 AAAA... you@host"
    ];
  };

  # Passwordless sudo *inside the isolated VM* so devops agents have full
  # system control without host escape (the VM itself is the boundary).
  security.sudo.wheelNeedsPassword = false;

  # --- Base packages always present (full toolchains live in dev-environment.nix) ---
  environment.systemPackages = with pkgs; [
    vim
    htop
    curl
    wget
    tailscale
  ];
}
