---
title: "NixOS on the Framework Desktop"
created_at: 2025-10-12T18:07:52Z
updated_at:
tags: ["nixos", "nix", "computer", "framework"]
cover: "/assets/images/posts/nixos-on-framework-desktop/cover.webp"
custom:
    slug: nixos-on-framework-desktop
    summary: |
      Hi, it's been a while (again). I've been feeling better over the past few weeks. Coincidentally, my Framework Desktop finally arrived. It's a cute lil machine that I really love. Like any other machine I get my hands on (except macbooks lol), I install NixOS in it!

---

# {{ metadata.title }}

<picture>
    <img src="{{ metadata.cover }}" alt="a framework desktop with a mini Hiro on top" loading="lazy">
</picture>

<span class="post-metadata">
  {{ metadata.created_at|published_on(format="short") }}
</span>

<div>
{% from "component/tags.html" import tags %}
{{ tags(metadata.tags) }}
</div>

Hi, it's been a while (again). I've been feeling better over the past few weeks.
Coincidentally, my Framework Desktop finally arrived. It's a cute lil machine
that I really love. Like any other machine I get my hands on (except macbooks
lol), I install NixOS in it!

I also redid bits and pieces of my website. I think I got bored of gruvbox (yeah
I know, I know). As time goes on, the more utilitarian I become. But this is
probably as barebones as it gets in terms of design.

---

You'll need:

