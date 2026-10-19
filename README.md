# virt-box — Declarative NixOS KVM Appliance for Pi, OpenCode & OpenRig Agents

Zero-custom-software, declarative NixOS KVM virtual machine for any Linux
`libvirt`/`QEMU`/`KVM` host. Inside the VM, **Pi
(`@earendil-works/pi-coding-agent`)** (primary), **OpenRig (`@openrig/cli`)**
(multi-agent team topologies with first-class `runtime: pi`), and **OpenCode
(`anomalyco/opencode`)** (secondary) agents have full system development
access (compilers, Nix flakes, `nix-ld`, `envfs`, rootless Podman, headless
Chromium/Playwright) while remaining isolated from the host filesystem.

Four WebUIs + OpenRig TUI/daemon + native Android apps are exposed securely
over **Tailscale Serve** (no public ports):

| URL (guest tailnet name) | Backend | App |
|---|---|---|
| `https://virt-box.<tailnet>.ts.net/` (`:443`) | Paseo daemon `:6767` | Paseo WebUI + Paseo Android (`sh.paseo`) |
| `https://virt-box.<tailnet>.ts.net:8443` | pi-web-ui `:8787` | `xing-shuyin/pi-web-ui` browser cockpit |
| `https://virt-box.<tailnet>.ts.net:8504` | pi-web `:8504` | `@jmfederico/pi-web` persistent sessions |
| `https://virt-box.<tailnet>.ts.net:3000` | OpenChamber `:3000` | OpenChamber web |
| `https://virt-box.<tailnet>.ts.net:4096` | opencode `:4096` | `opencode attach` + OpenCode Mobile (`app.getopencode`) |
| `https://virt-box.<tailnet>.ts.net:7681` | ttyd+tmux `:7681` | OpenRig TUI (`openrig-tui`, touch/mouse, add to Home Screen as PWA) |
| `https://virt-box.<tailnet>.ts.net:7433` | OpenRig daemon `:7433` | OpenRig daemon + bundled web UI |

Why separate ports instead of subpaths? WebSocket-heavy SPAs
(`paseo`, `pi-web-ui`, `pi-web`, `openchamber`) emit root-relative `/ws` and
`/api` requests that break under a subpath reverse proxy. Tailscale Serve
multi-port HTTPS avoids this entirely.

> **Port / data-dir isolation:** `xing-shuyin/pi-web-ui` and
> `@jmfederico/pi-web` both default to `PI_WEB_DATA_DIR=~/.pi-web`. This
> repo isolates them (`~/.local/share/pi-web-ui` on `:8787` vs
> `~/.local/share/pi-web-jm` on `:8504`).

> **Node 24 + hybrid NPM + Nix:** `@openchamber/web` v2.5+ requires
> `node >= 24.14.0`, and the Pi/Paseo/WebUI npm packages release daily. NixOS
> provides `nodejs_24` + `nix-ld` + compilers; a `virt-box-npm-bootstrap`
> service installs the exact npm packages into `/home/agent/.npm-global`
> without custom Nix derivations.

## Repo layout

```
flake.nix                    # nixpkgs-unstable + home-manager + sops-nix + disko
nixos/
  configuration.nix          # guest base: UEFI, qemu-guest, agent user, tailscale, SSH
  modules/
    dev-environment.nix      # nix-ld + envfs + direnv + podman + toolchains + playwright + ttyd/sqlite
    secrets.nix              # sops-nix -> /run/secrets + agent-secrets.env template
    agents.nix               # 4 Pi profiles + OpenCode config + tmux/openrig seeds + wrappers
    webuis.nix               # npm bootstrap + 8 systemd services + tailscale-serve
    backups.nix              # vdb mount + restic daily (incl. sqlite snapshot) + config auto-push timer
profiles/
  pi/{coder,researcher,auditor,devops}/{settings.json,mcp.json,SYSTEM.md}
  opencode/opencode.json      # base config with {env:VAR} indirection
  openrig/pi-squad.yaml       # Pi-native OpenRig team topology (runtime: pi seats)
scripts/
  host-provision-vm.sh        # build image + create disks + virt-install
  host-setup-cockpit.sh       # cockpit-machines over Tailscale Serve on the host
secrets/
  secrets.example.yaml        # copy to secrets.yaml, encrypt with sops
Justfile                      # build-image | create-vm | deploy | setup-host-cockpit | ...
```

