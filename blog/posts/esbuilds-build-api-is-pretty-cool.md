---
title: "esbuild's build API is pretty cool"
created_at: 2025-04-19T12:56:17Z
updated_at: 2025-04-19T12:56:17Z
tags: ["esbuild", "sass", "javascript", "nix"]
cover: /assets/images/posts/esbuilds-build-api-is-pretty-cool/cover.jpg
custom:
    slug: esbuilds-build-api-is-pretty-cool
    summary: |
        Exploring the basics of esbuild's build API, to build SASS, CSS, and JS.
        As a sweet treat, how to package these all up with nix.
---

# {{ metadata.title }}

<div>
{% from "component/img.html" import img %}
</div>

<div>
{{ img(src=metadata.cover, alt="2 esbuild logo side by side in white and dark backgrounds") }}
</div>

<span class="post-metadata">
  {{ metadata.created_at|published_on(format="short") }}
</span>

<div>
{% from "component/tags.html" import tags %}
{{ tags(metadata.tags) }}
</div>

Happy new year (for this blog)! I know I'm 4 months late but hey, it's fine.

Lately I've been messing around with `scss` after experiencing a few paper cuts
with vanilla CSS. Being able to use variables in media queries, and having mixins
are quite nice to have. Using `sass` in your existing project is straightforward
because of its CLI, but I use `esbuild` for most of my pet projects for bundling
and/or minifying CSS/JS files. I'd rather not have to run two CLI programs just
to prepare everything for me. Running one `esbuild` script is just more convenient.

But first, a basic build file!

Run `npm init`, and add `esbuild` to your project's dependencies.

```json
// package.json
{
  "name": "foo",
  "version": "1.0.0",
  "main": "watch.js",
  "scripts": {
    "test": "echo \"Error: no test specified\" && exit 1"
  },
  "type": "module",
  "author": "",
  "license": "ISC",
  "description": "",
  "dependencies": {
    "esbuild": "^0.25.2",
  }
}
```

Then create our `esbuild` build file

```js
// build.js
import * as esbuild from 'esbuild'

let result = await esbuild.build({
    entryPoints: ["assets/**/*"],
    outdir: "public",
})
```

This watches the `assets` directory for any changes, and spits out the "final"
assets in the `public` directory as is. Nothing too interesting at the moment.

Then in the `package.json` file, add an entry to `scripts` that executes our
`esbuild` script:

```json
//package.json

// ...
"scripts": {
  "build": "node build.js", // new!
  "test": "echo \"Error: no test specified\" && exit 1"
},
// ...
```

Let's try running `npm run build` with this assets directory:

```sh
 4096 B    ┌─ style.css
 4096 B ┌─ css
 4096 B │  ┌─ script.js
 4096 B ├─ script
 4096 B │  ┌─ style.scss
 4096 B ├─ sass
12288 B assets
```

Well, I ran into this error:

```sh
> foo@1.0.0 watch
> node watch.js

✘ [ERROR] No loader is configured for ".scss" files: assets/sass/style.scss

./node_modules/esbuild/lib/main.js:1477
  let error = new Error(text);
              ^

Error: Build failed with 1 error:
error: No loader is configured for ".scss" files: assets/sass/style.scss
    at failureErrorWithLog (./node_modules/esbuild/lib/main.js:1477:15)
    at ./node_modules/esbuild/lib/main.js:946:25
    at ./node_modules/esbuild/lib/main.js:898:52
    at buildResponseToResult (./node_modules/esbuild/lib/main.js:944:7)
    at ./node_modules/esbuild/lib/main.js:971:16
    at responseCallbacks.<computed> (./node_modules/esbuild/lib/main.js:623:9)
    at handleIncomingPacket (./node_modules/esbuild/lib/main.js:678:12)
    at Socket.readFromStdout (./node_modules/esbuild/lib/main.js:601:7)
    at Socket.emit (node:events:518:28)
    at addChunk (node:internal/streams/readable:561:12) {
  errors: [Getter/Setter],
  warnings: [Getter/Setter]
}

Node.js v22.14.0
```

The error message does make sense. `esbuild` by default does not handle `scss`
files. I suppose it should only care about "native" web technologies so fair
enough. Fortunately, they have a `plugins` property in their API as well. Even
better, someone already wrote a loader for it!

```json
// package.json

// ...
"dependencies": {
  "esbuild-sass-plugin": "^3.3.1"
}
// ...
```

