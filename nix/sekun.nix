{ pkgs, version, system, puggle, minhtml }: pkgs.stdenv.mkDerivation {
  inherit version;
  name = "sekun";
  src = ../.;
  buildInputs = [ ];
  nativeBuildInputs = with pkgs; [ esbuild gzip puggle brotli imagemagick minhtml ];

  buildPhase = ''
    mkdir $out

    # HTML
    puggle build
    find public -name '*.html' -execdir minhtml --keep-closing-tags --minify-js --minify-css {} --output {} \;
    find public -name '*.html' -execdir brotli --best {} -f \;

    # Images
    mkdir -p $out/assets/images
    cp -r assets/images $out/assets

    ## favicons
    find $out/assets/images -name 'apple-*.png' -execdir mogrify -sampling-factor 4:2:0 -strip -quality 35 -interlace JPEG -colorspace gray -format jpg {} \;
    find $out/assets/images -name 'favicon-*.png' -execdir mogrify -sampling-factor 4:2:0 -strip -quality 35 -interlace JPEG -colorspace gray -format jpg {} \;


    ## Other images
    # find $out -name '*.jpg' -execdir mogrify -sampling-factor 4:2:0 -strip -quality 85 -interlace JPEG -colorspace RGB -format jpg {} \;
    # find $out -name '*.png' -execdir mogrify -strip {} \;
    # find $out -name '*.webp' -execdir mogrify -quality 5 -strip {} \;

    find $out -name 'hiro-alt.webp' -execdir mogrify \
      -colorspace gray -quality 75 -resize 60% -strip {} \;

    ## Post images
    find $out/assets/images/posts -name 'cover.*' -execdir mogrify \
      -quality 75 -resize 1280x720 -strip -format webp {} \;

    # CSS
    mkdir -p $out/assets/css
    esbuild ./assets/css/*.css --minify --outdir=$out/assets/css
    esbuild ./assets/css/**/*.css --minify --outdir=$out/assets/css
    find $out/assets/css -name '*.css' -execdir brotli --best {} -f \;

    mv public/* $out
  '';
}