## 1. Host prerequisites

Any Linux KVM host (Ubuntu/Debian/Fedora/Arch) with Nix installed:

```bash
# Fedora example:
sudo dnf install -y nix qemu-kvm libvirt virt-install virt-manager edk2-ovmf swtpm swtpm-tools
sudo systemctl enable --now libvirtd
sudo usermod -aG libvirt,qemu,kvm $USER   # re-login afterwards

# /etc/nix/nix.conf needs:
#   experimental-features = nix-command flakes
#   trusted-users = root @wheel <you>
```

Enter the host dev shell (provides `sops`, `age`, `ssh-to-age`,
`nixos-rebuild`, `just`):

```bash
nix develop
```

## 2. Secrets (`sops-nix`)

```bash
cp secrets/secrets.example.yaml secrets/secrets.yaml
# 1. Put your admin age public key + the VM host key (ssh-to-age) in .sops.yaml:
#      ssh-to-age -i /etc/ssh/ssh_host_ed25519_key.pub   # run on the VM/host key
# 2. Encrypt:
sops secrets/secrets.yaml   # fill in API keys, webui_password, restic_password, ...
```

Keys supported: `anthropic_api_key`, `openai_api_key`, `gemini_api_key`,
`openrouter_api_key`, `opencode_api_key`, `deepseek_api_key`,
`tavily_api_key`, `firecrawl_api_key`, `firecrawl_api_url`,
`searxng_base_url`, `context7_api_key`, `webui_password`,
`tailscale_auth_key`, `restic_password`, `github_ssh_private_key`.

Secrets decrypt to `/run/secrets/*` (0400, `agent:users`) and are rendered
into `/home/agent/.config/virt-box/secrets.env`, consumed as
`EnvironmentFile` by every agent service. OAuth token files
(`~/.pi/agent/auth.json`, `~/.local/share/opencode/auth.json`) stay writable
so `pi auth` / `opencode auth` refreshes work.

## 3. Build + provision

```bash
cp .env.example .env   # adjust sizes/paths; backup disk can live on a 2nd drive
just build-image       # nixos-rebuild build-image --image-variant qcow-efi --flake .#virt-box
just create-vm         # virt-install q35/UEFI/TPM2/virtio + vda OS + vdb backup disk
virsh list --all
just deploy            # nixos-rebuild switch --target-host root@$VM_IP (fast updates)
just setup-host-cockpit  # Cockpit :9090 over Tailscale Serve on the host
```

Defaults: 16 GB RAM, 8 vCPUs, 100 GB OS disk, 100 GB backup disk.

## 4. Connect clients over Tailscale

Inside the guest, `tailscale-serve-webuis.service` registers Serve listeners
automatically (zero-touch join via `tailscale_auth_key` when set). Then:

- **Browser:** open the URLs in the table above (Paseo `:443`, pi-web-ui
  `:8443`, pi-web `:8504`, OpenChamber `:3000`, OpenRig TUI `:7681`, OpenRig
  daemon `:7433`). The `:7681` page is a persistent `tmux`-backed terminal —
  closing the tab or locking your phone never interrupts the session, and it
  can be added to the Home Screen as a fullscreen PWA.
- **Paseo Android (`sh.paseo`):** Add host → Tailscale direct
  `https://virt-box.<tailnet>.ts.net` (or `100.x:6767` + Bearer password).
- **OpenCode Mobile (`app.getopencode`):**
  `opencode pair --url https://virt-box.<tailnet>.ts.net:4096`, scan in app.
- **Cockpit (host):** `https://<host>.<tailnet>.ts.net:9090` for start/stop,
  reboot, console, and qcow2 snapshots.
- **SSH fallback:** Termux + `tailscale` + `ssh agent@virt-box` + `tmux`.

Run `just pair-mobile` for a pairing cheat-sheet.

## 5. Pi profiles (`ppi` / `PI_CODING_AGENT_DIR`)

NixOS seeds four baselines, copied (writable) to `~/.pi/profiles/<name>/`:

