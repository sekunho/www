{ pkgs, version, fonts, system, puggle }: pkgs.stdenv.mkDerivation {
  inherit version;
  name = "sekun";
  src = ../.;
  buildInputs = [ fonts.packages.${system}.berkeley-mono-1009 ];
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
    cp ./assets/images/*.webp $out/assets/images
    cp ./assets/images/favicon* $out/assets/images
    cp ./assets/fonts/* $out/assets/fonts

    ln -s ${fonts.packages.${system}.berkeley-mono-1009}/share/fonts/web/berkeley-mono-variable/WEB/BerkeleyMonoVariable-Regular.woff2 $out/assets/fonts/BerkeleyMonoVariable-Regular.woff2
    ln -s ${fonts.packages.${system}.berkeley-mono-1009}/share/fonts/web/berkeley-mono-variable/WEB/BerkeleyMonoVariable-Italic.woff2 $out/assets/fonts/BerkeleyMonoVariable-Italic.woff2

    ${puggle}/bin/puggle build
    cp -r public/* $out
  '';
}