1. a USB drive with a `NixOS` [minimal ISO](https://nixos.org/download) flashed into it
    - We'll also be using the minimal ISO just because. Idk. Maybe you're installing
one remotely? Who knows!
2. a Framework Desktop
3. internet

> [!NOTE]
> For this installation, I won't be using secure boot. If you do wish to use secure
boot, you can use [`nix-community/lanzaboote`](https://github.com/nix-community/lanzaboote).
If not, you can disable secure boot in your Framework's BIOS. Spam `F2` while
you're booting up your computer, and you'll find the option under Secure boot.

Here you'll be greeted with the boot selector (just choose any of the kernel versions)

<picture>
  <source srcset="/assets/images/posts/nixos-on-framework-desktop/boot-selector.webp" type="image/webp">
  <img src="/assets/images/posts/nixos-on-framework-desktop/boot-selector.png" alt="a boot selector for NixOS with different kernel versions" loading="lazy">
</picture>

after choosing one, you'll see the terminal

<picture>
  <source srcset="/assets/images/posts/nixos-on-framework-desktop/terminal.webp" type="image/webp">
  <img src="/assets/images/posts/nixos-on-framework-desktop/terminal.png" alt="a terminal that shows up once you boot into a minimal NixOS ISO" loading="lazy">
</picture>

Great!

## Connecting through Wi-Fi

Since I haven't gotten around to running an ethernet cable just yet, I need to
connect to the internet through Wi-Fi. We'll need the `wpa_supplicant` service
for this.

```sh
[nixos@nixos:~]$ sudo systemctl start wpa_supplicant
[nixos@nixos:~]$ wpa_cli
wpa_cli v2.11
Copyright (c) 2004-2024, Jouni Malinen <j@w1.fi> and contributors

This software may be distributed under the terms of the BSD license.
See README for more details.

Selected interface 'wlp192s0'

Interactive mode

>
```

First scan for available Wi-Fi networks

```
> scan
OK
<3>CTRL-EVENT-SCAN-STARTED
<3>CTRL-EVENT-REGDOM-CHANGE init=BEACON_HINT type=UNKNOWN
<3>CTRL-EVENT-REGDOM-BEACON-HINT before freq=5240 max_tx_power=2000 no_ir=1
<3>CTRL-EVENT-REGDOM-BEACON-HINT after freq=5240 max_tx_power=2000
<3>CTRL-EVENT-SCAN-RESULTS
<3>WPS-AP-AVAILABLE
<3>CTRL-EVENT-NETWORK-NOT-FOUND
> scan_results
bssid / frequency / signal level / flags / ssid
MAC ADDRESS    FREQUENCY   FLAGS  [WPA2-PSK-CCMP]     SSID_NAME
```

You'll find your SSID at the end of each row. Just pick out which one matches
your SSID, and connect to it.

```
> add_network
0
<3>CTRL-EVENT-NETWORK-ADDED 0
> set_network 0 ssid "YOUR_SSID_NAME_HERE"
OK
> set_network 0 psk "YOUR_WIFI_PASSWORD_HERE"
OK
> enable_network 0
OK
<3>CTRL-EVENT-SCAN-STARTED
<3>CTRL-EVENT-SCAN-RESULTS
<3>WPS-AP-AVAILABLE
<3>SME: Trying to authenticate with YOUR_ROUTER_MAC_ADDRESS (SSID='YOUR_SSID_NAME' freq=5500 MHz)
<3>Associated with YOUR_ROUTER_MAC_ADDRESS
<3>CTRL-EVENT-SUBNET-STATUS-UPDATE status=0
<3>CTRL-EVENT-REGDOM-CHANGE init=COUNTRY_IE type=COUNTRY alpha2=YOUR_COUNTRY_CODE
<3>Channel list changed: 6 GHz was enabled
<3>WPA: Key negotiation completed with YOUR_ROUTER_MAC_ADDRESS [PKT=CCMP GTK=CCMP]
<3>CTRL-EVENT-CONNECTED - Connection to YOUR_ROUTER_MAC_ADDRESS completed [id=0 id_str=]
> ping google.com
PONG
```

Looks like we have internet now. :)

## Declarative disk partitioning

When I first installed NixOS a few years ago, I manually set up the partitions
which wasn't too bad but I always thought that it would be nice to have some
kind of declarative configuration for this since it didn't seem so dynamic in
nature. Fast forward to today, and we now have `disko`!

Let's yoink one of the example configurations on `disko`'s repository:

```sh
[nixos@nixos:~]$ curl \
  https://raw.githubusercontent.com/nix-community/disko/master/example/zfs-encrypted-root.nix \
  -o /tmp/disk-config.nix
```

This one is a sample configuration for a `zfs` pool with an encrypted root. In
the `disk` attribute, we need to define the physical devices in the system, and
the logical partitions we would like them to have. I only have one physical disk
under the name `/dev/nvme0n1` which I can verify with `lsblk`.

For this disk, I need 2 partitions: a boot partition (`ESP`) for the bootloader,
and a `zfs` partition for our pool.

```diff
{
  disko.devices = {
    disk = {
      root = {
        type = "disk";
        device = "/dev/nvme0n1";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
-               mountOptions = [ "nofail" ];
+               mountOptions = [ "umask=0077" ];
              };
            };
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "zroot";
              };
            };
          };
        };
      };
    };
### FOLD_START
    zpool = {
      zroot = {
        type = "zpool";
        rootFsOptions = {
          mountpoint = "none";
          compression = "zstd";
          acltype = "posixacl";
          xattr = "sa";
          "com.sun:auto-snapshot" = "true";
        };
        options.ashift = "12";
        datasets = {
          "root" = {
            type = "zfs_fs";
            options = {
              encryption = "aes-256-gcm";
              keyformat = "passphrase";
              #keylocation = "file:///tmp/secret.key";
              keylocation = "prompt";
            };
            mountpoint = "/";

          };
          "root/nix" = {
            type = "zfs_fs";
            options.mountpoint = "/nix";
            mountpoint = "/nix";
          };

          # README MORE: https://wiki.archlinux.org/title/ZFS#Swap_volume
          "root/swap" = {
            type = "zfs_volume";
            size = "10M";
            content = {
              type = "swap";
            };
            options = {
              volblocksize = "4096";
              compression = "zle";
              logbias = "throughput";
              sync = "always";
              primarycache = "metadata";
              secondarycache = "none";
              "com.sun:auto-snapshot" = "false";
            };
          };
        };
      };
### FOLD_END
    };
  };
}
```

> [!NOTE]
> I changed the `mountOptions` since I couldn't get it to boot with `nofail`.

For the `zfs` pool I want encryption, and compression enabled. I'm not going to
use `zfs`' `dedup` since `nix` has it built-in, and people generally caution from
using it. So for my datasets, I want:

- `root`
- `root/nix`
- `root/home`
- `root/persist`

You could add more if you need it for other purposes like movies/film that have
much larger file sizes that may benefit from a larger `recordsize`.

```diff
{
  disko.devices = {
### FOLD_START
    disk = {
      root = {
        type = "disk";
        device = "/dev/nvme0n1";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "zroot";
              };
            };
          };
        };
      };
### FOLD_END
    };
    zpool = {
      zroot = {
        type = "zpool";
        rootFsOptions = {
          mountpoint = "none";
          compression = "zstd";
          acltype = "posixacl";
          xattr = "sa";
-         "com.sun:auto-snapshot" = "true";
+         atime = "off";
+         # Encryption
+         encryption = "aes-256-gcm";
+         keyformat = "passphrase";
+         keylocation = "prompt";
        };
        options.ashift = "12";
        datasets = {
          "root" = {
            type = "zfs_fs";
-           options = {
-             encryption = "aes-256-gcm";
-             keyformat = "passphrase";
-             #keylocation = "file:///tmp/secret.key";
-             keylocation = "prompt";
-           };
+           options."com.sun:auto-snapshot" = "false";
            mountpoint = "/";
-
+           postCreateHook = "zfs list -t snapshot -H -o name | grep -E '^zroot/root@blank$' || zfs snapshot zroot/root@blank";
          };
          "root/nix" = {
            type = "zfs_fs";
-           options.mountpoint = "/nix";
            mountpoint = "/nix";
+           options."com.sun:auto-snapshot" = "false";
          };
-         # README MORE: https://wiki.archlinux.org/title/ZFS#Swap_volume
-         "root/swap" = {
-           type = "zfs_volume";
-           size = "10M";
-           content = {
-             type = "swap";
-           };
-           options = {
-             volblocksize = "4096";
-             compression = "zle";
-             logbias = "throughput";
-             sync = "always";
-             primarycache = "metadata";
-             secondarycache = "none";
-             "com.sun:auto-snapshot" = "false";
-           };
+         "root/home" = {
+           type = "zfs_fs";
+           mountpoint = "/home";
+           options."com.sun:auto-snapshot" = "true";
+         };
+         "root/persist" = {
+           type = "zfs_fs";
+           mountpoint = "/persist";
+           options."com.sun:auto-snapshot" = "true";
          };
        };
      };
  };
}
```

Some notes:

- Set `atime="off"` for performance [reasons](https://www.unixtutorial.org/zfs-performance-basics-disable-atime/)
- Added `root/nix` for all `nix` purposes
- Removed `root/swap` since there's this [issue](https://github.com/openzfs/zfs/issues/7734)
- Added encryption for root

If it all looks good, we can run `disko`

```sh
[nixos@nixos:~]$ sudo nix --experimental-features "nix-command flakes" run \
  github:nix-community/disko/latest -- \
  --mode destroy,format,mount \
  /tmp/disk-config.nix
```

...and somewhere along the process, it's going to prompt you for the passphrase for
encryption. So keep it somewhere safe (like a password manager)!

```sh
+ zpool create -f zroot -R /mnt -o ashift=12 -0 acltype=posixacl -0 atime=off -O compression=zstd -O encryption=aes-256-gcm -O keyformat=passphrase -O keylocation=prompt -O mountpoint=none -O xattr=sa /dev/disk/by-partitionlabel/disk-root-zfs
Enter new passphrase:
```

After all that, double check with `lsblk` if your disk is present with 2 partitions,
and all the datasets defined.

<picture>
  <source srcset="/assets/images/posts/nixos-on-framework-desktop/disk-check.webp" type="image/webp">
  <img src="/assets/images/posts/nixos-on-framework-desktop/disk-check.png" alt="results after running lsblk and zfs list" loading="lazy">
</picture>

So far everything looks good!

> [!NOTE]
> I added a `root/media` dataset but did not include it in the post.

## OS configuration

The fun part about NixOS is that majority of it can be configured with `nix`!

For demonstration purposes, we'll set up a basic, and minimal configuration for
booting into NixOS. Feel free to add more things later, or if you prefer to have
some other desktop environment for example.

First we need to generate some boilerplate configuration, and do a hardware scan
for NixOS to work. Normally, the hardware scan will include disks, and their
partitions. But since we're using `disko` to provide filesystem metadata, we
need to skip this.

Here are the important flags in `man nixos-generate-config`:

- `--root <ROOT>`: If this option is given, treat the directory `<ROOT>` as the root of
the file system. This means that configuration files will be written to `<ROOT>/etc/nixos`,
and that any file systems outside of `<ROOT>` are ignored for the purpose of generating the `fileSystems`
option.
- `--no-filesystems`: Omit everything concerning file systems and swap devices
from the hardware configuration.
- `--flake`: Also generate `/etc/nixos/flake.nix`

> [!NOTE]
> If you already have an existing flake configuration, you can skip `--flake`,
and instead use the generated `configuration.nix`, `hardware-configuration.nix`,
and `disk-config.nix` in a new `nixosConfigurations` attribute.

So to generate the initial config files:

```sh
[nixos@nixos:~]$ sudo nixos-generate-config --no-filesystems --flake --root /mnt
writing /mnt/etc/nixos/hardware-configuration.nix...
writing /mnt/etc/nixos/flake.nix...
writing /mnt/etc/nixos/configuration.nix...
For more hardware-specific settings, see https://github.com/NixOS/nixos-hardware
```

The last line tells us something interesting. It makes sense that for pre-built
machines, there has to be some bundle of configurations that already exists,
preferably from the manufacturer, to make it run smoothly. It turns out for
Framework machines, they have a bunch!

Finally, copy the `disk-config.nix` to the same directory as all the other files.

```sh
[nixos@nixos:~]$ sudo cp /tmp/disk-config.nix /mnt/etc/nixos/disk-config.nix
```

### Integrating `disko` into NixOS for hardware discovery

Earlier, we used `disko` to create partitions, and manage the `zfs` pool. But
we also need to integrate it into the NixOS configuration to make NixOS aware of
the filesystem configuration. You can follow `nix-communituy/disko` for the
latest setup guide but at the time of writing, add `disko` to the flake inputs,
and add it to the list of `modules` in the `nixosConfiguration` entry:

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs = inputs@{ self, nixpkgs, disko, ... }: {
    nixosConfigurations.litten = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";

      modules = [
        ./configuration.nix
        disko.nixosModules.disko
      ];
    };
  };
}
```

> [!WARNING]
> The default `flake.nix` comes with only an unstable version of `nixpkgs` included.
Generally it's preferable to have the latest release for the base instead, and
use unstable for a select few programs. Generally ones you need the latest versions
for.
>
> At the time of writing, the latest stable is `nixos-25.05`.

NixOS also has to be aware of the `disk-config.nix` file. To do so, in the
`configuration.nix` file, add `./disk-config.nix` in the list of imports:

```diff
  imports =
    [
      ./hardware-configuration.nix
+     ./disk-config.nix
    ];