| Wrapper | Focus | MCPs |
|---|---|---|
| `pi-coder` | Full dev | codebase-memory, context7, playwright, semgrep, openrig |
| `pi-researcher` | Web + codebase research | searxng, firecrawl, tavily, context7, codebase-memory |
| `pi-auditor` | Read-only red-proof QA | semgrep, codebase-memory |
| `pi-devops` | NixOS/Podman/systemd | codebase-memory, context7, semgrep, openrig |

```bash
pi-coder "implement feature X"
ppi use researcher -p "investigate Y"   # mutable runtime switching
pi config                               # live edits persist in ~/.pi/profiles/*
virt-box-sync-profiles                  # sync runtime edits back to /etc/nixos/profiles
```

Every profile is also registered in Paseo (`~/.paseo/config.json` providers
`pi-coder/...` + `daemon.agentProfiles`) for one-tap switching in the Paseo
WebUI and Android app.

OpenCode mirrors this with `opencode-coder/...` wrappers
(`OPENCODE_CONFIG` + `OPENCODE_CONFIG_DIR` overlays) and a shared base
`~/.config/opencode/opencode.json` using `{env:VAR}` secret indirection.

### OpenRig team topologies (`runtime: pi`) + MCP control plane

NixOS seeds `~/.openrig/specs/pi-squad.yaml` (builder + researcher + QA seats,
all `runtime: pi`) and a touch/mouse-enabled `~/.tmux.conf`. The persistent
`openrig` tmux session (window 0: `openrig-tui`, window 1: operator shell) is
served over `ttyd` on `:7681`; the OpenRig daemon + bundled UI listens on
`:7433`.

```bash
rig up ~/.openrig/specs/pi-squad.yaml --cwd .  # boot the Pi squad
rig ps && rig status                            # inspect seats
```

`pi-coder`, `pi-devops`, and OpenCode all ship the `openrig` MCP server (`rig
mcp serve`), so from Paseo (`:443` / `sh.paseo`), `pi-web-ui` (`:8443`), or
OpenChamber you can just ask: *"boot the `pi-squad` rig and assign task X to
`dev-build`"* — the agent drives `rig_up` / `rig_send` / `rig_ps` itself.

## 6. Backups

- **Data & workspaces (Restic, daily):** the secondary disk
  (`vdb`/`virt-box-backup`, ext4 label `VIRTBOX_BACKUP`) mounts at
  `/mnt/backup`. `services.restic.backups.virtbox-local` backs up `~/.pi`,
  `~/.openrig`, `~/.local/share/opencode`, `~/.paseo`, both pi-web data dirs,
  `~/workspaces`, and `/etc/nixos` (excluding caches/`node_modules`)
  encrypted with `restic_password`, retaining 7 daily / 4 weekly / 6 monthly.
  A `backupPrepareCommand` takes an atomic SQLite snapshot
  (`openrig.sqlite` → `openrig-backup.sqlite`) first, so running rigs and the
  daemon are never interrupted.
  ```bash
  restic-virtbox-local snapshots
  restic-virtbox-local restore latest --target /tmp/restore
  just backup-now
  ```
- **Configs (Git auto-push, hourly):** `virt-box-config-sync.timer` syncs
  `~/.pi/profiles/*/settings.json|mcp.json|SYSTEM.md` and
  `~/.openrig/specs/*.yaml` back to `/etc/nixos/profiles/` and pushes to
  `origin/main` with the deploy key.
- **Full-VM snapshots:** Cockpit → VM → Snapshots, or
  `just snapshot my-checkpoint`.

## 7. Verification

```bash
just validate        # bash -n scripts/*.sh + jq empty profiles/**/*.json
just check           # nix flake check --no-build + eval toplevel drvPath
```

Manual: `virsh list` shows `virt-box` running → `tailscale status` shows it
joined → open all seven Serve URLs (`:443`, `:8443`, `:8504`, `:3000`,
`:7681`, `:7433`, `:4096`) → switch `pi-coder`…`pi-devops` in Paseo →
`restic-virtbox-local snapshots` shows backups on `/mnt/backup` → from Paseo
or `pi-web-ui`, ask `pi-coder` to call `rig_ps` via the `openrig` MCP.
