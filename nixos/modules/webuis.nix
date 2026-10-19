# WebUIs, orchestrators & Tailscale Serve.
#
# Port/data-dir isolation (critical — both Pi WebUIs default to
# PI_WEB_DATA_DIR=~/.pi-web and read PI_WEB_PORT):
#   xing-shuyin/pi-web-ui : 127.0.0.1:8787, data ~/.local/share/pi-web-ui
#   jmfranco/pi-web       : 127.0.0.1:8504, data ~/.local/share/pi-web-jm
# WebSocket-heavy SPAs break under URL subpaths, so each WebUI gets its own
# Tailscale Serve HTTPS port on the guest MagicDNS name:
#   :443  -> Paseo (127.0.0.1:6767)
#   :8443 -> pi-web-ui (127.0.0.1:8787)
#   :8504 -> pi-web (127.0.0.1:8504)
#   :3000 -> OpenChamber (127.0.0.1:3000)
#   :4096 -> opencode serve (127.0.0.1:4096)
#   :7681 -> OpenRig TUI via ttyd+tmux (127.0.0.1:7681)
#   :7433 -> OpenRig daemon + bundled UI (127.0.0.1:7433)
{ config, lib, pkgs, ... }:

let
  agentHome = "/home/agent";
  npmRoot = "${agentHome}/.npm-global";
  secretsEnv = "-/home/agent/.config/virt-box/secrets.env";
  nodePkg = pkgs.nodejs_24;

  npmBin = name: "${npmRoot}/bin/${name}";
