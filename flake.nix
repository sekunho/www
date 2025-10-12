{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    puggle-flake.url = "github:sekunho/puggle?ref=feat/themes";
    flake-utils.url = "github:numtide/flake-utils";

    tacopkgs = {
      url = "git+ssh://git@github.com/tacohirosystems/tacopkgs";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        # flake-parts.follows = "flake-parts";
        # git-hooks.follows = "git-hooks";
      };
    };
  };

  outputs = { self, nixpkgs, puggle-flake, flake-utils, tacopkgs }:
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-darwin" ] (system:
      let
        pkgs = import nixpkgs { inherit system; };
        puggle = puggle-flake.packages.${system}.puggle;
        sekun = import ./nix/sekun.nix {
          inherit pkgs puggle system;
          inherit (tacopkgs.packages.${system}) minhtml;
          version = "2024-10-16";
        };
      in
      {
        packages = {
          inherit sekun;
          inherit (tacopkgs.packages.${system}) minhtml;
          default = sekun;
        };

        devShells = {
          default = pkgs.mkShell {
            buildInputs = with pkgs; [
              self.packages.${system}.minhtml
              nixpkgs-fmt
              puggle
              nil
              watchexec
              git
              erdtree
              just

              graphicsmagick
              libjxl
              libavif
              libheif
              pkg-config

              gzip
              brotli
              zstd
            ];
          };
        };
      });
}
