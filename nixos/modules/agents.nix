# Hybrid declarative + mutable Pi profile system + OpenCode config.
#
# NixOS seeds four baseline Pi profiles (coder/researcher/auditor/devops).
# Profiles are COPIED (not symlinked) into ~/.pi/profiles/<name>/ so `ppi`,
# `pi config`, `pi install`, and `pi mcp add` can mutate them live without a
# NixOS rebuild, while CLI wrappers (pi-coder, ...) + Paseo provider env
# (PI_CODING_AGENT_DIR) select them.
{ config, lib, pkgs, ... }:

let
  # Baseline profile metadata. The JSON/Markdown sources live in
  # profiles/pi/<name>/{settings.json,mcp.json,SYSTEM.md} and are seeded to
  # the mutable locations on activation.
  piProfiles = [ "coder" "researcher" "auditor" "devops" ];

  mkPiWrapper = name: pkgs.writeShellScriptBin "pi-${name}" ''
    export PI_CODING_AGENT_DIR="''${PI_CODING_AGENT_DIR:-/home/agent/.pi/profiles/${name}}"
    exec /home/agent/.npm-global/bin/pi "$@"
  '';

  mkOcWrapper = name: pkgs.writeShellScriptBin "opencode-${name}" ''
    export OPENCODE_CONFIG="/home/agent/.config/opencode/profiles/${name}/opencode.json"
    export OPENCODE_CONFIG_DIR="/home/agent/.config/opencode/profiles/${name}"
    exec ${pkgs.opencode}/bin/opencode "$@"
  '';
