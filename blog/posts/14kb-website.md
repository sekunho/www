---
title: "14kb website"
created_at: 2025-08-26T18:36:52Z
updated_at:
tags: []
cover:
custom:
    slug: 14kb-website
---

# 14kb website

<div>
{% from "component/img.html" import img %}
</div>

<span class="post-metadata">
  {{ metadata.created_at|published_on(format="short") }}
</span>

I recently read this ["Why your website should be under 14kb in size"](https://endtimes.dev/why-your-website-should-be-under-14kb-in-size/)
explaining exactly what it says in the tin, and found it to be an interesting read.
Though it does not exactly get into that much detail on what strategies you could
take to reduce it. So I'll be exploring some approaches on reducing page sizes.

Starting off with my static blog! So this is what I'm dealing with here:

<div>
{{ img(src="/assets/images/posts/14kb-website/blog-requests.png", alt="hi") }}
</div>

Well. ~290kb for a static website is pretty bad considering there aren't that
much files here. It's a rather simple website, and I'm surprised it's even this
big. Taking a closer look, the bulk of it comes from fonts followed by images,
stylesheets, and the main document. The good news is that the fonts don't block
the browser from rendering the document but it's still not that great to see
3 digits in kb for this.

Fortunately, I was able to remove the need for `hljs` not too long ago after
implementing a [highlighter for puggle](https://github.com/sekunho/puggle/commit/686a0ba8685c9790b83813e85b5ea2c8330d4573),
which reduced the page size quite a bit.

Some actionable points:

1. Reduce document size further: it's already ~3kb but there's still room for
further optimization though not that much.
2. Use a more web optimized image codec instead of PNGs; and
3. Ditch Jetbrains Mono!

## Minifying the HTML document

Although the document is already being compressed by the CDN using `zstd`, we
could shave off a few in size by minifying the document. We don't exactly need
this to be presented for humans to read since the browser already parses HTML
and presents them in an interactive way through your browser's dev tools.

The way my website is built is I wrote it as a `nix` package which uses `esbuild`,
`gzip`, and `puggle` to turn my markdown files into boring HTML documents.

```nix
{ pkgs, version, system, puggle }: pkgs.stdenv.mkDerivation {
  inherit version;
  name = "sekun";
  src = ../.;
  buildInputs = [ ];
  nativeBuildInputs = with pkgs; [ esbuild gzip puggle ];

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
  '';
}
```

It's not exactly the best, and using the CLI is rather restrictive since we're only
allowed to perform operations that it comes out of the box. If I need to extend
`esbuild` to include minifying HTML files, or compressing them into `.gzip`, I
would have to run them after the main build process which makes things feel like
they're all over the place.

`esbuild` offers a build API which allows us to extend your pipeline of transformations.
I wrote a short blog post about it ["esbuild's build API is pretty cool"](/blog/esbuilds-build-api-is-pretty-cool/) which also includes integrating stuff with `nix`. Kind of
ironic because I used it for another project, and not for my blog. Let's change
that.

> You could read the aforementioned blog post if you need more details but to keep
> it short, `esbuild` needs a simple JS project with an entrypoint file that imports
> all the dependencies needed to execute the build.

### Consolidating the build pipeline

Unfortunately for me, I couldn't find a plugin for this so I wrote a simple one.
