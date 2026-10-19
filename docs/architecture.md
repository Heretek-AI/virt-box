# virt-box — Zero-Custom-Code Declarative NixOS KVM for AI Coding Agents

Date: 2026-10-19. Host: Fedora + libvirt/QEMU/KVM. Guest: beefy NixOS for `pi` + `opencode` with full system access.
Repos: Pi is `earendil-works/pi` (npm `@earendil-works/pi-coding-agent` v1.3.0), OpenCode is `anomalyco/opencode` (v2.0.32 upstream, nixpkgs `1.19.0` lags). `nixos-generators` is archived Jan 2026 — use `nixos-rebuild build-image`.

## 1. Verdict

- **Bootstrap:** `nixos-rebuild build-image --image-variant qcow-efi --flake .#vbox` → `virt-install --import`. Least code, UEFI qcow2, works from Fedora with only Nix installed.
- **Updates:** `nixos-rebuild switch --flake .#vbox --target-host root@$VM_IP`. Golden-image rebuild only for fresh images.
- **Guest base:** `programs.nix-ld` + `services.envfs` + `programs.direnv` + rootless podman + tailscale + openssh + qemuGuest/fstrim.
- **Agents:** `pkgs.opencode` + upstream `github:earendil-works/pi/stable` overlay; `programs.opencode` HM module for base + custom module generating N `pi-*` / `opencode-*` profiles via `toJSON`; secrets via sops-nix/agenix + `EnvironmentFile`, never literal in store; isolate untrusted runs with separate UIDs or containers.

## 2. Workflow 1 — Bootstrap / build / update from Fedora

### 2.1 Comparison

| Approach | Verdict |
|---|---|
| A. `nixos-rebuild build-image --image-variant qcow-efi` (nixpkgs ≥25.05) | **Use.** Successor to nixos-generators. `nixosConfigurations.vm` + `image.modules` only. |
| B. `nixos-generate -f qcow/qcow-efi` | Deprecated, archived read-only. Migrate to A. |
| C. disko + nixos-anywhere `--target-host` | Use only to test partitioning / replicate cloud kexec flow. Destroys target disk, needs kexec + ≥1GB RAM. |
| D. virt-install ISO + manual `nixos-install` | Fallback/debug. Bootstrap imperative, then declarative. |
| E. `nixos-rebuild build-vm` | Test harness only (`result/bin/run-*-vm`), shares host store. Not a libvirt guest. |