in
{
  # npm global root on PATH for the agent user.
  environment.variables = {
    NPM_CONFIG_PREFIX = npmRoot;
  };

  users.users.agent.packages = with pkgs; [
    nodejs_24
    gcc
    gnumake
    python3
  ];

  # Bootstrap / update all daily-release npm agent packages into
  # ~/.npm-global (no custom Nix derivations needed; nix-ld + gcc/make/python
  # let node-pty / better-sqlite3 compile cleanly).
  systemd.services.virt-box-npm-bootstrap = {
    description = "Install/update Pi + WebUI npm packages into ~/.npm-global";
    after = [ "network-online.target" "sops-nix.service" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "agent";
      RemainAfterExit = true;
      Environment = [
        "PATH=${nodePkg}/bin:${pkgs.gcc}/bin:${pkgs.gnumake}/bin:${pkgs.python3}/bin:${pkgs.bash}/bin:${pkgs.coreutils}/bin:/run/current-system/sw/bin"
        "NPM_CONFIG_PREFIX=${npmRoot}"
      ];
    };
    script = ''
      set -euo pipefail
      mkdir -p "${npmRoot}" ~/workspaces ~/.local/bin
      export PATH="${npmRoot}/bin:$PATH"
      ${nodePkg}/bin/npm config set prefix "${npmRoot}"
      ${nodePkg}/bin/npm install -g \
        @earendil-works/pi-coding-agent \
        pi-profiles \
        @getpaseo/cli \
        @openrig/cli \
        pi-web-ui \
        @jmfederico/pi-web \
        @openchamber/web \
        codebase-memory-mcp \
        agent-browser \
        @playwright/cli
      # Convenience symlinks for pi-web launchers (package bin names vary by release).
      for c in pi-web pi-web-server pi-web-sessiond rig openrig-tui; do
        if [ -x "${npmRoot}/bin/$c" ]; then ln -sf "${npmRoot}/bin/$c" ~/.local/bin/"$c" 2>/dev/null || true; fi
      done
    '';
  };

  systemd.services.virt-box-update-agents = {
    description = "Alias to re-run the npm bootstrap (update agent packages)";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.systemd}/bin/systemctl start virt-box-npm-bootstrap.service";
    };
  };

  # --- 1. Paseo daemon + WebUI (127.0.0.1:6767) ---
  systemd.services.paseo = {
    description = "Paseo multi-agent orchestrator (Pi + OpenCode)";
    after = [ "network-online.target" "virt-box-npm-bootstrap.service" "virt-box-seed-profiles.service" "paseo-config-seed.service" ];
    wants = [ "network-online.target" "paseo-config-seed.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      User = "agent";
      WorkingDirectory = agentHome;
      EnvironmentFile = secretsEnv;
      Environment = [
        "PATH=${npmRoot}/bin:${nodePkg}/bin:/run/current-system/sw/bin"
        "PASEO_HOME=${agentHome}/.paseo"
        "PASEO_LISTEN=127.0.0.1:6767"
        "PASEO_WEB_UI_ENABLED=true"
      ];
      ExecStart = "${npmBin "paseo"} daemon run --home ${agentHome}/.paseo";
      Restart = "always";
      RestartSec = "5s";
    };
  };

  # Seed Paseo config with per-profile Pi providers + opencode (one-tap
  # switching in Paseo WebUI + sh.paseo Android app).
  systemd.services.paseo-config-seed = {
    description = "Seed ~/.paseo/config.json with virt-box agent profiles";
    after = [ "virt-box-seed-profiles.service" ];
    before = [ "paseo.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "agent";
      RemainAfterExit = true;
      ExecStart = "${pkgs.bash}/bin/bash /etc/nixos/scripts-seed/seed-paseo.sh";
    };
  };

  environment.etc."nixos/scripts-seed/seed-paseo.sh" = {
    mode = "0755";
    text = ''
      #!${pkgs.bash}/bin/bash
      set -euo pipefail
      mkdir -p /home/agent/.paseo
      BASE_JSON=$(${pkgs.jq}/bin/jq -n '
      {
        "$schema": "https://paseo.sh/schemas/paseo.config.v1.json",
        version: 1,
        daemon: {
          listen: "127.0.0.1:6767",
          hostnames: ["localhost", ".localhost", "virt-box"],
          mcp: { enabled: true },
          relay: { enabled: false },
          agentProfiles: [
            { id: "pi-coder",      name: "Pi Coder",      provider: "pi-coder" },
            { id: "pi-researcher", name: "Pi Researcher", provider: "pi-researcher" },
            { id: "pi-auditor",    name: "Pi Auditor",    provider: "pi-auditor" },
            { id: "pi-devops",     name: "Pi DevOps",     provider: "pi-devops" },
            { id: "opencode",      name: "OpenCode",      provider: "opencode" }
          ]
        },
        agents: {
          providers: {
            "pi-coder":      { extends: "pi", label: "Pi (Coder)",      command: ["/home/agent/.npm-global/bin/pi", "--mode", "rpc"], env: { PI_CODING_AGENT_DIR: "/home/agent/.pi/profiles/coder" } },
            "pi-researcher": { extends: "pi", label: "Pi (Researcher)", command: ["/home/agent/.npm-global/bin/pi", "--mode", "rpc"], env: { PI_CODING_AGENT_DIR: "/home/agent/.pi/profiles/researcher" } },
            "pi-auditor":    { extends: "pi", label: "Pi (Auditor)",    command: ["/home/agent/.npm-global/bin/pi", "--mode", "rpc"], env: { PI_CODING_AGENT_DIR: "/home/agent/.pi/profiles/auditor" } },
            "pi-devops":     { extends: "pi", label: "Pi (DevOps)",     command: ["/home/agent/.npm-global/bin/pi", "--mode", "rpc"], env: { PI_CODING_AGENT_DIR: "/home/agent/.pi/profiles/devops" } },
            "opencode":      { command: ["/run/current-system/sw/bin/opencode"] }
          }
        },
        features: { webUi: { enabled: true } }
      }')
      if [ -f /home/agent/.paseo/config.json ]; then
        tmp="$(mktemp)"
        ${pkgs.jq}/bin/jq -s '.[0] * .[1]' /home/agent/.paseo/config.json <(printf '%s' "$BASE_JSON") > "$tmp" && mv "$tmp" /home/agent/.paseo/config.json
      else
        printf '%s\n' "$BASE_JSON" > /home/agent/.paseo/config.json
      fi
      chmod 0600 /home/agent/.paseo/config.json
    '';
  };

  # --- 2. xing-shuyin/pi-web-ui (127.0.0.1:8787) ---
  systemd.services.pi-web-ui = {
    description = "xing-shuyin pi-web-ui Pi cockpit";
    after = [ "virt-box-npm-bootstrap.service" "sops-nix.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      User = "agent";
      WorkingDirectory = "${agentHome}/workspaces";
      EnvironmentFile = secretsEnv;
      Environment = [
        "PATH=${npmRoot}/bin:${nodePkg}/bin:/run/current-system/sw/bin"
        "PI_WEB_HOST=127.0.0.1"
        "PI_WEB_PORT=8787"
        "PI_WEB_DATA_DIR=${agentHome}/.local/share/pi-web-ui"
        "PI_WEB_CWD=${agentHome}/workspaces"
      ];
      ExecStart = "${npmBin "pi-web-ui"} --port 8787 --host 127.0.0.1 --cwd ${agentHome}/workspaces --data-dir ${agentHome}/.local/share/pi-web-ui";
      Restart = "always";
      RestartSec = "5s";
    };
  };

  # --- 3. @jmfederico/pi-web session daemon + web server (127.0.0.1:8504) ---
  systemd.services.pi-web-sessiond = {
    description = "jmfederico pi-web session daemon";
    after = [ "virt-box-npm-bootstrap.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      User = "agent";
      Environment = "PATH=${npmRoot}/bin:${nodePkg}/bin:/run/current-system/sw/bin";
      ExecStart = "${pkgs.bash}/bin/bash -c 'exec ${npmRoot}/bin/pi-web-sessiond || exec ${npmRoot}/bin/pi-web-session --foreground || exec ${npmRoot}/bin/pi-web sessiond'";
      Restart = "always";
      RestartSec = "5s";
    };
  };

  systemd.services.pi-web = {
    description = "jmfederico pi-web persistent session server";
    after = [ "pi-web-sessiond.service" "sops-nix.service" ];
    wants = [ "pi-web-sessiond.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      User = "agent";
      WorkingDirectory = agentHome;
      EnvironmentFile = secretsEnv;
      Environment = [
        "PATH=${npmRoot}/bin:${nodePkg}/bin:/run/current-system/sw/bin"
        "PI_WEB_HOST=127.0.0.1"
        "PI_WEB_PORT=8504"
        "PI_WEB_DATA_DIR=${agentHome}/.local/share/pi-web-jm"
        "PI_WEB_CONFIG=${agentHome}/.config/pi-web/config.json"
      ];
      ExecStartPre = "${pkgs.bash}/bin/bash -c 'mkdir -p ${agentHome}/.local/share/pi-web-jm ${agentHome}/.config/pi-web'";
      # Bin name varies by @jmfederico/pi-web release (pi-web-server vs pi-web).
      ExecStart = "${pkgs.bash}/bin/bash -c 'exec ${npmRoot}/bin/pi-web-server --port 8504 --host 127.0.0.1 || exec ${npmRoot}/bin/pi-web --port 8504 --host 127.0.0.1'";
      Restart = "always";
      RestartSec = "5s";
    };
  };

  # --- 4. opencode serve (127.0.0.1:4096) — OpenCode Mobile app backend ---
  systemd.services.opencode-serve = {
    description = "opencode headless server (OpenCode Mobile + SDK clients)";
    after = [ "network-online.target" "virt-box-seed-profiles.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      User = "agent";
      WorkingDirectory = "${agentHome}/workspaces";
      EnvironmentFile = secretsEnv;
      Environment = "PATH=${pkgs.opencode}/bin:${nodePkg}/bin:/run/current-system/sw/bin";
      ExecStart = "${pkgs.opencode}/bin/opencode serve --hostname 127.0.0.1 --port 4096";
      Restart = "always";
      RestartSec = "5s";
    };
  };

  # --- 5. OpenChamber web (127.0.0.1:3000) driving the local opencode server ---
  systemd.services.openchamber = {
    description = "OpenChamber web UI for OpenCode";
    after = [ "opencode-serve.service" "virt-box-npm-bootstrap.service" ];
    wants = [ "opencode-serve.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      User = "agent";
      WorkingDirectory = agentHome;
      EnvironmentFile = secretsEnv;
      Environment = [
        "PATH=${npmRoot}/bin:${nodePkg}/bin:/run/current-system/sw/bin"
        "OPENCODE_HOST=http://127.0.0.1:4096"
        "OPENCODE_SKIP_START=true"
      ];
      ExecStart = "${npmBin "openchamber"} serve --port 3000 --host 127.0.0.1 --foreground";
      Restart = "always";
      RestartSec = "5s";
    };
  };

  # --- 6. OpenRig daemon (127.0.0.1:7433) ---
  systemd.services.openrig-daemon = {
    description = "OpenRig multi-agent topology daemon";
    after = [ "network-online.target" "virt-box-npm-bootstrap.service" "virt-box-seed-profiles.service" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "forking";
      User = "agent";
      WorkingDirectory = "${agentHome}/workspaces";
      EnvironmentFile = secretsEnv;
      Environment = [
        "PATH=${npmRoot}/bin:${nodePkg}/bin:${pkgs.tmux}/bin:${pkgs.git}/bin:/run/current-system/sw/bin"
        "OPENRIG_HOME=${agentHome}/.openrig"
        "OPENRIG_HOST=127.0.0.1"
        "OPENRIG_PORT=7433"
      ];
      ExecStart = "${npmBin "rig"} daemon start --host 127.0.0.1 --port 7433 --no-kernel";
      ExecStop = "${npmBin "rig"} daemon stop";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };

  # --- 7. Persistent tmux + ttyd Web/Mobile TUI for OpenRig (127.0.0.1:7681) ---
  systemd.services.openrig-tmux = {
    description = "Persistent tmux session hosting openrig-tui";
    after = [ "openrig-daemon.service" ];
    wants = [ "openrig-daemon.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "forking";
      User = "agent";
      WorkingDirectory = "${agentHome}/workspaces";
      EnvironmentFile = secretsEnv;
      Environment = [
        "PATH=${npmRoot}/bin:${nodePkg}/bin:${pkgs.tmux}/bin:${pkgs.git}/bin:/run/current-system/sw/bin"
        "OPENRIG_HOME=${agentHome}/.openrig"
      ];
      ExecStart = pkgs.writeShellScript "start-openrig-tmux" ''
        ${pkgs.tmux}/bin/tmux has-session -t openrig 2>/dev/null && exit 0
        ${pkgs.tmux}/bin/tmux new-session -d -s openrig -n "tui" -x 220 -y 55 \
          "bash -lc 'while true; do ${npmBin "openrig-tui"} || sleep 2; done'"
        ${pkgs.tmux}/bin/tmux new-window -t openrig:1 -n "rig-shell" -c "${agentHome}/workspaces"
        ${pkgs.tmux}/bin/tmux select-window -t openrig:0
      '';
      ExecStop = "${pkgs.tmux}/bin/tmux kill-session -t openrig";
      RemainAfterExit = true;
      Restart = "on-failure";
    };
  };

  systemd.services.openrig-ttyd = {
    description = "ttyd Web & Android terminal for OpenRig TUI";
    after = [ "openrig-tmux.service" ];
    wants = [ "openrig-tmux.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      User = "agent";
      WorkingDirectory = "${agentHome}/workspaces";
      Environment = [
        "PATH=${npmRoot}/bin:${nodePkg}/bin:${pkgs.tmux}/bin:/run/current-system/sw/bin"
        "OPENRIG_HOME=${agentHome}/.openrig"
      ];
      # Single-line argv: systemd does not interpret shell `\` continuations.
      ExecStart = "${pkgs.ttyd}/bin/ttyd --writable --interface 127.0.0.1 --port 7681 --ping-interval 10 --client-option fontSize=15 --client-option disableLeaveAlert=true --client-option titleFixed=OpenRig\\ TUI\\ (virt-box) ${pkgs.tmux}/bin/tmux new-session -A -s openrig";
      Restart = "always";
      RestartSec = "3s";
    };
  };

  # --- Tailscale Serve: multi-port HTTPS on the guest tailnet name ---
  systemd.services.tailscale-serve-webuis = {
    description = "Expose agent WebUIs via Tailscale Serve (tailnet-only HTTPS)";
    after = [ "tailscaled.service" "paseo.service" "pi-web-ui.service" "pi-web.service" "openchamber.service" "opencode-serve.service" "openrig-ttyd.service" "openrig-daemon.service" ];
    wants = [ "tailscaled.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.bash}/bin/bash /etc/nixos/scripts-seed/tailscale-serve.sh";
      ExecStop = "${pkgs.tailscale}/bin/tailscale serve off";
    };
  };

  environment.etc."nixos/scripts-seed/tailscale-serve.sh" = {
    mode = "0755";
    text = ''
      #!${pkgs.bash}/bin/bash
      set -euo pipefail
      TS=${pkgs.tailscale}/bin/tailscale
      # Wait for tailscaled to be up (max ~60s).
      for i in $(seq 1 30); do $TS status >/dev/null 2>&1 && break; sleep 2; done
      # Paseo WebUI + sh.paseo Android app direct host
      $TS serve --bg --https=443  http://127.0.0.1:6767 || true
      # xing-shuyin/pi-web-ui
      $TS serve --bg --https=8443 http://127.0.0.1:8787 || true
      # @jmfederico/pi-web
      $TS serve --bg --https=8504 http://127.0.0.1:8504 || true
      # OpenChamber web
      $TS serve --bg --https=3000 http://127.0.0.1:3000 || true
      # OpenCode server (opencode attach + app.getopencode mobile)
      $TS serve --bg --https=4096 http://127.0.0.1:4096 || true
      # OpenRig persistent TUI (ttyd + tmux, touch/mouse enabled)
      $TS serve --bg --https=7681 http://127.0.0.1:7681 || true
      # OpenRig daemon + bundled web UI
      $TS serve --bg --https=7433 http://127.0.0.1:7433 || true
      $TS serve status || true
    '';
  };
}
