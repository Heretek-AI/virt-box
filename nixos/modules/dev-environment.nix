# Full system development environment for Pi + OpenCode agents.
#
# Provides nix-ld (prebuilt binaries / node-pty / Playwright), envfs
# (/bin/bash + /usr/bin/env shebangs), direnv + nix-direnv, nix-index,
# rootless Podman, language toolchains, static analysis, and headless
# Chromium / Playwright browsers.
{ config, lib, pkgs, ... }:

{
  # Run unpatched binaries (node-pty, Playwright browsers, downloaded tools).
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      stdenv.cc.cc.lib
      stdenv.cc.libc
      zlib
      zstd
      curl
      openssl
      attr
      libssh
      bzip2
      libxml2
      acl
      libsodium
      util-linux
      xz
      systemd
      glib
      nss
      nspr
      dbus
      atk
      at-spi2-atk
      cups
      libdrm
      expat
      libxkbcommon
      xorg.libX11
      xorg.libXcomposite
      xorg.libXdamage
      xorg.libXext
      xorg.libXfixes
      xorg.libXrandr
      mesa
      alsa-lib
      pango
      cairo
      icu
      libunwind
      libcap
      libusb1
      udev
      fontconfig
      freetype
      libkrb5
    ];
  };

  # Resolve /bin/bash and /usr/bin/env shebangs from $PATH (FUSE).
  services.envfs.enable = true;

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
  programs.nix-index.enable = true;

  # Rootless Podman (docker-compatible CLI). Never enable together with
  # virtualisation.docker — the socket/compat shims conflict.
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    defaultNetwork.settings.dns_enabled = true;
  };

  environment.systemPackages = with pkgs; [
    # Languages & runtimes (Node 24 required by @openchamber/web v2.5+)
    nodejs_24
    bun
    python312
    uv
    rustc
    cargo
    go
    gcc
    clang
    gnumake
    cmake
    pkg-config
    corepack

    # Static analysis & search
    semgrep
    ast-grep
    ripgrep
    fd
    jq
    yq-go
    git
    gh
    lazygit
    tmux
    htop
    direnv
    nix-index
    devenv

    # OpenRig TUI-over-Web + atomic SQLite snapshots
    ttyd
    sqlite

    # Headless browser / Playwright. Agents use PLAYWRIGHT_BROWSERS_PATH so
    # they never try to download non-NixOS browser binaries at runtime.
    chromium
    playwright-driver.browsers
  ];

  environment.variables = {
    PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
  };
}
