{ pkgs, version, system, puggle, minhtml }: pkgs.stdenv.mkDerivation {
  inherit version;
  name = "sekun";
  src = ../.;
  buildInputs = [ ];
  nativeBuildInputs = with pkgs; [ esbuild gzip puggle brotli imagemagick minhtml ];

  buildPhase = ''
    mkdir -p $out/www

    # HTML
    puggle build
    find public -name '*.html' -execdir minhtml --keep-closing-tags --minify-js --minify-css {} --output {} \;
    find public -name '*.html' -execdir brotli --best {} -f \;
    find public -name '*.html' -execdir gzip --best --keep {} -f \;

    # Images
    mkdir -p $out/www/assets/images
    cp -r assets/images $out/www/assets

    ## favicons
    find $out/www/assets/images -name 'apple-*.png' -execdir mogrify -sampling-factor 4:2:0 -strip -quality 35 -interlace JPEG -colorspace gray -format jpg {} \;
    find $out/www/assets/images -name 'favicon-*.png' -execdir mogrify -sampling-factor 4:2:0 -strip -quality 35 -interlace JPEG -colorspace gray -format jpg {} \;

    ## Other images
    # find $out/www -name '*.jpg' -execdir mogrify -sampling-factor 4:2:0 -strip -quality 85 -interlace JPEG -colorspace RGB -format jpg {} \;
    # find $out/www -name '*.png' -execdir mogrify -strip {} \;
    # find $out/www -name '*.webp' -execdir mogrify -quality 5 -strip {} \;

    find $out/www -name 'hiro-alt.webp' -execdir mogrify \
      -colorspace gray -quality 75 -resize 60% -strip {} \;

    ## Post images
    find $out/www/assets/images/posts -name 'cover.*' -execdir mogrify \
      -quality 75 -resize 1280x720 -strip -format webp {} \;

    # CSS
    mkdir -p $out/www/assets/css
    esbuild ./assets/css/*.css --minify --outdir=$out/www/assets/css
    esbuild ./assets/css/**/*.css --minify --outdir=$out/www/assets/css
    find $out/www/assets/css -name '*.css' -execdir brotli --best {} -f \;
    find $out/www/assets/css -name '*.css' -execdir gzip --best {} --keep -f \;

    ## Vendored JS
    # mkdir -p $out/www/assets/scripts
    # cp -r ./assets/scripts $out/www/assets
    # find $out/www/assets/scripts -name '*.js' -execdir brotli --best {} -f \;
    # find $out/www/assets/scripts -name '*.js' -execdir gzip --best --keep {} -f \;

    cp Caddyfile.prod $out/Caddyfile
    mv public/* $out/www
  '';
}
