{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    disko.url = "github:nix-community/disko/latest";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, disko, sops-nix }:
  let
    system = "x86_64-linux";
    pkgs = import nixpkgs { inherit system; };
  in
  {
    nixosModules = {
      hetzner = import ./modules/hetzner/default.nix;
    };

    nixosConfigurations = {
      server-a = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          disko.nixosModules.disko
          self.nixosModules.hetzner
          ./hosts/server-a/configuration.nix
        ];
        specialArgs = {
          inherit self;
          operatorPublicKeys = [ "<USER_A_PUBLIC_SSH_KEY>" ];
          extraGroups = [];
        };
      };
    };

    devShells.${system}.default = pkgs.mkShell {
      buildInputs = with pkgs; [
        nixd
        nixpkgs-fmt
        hcloud
        nixos-anywhere
        sops
        ssh-to-age
        just
      ];
    };
  };
}