```

and we want to tell `initrd` to load the `zfs` module:

```diff
boot.loader.systemd-boot.enable = true;
boot.loader.efi.canTouchEfiVariables = true;
+ boot.supportedFilesystems = [ "zfs" ];
+ boot.initrd.kernelModules = [ "zfs" ];
```

> [!CAUTION]
> You need to make sure that the current kernel version is supported by `zfs`.
> If you're using the current stable in NixOS, chances are it's fine. But double
> check if you are manually setting the `boot.kernelPackages` attribute.
>
> `zfs` indicates the upper bound of supported kernel versions in their
> [releases](https://github.com/openzfs/zfs/releases) page.

Finally, NixOS will complain if we don't [specify a host ID](https://wiki.nixos.org/wiki/ZFS#Installation
)
so we need to specify that.

So this [bit](https://search.nixos.org/options?channel=25.05&show=networking.hostId&query=hostId)
says you can generate one like so:

```sh
head -c4 /dev/urandom | od -A none -t x4
```

and while we're at it, you can also set your preferred host name. I named this
one `litten` cause it's tiny, and has a similar color scheme cause of its tiles
lol.

```diff
# networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";
+ networking.hostName = "litten";
+ networking.hostId = "REPLACE_ME";
```

On to the next!

### Framework-specific configuration

So circling back to existing configurations for the Framework Desktop, turns out
there's already one for it, and we just need to set it up in a similar way as
`disko`. Pretty convenient!

```diff
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
+   nixos-hardware.url = "github:NixOS/nixos-hardware";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
- outputs = inputs@{ self, nixpkgs, disko, ... }: {
+ outputs = inputs@{ self, nixpkgs, disko, nixos-hardware, ... }: {
    nixosConfigurations.litten = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";

      modules = [
        ./configuration.nix
        disko.nixosModules.disko
+       nixos-hardware.nixosModules.framework-desktop-amd-ai-max-300-series
      ];
    };
  };
}
```

We'll want to enable `networkmanager` to use Wi-Fi.

```diff
# Pick only one of the below networking options.
# networking.wireless.enable = true; # Enables wireless support via wpa_supplicant.
- # networking.networkmanager.enable = true; # Easiest to use and most distros use this by default.
+ networking.networkmanager.enable = true;
```

That's pretty much it.

### Setting up a user

We'll need a user to boot into

```diff
# Define a user account. Don't forget to set a password with `passwd`.
- # users.users.alice = {
- #   isNormalUser = true;
- #   extraGroups = [ "wheel" ] # Enable `sudo` for the user.
- #   packages = with pkgs; [
- #     tree
- #   ];
- # };
+ users.users.sekun = {
+   isNormalUser = true;
+   extraGroups = [ "wheel" "networkmanager" ];
+   packages = with pkgs; [];
+ };
```

Replace my name with whatever you want unless you're also sekun then, woah.

### Desktop environment

Switching desktop environments is probably one of the easiest things to do in
NixOS compared to other distros. Personally, I like KDE so I'm sticking with it.
Gnome has too much padding for my taste. Looks pretty though.

```diff
- # Enable the X11 windowing system.
- # services.xserver.enable = true;
+ services = {
+   xserver.enable = true;
+
+   displayManager.sddm.enable = true;
+   displayManager.sddm.wayland.enable = true;
+   desktopManager.plasma6.enable = true;
+ };
```

I still like leaving `X11` available just in case I need something that doesn't
work on wayland.

> [!NOTE]
> If you want to read up more on what DEs are available in NixOS:
[Category:Desktop environment](https://wiki.nixos.org/wiki/Category:Desktop_environment).
>
> You can also browse the available [options](https://search.nixos.org/options?query=desktopManager).

## Installation

Do go over the `configuration.nix` file to see what else you would like enabled!
If it all looks good, we're ready to install NixOS!

```sh
sudo nixos-install --root /mnt --flake '/mnt/etc/nixos#litten'
```

and at the end of the installation, it'll ask you to set the `root` user's password.
It should look something like this if everything goes well. `sudo reboot`, and
boot into NixOS!

<picture>
  <source srcset="/assets/images/posts/nixos-on-framework-desktop/installation-done.webp" type="image/webp">
  <img src="/assets/images/posts/nixos-on-framework-desktop/installation-done.png" alt="terminal after installing NixOS" loading="lazy">
</picture>

Here it asks us for the `zfs` pool's encryption passphrase. Nice.

<picture>
  <source srcset="/assets/images/posts/nixos-on-framework-desktop/root-unlock.webp" type="image/webp">
  <img src="/assets/images/posts/nixos-on-framework-desktop/root-unlock.png" alt="prompt asking for zpool root passphrase" loading="lazy">
</picture>


<picture>
  <source srcset="/assets/images/posts/nixos-on-framework-desktop/login-screen.webp" type="image/webp">
  <img src="/assets/images/posts/nixos-on-framework-desktop/login-screen.png" alt="sddm login screen" loading="lazy">
</picture>

## Conclusion

Documentation for ZFS in NixOS is still kind of sparse since I found answers
in different places. It's still enough to put something together but not without
effort.

The nice thing is you more or less only have to set up the configuration once.
After this, it's best to keep it somewhere easily accessible (like `git`) so that
you can download it, and just run `disko`, and `nixos-install`. I like that there
aren't as much "imperative" steps to setting up NixOS. It's one of the major
reasons why I've completely stopped distrohopping.

Managing KDE's configuration probably isn't the best experience even with the
plasma manager project. One is better off with another DE if that's important.
I'm just satisfied enough with KDE to not switch over to others yet. Plus I
mostly use stock KDE anyway.

Finally, this little machine is also such a capable thing! KDE is so much more
smoother vs my Ryzen 5950x + 3090ti back home. Well mainly because the Nvidia
experience in Linux is horrible. Maybe I'll benchmark a bunch of stuff in one of
these weekends.

---

So below are the complete files for `flake.nix`, `configuration.nix`, and `disk-config.nix`.
Or check out my configuration in [`sekunho/dotfiles`](https://github.com/sekunho/dotfiles)
(if it's already there).

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixos-hardware.url = "github:NixOS/nixos-hardware";
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/*";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs = inputs@{ self, nixpkgs, determinate, disko, nixos-hardware, ... }: {
    nixosConfigurations.litten = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";

      modules = [
        ./configuration.nix
        disko.nixosModules.disko
        nixos-hardware.nixosModules.framework-desktop-amd-ai-max-300-series
        determinate.nixosModules.default
      ];
    };
  };
}
```

