---
title: "What I learned from building an emoji URL shortener in Rust"
created_at: 2022-04-11T06:20:00Z
updated_at:
tags: ["nix", "postgresql", "rust", "axum"]
cover: "/assets/images/posts/what-i-learned-from-building-a-rust-emoji-url-shortener/cover.png"

custom:
    slug: what-i-learned-from-building-a-rust-emoji-url-shortener

    summary: |
        Alright, that was a lot. I did learn a lot from this experience. I actually only
        read until chapter 10 of the Rust Book, and skipped to some parts like advanced
        traits, and other things. I really like the fact that there's a detailed book
        that talks about some idiomatic Rust patterns, and even the more advanced stuff,
        that's completely FREE. How crazy is that? My wallet is spared!
---

# What I learned from building an emoji URL shortener in Rust

<div>
{% from "component/img.html" import img %}
</div>

<div>
{{ img(src=metadata.cover, alt="HackerNews URL pointing to a shortened emojied.net URL") }}
</div>

<span class="post-metadata">
  {{ metadata.created_at|published_on(format="short") }}
</span>

So, I made an emoji URL shortener with Rust and shared it in some places
including the [Rust community](https://old.reddit.com/r/rust/comments/tznryk/i_made_my_first_project_with_rust_its_a_url/).
And oh man this is the first thing I made that got this many visitors which is
pretty nice knowing that people were curious enough to try it ~~despite them probably
feeling disgusted from me bringing such a thing to existence~~.

* Repo: [https://github.com/sekunho/emojied](https://github.com/sekunho/emojied)
* Website: [https://emojied.net](https://emojied.net)

Some glowing ✨ reviews:

> "Thanks, I hate it." -- Pay08, 2022

> "downvoted for being a menace to society." -- MultiplyAccumulate, 2022

> "blursed " -- Jaxius3

> "“Made with regret.” Hahahaha. Excellent." -- IronWhiskers, 2022

> "What is wrong with you?" -- Jeff

<div>
{{img(src="/assets/images/posts/what-i-learned-from-building-a-rust-emoji-url-shortener/stats.png", alt="Cloudflare stats page for emojied.net", size="sm")}}
</div>

Here are some of the things I learned from building a simple project.

## Tech Stack

After looking around, I decided to go with the following:

- `axum` (web server)
- `maud` (HTML templates via Rust macros)
- `postgres` (persistent data storage and business logic)
- `sqitch` (database schema migration tool)
- `typescript` (you know what this is)
- `docker` ("simple" deploys)
- `nix` (reproducible environments)

## PostgreSQL Procedures

Procedures are _extremely_ cool although this isn't exactly new to me. I've been
experimenting with this in one of my previous, unfinished projects called GNAWEX
[^1] (One day I will finish it don't you worry).

This allows you to implement some business logic in SQL, without having to
implement it in the application level. If ever PostgreSQL is a constant in your
project, and intend to rewrite the app from scratch, you might just end up having
to rewrite the glue rather than your business logic. `emojied` isn't doing
anything too exciting though, so I can't really demonstrate all that is cool
about it.

Okay, an example would be fetching a URL given an identifier, and incrementing
the `clicks` column by one. Here's an example of a procedure that does exactly
that:

```sql
CREATE FUNCTION app.get_url(query TEXT)
                          -- ^ This contains the emoji sequence `identifier`
  RETURNS TEXT
  LANGUAGE sql
  AS $$
    -- Considered as a "clicked" link whenever this gets triggered
    UPDATE app.links
      SET clicks = clicks + 1
      WHERE links.identifier = $1;

    -- Builds the URL so that I don't have to do this in the web server
    SELECT concat(scheme, '://', hosts.name, path) AS url
      FROM app.links
      JOIN app.hosts
      ON links.host = hosts.host_id
      WHERE links.identifier = $1;
  $$;
```

It's a simple function that uses SQL as the language that expects any `TEXT`,
and returns a `TEXT` as well, which is a sequence of emojis, and the URL it
maps to respectively. Since whatever happens in this procedure is in the same
transaction as what called it, e.g (`SELECT * FROM app.get_url('🍊🌐')`), if any
of this fails, then it rolls back everything, including the incrementing of
`clicks`. If this was at the application level, I'd have to reach for whatever
transaction implementation it uses (like `Ecto.Multi`) which doesn't make sense
in this case cause Postgres already natively supports transactions.

I try to make heavy use of stored procedures as long as it's applicable.
Inserting to multiple tables with one function, fetching leaderboard entries,
etc.

## Error handling with implicit `From<T>`

Error handling is pretty nice with Rust, especially since I was never a fan of
exceptions since it made control flow so weird. Although that may be because I
never really invested that much time working with them. In Rust, I like that
you can do two things for errors: errors encoded as ADTs, or panic (unrecoverable).
Although I'm not entirely sure if all errors can be encoded in sum types, and
what can be done if ever one needs to recover from a panic. But for `emojied`,
I definitely don't have to think about that.

What I did have to deal with was finding a more convenient way when dealing with
other `Error` types. For instance, there's `tokio_postgres::Error`, then there's
`env::VarError`, and if I need to bubble up these errors to the binary, I'm gonna
need a convenient enough way to do that otherwise I'm gonna have a difficult time.

Let's say I have two errors, a database one, and an application one.

```rust
enum AppError {
  Foo,
  Baz
}

enum DbError {
    FailedToConnect,
    InvalidTLSCert
}

fn some_db_action() -> Result<String, DbError> {
    Err(DbError::FailedToConnect)
}

fn some_app_action() -> Result<String, AppError> {
    let result1 = some_db_action()?;
    let result2 = some_db_action()?;

    Ok(result1)
}
```

This fails to compile, here's what `rustc` says:

```
error[E0277]: `?` couldn't convert the error to `AppError`
    |
212 | fn app_action() -> Result<String, AppError> {
    |                    ------------------------ expected `AppError` because of this
213 |     let result1 = db_action()?;
214 |     let result2 = db_action()?;
    |                              ^ the trait `From<url::DbError>` is not implemented for `AppError`
    |
    = note: the question mark operation (`?`) implicitly performs a conversion on the error value using the `Fro
m` trait
    = note: required because of the requirements on the impl of `FromResidual<Result<Infallible, url::DbError>>`
 for `Result<std::string::String, AppError>`

For more information about this error, try `rustc --explain E0277`.
```

So it tells me that using `?` implicitly converts `DbError` to `AppError` via
the `From` trait. And because I do not have a trait instance like
`impl From<DbError> for AppError`, it fails.

Another thing is I somehow need to bubble up `DbError` up to the application
error somehow. The method I ended up using is to just add a field to the
`AppError` record. It's a bit tiring to copy all the `DbError` variants over to
the `AppError` enum. I mean, it's fine for this one since it doesn't have that
many, but it becomes.

```rust
enum AppError {
    DbError(DbError), // Hooray!
    Foo,
    Baz
}
```

And then I can create a `From<DbError>` instance:

```rust
impl From<DbError> for AppError {
    fn from(e: DbError) -> Self {
        AppError::DbError(e)
    }
}
```

Which compiles!

If I wanted to avoid `From`, I could do this:

```
let result1 = db_action().map_err(|_| AppError::Foo)?;
```

Except it's kinda annoying cause I have to do this at every call site. Although
there are times when I did end up using this.

## Application configuration

While convenient, I can't just hard-code everything into the application,
especially for a public project. There are a lot of sensitive data like certs,
and sometimes it's just _more_ convenient for whoever is using the application
to change stuff without touching the source code. In my case, I had to make it
flexible enough to change database credentials.

> A common way to do it is through environment variables.
>
> e.g `PG__HOST="db.example.com" emojied`. So whenever I need to update stuff, all
> I have to do is just change the environment variable, and I'm spared from
> touching the source code!

Here's `emojied`'s config for it to run:

```rust
pub struct AppConfig {
    /// Application host
    pub host: String,

    /// PostgreSQL config
    pub pg: tokio_postgres::Config,

    /// Pool manager config
    pub manager: ManagerConfig,

    /// Pool size
    pub pool_size: usize,

    pub ca_cert_path: Option<String>,
}
```

Then I created an associated function for it called `from_env/0` which returns
a `Result<AppConfig, Error>`. I'll talk about the `Error` part in the `Error
Handling` section. Then I can use Rust's `std::env` module to get a var's value!

Here's a tiny example:

```rust
use std::env;

struct AppConfig {
  pg_host: String,
}

impl AppConfig {
  fn from_env() -> Result<AppConfig, Error> {
      let host = env::var("PG__HOST")?;

      Ok(AppConfig { pg_host: host })
  }
}
```

> Side note: This kinda looks monadic, where it binds `AppConfig` to `host`, and
> evaluates to `Error` and "exits" otherwise.

## Handling database...handler in `axum`

I created this database handle that has all the things I need to communicate
with the database server:

```rust
pub struct Handle {
    pub pool: Pool,
}
```

It's pretty simple. It's a struct that has a `pool` field. Then I created two
more functions to make things more convenient: `new/1`, and `client/1`.

`new(config: AppConfig) -> Result<Handle, Error>` expects an `AppConfig` as an
argument, and if all goes well, then a new database handle with all the important
things in it. `client(&self) -> Result<Pool, Error>` expects a reference to
`self`, which is `Handle` in this case. This uses the DB pool to create a new
client. From this client, you can do DB queries with it.

```rust
// Grabs a client from the pool
let client = handle.client().await?;

// Runs a query that gets a URL's stats
let data = client
    .query("SELECT * FROM app.get_url_stats($1)", &[&identifier])
    .await?;

// Manually maps the row to a leaderboard entry
let db_id = data[0].try_get(0)?;
let db_clicks = data[0].try_get(1)?;
let db_url = data[0].try_get(2)?;

Ok(leaderboard::Entry {
    identifier: db_id,
    clicks: db_clicks,
    url: db_url,
})
```

Okay, so I somehow need access to the database handle in the "controllers", like
in `controllers::leaderboard`.

> I'm only calling it a controller since it's a common concept. `axum` doesn't
> call it that.

```rust
let app = Router::new()
    .route("/leaderboard", routing::get(controllers::leaderboard));
```

`axum` recommends [^2] mentions that you could use "request extensions" which
looks like it acts like middleware. It recommends to have `Arc` inhabit
`Extension` (`Extension<Arc<T>>`), but why?

Time to do it in some wrong ways. This is fine since `rustc` is quite helpful
with its error messages.

I'll try to move `handle` instead:

```rust
use axum::{extract::Extension, routing::get, Router};
use std::net::SocketAddr;

pub async fn run(handle: db::Handle) -> Result<(), hyper::Error> {
    let app = Router::new()
        .route("/leaderboard", routing::get(controllers::leaderboard))
        .layer(Extension(handle));
                      // ^ Here

    let addr = SocketAddr::from(([0, 0, 0, 0], 3000));

    axum::Server::bind(&addr)
        .serve(app.into_make_service())
        .with_graceful_shutdown(signal_shutdown())
        .await
}
```

Doing that gives me this error:

```
error[E0277]: the trait bound `db::Handle: Clone` is not satisfied
  --> src/lib.rs:36:16
   |
36 |         .layer(Extension(handle));
   |          ----- ^^^^^^^^^^^^^^^^^ the trait `Clone` is not implemented for `db::Handle`
   |          |
   |          required by a bound introduced by this call
   |
   = note: required because of the requirements on the impl of `tower_layer::Layer<Route<_>>` for `Extension<db::
Handle>`

For more information about this error, try `rustc --explain E0277`.
```

It seems like I need to derive `Clone` for `db::Handle` since it probably gets
cloned every time, although I'm not sure exactly when it does get cloned. In
every new request?

So what happens if I _do_ derive `Clone`?

```rust
#[derive(Clone)]
struct Handle {
  pub pool: Pool
}
```

Then I need to make sure that the function's type signature matches:

```rust
pub async fn leaderboard(
    Extension(handle): Extension<db::Handle>
 // ^ Here! axum seems to know exactly where to apply it to the args. Not sure
 // how this is done (yet).
) -> (StatusCode, Markup) {
    match leaderboard::fetch(&handle).await {
        Ok(entries) => {
            (StatusCode::OK, views::leaderboard::render(entries))
        },
        Err(_e) => (StatusCode::INTERNAL_SERVER_ERROR, maud::html! {}),
    }
}
```

Well, it seems to compile just fine. The leaderboard page works fine as well.
I don't really have that much experience with this yet but my current assumption
is that I'm required to derive `Clone` for `Handle` since there's no way to do
shared ownership. So what it does is that it ends up cloning it every time. But,
what if I don't want to clone it? What if I just pass around references?

```rust
pub async fn run(handle: db::Handle) -> Result<(), hyper::Error> {
    let app = Router::new()
        .route("/leaderboard", routing::get(controllers::leaderboard))
        .layer(Extension(&handle));
                      // ^ Here

    let addr = SocketAddr::from(([0, 0, 0, 0], 3000));

    axum::Server::bind(&addr)
        .serve(app.into_make_service())
        .with_graceful_shutdown(signal_shutdown())
        .await
```

Compiles with this helpful error message:

```
error[E0597]: `handle` does not live long enough
  --> src/lib.rs:36:26
   |
22 |       let app = Router::new()
   |  _______________-
23 | |         .route("/leaderboard", routing::get(controllers::leaderboard))
24 | |         .layer(Extension(&handle));
   | |__________________________^^^^^^^_- argument requires that `handle` is borrowed for `'static`
   |                            |
   |                            borrowed value does not live long enough
...
44 |   }
   |   - `handle` dropped here while still borrowed

For more information about this error, try `rustc --explain E0597`.
```

Unfortunately, I'm not too familiar with how lifetimes work in `async`/`await`.
But it looks like since it's non-blocking, `handle` gets dropped since the function
reaches the end of its scope while the server is still running.

> This is all just somewhat smart guessing though. I'm gonna need to do more
> reading on this topic.

Wait, what about `app` then? Won't this get dropped as well? I wanted to confirm
if this did get moved, or if it did some other trickery I had no idea about:

```rust
    let app = Router::new()
        .route("/leaderboard", routing::get(controllers::leaderboard))
        .layer(Extension(handle));

    let addr = SocketAddr::from(([0, 0, 0, 0], 3000));

    let foo =
        axum::Server::bind(&addr)
            .serve(app.into_make_service())
            .with_graceful_shutdown(signal_shutdown())
            .await;

    println!("{:?}", app);

    foo
```

So if `app` does get moved, then `rustc` should complain about me accessing a
variable with no ownership; which it does:

```rust
error[E0382]: borrow of moved value: `app`
   --> src/lib.rs:46:22
    |
22  |     let app = Router::new()
    |         --- move occurs because `app` has type `Router`, which does not implement the `Copy` trait
...
42  |             .serve(app.into_make_service())
    |                        ------------------- `app` moved due to this method call
...
46  |     println!("{:?}", app);
    |                      ^^^ value borrowed here after move
    |
note: this function takes ownership of the receiver `self`, which moves `app`
```

Phew! It's almost like I'm encouraged to try out all the failed scenarios to
learn a lot of things since the compiler is quite helpful.

Okay, since I didn't want this to get cloned all the time, I will just follow
what `axum` used in its examples - the usage of `Arc<T>`:

```rust
pub async fn run(handle: db::Handle) -> Result<(), hyper::Error> {
    let handle = Arc::new(handle);
    //  ^ Shadow previous binding with `Arc<db::Handle>`

    let app = Router::new()
        .route("/leaderboard", routing::get(controllers::leaderboard))
        .layer(Extension(handle));
                      // ^ Here

    let addr = SocketAddr::from(([0, 0, 0, 0], 3000));

    axum::Server::bind(&addr)
        .serve(app.into_make_service())
        .with_graceful_shutdown(signal_shutdown())
        .await
}
```

And then I'll remove the `Clone` derivation:

```rust
pub struct Handle {
    pub pool: Pool,
}
```

So if I'm not mistaken, which I probably am, `Arc<T>` should allow me to share
ownership of `db::Handle` without having to clone it [^3].

```rust
pub async fn leaderboard(
    Extension(handle): Extension<Arc<db::Handle>>
) -> (StatusCode, Markup) {
    match leaderboard::fetch(&*handle).await {
        Ok(entries) => {
            (StatusCode::OK, views::leaderboard::render(entries))
        },
        Err(_e) => (StatusCode::INTERNAL_SERVER_ERROR, maud::html! {}),
    }
}
```

Then in `leaderboard::fetch/1`:

```rust
pub async fn fetch_url(
    handle: &db::Handle,
    identifier: String
) -> Result<String, Error> {
    let client = handle.client().await?;
    let row = client
        .query_one("SELECT app.get_url($1)", &[&identifier])
        .await?;

    row.try_get(0).map_err(|e| Error::from(e))
}
```

Although, I had to manually dereference it to get the reference to `Handle`. It's
also a good thing that I don't have to mutate `handle` at all because otherwise
this would've been a more painful experience.

## Connecting to a managed database

Initially, I used `sqlx` as the db library since it gets recommended in almost
every post about SQL libraries on the Rust subreddit. It worked fine for me
until I had to get it to connect to DO's managed DB. It required me to connect
to it via TLS, and it wasn't a pleasant experience trying to debug what's wrong
with `sqlx`, so I ditched it settled with `tokio-postgres`, `deadpool-postgres`,
and `native-tls`. Oh, I also had a difficult time [^9] with `rustls` since it
didn't seem to like DO's CA certificate, which is why I settled with `native-tls`.

`native-tls` needed OpenSSL setup, which I was able to do with Nix (for the
dev environment):

```nix
  # ...
        devShell = pkgs.mkShell {
          # inherit (self.checks.${system}.pre-commit-check) shellHook;

          buildInputs = with pkgs; [
            # Back-end
            pkgs.rustc
            pkgs.cargo

            pkgs.openssl
            pkgs.pkg-config
          ];

          PKG_CONFIG_PATH = "${pkgs.openssl.dev}/lib/pkgconfig";
        };

  # ...
```

So I had to provide the CA cert during runtime, not build-time since: 1) it'll
be easier to distribute the static binary and Docker image, and 2) some CA certs
are only given during runtime (like DO if ever you're using app platform). This
was my process:

1. Build static binary & image without CA certs and other DB secrets
2. When the image runs, it's assumed that the necessary environment variables,
like one that contains the certificate contents, exist.
3. Write the certificate contents to a file.
4. Run `emojied`

This seems to be a pretty standard process, although this is fairly tedious.

```rust
// src/config.rs
use tokio_postgres::config::SslMode;

let mut pg_config = tokio_postgres::Config::new();

// I also read other PG values like hostname, DB name, user, etc. but excluded
// those for brevity.

// Not providing CA_CERT is fine
let ca_cert_path = match env::var("PG__CA_CERT") {
    Ok(path) => {
        // I think `Prefer` is fine as well, which is the default
        // for `tokio-postgres`.
        pg_config.ssl_mode(SslMode::Require);
        Some(path)
    },
    Err(_e) => {
        None
    }
};
```

I allowed it to continue running without the cert path in `PG__CA_CERT` for
dev environments.

```rust
// Somewhere in src/db.rs

let manager = match app_config.ca_cert_path {
    Some(ca_cert_path) => {
        // Read file into byte vector
        let cert = std::fs::read(ca_cert_path)
            .map_err(|e| Error::CACertFileError(e))?;

        // Create a certificate from a PEM file
        let ntls_cert = Certificate::from_pem(&cert)
            .map_err(|_| Error::InvalidCACert)?;

        let tls = TlsConnector::builder()
            .add_root_certificate(ntls_cert)
            .build()
            .map_err(|_| Error::FailedToBuildTlsConnector)?;

        let conn = MakeTlsConnector::new(tls);

        Manager::from_config(app_config.pg, conn, app_config.manager)
    }
    None => Manager::from_config(app_config.pg, NoTls, app_config.manager),
};

// Since we need a `manager` to build a pool
let pool = Pool::builder(manager)
    .max_size(app_config.pool_size)
    .build()
    .map_err(|_| Error::FailedToBuildPool)?;
```

> The process was quite similar with SQLx but there was something, that I don't
> really remember anymore, which made it so frustrating to work with.

Unfortunately, DO doesn't support multiline environment variables, for some
reason, so cramming everything including the `BEGIN CERTIFICATE` and `END CERTIFICATE`
into one line resulted in it getting rejected. So, I just got what's in between,
and manually appended it to the file instead.

```sh
echo "Dumping CA certificate to /app/ca-certificate.crt"
echo "-----BEGIN CERTIFICATE-----" > /app/ca-certificate.crt
echo $CA_CERT >> /app/ca-certificate.crt
echo "-----END CERTIFICATE-----" >> /app/ca-certificate.crt

echo "Executing emojied"

./emojied
```

Kind of hacky, and inconvenient especially if I forget. But it works!

## URL redirect woes

This is a short one. For the redirect, I returned an HTTP status 301 [^4] with
a response containing the URL to redirect to. So the process goes something
like this:

1. Enter [https://emojied.net/🍊🌐](https://emojied.net/🍊🌐) in the browser.
2. `emojied` looks for an entry with `🍊🌐`, and gets the associated URL.
3. Respond with an HTTP 301 and the URL
4. Browser automatically performs the redirect

Unfortunately, and I spent 30mins on this scratching my head why this was
happening, the request would get cached, and this is bad! It's bad because I
had to increment the `clicks` column every time the link is visited. But if it's
cached, then the server won't bother to call the functions it needs to call!

Then, I found out that `301` gets cached automatically by the browser [^5],
and that I needed to use `302`.

## HTML templating with `maud`

I had a pleasant experience with server-side templating while I was building
a Haskell project called [swoogle](https://swoogle.sekun.dev). I used `lucid`
[^6] which was a pretty darn elegant HTML DSL.

```haskell
-- Category options
select_
  [ id_ "category-options"
  , name_ "resource"
  , class_ "bg-white font-semibold dark:bg-su-dark-bg-alt text-su-fg dark:text-su-dark-fg"
  , required_ "required"
  ] $ do
  option_ [disabled_ "disabled", selected_ "selected", value_ ""] "Category"
  option_ [value_ "people"] "People"
  option_ [value_ "film"] "Film"
  option_ [value_ "starship"] "Starship"
  option_ [value_ "vehicle"] "Vehicle"
  option_ [value_ "species"] "Species"
  option_ [value_ "planet"] "Planet"
```

Well, I wanted something like that in Rust, and I found `maud` [^7]. I did run
into a problem when I tried to use its latest version with `axum` since something
must've changed in `axum`, so I had to pull from the `main` instead:

```
[dependencies]
...
maud = { git = "https://github.com/lambda-fairy/maud", branch = "main", features = ["axum"] }
...
```

So with this, I could do stuff like:

```rust
fn foo() -> Markup {
  html! {
    ("Hello")
    h1 class="text-red-500" { ("Hello!") }

    h2 class=("font-semibold") { ("Hey") }
  }
}
```

## `<noscript>` tag, and problems with JS toggling extensions

I wanted to have the website work with JS disabled because, well, it was a very
simple website. There was no reason why I couldn't make all the important features
work without JS!

So I ended up making heavy use of the `<noscript>` tag, since it allowed me to
display alternative content when the browser has JS disabled. You'll see it
littered all over the codebase, like so:

```rust
@match data {
    RootData::Auto(_) => {
        noscript {
            div class="w-full sm:w-4/5 mt-2 mx-auto text-su-fg-1 dark:text-su-dark-fg-1" {
                a href="?custom_url=t" type="button" class="font-medium underline" {
                    "Custom URL"
                }
            }
        }
    }

    RootData::Custom(_) => {
        noscript {
            div class="w-full sm:w-4/5 mt-2 mx-auto text-su-fg-1 dark:text-su-dark-fg-1" {
                a href="/" type="button" class="font-medium underline" {
                    "Autogenerate a custom URL for me"
                }
            }
        }
    }
}
```

These only get rendered by the browser when JS is disabled. But what do browser
extensions like `NoScript` when it "disables" JS? It's something like this:

1. Block requests for JS files via CSP (Content Security Policies)
2. Replace `noscript` tags to `span` or `div` tags

The problem I ended up with was in \#2. Why? Because the `noscript` tag attributes
weren't copied over to the new `span`/`div` tags. And that breaks a lot of stuff.

So while `emojied` does work without JS, it won't work due to how the extensions
work [^8].

## Conclusion

Alright, that was a lot. I did learn a lot from this experience. I actually only
read until chapter 10 of the Rust Book, and skipped to some parts like advanced
traits, and other things. I really like the fact that there's a detailed book
that talks about some idiomatic Rust patterns, and even the more advanced stuff,
that's completely **FREE**. How crazy is that? My wallet is spared!

I usually try to avoid failure, even in Haskell, cause its error messages are
pretty bad. When I started out, it was pretty much worthless to read GHC's error
messages since it would just confuse me even more. It was only until I had people
guide me (like justosophy, thank you) that I slowly got to understand what GHC
was trying to tell me. With Rust though, it's a completely different experience.

I like _failing_ because Rust is very helpful with its error messages. In fact,
I discover new things by reading it so I'm not punished for trying out different
things that don't work just to gain more insight.

I also like that it's fairly easy on resources. I didn't even bother optimizing
this at all since I mostly have no idea what I'm doing, and I'm trying to avoid
having to deal with lifetimes as much as possible. I'm hosting this on a 1x shared
vCPU + 512MB RAM, and it didn't break a sweat during peak load.

Anyway, so far, so good! I'm pretty ecstatic to continue learning Rust.

## Footnotes

[^1]: [https://github.com/gnawex/gnawex](https://github.com/gnawex/gnawex)

[^2]: [https://docs.rs/axum/0.5.1/axum/#using-request-extensions](https://docs.rs/axum/0.5.1/axum/#using-request-extensions)

[^3]: [https://doc.rust-lang.org/std/sync/struct.Arc.html](https://doc.rust-lang.org/std/sync/struct.Arc.html)

[^4]: [https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/301](https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/301)

[^5]: [https://developer.mozilla.org/en-US/docs/Web/HTTP/Caching#targets_of_caching_operations](https://developer.mozilla.org/en-US/docs/Web/HTTP/Caching#targets_of_caching_operations)

[^6]: [https://hackage.haskell.org/package/lucid](https://hackage.haskell.org/package/lucid)

[^7]: [https://github.com/lambda-fairy/maud](https://github.com/lambda-fairy/maud)

[^8]: [https://github.com/hackademix/noscript/issues/238](https://github.com/hackademix/noscript/issues/238)

[^9]: [https://old.reddit.com/r/rust/comments/txglob/need_help_regarding_deadpoolpostgres_rustls_and/](https://old.reddit.com/r/rust/comments/txglob/need_help_regarding_deadpoolpostgres_rustls_and/)

[^10]: [https://www.manning.com/books/rust-in-action](https://www.manning.com/books/rust-in-action)