The `esbuild` API has a `plugins` key that allows us to specify callbacks whenever
the file matches the filter set by the plugin. For `esbuild-sass-plugin`, its
default pattern is `/.(s[ac]ss|css)$/` which in this case works just fine.

```js
import * as esbuild from 'esbuild'
import { sassPlugin } from 'esbuild-sass-plugin'

let ctx = await esbuild.build({
  entryPoints: ["assets/**/*"],
  outdir: "public",
  minify: true, // <-- 1
  treeShaking: true, // <-- 2
  plugins: [sassPlugin()],
}
```

> [!NOTE]
> 1 & 2 are not necessary but I just added it to show that you could do more stuff
> as well.

Runnng `npm run build` creates a `public` directory with our assets built, and
transformed by `esbuild`!

```
 4096 B    ┌─ style.css
 4096 B ┌─ css
 4096 B │  ┌─ script.js
 4096 B ├─ script
 4096 B │  ┌─ style.css
 4096 B ├─ sass
12288 B public
```


And we can verify this by taking a look at `./public/sass`

```css
.foo{color:#00f}@media (min-width: 40rem){.foo{color:red}}
```

## Packaging the build script with `nix`

The script has two dependencies: `esbuild`, and a `sass` loader plugin
`esbuild-sass-plugin`. I could use `npm install` to fetch these dependencies for
me (like a normal person) but I'm too far gone to do anything normally, and that's
no fun!

Create a `flake.nix` file with this:

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = { self, nixpkgs }: {
    devShells.x86_64-linux.default =
      let
        pkgs = import nixpkgs { system = "x86_64-linux"; };
      in pkgs.mkShell {
        buildInputs = with pkgs; [ nodejs_22 git ];
      };
  };
}
```

> If you're using platforms other than `x86_64-linux`, feel free to change it
> accordingly, or use `flake-utils`
> (but Isabel [will run after ya](https://bsky.app/profile/isabelroses.com/post/3ld4gbggzqs2l)).

There are lots of build tools for JS, probably a new one every 2 months. I don't
even know anymore. As a result, there are also lots of `nix` tools for it. But
I recently discovered [`pkgs.buildNpmPackage`](https://github.com/NixOS/nixpkgs/blob/master/doc/languages-frameworks/javascript.section.md#buildnpmpackage-javascript-buildnpmpackage),
and it was surprisingly simple so that's what we'll use here.

```nix
# flake.nix

  # ...
  outputs = { self, nixpkgs }: {
    packages.x86_64-linux.default =
      let
        pkgs = import nixpkgs { system = "x86_64-linux"; };
      in
        pkgs.buildNpmPackage {
          name = "foo-static";
          version = "1.0.0";
          src = ./.;
          npmDepsHash = "???";

          installPhase = ''
            mkdir $out
            npm run build
            cp -r public/ $out
          '';
        };
  # ...
```

`name`, `version`, and `src` are straightforward. But what's `npmDepsHash`?

According to the docs:

> `npmDepsHash`: The output hash of the dependencies for this project. Can be
> calculated in advance with `prefetch-npm-deps`.

Okay, nice. So I just need to add `prefetch-npm-deps` to the dev shell, and point
the `package-lock.json` to it.

```nix
# flake.nix

# ...
buildInputs = with pkgs; [ prefetch-npm-deps nodejs_22 git ];
# ...
```

And run it

```sh
$ prefetch-npm-deps package-lock.json
sha256-xF5hnIqw3atLZCa8H88sVOF8nrHXH5Qfh9I1mfTpFvo=
```

```nix
# flake.nix

  # ...
  outputs = { self, nixpkgs }: {
    packages.x86_64-linux.default =
      let
        pkgs = import nixpkgs { system = "x86_64-linux"; };
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
  # ...
```

Now we can run `nix build`, which gets us this:

```sh
 4096 B       ┌─ style.css
 4096 B    ┌─ css
 4096 B    │  ┌─ script.js
 4096 B    ├─ script
 4096 B    │  ┌─ style.css
 4096 B    ├─ sass
12288 B ┌─ public
12288 B qydjw7ghmmz46lpcfa6sf4jj6sisl36z-foo-static
```

So now I'm able to use these as a dependency of another `nix` derivation. Neat!

> If you would like to check out the final result of everything in this article,
> you may find it under the [`examples/esbuild-build-api`](https://github.com/sekunho/sekun.net/tree/main/examples/esbuild-build-api) directory.
