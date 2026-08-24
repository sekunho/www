---
title: "Declarative GNOME Customizations with Stylix"
created_at: 2026-08-22T14:15:00Z
updated_at:
tags: ["nixos", "stylix", "gnome", "home-manager"]
cover: "/assets/images/posts/declarative-customizations-with-nix-stylix/cover.png"
custom:
    slug: declarative-operating-system-customizations-with-stylix
    summary: Declaratively customize GNOME and other desktop environments with NixOS and stylix!

---

# {{ metadata.title }}

<span class="post-metadata">
  {{ metadata.created_at|published_on(format="short") }}
</span>

<div>
{% from "component/tags.html" import tags %}
{{ tags(metadata.tags) }}
</div>

<picture class="cover">
  <img src="{{ metadata.cover }}" alt="a screenshot of a customized GNOME 50 desktop with the Ayu Dark theme" loading="lazy">
</picture>

<h2 class="toc">Table of Contents</h2>

1. [Introduction](#introduction)
2. [Requirements](#requirements)
3. [Setting a Wallpaper](#setting-a-wallpaper)
4. [Customizing Color Schemes](#customizing-color-schemes)
5. [Custom Icon Themes](#custom-icon-themes)
6. [Custom Cursor Themes](#custom-cursor-themes)
7. [Change Default Global fonts](#change-default-global-fonts)
8. [Granular Program Customizations](#granular-program-customizations)
9. [Conclusion](#conclusion)

## Introduction

NixOS is pretty neat when it comes to having a unified configuration for programs,
system configs, and even `systemd` services. But I haven't really bothered much
with customizations such as ricing or even just basic theming/wallpaper stuff.
I normally use `sway` which has its own configuration file. But for other [DEs](https://wiki.archlinux.org/title/Desktop_environment)
such as GNOME or KDE, I was under the impression that customizations are either
too tedious as you have to manually manage `dconf` files or messy. For example,
with GNOME, one would typically need to install GNOME Tweaks just to do basic
customizations such as changing the default fonts or using custom color schemes,
but we're using `nix` so we don't need to!

And fortunately, today is one of these times that I felt curious with the GNOME
experience since I last tried it, which was around GNOME 40 I think. To anticipate
for the upcoming GNOME 51 release, I'll be catching up with GNOME 50. Which is
also a good time to explore what [`stylix`](https://nix-community.github.io/stylix/) can do!

## Requirements

At the time of writing, I'm using NixOS 26.05 with Home Manager 26.05 standalone.
In both cases, the [docs](https://nix-community.github.io/stylix/installation.html)
recommends that it be manually installed. But in summary, it's just the standard:

1. Add `stylix` to flake inputs
2. Add the respective module (either the normal `stylix` NixOS module or home module)

> [!WARNING]
> You have to be sure that your base NixOS version, Home Manager (if you're using
it) and `stylix` release versions are all the same. If you're on NixOS 26.05,
they all have to be on 26.05. Pinning it to the same `nixpkgs` input is not enough.

You can also use `stylix` with `nix-darwin` or anything that supports home manager,
so this isn't necessarily a GNOME nor NixOS specific thing! It's covered in their
documentation. I won't be covering `nix-darwin` because I dislike macOS.

Let's start with something easy like changing the default wallpaper.

## Setting a Wallpaper

...cause the default one NixOS GNOME came with is pretty bland:

<figure>
  <img src="/assets/images/posts/declarative-customizations-with-nix-stylix/default-nixos-wallpaper.png">
  <caption>
      Figure 1 - Default NixOS wallpaper for GNOME
  </caption>
</figure>

After picking a wallpaper, I like keeping it in my `dotfiles` directory so that
I can easily set it with `stylix`, and because I'm using GNOME for this example,
I also need to have it use the base `stylix.image` setting for it to change:

```nix
# modules/themes/ayu-dark.nix
{ ... }: {
  stylix = {
    image = ../../wallpapers/jupiter.jpg;

    targets = {
      gnome = {
        image.enable = true;
      };
    };
  };
}
```

The idea seems to be I have one global configuration that other targets such as
GNOME or other DEs may reuse. But I could also optionally override it if
I need something different I suppose?

You could also [use a URL](https://nix-community.github.io/stylix/configuration.html#wallpaper)
but I like keeping a copy just in case it breaks.

Then you can add it to your home manager module output:

```nix
# flake.nix
# ...
  homeConfigurations.<USER>.modules = [
    # ...
    stylix.homeModules.stylix
    ./modules/themes/ayu-dark.nix
  ];
# ...
```

And run `home-manager switch --flake . -b backup`. As a result, I get something like this:

<figure>
  <img src="/assets/images/posts/declarative-customizations-with-nix-stylix/new-nixos-wallpaper.png">
  <caption>
      Figure 2 - The new wallpaper of Jupiter! The deep blacks are good for OLED. :D
  </caption>
</figure>

## Customizing Color Schemes

With GNOME, you can customize color schemes and there are predefined ones from
the [tinted schemes](https://github.com/tinted-theming/schemes) repository so
have a look for one you like!

By default GNOME has a default light Adwaita theme:

<figure>
  <img src="/assets/images/posts/declarative-customizations-with-nix-stylix/color-scheme-default.png">
  <caption>
      Figure 3 - Calendar with the default light Adwaita
  </caption>
</figure>

```diff
# modules/themes/ayu-dark.nix
- { ... }: {
+ { config, pkgs, ... }: {
  stylix = {
    enable = true;
    image = ../../wallpapers/jupiter.jpg;

+   base16Scheme = "${config.stylix.inputs.tinted-schemes}/base16/ayu-dark.yaml";

    targets = {
      gnome = {
        image.enable = true;
+       colors.enable = true;
      };
    };
  };
}
```

Then reapply our home configuration with `home-manager switch --flake . -b backup`
again. But you either need to logout or actually restart (not just exit) the application
like `pkill calendar` to see the new theme:

<figure>
  <img src="/assets/images/posts/declarative-customizations-with-nix-stylix/color-scheme-ayu-dark.png">
  <caption>
      Figure 4 - Calendar but with Ayu Dark
  </caption>
</figure>

> [!NOTE]
> If you want to use an existing color scheme but want to update a few things,
`stylix` lets you override it! [Read more](https://nix-community.github.io/stylix/configuration.html#overriding)

## Custom Icon Themes

The default icon theme I had OOTB was HiColor which also was odd since GNOME 50
in other distros come with the Adwaita theme. For the readers with a keen eye,
you might've noticed that the calendar app's _Toggle Sidebar_ option had a broken
icon. We can verify that this is the case by checking `dconf`'s `GSettings` DB:

```sh
$ dconf read /org/gnome/desktop/interface/icon-theme
'HiColor'
```

To make it more evident, the file app (Nautilus) looks like this:

<figure>
  <img src="/assets/images/posts/declarative-customizations-with-nix-stylix/icon-theme-default.png">
  <caption>
      Figure 5 - HiColor is a limited icon set which is why there are broken sidebar icons
      and file icons.
  </caption>
</figure>

So let's use [MoreWaita](https://github.com/somepaulo/MoreWaita) though honestly
just the regular Adwaita icon theme would probably be enough. Just that MoreWaita
has more icons.

> [!NOTE]
> `stylix` doesn't actually have any mention of being able to configure icons in
their docs' configuration page. My guess is it's because it was a somewhat recent
feature. The relevant section would be in their [Platform section](https://nix-community.github.io/stylix/options/platforms/nixos.html#stylixiconsenable)
.

```diff
# modules/themes/ayu-dark.nix
{ config, pkgs, ... }: {
  stylix = {
    enable = true;
    image = ../../wallpapers/jupiter.jpg;

    base16Scheme = "${config.stylix.inputs.tinted-schemes}/base16/ayu-dark.yaml";
+
+   icons = {
+     enable = true;
+     package = pkgs.morewaita-icon-theme;
+     light = "MoreWaita";
+     dark = "MoreWaita";
+   };

    targets = {
      gnome = {
        image.enable = true;
        colors.enable = true;
      };
    };
  };
}
```

> [!WARNING]
> Check the icon's canonical name otherwise it will not load correctly. For example,
I mistakenly spelled it as _Morewaita_ instead of _MoreWaita_ and that 1 case
difference made it fallback to the default HiColor theme.

Applying this change would update the `dconf` entries for you which we can validate:

```sh
$ dconf read /org/gnome/desktop/interface/icon-theme
'MoreWaita'
```

And our file app's icons are shiny and new!

<figure>
  <img src="/assets/images/posts/declarative-customizations-with-nix-stylix/icon-theme-morewaita.png">
  <caption>
      Figure 6 - More Adwaita icons
  </caption>
</figure>

## Custom Cursor Themes

The default for me was Breeze, I think? I think it was cause I had switched over
from KDE before, and I suppose something wasn't cleaned up properly. So I only
had a white square as a cursor.

We can set the cursor theme as well, and I'm going to use Adwaita (surprise). The
Adwaita cursors are a part of the Adwaita icon set.


```diff
# modules/themes/ayu-dark.nix
{ config, pkgs, ... }: {
  stylix = {
    enable = true;
    image = ../../wallpapers/jupiter.jpg;

    base16Scheme = "${config.stylix.inputs.tinted-schemes}/base16/ayu-dark.yaml";

    icons = {
      enable = true;
      package = pkgs.morewaita-icon-theme;
      light = "MoreWaita";
      dark = "MoreWaita";
    };
+
+   cursor = {
+     name = "Adwaita";
+     package = pkgs.adwaita-icon-theme;
+     size = 24;
+   };

    targets = {
      gnome = {
        image.enable = true;
        colors.enable = true;
      };
    };
  };
}
```

Apply, and validate:

```sh
$ dconf read /org/gnome/desktop/interface/cursor-theme
'Adwaita'
```

## Change Default Global Fonts

My default font is not exactly the prettiest either so I'd like to change that.
The default one was set to _DejaVu Sans_ for some reason despite initially expecting
it to be _Adwaita Sans_.

```sh
$ gsettings get org.gnome.desktop.interface font-name
'DejaVu Sans 12'
```

So I need to change it over to Adwaita Sans. Based on `stylix`'s [docs](https://nix-community.github.io/stylix/configuration.html#fonts), I'm able to change the different global fonts based on their families.
I'm personally okay with the default serif font but I'd like to change the sans
serif and monospace fonts.

```diff
# modules/themes/ayu-dark.nix
{ config, pkgs, ... }: {
  stylix = {
    enable = true;
    image = ../../wallpapers/jupiter.jpg;

    base16Scheme = "${config.stylix.inputs.tinted-schemes}/base16/ayu-dark.yaml";

    icons = {
      enable = true;
      package = pkgs.morewaita-icon-theme;
      light = "MoreWaita";
      dark = "MoreWaita";
    };

    cursor = {
      name = "Adwaita";
      package = pkgs.adwaita-icon-theme;
      size = 24;
    };
+
+   fonts = {
+     sansSerif = {
+       package = pkgs.adwaita-fonts;
+       name = "Adwaita Sans";
+     };
+
+     monospace = {
+       package = pkgs.adwaita-fonts;
+       name = "Adwaita Mono";
+     };
+   };

    targets = {
      gnome = {
        image.enable = true;
        colors.enable = true;
      };
    };
  };
}
```

If you have private fonts that you purchased, you can package them with `nix`
and use it here as well in place of the `pkgs.adwaita-fonts` package.

<figure>
  <img src="/assets/images/posts/declarative-customizations-with-nix-stylix/font-adwaita.png">
  <caption>
      Figure 7 - Calendar with Adwaita Sans
  </caption>
</figure>

## Granular Program Customizations

Some programs have their own customizations but typically if they're using GTK 4
then chances are they'll follow the global system theme. But say for programs like
Firefox, they require a bit more customizations.

Fortunately, there are some settings that `stylix` provides for us to let Firefox
blend together with the rest of the system. At the moment, it looks like this:

<figure>
  <img src="/assets/images/posts/declarative-customizations-with-nix-stylix/firefox-default-theme.png">
  <caption>
      Figure 8
  </caption>
</figure>

A bit out of place as our global theme uses a dark theme but Firefox seems to
have its own. You can specify customizations of individual programs by adding a
new target just like we did with `targets.gnome`:

```diff
# modules/themes/ayu-dark.nix
{ config, pkgs, ... }: {
  stylix = {
    enable = true;
    image = ../../wallpapers/jupiter.jpg;

    base16Scheme = "${config.stylix.inputs.tinted-schemes}/base16/ayu-dark.yaml";

    icons = {
      enable = true;
      package = pkgs.morewaita-icon-theme;
      light = "MoreWaita";
      dark = "MoreWaita";
    };

    cursor = {
      name = "Adwaita";
      package = pkgs.adwaita-icon-theme;
      size = 24;
    };

    fonts = {
      sansSerif = {
        package = pkgs.adwaita-fonts;
        name = "Adwaita Sans";
      };

      monospace = {
        package = pkgs.adwaita-fonts;
        name = "Adwaita Mono";
      };
    };

    targets = {
      gnome = {
        image.enable = true;
        colors.enable = true;
      };
+
+     firefox = {
+       enable = true;
+       firefoxGnomeTheme.enable = true;
+       colors.enable = true;
+       fonts.enable = true;
+     };
    };
  };
}
```

The `firefox.firefoxGnomeTheme` is particularly important as we need to tell it
to use our GNOME theme. One config apply and program restart after, we get this:

<figure>
  <img src="/assets/images/posts/declarative-customizations-with-nix-stylix/firefox-gnome-theme.png">
  <caption>
      Figure 9
  </caption>
</figure>

Seems like the window decoration properly follows the GNOME theme now but it still
looks pretty awkward as the window control icons have no contrast while the sidebar
and the websites themselves are still using their own light theme versions!
Well this is because we need to specify the polarity of this theme, or basically
whether or not this theme is a light or dark theme so that websites and other
things can automatically switch over to their respective versions.

```diff
# modules/themes/ayu-dark.nix
{ config, pkgs, ... }: {
  stylix = {
    enable = true;
    image = ../../wallpapers/jupiter.jpg;
+   polarity = "dark";

    base16Scheme = "${config.stylix.inputs.tinted-schemes}/base16/ayu-dark.yaml";

    icons = {
      enable = true;
      package = pkgs.morewaita-icon-theme;
      light = "MoreWaita";
      dark = "MoreWaita";
    };

    cursor = {
      name = "Adwaita";
      package = pkgs.adwaita-icon-theme;
      size = 24;
    };

    fonts = {
      sansSerif = {
        package = pkgs.adwaita-fonts;
        name = "Adwaita Sans";
      };

      monospace = {
        package = pkgs.adwaita-fonts;
        name = "Adwaita Mono";
      };
    };

    targets = {
      gnome = {
        image.enable = true;
        colors.enable = true;
      };

      firefox = {
        enable = true;
        firefoxGnomeTheme.enable = true;
        colors.enable = true;
        fonts.enable = true;
      };
    };
  };
}
```

And now we get a nice dark theme for our sidebar and all the website we visit.
One thing that's still awkward is that the sidebar doesn't seem to follow our
general color scheme but this will do for now.

<figure>
  <img src="/assets/images/posts/declarative-customizations-with-nix-stylix/firefox-gnome-theme-dark.png">
  <caption>
      Figure 10 - Firefox now respecting dark mode!
  </caption>
</figure>

## Conclusion

### stylix

`stylix` is surprisingly convenient for customizations. Some things are a bit
awkward like with Firefox, I had to turn on a bunch of attributes just to get
the color scheme to work. But I think this is due to it needing the flexibility
across different DEs. Some DEs also have limited support such as with `sway` which
is also expected as `sway` has their own configuration format and I don't think
I would even switch over to `stylix` if it had better integration. Though for GNOME,
not having to use GNOME Tweaks to manually fiddle around with `GSettings` makes for
a better and more consistent configuration experience IMO.

The alternative is to manually set the relevant `dconf` entries through NixOS'
`programs.dconf` attribute so if you're a stickler with using yet-anothe-nix-tool,
then this would work and would still be reproducible.

### GNOME

On the DE side of things, GNOME still has one of the best out-of-the-box experience
for Linux. Everything is smooth and snappy on my Framework Desktop. Though I
suppose the bar is quite low after being an NVIDIA Linux ~~victim~~ user for a
few years. :)

<picture>
  <source srcset="/assets/images/not-by-ai.webp" type="image/webp">
  <img style="width: 8rem;" src="/assets/images/not-by-ai.png" alt="not by AI" loading="lazy">
</picture>
