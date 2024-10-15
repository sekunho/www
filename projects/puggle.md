---
title: puggle
created_at: 2024-06-29T06:15:51Z
updated_at:
summary: A simple, and flexible static site generator
cover: "/assets/images/projects/puggle/cover.png"
tags: ["rust", "jinja2"]
---

# [ANN] puggle v0.1 - yet another static site generator

[GitHub](https://github.com/sekunho/puggle)

<figure>
    <img src="{{ metadata.cover }}" alt="A drawing of an ant eater" />
    <figcaption>
        Anteater from Im australischen Busch und an den Küsten des Korallenmeeres. Reiseerlebnisse und Beobachtungen eines Naturforschers in Australien, Neu Guinea und den Molukken (1866) -
        <a href="https://creazilla.com/media/traditional-art/3446271/anteater-from-im-australischen-busch-und-an-den-kusten-des-korallenmeeres.-reiseerlebnisse-und-beobachtungen-eines-naturforschers-in-australien-neu-guinea-und-den-molukken-1866-published-by-richard-wolfgang-semon.">Source</a>
    </figcaption>
</figure>

`puggle` is a site generator for when you wish to turn your markdown files into
a bunch of HTML pages.


## Features

- **Flexible.** It doesn't fully rely on a [directory-based](https://gohugo.io/getting-started/directory-structure/)
structure to generate pages. Instead, pages are explicitly defined in the config file.
- **Expressive.** You may use control flow, conditionals, loops, or even embed
other templates into your markdown files.
- **Portable binary**. Just download `puggle` binary, and puggle away!

> "Fun" fact: This started off as a module in [`site`](https://github.com/sekunho/sekun.net)
but then it became more clear to me that it could be its own project. I couldn't
find a name for it so I ended up using a term I learned about recently &mdash;
_puggle_.

## Quick start

A `puggle` project starts with a configuration file `puggle.yml`. This config
file allows us to define the pages we want to have for our static site.

```yaml
# ./puggle.yml
templates_dir: templates
dest_dir: dist

pages:
  - name: blog
    template_path: layout/blog.html
```

Here we defined a page called `blog`, as well as the relative path to the template
that it should use. This template will be used to generate the HTML file for our
blog page.

We also specified our templates directory. This is the base path of all
`template_path`s. So in our example, the actual relative path `puggle` will use
is `./templates/layout/blog.html`.

Next, let's create our blog page's template.

```html
<!-- ./templates/layout/blog.html -->
<!DOCTYPE html>
<html>
  <head>
    <title>Blog</title>
  </head>

  <body>
    Welcome to my blog.
  </body>
</html>
```

Running `puggle build` would create the following:

```
dist
└─ blog
   └─ index.html
```

...with an `dist/blog/index.html`

```html
<!-- ./dist/blog/index.html -->
<!DOCTYPE html>
<html>
  <head>
    <title>Blog</title>
  </head>

  <body>Welcome to my blog.</body>
</html>
```

This is not very interesting though because we want to have posts in our blog.
We also want our template to be slightly different from our main blog page.
So let's create some entries!

`puggle` has two ways of sourcing page entries:

1. Fetch every single markdown file in a specific directory, recursively; and
2. Referencing the markdown file directly.

Let's update our `puggle.yml`.

```yaml
# ./puggle.yml
templates_dir: templates
dest_dir: dist

pages:
  - name: blog
    template_path: layout/blog.html

    entries:
      - source_dir: blog/posts
        template_path: layout/post.html
```

Here we're defining our source directory for our blog's entries to be `./blog/posts`.
`puggle` will search for every single markdown file under that directory.

Then create `./blog/posts/first.md`

```md
<!-- ./blog/posts/first.md -->
---
title: First post
summary: For my first blog post, I shall...
cover: "/assets/images/post_cover.jpg"
created_at: 2024-06-29T17:29:00Z
updated_at:
tags: ["hello", "world"]
---

# First post

Hello, world!
```

> 💡 You'll notice a YAML-style metadata block at the top of the markdown file,
> and this is what allows you to do some pretty cool things with `puggle`. For
> now, just think of it as potentially useful data that we could use.
>
> Here's a quick rundown:
>
> - `title` (required): Used to label your page entry's title. You can use this to
> index a page's entries.
> - `created_at` (required): UTC timestamp of when the page was created. e.g `2024-06-29T17:29:00Z`
> - `updated_at` (can be left blank): UTC timestamp of when the page was updated. e.g `2024-06-29T17:29:00Z`
> - `tags` (required): A list of strings. You may define this as an empty list. e.g `["nixos", "rust"]`

And a template for our blog's entries

```html
<!-- ./templates/layout/post.html -->
<!DOCTYPE html>
<html>
  <head>
    <title>Blog Post</title>
  </head>

  <body>
    {% raw %}{% block content %}{% endblock %}{% endraw %}
  </body>
</html>
```

The `{% raw %}{% block content %}{% endblock %}{% endraw %}` defines a `block`
statement for us to inject content into it. `puggle` requires the content block
to be present in the entry template otherwise it would have nowhere to inject
the generated HTML file into, and would result in a blank HTML file.

`puggle build` would then create the following:

```
dist
└─ blog
   ├─ first
   │  └─ index.html
   └─ index.html
```

...with an `dist/blog/first/index.html`

```html
<!-- ./dist/blog/first/index.html -->
<!DOCTYPE html>
<html>
  <head>
    <title>Blog</title>
  </head>

  <body>
    <h1>First post</h1>
    <p>Hello, world!</p>
  </body>
</html>
```

### Page entry metadata

Metadata provides a lot of flexibility for you to inject data into your templates,
or markdown files.

Therefore changing our blog entry to

```md
<!-- ./blog/posts/first.md -->
---
title: First post
summary: For my first blog post, I shall...
cover: "/assets/images/post_cover.jpg"
created_at: 2024-06-29T17:29:00Z
updated_at:
tags: ["hello", "world"]
---

# {{ metadata.title }}

Hello, world!
```

Would give us the same result because `puggle` understands that we're referencing
the `title` attribute defined in the entry's metadata. `puggle` also allows you
to use _all_ page entries' metadata in other pages.

The entry's template file can also reference the entry's metadata so you could
set the `title` tag to our entry title for example.

```html
<!-- ./templates/layout/post.html -->
<!DOCTYPE html>
<html>
  <head>
    <title>{{ metadata.title }} - Blog</title>
  </head>

  <body>
    {% raw %}{% block content %}{% endblock %}{% endraw %}
  </body>
</html>
```

> You can't reference metadata attributes in a page entry from another entry
> because each entry can only know about its own metadata.

Let's index our blog's entries in our blog page!

```html
<!-- ./templates/layout/blog.html -->
<!DOCTYPE html>
<html>
  <head>
    <title>Blog</title>
  </head>

  <body>
    Welcome to my blog.

    {% raw %}{% for page_name, page_entries in sections|items %}
      {% if page_name == "blog" %}
        <ul>
          {% for entry in entries %}
            <li>{{ entry.created_at|dateformat(format="short") }} - {{ entry.title }}</li>
          {% endfor %}
        </ul>
      {% endif %}
    {% endfor %}{% endraw %}
  </body>
</html>
```

Would result in this HTML page

```html
<!-- ./dist/blog/index.html -->
<!DOCTYPE html>
<html>
  <head>
    <title>Blog</title>
  </head>

  <body>
    Welcome to my blog.

    <ul>
      <li>2024-06-29 - First post</li>
    </ul>
  </body>
</html>
```

## Conclusion

I think `puggle` is pretty simple, and in a way, limited in what it can do. But
it's flexible, and expressive enough especially thanks to `jinja2`, specifically
[`mitsuhiko/minijinja`](https://github.com/mitsuhiko/minijinja). This entire site
uses `puggle`! Perhaps, in the future, I could extend `puggle` a bit more to be
easier to work with.

<hr>

Here's the `puggle.yml` complete manifest.

```yaml
# puggle.yml

## Relative or absolute path to your templates' root directory.
templates_dir: <DIR_PATH>

## Relative or absolute path to the directory you want the HTML pages to be.
dest_dir: <DIR_PATH>

pages:
  ## Define a standalone page
  - name: <STRING>
    # Relative path from `templates_dir`
    template_path: <FILE_PATH>

  ## Define a page with entries
  - name: <STRING>
    template_path: <FILE_PATH>

    ## Entries are, well, entries under a certain page. You may think of it like
    ## how you would with a blog with posts in it.
    entries:
      ## You may use a folder to put all your markdown files. `puggle` will also
      ## recursively traverse nested directories in this folder.
      - source_dir: <DIR_PATH>
        template_path: <FILE_PATH>

      ## Or you may directly reference a markdown file.
      - markdown_path: <FILE_PATH>
        template_path: <FILE_PATH>
```