in
{
  environment.systemPackages =
    (map mkPiWrapper piProfiles)
    ++ (map mkOcWrapper piProfiles)
    ++ (with pkgs; [
      opencode
      nodejs_24
      jq
    ])
    ++ [
      # Helper to sync runtime edits back into the repo checkout at /etc/nixos.
      (pkgs.writeShellScriptBin "virt-box-sync-profiles" ''
      set -euo pipefail
      SRC_BASE="/home/agent/.pi/profiles"
      DST_BASE="/etc/nixos/profiles/pi"
      for p in ${lib.concatStringsSep " " piProfiles}; do
        for f in settings.json mcp.json SYSTEM.md; do
          if [ -f "$SRC_BASE/$p/$f" ]; then
            install -Dm644 "$SRC_BASE/$p/$f" "$DST_BASE/$p/$f"
            echo "synced $p/$f"
          fi
        done
      done
      if [ -f /home/agent/.config/opencode/opencode.json ]; then
        install -Dm644 /home/agent/.config/opencode/opencode.json /etc/nixos/profiles/opencode/opencode.json
        echo "synced opencode.json"
      fi
      if [ -d /home/agent/.openrig/specs ]; then
        mkdir -p /etc/nixos/profiles/openrig
        for spec in /home/agent/.openrig/specs/*.yaml; do
          [ -e "$spec" ] || continue
          install -Dm644 "$spec" "/etc/nixos/profiles/openrig/$(basename "$spec")"
          echo "synced openrig spec $(basename "$spec")"
        done
      fi
      echo "Done. Review with: git -C /etc/nixos diff"
    '')
  ];

  # Seed-and-merge profiles on every activation: create dirs writable, seed
  # settings.json/mcp.json/SYSTEM.md if missing (or merge baseline `skills`
  # / `extensions` keys via jq without clobbering runtime additions),
  # symlink shared auth.json + models.json (ppi native layout), install orca
  # extensions + shared skills, generate opencode.json with secret indirection.
  systemd.services.virt-box-seed-profiles = {
    description = "Seed mutable Pi profiles + OpenCode config from /etc/nixos baselines";
    wantedBy = [ "multi-user.target" ];
    after = [ "sops-nix.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "agent";
      RemainAfterExit = true;
      ExecStart = "${pkgs.bash}/bin/bash /etc/nixos/scripts-seed/seed-profiles.sh";
    };
  };

  environment.etc."nixos/scripts-seed/seed-profiles.sh" = {
    mode = "0755";
    text = ''
      #!${pkgs.bash}/bin/bash
      set -euo pipefail
      BASELINE="/etc/nixos/profiles/pi"
      DEST_BASE="/home/agent/.pi/profiles"
      AGENT_DIR="/home/agent/.pi/agent"
      mkdir -p "$AGENT_DIR"/{extensions,skills,sessions} /home/agent/.config/opencode /home/agent/workspaces

      # Shared auth/models stay in ~/.pi/agent and are symlinked into profiles.
      for f in auth.json models.json; do
        [ -f "$AGENT_DIR/$f" ] || echo '{}' > "$AGENT_DIR/$f"
        chmod 0600 "$AGENT_DIR/$f"
      done

      for p in ${lib.concatStringsSep " " piProfiles}; do
        d="$DEST_BASE/$p"
        mkdir -p "$d"/{extensions,skills,tools,prompts,sessions}
        chmod -R u+rw "$d"
        for f in settings.json mcp.json SYSTEM.md; do
          if [ ! -f "$d/$f" ] && [ -f "$BASELINE/$p/$f" ]; then
            cp "$BASELINE/$p/$f" "$d/$f"
            chmod u+rw "$d/$f"
            echo "seeded $p/$f"
          elif [ -f "$d/$f" ] && [ -f "$BASELINE/$p/$f" ] && [[ "$f" == *.json ]]; then
            # Merge baseline keys without clobbering runtime additions:
            # baseline keys win only when missing in the live file, except
            # `skills`/`extensions` which are union-merged.
            tmp="$(mktemp)"
            ${pkgs.jq}/bin/jq -s --sort-keys '
              .[1] as $base | .[0] as $live
              | ($live * ($base | with_entries(select(.value == null or .value == "" | not)))) as $merged
              | $merged
              | .skills = ((($live.skills // []) + ($base.skills // [])) | unique)
              | .extensions = ((($live.extensions // []) + ($base.extensions // [])) | unique)
            ' "$d/$f" "$BASELINE/$p/$f" > "$tmp" && mv "$tmp" "$d/$f"
          fi
        done
        for f in auth.json models.json; do
          [ -e "$d/$f" ] || ln -s "$AGENT_DIR/$f" "$d/$f"
        done
      done

      # Shared orca status/spinner extensions + skills placeholder (ppi layout).
      [ -f "$AGENT_DIR/extensions/orca-status.ts" ] || echo '// orca status extension placeholder — replaced by pi install at runtime' > "$AGENT_DIR/extensions/orca-status.ts"

      # OpenCode base config with {env:VAR} secret indirection (never literals).
      if [ ! -f /home/agent/.config/opencode/opencode.json ] && [ -f /etc/nixos/profiles/opencode/opencode.json ]; then
        cp /etc/nixos/profiles/opencode/opencode.json /home/agent/.config/opencode/opencode.json
        chmod u+rw /home/agent/.config/opencode/opencode.json
      fi
      mkdir -p /home/agent/.config/opencode/profiles
      for p in ${lib.concatStringsSep " " piProfiles}; do
        mkdir -p "/home/agent/.config/opencode/profiles/$p"
        [ -f "/home/agent/.config/opencode/profiles/$p/opencode.json" ] || \
          cp /etc/nixos/profiles/opencode/opencode.json "/home/agent/.config/opencode/profiles/$p/opencode.json"
      done

      # tmux touch/mouse support so openrig-tui is clickable/tappable in ttyd
      # (desktop browser + Android) and scrollback survives inspection.
      # (printf, not heredoc: Nix ''-string indentation would indent a heredoc
      # terminator and bash would never see it at column 0.)
      if [ ! -f /home/agent/.tmux.conf ]; then
        printf '%s\n' 'set -g mouse on' 'set -g history-limit 200000' 'set -g window-size latest' 'set -g default-terminal "tmux-256color"' > /home/agent/.tmux.conf
        chmod 0644 /home/agent/.tmux.conf
        echo "seeded ~/.tmux.conf"
      fi

      # Pi-native OpenRig topology specs (mutable; synced back on auto-push).
      mkdir -p /home/agent/.openrig/specs
      if [ ! -f /home/agent/.openrig/specs/pi-squad.yaml ] && [ -f /etc/nixos/profiles/openrig/pi-squad.yaml ]; then
        cp /etc/nixos/profiles/openrig/pi-squad.yaml /home/agent/.openrig/specs/pi-squad.yaml
        chmod u+rw /home/agent/.openrig/specs/pi-squad.yaml
        echo "seeded openrig spec pi-squad.yaml"
      fi
    '';
  };

  # Ship baseline profile sources into /etc/nixos/profiles (the flake checkout
  # is linked there on the guest; see README deploy step).
  environment.etc = lib.mkMerge [
    (lib.mkMerge (map
      (p: {
        "nixos/profiles/pi/${p}/settings.json".source = ../../profiles/pi/${p}/settings.json;
        "nixos/profiles/pi/${p}/mcp.json".source = ../../profiles/pi/${p}/mcp.json;
        "nixos/profiles/pi/${p}/SYSTEM.md".source = ../../profiles/pi/${p}/SYSTEM.md;
      })
      piProfiles))
    {
      "nixos/profiles/opencode/opencode.json".source = ../../profiles/opencode/opencode.json;
      "nixos/profiles/openrig/pi-squad.yaml".source = ../../profiles/openrig/pi-squad.yaml;
    }
  ];
}
