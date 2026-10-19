# Zero-leak secrets: sops-nix decrypts secrets/secrets.yaml to /run/secrets/*
# (tmpfs, 0400, owned by agent) and renders an EnvironmentFile template
# consumed by agent systemd services + interactive shells. Nothing secret is
# ever interpolated into the Nix store (no builtins.toJSON of secrets).
#
# OAuth token files (~/.pi/agent/auth.json, ~/.local/share/opencode/auth.json)
# stay user-writable so `pi auth` / `opencode auth` refreshes never hit
# read-only errors.
{ config, lib, pkgs, ... }:

let
  hasSecretsFile = builtins.pathExists ../../secrets/secrets.yaml;
in
{
  config = lib.mkMerge [
    {
      # Make secrets available in interactive shells without baking them into the
      # store: shells source the rendered template at login when present.
      programs.bash.interactiveShellInit = ''
        if [ -f /home/agent/.config/virt-box/secrets.env ]; then
          set -a; . /home/agent/.config/virt-box/secrets.env 2>/dev/null; set +a
        fi
      '';
      programs.zsh.interactiveShellInit = lib.mkIf config.programs.zsh.enable ''
        if [ -f /home/agent/.config/virt-box/secrets.env ]; then
          set -a; . /home/agent/.config/virt-box/secrets.env 2>/dev/null; set +a
        fi
      '';
    }

    (lib.mkIf hasSecretsFile {
      sops.defaultSopsFile = ../../secrets/secrets.yaml;
      sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

      sops.secrets = {
        anthropic_api_key = { owner = "agent"; group = "users"; mode = "0400"; };
        openai_api_key = { owner = "agent"; group = "users"; mode = "0400"; };
        gemini_api_key = { owner = "agent"; group = "users"; mode = "0400"; };
        openrouter_api_key = { owner = "agent"; group = "users"; mode = "0400"; };
        opencode_api_key = { owner = "agent"; group = "users"; mode = "0400"; };
        deepseek_api_key = { owner = "agent"; group = "users"; mode = "0400"; };
        tavily_api_key = { owner = "agent"; group = "users"; mode = "0400"; };
        firecrawl_api_key = { owner = "agent"; group = "users"; mode = "0400"; };
        firecrawl_api_url = { owner = "agent"; group = "users"; mode = "0400"; };
        searxng_base_url = { owner = "agent"; group = "users"; mode = "0400"; };
        context7_api_key = { owner = "agent"; group = "users"; mode = "0400"; };
        webui_password = { owner = "agent"; group = "users"; mode = "0400"; };
        tailscale_auth_key = { owner = "agent"; group = "users"; mode = "0400"; };
        restic_password = { owner = "agent"; group = "users"; mode = "0400"; };
        github_ssh_private_key = {
          owner = "agent";
          group = "users";
          mode = "0600";
          path = "/home/agent/.ssh/virt-box-deploy-key";
        };
      };

      # Rendered env file shared by all agent daemons (EnvironmentFile=) and
      # sourced by interactive shells. sops-install-secrets substitutes
      # config.sops.placeholder.<name> at activation time on tmpfs/ramfs, so
      # secret values never enter /nix/store.
      sops.templates."agent-secrets.env" = {
        owner = "agent";
        group = "users";
        mode = "0400";
        path = "/home/agent/.config/virt-box/secrets.env";
        content = ''
          ANTHROPIC_API_KEY=${config.sops.placeholder.anthropic_api_key}
          OPENAI_API_KEY=${config.sops.placeholder.openai_api_key}
          GEMINI_API_KEY=${config.sops.placeholder.gemini_api_key}
          OPENROUTER_API_KEY=${config.sops.placeholder.openrouter_api_key}
          OPENCODE_API_KEY=${config.sops.placeholder.opencode_api_key}
          DEEPSEEK_API_KEY=${config.sops.placeholder.deepseek_api_key}
          TAVILY_API_KEY=${config.sops.placeholder.tavily_api_key}
          FIRECRAWL_API_KEY=${config.sops.placeholder.firecrawl_api_key}
          FIRECRAWL_API_URL=${config.sops.placeholder.firecrawl_api_url}
          SEARXNG_BASE_URL=${config.sops.placeholder.searxng_base_url}
          CONTEXT7_API_KEY=${config.sops.placeholder.context7_api_key}
          PI_WEB_TOKEN=${config.sops.placeholder.webui_password}
          OPENCODE_SERVER_PASSWORD=${config.sops.placeholder.webui_password}
          OPENCHAMBER_UI_PASSWORD=${config.sops.placeholder.webui_password}
          PASEO_PASSWORD=${config.sops.placeholder.webui_password}
        '';
      };

      # Zero-touch Tailscale join on first boot when tailscale_auth_key is set.
      services.tailscale.authKeyFile = config.sops.secrets.tailscale_auth_key.path;
    })
  ];
}
