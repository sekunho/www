{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    puggle-flake.url = "git+https://forgejo.quoll-owl.ts.net/tacohirosystems/puggle?ref=main";
    flake-utils.url = "github:numtide/flake-utils";

    tacopkgs = {
      url = "git+ssh://git@github.com/tacohirosystems/tacopkgs";
      inputs = {
        nixpkgs.follows = "nixpkgs";
      };
    };
  };

  outputs = { self, nixpkgs, puggle-flake, flake-utils, tacopkgs }:
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-darwin" ] (system:
      let
        version = "2024-10-16";
        pkgs = import nixpkgs { inherit system; };
        puggle = puggle-flake.packages.${system}.puggle;
        sekun-www = import ./nix/sekun.nix {
          inherit pkgs puggle system version;
          inherit (tacopkgs.packages.${system}) minhtml;
        };
      in
      {
        packages = {
          sekun = sekun-www;
          inherit (tacopkgs.packages.${system}) minhtml;
          default = sekun-www;

          sekun-www-image = pkgs.dockerTools.streamLayeredImage {
            name = "sekun-www";
            tag = version;
            contents = [ sekun-www pkgs.caddy ];
            config = {
              Cmd = ["/bin/caddy" "file-server" "--root" "www" "--precompressed" "br" "zstd" "gzip"];
            };
          };
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

              caddy

              graphicsmagick
              libjxl
              libavif
              libheif
              pkg-config

              gzip
              brotli
              zstd
              dive
              yq

              imagemagick
            ];
          };
        };
      });
}
