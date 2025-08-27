{ pkgs, version, system, puggle }: pkgs.stdenv.mkDerivation {
  inherit version;
  name = "sekun";
  src = ../.;
  buildInputs = [ ];
  nativeBuildInputs = with pkgs; [ esbuild gzip puggle brotli ];

  buildPhase = ''
    mkdir -p $out/assets/css
    mkdir $out/assets/fonts

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
    ${pkgs.brotli}/bin/brotli -q 11 $out/public/**/*.html -f
    ${pkgs.brotli}/bin/brotli -q 11 $out/public/**/*.css -f
  '';
}
