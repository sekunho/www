{ pkgs, version, system, puggle }: pkgs.stdenv.mkDerivation {
  inherit version;
  name = "sekun";
  src = ../.;
  buildInputs = [ ];
  nativeBuildInputs = with pkgs; [ esbuild gzip puggle ];

  buildPhase = ''
    mkdir -p $out/assets/css
    # mkdir $out/assets/js
    mkdir $out/assets/fonts

    # esbuild \
    #   `find ./assets/js \( -name '*.js' \)` \
    #   --minify --outdir=$out/assets/js

    ${pkgs.esbuild}/bin/esbuild \
      ./assets/css/style.css \
      --bundle \
      --minify \
      --outfile=$out/assets/css/style.css \
      --external:'*.woff2'

    mkdir $out/assets/images

    # Copy images and fonts
    cp -r ./assets/images/* $out/assets/images
    cp ./assets/fonts/* $out/assets/fonts

    ${puggle}/bin/puggle build
    mv public/* $out
  '';
}