```nix
# configuration.nix
{ config, lib, pkgs, ... }: {
  imports =
    [
      ./hardware-configuration.nix
      ./disk-config.nix
    ];

  boot = {
    kernelPackages = pkgs.linuxPackages_6_16;

    # Use the systemd-boot EFI boot loader.
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = true;

    supportedFilesystems = [ "zfs" ];
    initrd.kernelModules = [ "zfs" ];
  };

  # Set your time zone.
  time.timeZone = "Europe/Amsterdam";

  nixpkgs.config.allowUnfree = true;


  nix = {
    settings.trusted-public-keys = [
      "cache.flakehub.com-3:hJuILl5sVK4iKm86JzgdXW12Y2Hwd5G07qKtHTOcDCM="
    ];

    settings.substituters = [
      "https://nix-community.cachix.org"
    ];
  };

  networking = {
    hostName = "litten";
    hostId = "REPLACE_ME";
    networkmanager.enable = true;
  };

  services = {
    xserver.enable = true;

    displayManager.sddm.enable = true;
    displayManager.sddm.wayland.enable = true;
    desktopManager.plasma6.enable = true;

    # Enable sound
    pipewire = {
      enable = true;
      pulse.enable = true;
    };
  };

  users = {
    users.sekun = {
      isNormalUser = true;
      extraGroups = [ "wheel" "networkmanager" ];
      packages = with pkgs; [
        tree
      ];
    };
  };

  environment.systemPackages = with pkgs; [ vim ];
  system.stateVersion = "25.05"; # Did you read the comment?
}
```

