# Dual-layer backups: daily encrypted Restic to the secondary disk (vdb at
# /mnt/backup) + systemd timer committing mutable configs back to GitHub.
{ config, lib, pkgs, ... }:

{
  # --- Secondary backup disk (/dev/vdb, label VIRTBOX_BACKUP) ---
  fileSystems."/mnt/backup" = {
    device = "/dev/disk/by-label/VIRTBOX_BACKUP";
    fsType = "ext4";
    options = [ "nofail" "discard" "noatime" ];
  };

  # Auto-format the backup disk on first boot if it has no filesystem.
  systemd.services.virt-box-format-backup-disk = {
    description = "Format vdb as VIRTBOX_BACKUP on first boot if unformatted";
    after = [ "local-fs-pre.target" ];
    before = [ "mnt-backup.mount" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      set -euo pipefail
      dev=""
      for cand in /dev/disk/by-id/virtio-virt-box-backup /dev/vdb; do
        if [ -b "$cand" ]; then dev="$cand"; break; fi
      done
      if [ -z "$dev" ]; then echo "no backup disk device found, skipping"; exit 0; fi
      if ! ${pkgs.e2fsprogs}/bin/blkid -o value -s LABEL "$dev" >/dev/null 2>&1; then
        echo "formatting $dev as VIRTBOX_BACKUP (ext4)"
        ${pkgs.e2fsprogs}/bin/mkfs.ext4 -L VIRTBOX_BACKUP "$dev"
      else
        echo "$dev already formatted ($( ${pkgs.e2fsprogs}/bin/blkid -o value -s LABEL "$dev"))"
      fi
    '';
  };

  # --- Daily Restic backups to /mnt/backup/restic-repo ---
  services.restic.backups.virtbox-local =
    let
      hasSecretsFile = builtins.pathExists ../../secrets/secrets.yaml;
      resticPasswordPath =
        if hasSecretsFile
        then config.sops.secrets.restic_password.path
        else "/etc/nixos/secrets/restic-password";
    in
    {
      repository = "/mnt/backup/restic-repo";
      passwordFile = resticPasswordPath;
      paths = [
        "/home/agent/.pi"
        "/home/agent/.openrig"
        "/home/agent/.local/share/opencode"
        "/home/agent/.paseo"
        "/home/agent/.local/share/pi-web-ui"
        "/home/agent/.local/share/pi-web-jm"
        "/home/agent/workspaces"
        "/etc/nixos"
      ];
      exclude = [
        "node_modules"
        ".cache"
        ".npm"
        "target/"
        ".venv/"
        ".direnv/"
        "*.qcow2"
      ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
      };
      # Atomically snapshot OpenRig's SQLite state so Restic captures a
      # transactionally consistent copy without stopping rigs or the daemon.
      # Guarded: no-op on first boot before OpenRig has created its database.
      backupPrepareCommand = ''
        if [ -f /home/agent/.openrig/openrig.sqlite ]; then
          ${pkgs.sqlite}/bin/sqlite3 /home/agent/.openrig/openrig.sqlite ".backup '/home/agent/.openrig/openrig-backup.sqlite'"
        fi
      '';
      pruneOpts = [
        "--keep-daily 7"
        "--keep-weekly 4"
        "--keep-monthly 6"
      ];
      initialize = true;
    };

  # One-command restore/snapshot helper on $PATH.
  environment.systemPackages =
    let
      hasSecretsFile = builtins.pathExists ../../secrets/secrets.yaml;
      resticPasswordPath =
        if hasSecretsFile
        then config.sops.secrets.restic_password.path
        else "/etc/nixos/secrets/restic-password";
    in
    [
      (pkgs.writeShellScriptBin "restic-virtbox-local" ''
        export RESTIC_REPOSITORY="/mnt/backup/restic-repo"
        export RESTIC_PASSWORD_FILE="${resticPasswordPath}"
        exec ${pkgs.restic}/bin/restic "$@"
      '')
    ];

  # --- Config sync + git auto-push timer (mutable profile/config changes) ---
  systemd.services.virt-box-config-sync = {
    description = "Sync mutable profile changes back to /etc/nixos and push to GitHub";
    after = [ "network-online.target" "sops-nix.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "agent";
      WorkingDirectory = "/etc/nixos";
      Environment = "PATH=${pkgs.git}/bin:${pkgs.openssh}/bin:/run/current-system/sw/bin";
      ExecStart = "${pkgs.bash}/bin/bash /etc/nixos/scripts-seed/config-sync.sh";
    };
  };

  systemd.timers.virt-box-config-sync = {
    description = "Hourly auto-commit of virt-box mutable configs";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
    };
  };

  # Backwards-compatible alias name from the design doc.
  systemd.services.virt-box-autocommit = {
    description = "Alias for virt-box-config-sync.service";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.systemd}/bin/systemctl start virt-box-config-sync.service";
    };
  };

  environment.etc."nixos/scripts-seed/config-sync.sh" = {
    mode = "0755";
    text = ''
      #!${pkgs.bash}/bin/bash
      set -euo pipefail
      cd /etc/nixos
      export GIT_SSH_COMMAND="${pkgs.openssh}/bin/ssh -i /home/agent/.ssh/virt-box-deploy-key -o StrictHostKeyChecking=accept-new"
      # Sync live profile edits back into the checkout.
      /run/current-system/sw/bin/virt-box-sync-profiles || true
      if ! ${pkgs.git}/bin/git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "/etc/nixos is not a git checkout, skipping push"; exit 0
      fi
      ${pkgs.git}/bin/git add -A profiles || true
      if ${pkgs.git}/bin/git diff --cached --quiet; then
        echo "no config changes to commit"; exit 0
      fi
      ${pkgs.git}/bin/git -c user.name="virt-box" -c user.email="virt-box@localhost" \
        commit -m "virt-box autocommit $(date -u +%FT%TZ)" || exit 0
      ${pkgs.git}/bin/git push origin main || ${pkgs.git}/bin/git push origin HEAD || true
    '';
  };
}
