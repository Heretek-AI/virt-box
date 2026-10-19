{
  description = "virt-box — declarative NixOS KVM appliance for Pi + OpenCode agents";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self
    , nixpkgs
    , home-manager
    , sops-nix
    , disko
    , ...
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in
    {
      nixosConfigurations.virt-box = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit self; };
        modules = [
          ./nixos/configuration.nix
          sops-nix.nixosModules.sops
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
          }
        ];
      };

      devShells.${system}.default = pkgs.mkShell {
        name = "virt-box-host";
        packages = with pkgs; [
          # Secrets management
          sops
          age
          ssh-to-age
          # NixOS image build + remote deploy
          nixos-rebuild
          # Task runner
          just
          # Host tooling
          jq
          yq-go
          git
          gh
          libvirt
        ];
        shellHook = ''
          echo "virt-box host shell — commands: just build-image | just create-vm | just deploy | just --list"
        '';
      };

      formatter.${system} = pkgs.nixpkgs-fmt;
    };
}