Sources: nixos-generators deprecation (https://github.com/nix-community/nixos-generators), NixOS manual build-image (https://nixos.org/manual/nixos/stable/#sec-image-nixos-rebuild-build-image), migration thread (https://discourse.nixos.org/t/migrating-from-nixos-generators-module-to-nixos-rebuild-build-image/75465), nixos-anywhere quickstart (https://raw.githubusercontent.com/nix-community/nixos-anywhere/main/docs/quickstart.md), disko (https://github.com/nix-community/disko), disko-images (https://raw.githubusercontent.com/nix-community/disko/master/docs/disko-images.md), examples (https://raw.githubusercontent.com/nix-community/nixos-anywhere-examples/main/flake.nix, https://raw.githubusercontent.com/nix-community/nixos-anywhere-examples/main/disk-config.nix, https://raw.githubusercontent.com/nix-community/nixos-anywhere-examples/main/configuration.nix), build-vm (https://wiki.nixos.org/wiki/Nixos-rebuild), remote deploy (https://www.mankier.com/8/nixos-rebuild, https://nixcademy.com/posts/nixos-rebuild-remote-deployment).

### 2.2 Fedora host prereqs

```bash
sudo dnf install -y nix qemu-kvm libvirt virt-install virt-manager edk2-ovmf swtpm swtpm-tools
sudo systemctl enable --now libvirtd
sudo usermod -aG libvirt,qemu,kvm $USER  # re-login
# /etc/nix/nix.conf:
# experimental-features = nix-command flakes
# trusted-users = root @wheel john
```

Fedora Nix/SELinux (https://discussion.fedoraproject.org/t/how-to-install-nix-cleanly/75493, https://saud.wtf/blog/fedora-nix, https://github.com/DeterminateSystems/nix-installer), nix.conf trusted-users (https://nixos.org/manual/nix/stable/command-ref/conf-file#conf-trusted-users). Keep qcow2 in `/var/lib/libvirt/images`, `chown qemu:qemu`, `restorecon`.

### 2.3 Minimal flake

```nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  outputs = { nixpkgs, ... }: {
    nixosConfigurations.vmbox = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [ ./configuration.nix ];
    };
  };
}
```

```nix
# configuration.nix
{ modulesPath, ... }: {
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  services.openssh.enable = true;
  services.spice-vdagentd.enable = true;
  services.qemuGuest.enable = true;
  users.users.root.openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAA… you@fedora" ];
  system.stateVersion = "25.11";
}
```

Build: `nixos-rebuild build-image --image-variant qcow-efi --flake .#vbox`
or `nix build .#nixosConfigurations.vmbox.config.system.build.images.qcow-efi`.

### 2.4 virt-install (UEFI, TPM, virtio, beefy)

```bash
sudo cp result/*.qcow2 /var/lib/libvirt/images/vmbox.qcow2
sudo chown qemu:qemu /var/lib/libvirt/images/vmbox.qcow2
sudo restorecon -v /var/lib/libvirt/images/vmbox.qcow2
virt-install \
  --name vmbox --os-variant nixos-unstable \
  --memory 16384 --vcpus 8,topology.sockets=1,cores=4,threads=2 \
  --cpu host-passthrough --machine q35 \
  --boot uefi,loader_secure=yes --features smm.state=on,acpi=on,apic=on \
  --tpm backend.type=emulator,backend.version=2.0,model=tpm-tis \
  --disk path=/var/lib/libvirt/images/vmbox.qcow2,format=qcow2,bus=virtio,cache=writeback,discard=unmap \
  --controller virtio-scsi --network network=default,model=virtio \
  --graphics spice,gl.enable=yes --video virtio,accel.accel3d=yes \
  --sound none --rng /dev/urandom,model=virtio --memballoon virtio \
  --import --noautoconsole
```

Schema/practice: libvirt domain XML (https://libvirt.org/formatdomain.html), UEFI (https://andreaskaris.github.io/blog/linux/libvirt-uefi-without-secureboot), TPM (https://computingforgeeks.com/enable-tpm-on-kvm-and-install-windows). Headless: `--graphics none --video none`.

### 2.5 Update loop

```bash
VM_IP=$(virsh domifaddr vmbox | awk '/ipv4/ {print $4}' | cut -d/ -f1 | head -n1)
nixos-rebuild switch --flake .#vbox --target-host "root@$VM_IP"
# offload build: --build-host root@$VM_IP
```

`--target-host` activates remotely over SSH as root; `--build-host` builds remotely. nixos-anywhere is install-only, hands off to `nixos-rebuild`/deploy-rs/colmena.

### 2.6 Pitfalls

- New work on nixos-generators → use `build-image`.
- disko device for virtio is `/dev/vda` (cloud examples use `/dev/sda`).
- UEFI secure boot needs `smm=on` + q35; TPM needs swtpm + `tpm-tis 2.0`.
- Non-root Fedora user must be in `trusted-users` or daemon/remote builds fail.
- nixos-anywhere kexec needs ≥1GB RAM, wired SSH.

## 3. Workflow 2 — Essential guest modules for agents

### 3.1 Base

```nix
{ pkgs, ... }: {
  programs.nix-ld.enable = true;
  services.envfs.enable = true;
  programs.nix-index.enable = true;
  programs.direnv = { enable = true; nix-direnv.enable = true; };
  programs.mosh.enable = true;
  services.qemuGuest.enable = true;
  services.spice-vdagentd.enable = true;
  services.fstrim.enable = true;
  services.irqbalance.enable = true;
  services.tailscale = { enable = true; useRoutingFeatures = "client"; openFirewall = true; };
  services.openssh = { enable = true; openFirewall = true;
    settings = { PermitRootLogin = "no"; PasswordAuthentication = false;
      KbdInteractiveAuthentication = false; }; };
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.trusted-users = [ "root" "@wheel" "agent" ];
  nix.gc = { automatic = true; dates = "weekly"; options = "--delete-older-than 30d"; };
  nix.optimise.automatic = true;
  environment.systemPackages = with pkgs; [
    git gh gnumake gcc clang pkg-config cmake
    nodejs corepack python3 uv cargo rustc go
    devenv direnv nix-index htop ripgrep fd jq
  ];
}
```

Sources: nix-ld (https://github.com/nix-community/nix-ld, https://raw.githubusercontent.com/NixOS/nixpkgs/nixos-25.05/nixos/modules/programs/nix-ld.nix), envfs (https://github.com/Mic92/envfs), direnv (https://raw.githubusercontent.com/NixOS/nixpkgs/nixos-25.05/nixos/modules/programs/direnv.nix, https://wiki.nixos.org/wiki/Direnv, https://github.com/nix-community/nix-direnv), nix-index (https://raw.githubusercontent.com/NixOS/nixpkgs/nixos-25.05/nixos/modules/programs/nix-index.nix), podman/docker (https://wiki.nixos.org/wiki/Podman, https://wiki.nixos.org/wiki/Docker), tailscale (https://raw.githubusercontent.com/NixOS/nixpkgs/nixos-25.05/nixos/modules/services/networking/tailscale.nix, https://wiki.nixos.org/wiki/Tailscale), sshd (https://raw.githubusercontent.com/NixOS/nixpkgs/nixos-25.05/nixos/modules/services/networking/ssh/sshd.nix), mosh (https://raw.githubusercontent.com/NixOS/nixpkgs/nixos-25.05/nixos/modules/programs/mosh.nix), qemu-guest (https://raw.githubusercontent.com/NixOS/nixpkgs/nixos-25.05/nixos/modules/virtualisation/qemu-guest-agent.nix), spice (https://raw.githubusercontent.com/NixOS/nixpkgs/nixos-25.05/nixos/modules/services/misc/spice-vdagentd.nix), nix config (https://raw.githubusercontent.com/NixOS/nixpkgs/nixos-25.05/nixos/modules/config/nix.nix, https://wiki.nixos.org/wiki/Flakes), sudo (https://raw.githubusercontent.com/NixOS/nixpkgs/nixos-25.05/nixos/modules/security/sudo.nix), devenv (https://devenv.sh/getting-started/), lib-list practice (https://l-lin.github.io/nix/running-an-external-binary-on-NixOS).

### 3.2 nix-ld libs — extend defaults

Default is systemd+nix closure only. For agents add:

```nix
programs.nix-ld.libraries = with pkgs; [
  stdenv.cc.cc.cc.lib zlib zstd curl openssl attr libssh bzip2 libxml2 acl libsodium util-linux xz systemd
  glib nss nspr dbus atk at-spi2-atk cups libdrm expat libxkbcommon
  xorg.libX11 xorg.libXcomposite xorg.libXdamage xorg.libXext xorg.libXfixes xorg.libXrandr
  mesa alsa-lib pango cairo icu libunwind libcap libusb1 udev fontconfig freetype libkrb5
];
```

Never set global `LD_LIBRARY_PATH` (breaks RPATH-patched nix binaries). Python from nixpkgs ignores `NIX_LD_LIBRARY_PATH` — wrap with `LD_LIBRARY_PATH=$NIX_LD_LIBRARY_PATH` only for that process.

### 3.3 envfs vs nix-ld

Use both. nix-ld = missing `.so`/interpreter; envfs = `/bin/bash`, `/usr/bin/env` shebangs (FUSE from `$PATH`). `buildFHSUserEnv` fights direnv/bwrap — avoid system-wide.

### 3.4 Containers — prefer rootless podman

```nix
{
  virtualisation.podman = { enable = true; dockerCompat = true;
    defaultNetwork.settings.dns_enabled = true; };
  users.users.agent = { isNormalUser = true;
    extraGroups = [ "podman" "wheel" ];
    subUidRanges = [{ startUid = 100000; count = 65536; }];
    subGidRanges = [{ startGid = 100000; count = 65536; }];
    linger = true; };
}
```

Docker rootful `docker` group == root; rootless docker needs `virtualisation.docker.rootless`. Never enable `dockerCompat` + docker together. `virtualisation.oci-containers.backend` for declarative containers.

### 3.5 Guest perf

```nix
{
  fileSystems."/".options = [ "discard" "noatime" ];
  boot.initrd.availableKernelModules = [ "virtio_pci" "virtio_blk" "virtio_scsi" "virtio_net" "virtio_balloon" "qemu_fw_cfg" ];
  nix.settings.max-jobs = "auto"; nix.settings.cores = 0;
  boot.kernel.sysctl = { "vm.swappiness" = 10; "vm.dirty_ratio" = 40; };
}
```

qemuGuest needs host `org.qemu.guest_agent.0` channel. fstrim mandatory on thin qcow2/NVMe. NVMe/CPU pinning/hugepages are host XML, not guest options.

### 3.6 Security tradeoff

Agents with `wheel` NOPASSWD + podman/docker == root. Accept only single-tenant + Tailscale-only SSH + `PasswordAuthentication=false` + firewall deny + separate `agent` user (never root) + weekly GC/prune.

## 4. Workflow 3 — Declarative Pi + OpenCode, N profiles

### 4.1 Packaging

- Pi: repo `earendil-works/pi` (https://github.com/earendil-works/pi/blob/main/README.md, https://github.com/earendil-works/pi/blob/main/flake.nix, https://github.com/earendil-works/pi/blob/main/nix/package.nix, npm https://www.npmjs.com/package/@earendil-works/pi-coding-agent). Old `pi-coding-agent` URL and `@mariozechner/*` 404/renamed. No `pkgs.pi` / `programs.pi` — use overlay `github:earendil-works/pi/stable` + custom module. Requires Node ≥22.19. `PI_PACKAGE_DIR` exists for store paths.
- OpenCode: upstream `anomalyco/opencode` (https://github.com/anomalyco/opencode, docs https://opencode.ai/docs/config/, https://opencode.ai/docs/mcp-servers/, https://opencode.ai/docs/agents/). `sst/opencode` stale. nixpkgs `pkgs.opencode` builds from source, pins `1.19.0` vs upstream `2.0.32`, forces `OPENCODE_DISABLE_AUTOUPDATE=true`. `dan-online/opencode-nix` archived — avoid. HM `programs.opencode` (https://github.com/nix-community/home-manager/blob/master/modules/programs/opencode.nix) + `programs.mcp` (https://raw.githubusercontent.com/nix-community/home-manager/master/modules/programs/mcp.nix) exist.

Docs: Pi configuration (https://raw.githubusercontent.com/earendil-works/pi/main/packages/coding-agent/docs/configuration.md), env (https://raw.githubusercontent.com/earendil-works/pi/main/packages/coding-agent/docs/environment-variables.md), settings/mcp/models/providers/skills/prompts/extensions/cli (…/docs/settings.md, …/docs/mcp.md, …/docs/models.md, …/docs/providers.md, …/docs/skills.md, …/docs/prompt-templates.md, …/docs/extensions.md, …/docs/cli.md), containerization (https://raw.githubusercontent.com/earendil-works/pi/main/packages/coding-agent/docs/containerization.md). Secrets: sops-nix (https://github.com/Mic92/sops-nix), agenix (https://github.com/ryantm/agenix).

### 4.2 Config paths

OpenCode (JSON/JSONC, `$schema: https://opencode.ai/config.json`): `~/.config/opencode/opencode.json`, `tui.json`, `./opencode.json` project override, `agents/ commands/ skills/ tools/ plugins/` + `AGENTS.md`. Env `OPENCODE_CONFIG{,_DIR,_CONTENT,_TUI}`, `OPENCODE_DB`, `OPENCODE_DISABLE_AUTOUPDATE`. Substitution `{env:VAR}`, `{file:path}`.

Pi (`PI_CODING_AGENT_DIR`, default `~/.pi/agent`): `settings.json` (`$schema: https://pi.dev/schemas/settings.schema.json`), `mcp.json` (`{mcpServers:{}}` Claude-style), `models.json`, `auth.json` (`"key": "!cmd"`), `AGENTS.md/SYSTEM.md/extensions/ skills/ prompts/`. Project `.pi/` after trust. Substitution `${VAR}`, `!cmd`.

```jsonc
// opencode.json
{ "$schema": "https://opencode.ai/config.json", "model": "anthropic/claude-sonnet-4-5",
  "autoupdate": false, "permission": { "edit": "ask", "bash": "ask" },
  "mcp": { "context7": { "type": "remote", "url": "https://mcp.context7.com/mcp",
    "headers": { "CONTEXT7_API_KEY": "{env:CONTEXT7_API_KEY}" } } } }
```

```json
// <agent-dir>/settings.json + mcp.json
{ "$schema": "https://pi.dev/schemas/settings.schema.json",
  "defaultTools": ["+codemode"], "extensions": ["./extensions/review.ts"], "skills": ["./skills/pdf-tools"] }
{ "mcpServers": { "docs": { "url": "https://example.com/mcp",
  "headers": { "Authorization": "Bearer ${DOCS_TOKEN}" } } } }
```

Pi stdio `{command, args[], env{}}` vs OpenCode `{type:"local", command:[...], environment:{}}` — do not mix.

### 4.3 N-profile Home Manager module

```nix
{ config, lib, pkgs, ... }:
let profiles = {
  dev = { opencode.model = "anthropic/claude-sonnet-4-5";
    pi.defaultTools = [ "+codING" "+grep" ]; };
  review = { opencode.tools = { write = false; }; pi.defaultTools = [ "-write" "+grep" ]; };
  docs = { pi.defaultTools = [ "-bash" "+codemode" ]; };
};
in {
  programs.opencode = { enable = true; package = pkgs.opencode;
    mutableSettings = true; settings = { model = profiles.dev.opencode.model; autoupdate = false; }; };
  xdg.configFile = lib.mapAttrs' (n: _: lib.nameValuePair "pi-profiles/${n}/settings.json"
    { source = pkgs.writeText "pi-${n}.json" (builtins.toJSON { defaultTools = profiles.${n}.pi.defaultTools; }); }) profiles;
  home.packages = lib.mapAttrsToList (n: _: pkgs.writeShellScriptBin "pi-${n}" ''
    export PI_CODING_AGENT_DIR="''${PI_CODING_AGENT_DIR:-${config.xdg.configHome}/pi-profiles/${n}}"
    exec ${lib.getExe pkgs.pi} "$@"
  '') profiles;
}
```

Use `programs.mcp.servers.<n>.env.<VAR>.file` → renders `{file:…}` with `enableMcpIntegration`. Validate via `programs.opencode.validateFiles = true` (`passthru.jsonschema`).

### 4.4 Isolation

| Method | When |
|---|---|
| Wrapper `pi-dev` / `OPENCODE_CONFIG` overlay | cheapest, same UID, no boundary |
| systemd user service + `EnvironmentFile=/run/secrets/…` (`programs.opencode.web.environmentFile`) | secret-safe daemon, not interactive |
| Separate Linux users + per-user `PI_CODING_AGENT_DIR`, sops `owner` | real UID boundary, per-agent auth/sessions |
| Containers (Pi Docker/sbx/OpenShell/Gondolin) | strongest, keys stay on host; never mount `~/.pi/agent` inside |

### 4.5 Secrets + updates

- sops-nix → `/run/secrets/*` + `sops.templates`, order `After=[sops-nix.service]`; agenix `age.secrets.*.path`. OpenCode `{file:/run/secrets/k}` or `EnvironmentFile`; Pi `"!cat /run/secrets/x"`, `models.json apiKey: "$VAR"`. Never literal keys in `toJSON` (store is world-readable).
- Pi `pi update` refuses under Nix — update via flake (`stable` + `nix flake update` / pin tag). OpenCode nixpkgs forces `OPENCODE_DISABLE_AUTOUPDATE=true` — update via channel bump, `mutableSettings=true` to avoid HM collision.

## 5. Pitfalls checklist

1. nixos-generators archived; wrong Pi/OpenCode repo names 404/redirect.
2. nixpkgs opencode lags upstream major version.
3. Need both nix-ld + envfs; global LD_LIBRARY_PATH poisons nix.
4. `dockerCompat` + docker conflict; rootless needs subUID/GID + linger.
5. Secrets in `builtins.toJSON` leak to store; MCP env dialects incompatible.
6. `/dev/vda` not `/dev/sda` for virtio disko; qemu-ga needs host channel; fstrim on thin images.
7. Flakes only see `git add`-ed files.

## 6. Next: virt-box skeleton

`flake.nix` (vbox qcow-efi) + `configuration.nix` (§2.3 + §3.1) + `modules/agents.nix` (§4.3) + `disk-config.nix` (`/dev/vda`, `imageSize="20G"`) + sops stub. Build → import → `switch --target-host` loop.
