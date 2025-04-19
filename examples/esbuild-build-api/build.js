import * as esbuild from 'esbuild'
import { sassPlugin } from 'esbuild-sass-plugin'

let ctx = await esbuild.build({
  entryPoints: ["assets/**/*"],
  outdir: "public",
  minify: true,
  treeShaking: true,
  plugins: [sassPlugin()],
})
