---
title: "Create Rust binaries, and Docker images with Nix"
created_at: 2022-04-11T06:20:00Z
updated_at: 2024-10-19T14:21:52Z
tags: ["nix", "emojied", "docker", "rust", "github actions"]
cover: "/assets/images/posts/create-rust-binaries-and-docker-images-with-nix/cover.png"
aliases:
    - create-static-binaries-and-docker-images-with-nix
custom:
    slug: create-rust-binaries-and-docker-images-with-nix
    summary: |
        While it did simplify things such as dependency management across different
        environments, and the deploy process, setting up is pretty complicated. I had
        to look through different references and the Nix matrix channel just to find a
        description of an attribute. Things aren't as well-documented but there's a lot
        of community effort to make this less painful.
---

# Create Rust binaries, and Docker images with Nix

<div>
{% from "component/img.html" import img %}
</div>

<div>
{{ img(src=metadata.cover, alt="Nix logo with arrows pointing from it to the Rust logo, and the Docker logo") }}
</div>

<span class="post-metadata">
  {{ metadata.created_at|published_on(format="short") }}
</span>

## Introduction

A few days ago, I [released](/posts/what-i-learned-from-building-a-rust-emoji-url-shortener)
~~the abomination of~~ a project called `emojied`
([website](https://emojied.net), [repo](https://github.com/sekunho/emojied)) to
the world. It went great, I'm glad people found it funny. However, I'm not too
pleased with the deployment process: from building the project to shipping it.
I made heavy use of Docker to build the necessary static assets, and binary.

Here's the current setup:

* Dev environment
    * PostgreSQL (handled by NixOS)
    * `rustc`, `openssl`, `cargo`, etc. (handled by Nix)
* CI/CD (GitHub Actions)
    1. Build static assets (just in GitHub Actions)
    2. Build static binary (Docker, `ekidd/rust-musl-builder`)
    3. Build prod image (Docker, `alpine`)

I've already tried to remove as much responsibility from \#3 by building the
static assets, and binary beforehand; I really need to do is copy it over.
\#2 is where the pain is because it does not reuse the dependencies from \#1.
So, I have two options here:

1. Use Docker for everything, but this complicates my dev environment cause now
I have to deal with containers; or
2. I use Nix for everything, including constructing the prod image.

I dislike the idea of using containers if all you want is reproducibility
because it seems like an overkill. It's annoying to setup volumes, annoying to
manage permissions, annoying to wait for it to pull an entire image. On the other
hand, while Nix is pretty difficult, it seems like a saner approach for what I
want to do, so I chose it.

So, here's how it went. (Spoiler: Kinda painful to setup)

## Starting point

This is the starting flake file:

```nix
{
  description = "";

  inputs = {
    # 1
    nixpkgs.url = "github:NixOS/nixpkgs";

    # Like `nixpkgs` but more bleeding-edge
    nixos-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    # 2
    flake-utils.url = "github:numtide/flake-utils";

    # 3
    naersk.url = "github:nix-community/naersk";
  };

  outputs = { self, nixpkgs, nixos-unstable, flake-utils, naersk }:
    flake-utils.lib.eachSystem [ "x86_64-linux" ] (system:
      let pkgs = nixpkgs.legacyPackages.${system};
           naersk-lib = naersk.lib."${system}".override {
             cargo = pkgs.cargo;
             rustc = pkgs.rustc;
           };
      in rec {
        # Build binary
        packages.emojied = naersk-lib.buildPackage {
          pname = "emojied";
          root = ./.;
        };

        # The package that gets built when I run `nix build`
        defaultPackage = packages.emojied;

        apps.emojied = flake-utils.lib.mkApp {
          drv = packages.emojied;
        };
      });
}
```

1. [`nixpkgs`](https://nixos.wiki/wiki/Nixpkgs) is like a package repository.
This is where you get `rustc`, `cargo`, etc. for example.
2. [`flake-utils`](https://github.com/numtide/flake-utils) just makes dealing
with flakes a bit more convenient, especially with multiple OSes (only doing
Linux for now).
3. [`naersk`](https://github.com/nix-community/naersk) makes it easier to build
static Rust binaries.

These are all _inputs_, where everything in the `outputs` field is sourced
from. `outputs` is where everything gets packaged. Another thing is, to help
with reproducibility, it pins these inputs to a specific GitHub commit via a
lock file. So no version numbers, but down to the commit. This is how projects
can be built in the future in the exact same way as now.

If you peek into `flake.lock`, you'll find something like this:

```
"naersk": {
  "inputs": {
    "nixpkgs": "nixpkgs"
  },
  "locked": {
    "lastModified": 1649096192,
    "narHash": "sha256-7O8e+eZEYeU+ET98u/zW5epuoN/xYx9G+CIh4DjZVzY=",
    "owner": "nix-community",
    "repo": "naersk",
    "rev": "d626f73332a8f587b613b0afe7293dd0777be07d",
    "type": "github"
  },
  "original": {
    "owner": "nix-community",
    "repo": "naersk",
    "type": "github"
  }
},
"nixpkgs": {
  "locked": {
    "lastModified": 1648219316,
    "narHash": "sha256-Ctij+dOi0ZZIfX5eMhgwugfvB+WZSrvVNAyAuANOsnQ=",
    "owner": "NixOS",
    "repo": "nixpkgs",
    "rev": "30d3d79b7d3607d56546dd2a6b49e156ba0ec634",
    "type": "github"
  },
  "original": {
    "id": "nixpkgs",
    "type": "indirect"
  }
}
```

There are more stuff in it, but hopefully this will make things a bit clearer.

That's the best ELI5 I can think of, so I recommend you check out the
[documentation](https://nixos.wiki/wiki/Flakes) for a more technical explanation.

So, I run `nix build` and...

## Problem 0: OpenSSL

Bam.

```
error: builder for '/nix/store/pv9szkam1rawk40ywp3v89k53zg4b1l4-emojied-deps-0.1.0.drv' failed with exit code 101;
       last 10 log lines:
       >   It looks like you're compiling on Linux and also targeting Linux. Currently this
       >   requires the `pkg-config` utility to find OpenSSL but unfortunately `pkg-config`
       >   could not be found. If you have OpenSSL installed you can likely fix this by
       >   installing `pkg-config`.
       >
       >   ', /sources/openssl-sys-0.9.72/build/find_normal.rs:180:5
       >   note: run with `RUST_BACKTRACE=1` environment variable to display a backtrace
       > warning: build failed, waiting for other jobs to finish...
       > error: build failed
       > [naersk] cargo returned with exit code 101, exiting
       For full logs, run 'nix log /nix/store/pv9szkam1rawk40ywp3v89k53zg4b1l4-emojied-deps-0.1.0.drv'.
error: 1 dependencies of derivation '/nix/store/r0h49v7i2vg5dckb9h2g8p7na048rk4g-emojied-0.1.0.drv' failed to build
```

I've seen this error before! Since `emojied` uses `native-tls`, and since it's
just a wrapper around OpenSSL, I need to have OpenSSL around. Thankfully,
`naersk` has a `buildInputs` attribute for us to use.

```nix
packages.emojied = naersk-lib.buildPackage {
  pname = "emojied";
  root = ./.;
  buildInputs = with pkgs; [ openssl pkg-config ];
};
```

Ran `nix build`, and I'm greeted with another problem!

## Problem 1: `git` submodule woes

```
Compiling maud_macros v0.23.0 (https://github.com/lambda-fairy/maud?branch=main#e6787cd6)
error: could not compile `maud_macros` due to 3 previous errors
warning: build failed, waiting for other jobs to finish...
error: build failed
error[E0583]: file not found for module `escape`
 --> /sources/maud_macros-0.23.0-e6787cd62165a075c7f16a32f8bbacc398f52d13/src/lib.rs:9:1
  |
9 | mod escape;
  | ^^^^^^^^^^^
  |
  = help: to create the module `escape`, create file "/nix/store/shixfmbv64zzi9i0rzb9c8870ydm7cf2-crates-io/maud_macr>


error[E0425]: cannot find function `escape_to_string` in module `escape`
   --> /sources/maud_macros-0.23.0-e6787cd62165a075c7f16a32f8bbacc398f52d13/src/generate.rs:272:17
    |
272 |         escape::escape_to_string(string, &mut self.tail);
    |                 ^^^^^^^^^^^^^^^^ not found in `escape`


error: aborting due to 2 previous errors


Some errors have detailed explanations: E0425, E0583.

For more information about an error, try `rustc --explain E0425`.

[naersk] cargo returned with exit code 101, exiting
```

It's telling me that `cargo` can't resolve the `escape` module for `maud_macros`.
I took a look at the [source](https://github.com/lambda-fairy/maud/tree/main/maud_macros/src),
and initially seemed like it's a submodule:

<div>
{{ img(src="/assets/images/posts/create-rust-binaries-and-docker-images-with-nix/maud-dir.png", alt="Screenshot of maud's GitHub repository") }}
</div>

Turns out there's a ticket ([#110](https://github.com/nix-community/naersk/issues/110))
pointing out that submodules isn't supported by `naersk`. Fortunately, by the
time I read this, there was a PR ready that fixed this. All it required was
adding `gitSubmodules = true;`:

```nix
packages.emojied = naersk-lib.buildPackage {
  pname = "emojied";
  root = ./.;
  gitSubmodules = true;
};
```

So this fixes everything then, right?

Wrong.

## Problem 2: Symlink woes

Remember how I said it was a submodule? Well, it turns out that `escape.rs` is
actually a symlink (the icons look too similar!). `cargo` handles it just fine
so running `cargo build` will work out. But this isn't the case for `naersk`. I
couldn't find any issue talking about symlinks so I opened one
([#230](https://github.com/nix-community/naersk/issues/230)). Unfortunately, I
had no idea how to fix it, so I just decided to manually clone it, and remove
the symlink for a copy instead. It's only one file, so it isn't that big of a
deal.

Kind of a hack, but it works now! A binary is available in `./result/bin/`,
albeit a symlink. I ran it with:

```sh
PG__DBNAME="emojied_db" PG__HOST="localhost" PG__USER="sekun" PG__PORT="5432" \
  ./result/bin/emojied
```

...and I was greeted with this unstyled page:

<div>
{{ img(src="/assets/images/posts/create-rust-binaries-and-docker-images-with-nix/no-static-assets.png", alt="Unstyled emojied.net frontpage") }}
</div>

## Problem 3: Static assets

`emojied` is comprised of two things: a server binary, and static assets. These
static assets are built using `tailwindcss`'s CLI, and `esbuild`... which was
not handled by `naersk`. It does not seem to provide an escape hatch, which
makes sense anyway cause it would be kinda weird to do things unrelated to Rust
in a Rust builder.

Now what?

Well, I found out about `overrideAttrs` and it is wonderful.

```nix
{
  # ...

  outputs = { self, nixpkgs, nixos-unstable, flake-utils, naersk }:
    flake-utils.lib.eachSystem [ "x86_64-linux" ] (system:
      let pkgs = nixpkgs.legacyPackages.${system};
          unstablepkgs = nixos-unstable.legacyPackages.${system};
          naersk-lib = naersk.lib."${system}".override {
            cargo = pkgs.cargo;
            rustc = pkgs.rustc;
          };

          # I moved it up here so I could bind it to `emojied`.
          emojied = (naersk-lib.buildPackage {
            pname = "emojied";
            root = ./.;
            nativeBuildInputs = with pkgs; [ ];
            buildInputs = with pkgs; [ openssl pkg-config ];
          }).overrideAttrs (old: {
            # I get access to `old` which has the previous attributes.
            # And I get to override anything!

            nativeBuildInputs = old.nativeBuildInputs ++ [
              unstablepkgs.nodePackages.typescript
              unstablepkgs.nodePackages.tailwindcss
              unstablepkgs.esbuild
            ];

            buildInputs = old.buildInputs;

            buildPhase = old.buildPhase + ''
              tailwindcss \
                --input assets/app.css \
                --config assets/tailwind.config.js \
                --output public/app.css \
                --minify

              esbuild \
                assets/app.ts \
                --outdir=public/ \
                --minify
            '';

            installPhase = old.installPhase + ''
              mv public $out/bin
              mv bin/run $out/bin/run
            '';
          });
      in
      rec {
        packages.emojied = emojied;
        defaultPackage = packages.emojied;

        apps.emojied = flake-utils.lib.mkApp {
          drv = packages.emojied;
        };
      });
}
```

I removed `gitSubmodules = true` since it wasn't necessary anymore. `buildPackage`
just spits out an attribute set, I can override it to add more things. Here, I
added new native build inputs (build time), new steps to `buildPhase`, and
`installPhase` for the static assets.

And I ran it like this:

```sh
cd result/bin

PG__DBNAME="emojied_db" PG__HOST="localhost" PG__USER="sekun" PG__PORT="5432" \
  ./emojied
```

<div>
{{ img(src="/assets/images/posts/create-rust-binaries-and-docker-images-with-nix/has-static-assets.png", alt="STyled emojied.net frontpage") }}
</div>

Beautiful.

Okay, so that seems to work but I have to run `emojied` in the same directory as
`public/` cause otherwise it won't find anything. Which is expected because:

```rust
pub async fn stylesheet() -> (StatusCode, HeaderMap, String) {
    let mut headers = HeaderMap::new();

    match fs::read_to_string("public/app.css") {
                           // ^ Relative path. Good job me!
        Ok(content) => {
            headers.insert(
                HeaderName::from_static("content-type"),
                HeaderValue::from_static("text/css; charset=utf-8"),
            );

            (StatusCode::OK, headers, content)
        }

        Err(_e) => (StatusCode::NOT_FOUND, headers, String::from("Not found")),
    }
}
```

I'm using relative paths! But other than that, it works. It's not exactly an issue
for the way I'm using it, which is:

1. Build the binary
2. Build static assets
3. Copy files from \#1 and \#2, and throw it into an image.

But with `nix run`, it gives me broken styles again. I don't want it to depend
on where I run it! So. Close.

## Problem 4: Making it work™

So the problem is that the file paths are relative which makes it depend on
where I run the binary. The plan then is to provide the static asset directory
path during runtime!

This way it's flexible enough to:

1. Ship off to a Docker image; and
2. Use `nix run` without breaking anything.

Something like this would be nice:

```
PG__DBNAME="emojied_db" \
PG__HOST="localhost" \
PG__USER="sekun" \
PG__PORT="5432" \
APP__STATIC_ASSETS="/foo/bar/public/" \
  ./emojied
```

I added another field to `AppConfig`, and checked if there's an argument called
`static_assets_path`:

```rust
// src/config.rs

struct AppConfig {
    // ...
    pub static_assets_path: String // See disclaimer below
}
```

Loaded it from the environment:

```rust
// src/config.rs

let static_assets_path = env::var("APP__STATIC_ASSETS")
    .map_err(|_| Error::MissingStaticAssetsPath)?;

// ...

Ok(AppConfig {
    // ...
    static_assets_path, // New!
})
```

Add `AppConfig` to the middleware:

```rust
// ...
let config = Arc::new(config);

let app = Router::new()
    // ...
    .layer(Extension(config));
```

And in the functions serving the files:

```rust
pub async fn js(
    Extension(config): Extension<Arc<AppConfig>> // New
) -> (StatusCode, HeaderMap, String) {
    let mut headers = HeaderMap::new();
    let mut static_assets_path = config.static_assets_path.clone(); // New

    static_assets_path.push_str("public/app.js"); // New

                          // Shiny, new path
    match fs::read_to_string(static_assets_path) {
        Ok(content) => {
            headers.insert(
                HeaderName::from_static("content-type"),
                HeaderValue::from_static("application/javascript; charset=utf-8"),
            );

            (StatusCode::OK, headers, content)
        }

        Err(_e) => (StatusCode::NOT_FOUND, headers, String::from("Not found")),
    }
}
```

...which I then repeated in 2 more functions because I was too lazy to make one
endpoint for static assets. Now, I feel the pain of my laziness.

> Disclaimer: Before you come after me with pitchforks, I later did a tiny
> refactor which uses `PathBuf` rather than a `String`.

Okay, but then I still need a way to set the environment variable automatically,
right? Currently, it's not very convenient to do it every time it's called with
`nix run`. Turns out [`makeWrapper`](https://nixos.wiki/wiki/Nix_Cookbook) exists.
(Thanks K900!)

```nix
{
  # ...

        packages.emojied-unwrapped = emojied;


        # New
        packages.emojied = pkgs.symlinkJoin {
          name = "emojied";
          paths = [ emojied ];
          buildInputs = [ pkgs.makeWrapper ];

          postBuild = ''
            wrapProgram $out/bin/emojied \
              --set APP__STATIC_ASSETS "${emojied}/bin/public"
                                      # ^ What a convenient way to get the path
          '';
        };

  # ...
}
```

So I'll get the "wrapped" version of emojied with `nix build`, which has the
static assets path already applied. Doing so gets me this:

```
sekun@nixos ~/P/emojiurl (chore/nixify-package)> nix build
sekun@nixos ~/P/emojiurl (chore/nixify-package)> ls -la result/bin
total 20
dr-xr-xr-x 3 root root 4096 Jan  1  1970 .
dr-xr-xr-x 3 root root 4096 Jan  1  1970 ..
-r-xr-xr-x 1 root root  264 Jan  1  1970 emojied
lrwxrwxrwx 1 root root   69 Jan  1  1970 .emojied-wrapped -> /nix/store/7nh13gwhhlmfmmb6qss47axj7nd99jw7-emojied-0.1.0/bin/emojied
dr-xr-xr-x 2 root root 4096 Jan  1  1970 public

sekun@nixos ~/P/emojiurl (chore/nixify-package)> ls -la
# ...
lrwxrwxrwx  1 sekun users      51 Apr 12 22:55 result -> /nix/store/300n6rjxm88asmqhv99hid9mi8148xjs-emojied
#...
```

So, it symlinked `.emojied-wrapped` to the original `emojied`, and `result` is
symlinked to a wrapped version of it. Is this another derivation? Seems like it,
although I don't really know since I'm not so familiar with this. I'll have to
do more reading. I'm just gonna manually test it to verify if it all works.
`.#emojied-unwrapped` needs to complain about the missing assets path if I don't
provide one, and `.#emojied` shouldn't.

```sh
sekun@nixos ~/P/emojiurl (chore/nixify-package)> PG__DBNAME="emojied_db" PG__HOST="localhost" PG__USER="sekun" PG__PORT="5432" nix run .#emojied-unwrapped
Loading configuration from environment
Application config error: Missing environment variable: `APP__STATIC_ASSETS=<PATH_TO_FILES>`

sekun@nixos ~/P/emojiurl (chore/nixify-package) [1]> PG__DBNAME="emojied_db" PG__HOST="localhost" PG__USER="sekun" PG__PORT="5432" nix run
Loading configuration from environment
Attempting to establish a database connection
Database connection established
```

...and it works as expected. The second one also serves the static assets
just fine! Hooray.

## Problem 5: Copy all that to a Docker image

The final step is copying what was built by Nix to a Docker image. I'm currently
using a `Dockerfile` for that but this won't work with this new setup. The problem
now is that Docker doesn't resolve symlinks that point outside the context, which
is problematic since `result` is a symlink that points to some place in `/nix/store`!
I could do some dirty hacks, but I could also just use Nix to build a Docker
image for me.

_Wait, did you say Nix could build Docker images?_

Oh yeah, big time; [`nix.dev`](https://nix.dev/tutorials/building-and-running-docker-images)
has a great starting point [^9] for doing so.

Here's what I ended up with:

```nix
# flake.nix

# ...

# In `outputs`
packages.emojied-docker = pkgs.dockerTools.buildImage {
  name = "emojied-docker";
  tag = "latest";

  contents = [ pkgs.bash ];

  config = {
    WorkingDir = "/app";
    Env = [ "PATH=${pkgs.coreutils}/bin/:${packages.emojied}/bin" ];

    ExposedPorts = {
      "3000/tcp" = {};
    };

    # bin/run is a script that handles the dumping of CA certs, and runs the
    # emojied server.
    Cmd = [ "${packages.emojied}/bin/run" ];
  };
};
```

If you squint hard enough, the contents of `config` just looks like a Nix version
of a `Dockerfile`, which it is! The other cool part is now the package versions
are in sync no matter what environment it is in. `contents` allows me to throw
in Nix packages to the image. Since it seemed like the `PATH`s aren't set automatically,
I had to specify it in `Env` for `coreutils`, and `emojied`.

It's basically like the other packages created, like `emojied`, and
`emojied-unwrapped`. Which means I can build it in the exact same way as them:


```sh
# Don't mind the branch change. I ran this in the morning.
sekun@nixos ~/P/emojiurl (main)> nix build .#emojied-docker
# some build-related output

sekun@nixos ~/P/emojiurl (main)> ls -la
# ...
lrwxrwxrwx  1 sekun users      78 Apr 13 12:28 result -> /nix/store/vmrja5imhrfhvl082j5qkqahcfj85adk-docker-image-emojied-docker.tar.gz
# ...
```

Instead, `result` is a symlink to some image tar file which you can load with
`docker load < result`.

```sh
sekun@nixos ~/P/emojiurl (main)> docker load < result
Loaded image: emojied-docker:latest

sekun@nixos ~/P/emojiurl (main)> docker images
# ...
emojied-docker latest 1a9092013b19 52 years ago 50MB
```

Sweet!

All that's left is to update the CI for these new steps, which is on the simpler
side of things now:

```yml
name: CI/CD

on:
  push:
    branches:
      - main

jobs:
  deploy:
    name: Build release and deploy
    runs-on: ubuntu-20.04

    steps:
      - name: Checkout repo
        uses: actions/checkout@v2

      - name: Setup Nix
        uses: cachix/install-nix-action@v15

      - name: Login to Docker Hub
        uses: docker/login-action@v1
        with:
          username: {% raw %}${{ secrets.DOCKER_HUB_USERNAME }}{% endraw %}
          password: {% raw %}${{ secrets.DOCKER_HUB_PASSWORD }}{% endraw %}

      - name: Build image
        run: |
          nix build .#emojied-docker
          docker load < result

      - name: Rename image
        run: docker tag emojied-docker:latest hsekun/emojied:latest

      - name: Push image
        run: docker push hsekun/emojied:latest
```

It's just so much easier, and I have more confidence that the CI will work
as intended now that Nix is handling the important parts, which I can do
locally. Not to say that Docker can't do the same thing, but I found that there
were some differences with volumes that made it painful to debug.

<div>
{{ img(src="/assets/images/posts/create-rust-binaries-and-docker-images-with-nix/sweet-green-gh-actions.png", alt="A screenshot of a GitHub actions job") }}
</div>

## Conclusion

While it did simplify things such as dependency management across different
environments, and the deploy process, setting up is pretty complicated. I had
to look through different references and the Nix matrix channel just to find a
description of an attribute. Things aren't as well-documented but there's a lot
of community effort to make this less painful.

Edit (April 24, 2022): Turns out that it actually isn't a static binary, and
I've modified the post accordingly. The upside is building the Docker image via
Nix with `emojied` in it means it's somewhat irrelevant to require it to be a
static binary to begin with. But it does mean I can't easily distribute it outside
`nix`, which is a bummer. Maybe I'll hunt for a workaround in the future. Right
now, I'm not too keen into sinking a lot of time into something I won't benefit
from.