```nix
# disk-config.nix
{
  disko.devices = {
    disk = {
      root = {
        type = "disk";
        device = "/dev/nvme0n1";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "zroot";
              };
            };
          };
        };
      };
    };
    zpool = {
      zroot = {
        type = "zpool";
        rootFsOptions = {
          acltype = "posixacl";
          atime = "off";
          compression = "zstd";
          mountpoint = "none";
          encryption = "aes-256-gcm";
          keyformat = "passphrase";
          #keylocation = "file:///tmp/secret.key";
          keylocation = "prompt";
          xattr = "sa";
        };
        options.ashift = "12";
        datasets = {
          "root" = {
            type = "zfs_fs";
            options."com.sun:auto-snapshot" = "false";
            mountpoint = "/";
            postCreateHook = "zfs list -t snapshot -H -o name | grep -E '^zroot/root@blank$' || zfs snapshot zroot/root@blank";
          };
          "root/nix" = {
            type = "zfs_fs";
            mountpoint = "/nix";
            options."com.sun:auto-snapshot" = "false";
          };

          "root/home" = {
            type = "zfs_fs";
            mountpoint = "/home";
            options."com.sun:auto-snapshot" = "true";
          };

          "root/persist" = {
            type = "zfs_fs";
            mountpoint = "/persist";
            options."com.sun:auto-snapshot" = "true";
          };
        };
      };
    };
  };
}
```

<picture>
  <source srcset="/assets/images/not-by-ai.webp" type="image/webp">
  <img style="width: 8rem;" src="/assets/images/not-by-ai.png" alt="not by AI" loading="lazy">
</picture>
