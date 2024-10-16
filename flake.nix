{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    puggle-flake.url = "github:sekunho/puggle";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, puggle-flake, flake-utils }:
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-darwin" ] (system:
      let
        pkgs = import nixpkgs { inherit system; };
        puggle = puggle-flake.packages.${system}.puggle;
        sekun = import ./nix/sekun.nix { inherit pkgs puggle system; version = "2024-10-16"; };
      in
      {
        packages = { inherit sekun; default = sekun; };

        devShells = {
          default = pkgs.mkShell {
            buildInputs = with pkgs; [ nixpkgs-fmt puggle nil ];
          };
        };
      });
}
