{ pkgs, version, system, puggle, minhtml }: pkgs.stdenv.mkDerivation {
  inherit version;
  name = "sekun";
  src = ../.;
  buildInputs = [ ];
  nativeBuildInputs = with pkgs; [ esbuild gzip puggle brotli ];

  buildPhase = ''
    mkdir -p $out/assets/css
    mkdir $out/assets/fonts

    ${pkgs.esbuild}/bin/esbuild \
      ./assets/css/**/*.css \
      --minify \
      --outdir=$out/assets/css

    ${pkgs.esbuild}/bin/esbuild \
      ./assets/css/*.css \
      --minify \
      --outdir=$out/assets/css

    mkdir $out/assets/images

    # Copy images and fonts
    cp -r ./assets/images/* $out/assets/images
    cp ./assets/fonts/* $out/assets/fonts

    ${puggle}/bin/puggle build

    ${minhtml}/bin/minhtml \
      --minify-js \
      --minify-css \
      public/**/*.html

    # compression stuff
    ## brotli
    ${pkgs.brotli}/bin/brotli --best public/blog/**/*.html -f
    ${pkgs.brotli}/bin/brotli --best public/blog/*.html -f
    ${pkgs.brotli}/bin/brotli --best public/contact/**/*.html -f
    ${pkgs.brotli}/bin/brotli --best public/contact/*.html -f
    ${pkgs.brotli}/bin/brotli --best public/projects/**/*.html -f
    ${pkgs.brotli}/bin/brotli --best public/projects/*.html -f
    ${pkgs.brotli}/bin/brotli --best public/*.html -f
    ${pkgs.brotli}/bin/brotli --best $out/assets/**/*.css -f
    ${pkgs.brotli}/bin/brotli --best $out/assets/*.css -f

    # gzip
    ${pkgs.gzip}/bin/gzip --best --keep public/blog/**/*.html -f
    ${pkgs.gzip}/bin/gzip --best --keep public/blog/*.html -f
    ${pkgs.gzip}/bin/gzip --best --keep public/contact/**/*.html -f
    ${pkgs.gzip}/bin/gzip --best --keep public/contact/*.html -f
    ${pkgs.gzip}/bin/gzip --best --keep public/projects/**/*.html -f
    ${pkgs.gzip}/bin/gzip --best --keep public/projects/*.html -f
    ${pkgs.gzip}/bin/gzip --best --keep public/*.html -f
    ${pkgs.gzip}/bin/gzip --best --keep $out/assets/**/*.css -f
    ${pkgs.gzip}/bin/gzip --best --keep $out/assets/*.css -f

    mv public/* $out
  '';
}
