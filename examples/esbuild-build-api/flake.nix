{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = { self, nixpkgs }: {
    packages.aarch64-darwin.default =
      let
        pkgs = import nixpkgs { system = "aarch64-darwin"; };
      in
        pkgs.buildNpmPackage {
          name = "foo-static";
          version = "1.0.0";
          src = ./.;
          npmDepsHash = "sha256-xF5hnIqw3atLZCa8H88sVOF8nrHXH5Qfh9I1mfTpFvo=";

          installPhase = ''
            mkdir $out
            npm run build
            cp -r public/ $out
          '';
        };

    devShells.aarch64-darwin.default =
      let
        pkgs = import nixpkgs { system = "aarch64-darwin"; };
      in pkgs.mkShell {
        buildInputs = with pkgs; [ prefetch-npm-deps nodejs_22 git erdtree ];
      };
  };
}
