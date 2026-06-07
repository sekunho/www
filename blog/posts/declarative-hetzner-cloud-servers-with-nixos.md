---
title: "Declarative Hetzner Cloud Servers with NixOS"
created_at: 2026-06-07T19:15:00Z
updated_at:
tags: ["nixos", "nix", "hetzner", "tailscale", "terraform", "opentofu", "infrastructure"]
cover: "/assets/images/posts/installing-nixos-on-hetzner-cloud/cover.jpg"
custom:
    slug: declarative-hetzner-cloud-servers-with-nixos
    summary: Learn how to run NixOS servers on Hetzner Cloud. From ZFS disk configuration with disko, sops secrets management, and other gotchas along the way.

---

# {{ metadata.title }}

<span class="post-metadata">
  {{ metadata.created_at|published_on(format="short") }}
</span>

<div>
{% from "component/tags.html" import tags %}
{{ tags(metadata.tags) }}
</div>

<picture>
    <img src="{{ metadata.cover }}" alt="a framework desktop with a mini Hiro on top" loading="lazy">
</picture>

<h2 class="toc">Table of Contents</h2>

- **Chapter 1: The base setup** _(you are here)_. Provision and install NixOS
servers in a declarative way.
    1. [Introduction](#introduction)
    2. [Requirements](#requirements)
    3. [A simple server configuration](#a-simple-server-configuration)
        - a. [Creating a base Hetzner module](#creating-a-base-hetzner-module)
        - b. [Defining the server](#defining-the-server)
        - c. [Declarative disk configuration with `disko`](#declarative-disk-configuration-with-disko)
        - d. [Wiring them all up](#wiring-them-all-up)
        - e. [Test end-to-end setup #1](#test-end-to-end-setup-1)
    4. [Encrypting the ZFS root](#encrypting-the-zfs-root)
        - a. [Managing our first secret](#managing-our-first-secret)
        - b. [Test end-to-end setup #2](#test-end-to-end-setup-2)
    5. [Summary](#summary)
- **Chapter 2: Terraforming NixOS Servers** _(soon)_. Learn how to integrate `terraform` and NixOS to reduce the number of imperative
steps.
- **Chapter 3: A Private Internet with Tailscale and NixOS** _(soon)_. Use Tailscale
and their generous free tier to have your very own private internet.

> [!NOTE]
> If you don't have a Hetzner account already, you can use my
[referral](https://hetzner.cloud/?ref=LhJNRG7uVBqb) which gives you a free €20
credit, and gives me a €10 credit. Doing so helps me a lot as I'm able to pay
for Hetzner's services to tinker around!

<h2 id="introduction">1. Introduction</h2>

_This is chapter 1 of 3 for this short series about NixOS servers._

If you're curious about NixOS, and are wondering what it would be like to run it
on Hetzner Cloud's cheapest server (CX23), you might like this one. For the uninitiated,
NixOS is an operating system that you can configure almost entirely through a common
configuration language. With NixOS, the following can be declaratively configured:

1. ZFS disk configuration with native ZFS encryption + `zstd` compression
2. `systemd` services
3. secrets management
4. tailscale integration
    - Accessing machines via `tailscale` SSH
    - Broadcasting private services within the tailnet (e.g `foo-service.my.ts.net` to expose a `foo` website)

You can definitely do more, but this is just to whet your appetite. Normally if
you were to do this with other Linux distributions, you need a third party tool
like `ansible` to achieve something similar.

> [!NOTE]
_Wait, sekun, another NixOS article?_
>
> Okay, you got me. But this time I wanted to yap about it again because the common
approach is to have a distinct two-phase installation where the first phase sets
up the core configuration + services while the second phase sets up the server-specific
configuration.

To demonstrate, we'll set up a NixOS server that serves a simple HTML page via `caddy`,
and this will only be accessible within the tailnet. This is deliberately kept simple
as the focus will be on the boring stuff: configurations, setup, and plumbing.

<figure>
  <img src="/assets/images/posts/installing-nixos-on-hetzner-cloud/diagram.svg">
  <caption>
      Figure 1.1 - A diagram of a simple VPS running a website that's only accessible
      within a tailnet.
  </caption>
</figure>

Seems simple enough! But also maybe interesting enough for you, dear reader. :D

The cool thing about this is you can replace or extend the caddy server to act
as a reverse proxy for other private services like your own file hosting, or
media server solely within your tailnet for pretty cheap.

I'll show you a workflow where once the installation command is executed, everything
will be provisioned without any additional steps. I'll deliberately keep some steps
manual so that you'll have the flexibility to automate it however you wish. Throughout
the article though, we'll be running the installation _a lot_ to validate if things
were set up correctly, and so that it's not so boring.

<h2 id="requirements">
    <a href="#requirements">
        2. Requirements
    </a>
</h2>

You'll need:

1. a Hetzner account
2. an existing NixOS machine. You'll need one to communicate with the NixOS host.
3. `nix` flakes feature enabled
4. a tailscale account
5. internet

This also assumes you know a thing or two about NixOS, Tailscale, and terraform.

<h2 id="a-simple-server-configuration">
    <a href="#a-simple-server-configuration">3. A simple server configuration</a>
</h2>

To start, we can initialize a flake with `nix flake init` although it's fairly
barebones. That generates a basic `flake.nix` file which will be the glue for everything.

Let's add a `nix` language server and formatter. You don't need to add these if
you prefer not to though. I like having these around to make working on `nix`
sources easier.

```diff
# flake.nix
{
- description = "A very basic flake";
-
  inputs = {
-    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
+    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
  };

- outputs = { self, nixpkgs }: {
+ outputs = { self, nixpkgs }:
+ let
+   system = "x86_64-linux";
+   pkgs = import nixpkgs { inherit system; };
+ in
+ {
-
-   packages.x86_64-linux.hello = nixpkgs.legacyPackages.x86_64-linux.hello;
-
-   packages.x86_64-linux.default = self.packages.x86_64-linux.hello;
-
+   devShells.${system}.default = pkgs.mkShell {
+     buildInputs = with pkgs; [ nixd nixpkgs-fmt ];
+   };
  };
}
```

Here we create a development shell for `x86_64-linux` machines with `nixd`, and
`nixpkgs-fmt` available. This can either be activated through `nix develop` or
automatically using `direnv`.

> [!NOTE]
At the time of writing, the latest stable release is 26.05. Ideally you should
pin the base system to a stable release and granularly use the unstable branch
for specific things.

So our strategy is to make things modular enough such that we're able to reuse
relevant configurations easily.

1. What are the configurations common across all Hetzner servers?
2. What are the configurations that diverge from each other?

<figure>
  <img src="/assets/images/posts/installing-nixos-on-hetzner-cloud/servers-modules.svg">
  <caption>
      Figure 1.2 - Two NixOS servers with shared modules, and unique modules. Now
      it feels a lot like putting legos together.
  </caption>
</figure>

With those questions we can split configurations into modules. Each Hetzner server
will have a core module for all things Hetzner, then another module for `tailscale`,
etc. That way we only really have to define these things once, and we can plug-and-play
configurations.

That's the high-level idea anyway. Let's make this more concrete!

<h3 id="creating-a-base-hetzner-module">
    <a href="#creating-a-base-hetzner-module">3a. Creating a base Hetzner module</a>
</h3>

Let's start with the base Hetzner configuration first. In every server we need
SSH access and an operator user. The operator user will serve as the main account
for the usual admin work. Each server also has a hardware configuration, and a
disk configuration. The former will be auto-generated but the latter would have
to be configured separately.

```nix
# modules/hetzner/default.nix
{ modulesPath, operatorPublicKeys, extraGroups }: {
  # TODO(1): Add disk configuration
  imports = [
    ./hardware-configuration.nix
  ];

  # 1
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      X11Forwarding = false;
      AllowUsers = [ "operator" ];
    };
    extraConfig = ''
      MaxAuthTries 2
      ChallengeResponseAuthentication no
      AllowTcpForwarding no
      AllowAgentForwarding no
    '';
  };

  # 2
  security.sudo.wheelNeedsPassword = false;

  # 3
  users.users = {
    operator = {
      isNormalUser = true;
      uid = 1000;
      home = "/home/operator";
      extraGroups = [ "wheel" "networkmanager" ] ++ extraGroups;
      group = "users";
      openssh.authorizedKeys.keys = operatorPublicKeys;
    };
  };

  # 4
  boot = {
    loader.grub = {
      enable = true;
      efiSupport = true;
      efiInstallAsRemovable = true;
    };
  };
}
```

Some points:

1. `imports`: Technically the `hardware-configuration.nix` file does not exist
yet but this file is auto-generated so we don't need to create it. The only
thing we need to set up is the disk configuration.
2. `services.openssh`: This is for basic server hardening. There's no reason for
us to use passwords for SSH sessions nor should we allow root logins. We'll have
one `sudo` user for admin work instead which would require an SSH key.
3. Our user accounts don't have passwords so this should be disabled. There are
also times when builds freeze because it asks for a password, despite the absence
of it.
4. `users.users.operator`: I like adding a common `operator` user across my machines just
to make things consistent. You don't have to do this but it takes one less block
of configs out of the downstream host configurations. Removes redundancy, and
guess work.
5. `boot.loader.grub`: You will need this for the VPS to boot. Don't be like
<a href="https://bsky.app/profile/sekun.net/post/3ma7u7wii5c2z" target="_blank">me</a>.
Hetzner uses BIOS for their older machines but has UEFI enabled for their newer
ones. I'll elaborate a bit more in [2c. Declarative disk configuration with `disko`](#declarative-disk-configuration-with-disko).

<h3 id="defining-the-server">
    <a href="#defining-the-server">3b. Defining the server</a>
</h3>

Let's add a simple server configuration to start with. It won't do much for now
though.

```nix
{ self, config, pkgs, ... }: {
  networking = {
    hostName = "server-a";

    firewall = {
      enable = true;
      trustedInterfaces = [];
      allowedTCPPorts = [ 22 ];
      allowedUDPPorts = [];
    };
  };

  services = {
    caddy = {
      enable = true;

      virtualHosts = {
        "http://localhost:8080".extraConfig = ''
            respond "hello, world!"
        '';
      };
    };
  };

  systemd.services.caddy.serviceConfig.TimeoutStopSec = 10;
  system.stateVersion = "26.05";
}
```

This sets up a `caddy` server that's listening to port 8080, and responds with
`hello, world!`. But we can't run this yet. So, disk configuration next!

<h3 id="declarative-disk-configuration-with-disko">
    <a href="#declarative-disk-configuration-with-disko">3c. Declarative disk configuration with disko</a>
</h3>

Back then you used to have to run a series of imperative commands to set up a `zfs`
disk configuration which in fairness was documented well enough for Linux. But these
days it's much better because of [`disko`](https://github.com/nix-community/disko)!

In terms of configuration, I recommend you check out the `disko` repository's
examples directory. I yoinked my configuration from there, and manually tested
if it worked or not.

> [!NOTE]
I've also written about it in [NixOS on Framework Desktop](/blog/nixos-on-framework-desktop#declarative-disk-partitioning).
If ever you're curious about how you could set it up for that lil' machine.

To start, let's fetch a sample `zfs` + native encryption configuration. But
let's worry about the root encryption later.

```sh
$ mkdir -p modules/hetzner
$ curl \
    https://raw.githubusercontent.com/nix-community/disko/2db1d64fc084b1d15e3871dffc02c62a94ed6ed7/example/zfs-encrypted-root.nix \
    -o modules/hetzner/disk-config.nix
```

> [!NOTE]
You can use the [`master` branch](https://raw.githubusercontent.com/nix-community/disko/master/example/zfs-encrypted-root.nix)
for the latest example but these don't get updated often.

Here's what we're starting with:

```nix
# modules/hetzner/disk-config.nix
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
                mountOptions = [ "nofail" ];
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

The `disko.devices.disk` bit is where we'll define the VPS' actual devices. Typically
for VPS it has a single drive at `/dev/sda`, and we'll define some partitions in this.
Hetzner [seems](https://old.reddit.com/r/hetzner/comments/hpsop8/hetzner_cloud_server_os_boot_uefi_or_bios/fy53gpc/) to use
BIOS as the default, not UEFI hence why we need to specify a `boot` partition. However,
it also seems like newer servers are now using UEFI by default, and Hetzner [recommends](https://docs.hetzner.cloud/changelog#2023-08-23-old-server-types-with-dedicated-amd-vcpus-are-deprecated)
that we also have an ESP partition just in case you'd want to use the newer ones.
We then allocate the rest of the disk to the `zfs` partition for your pool.

Feel free to adjust the `boot` and `esp` partition size according to your needs.

```diff
# modules/hetzner/disk-config.nix
{
  disko.devices = {
    disk = {
      root = {
        type = "disk";
-       device = "/dev/nvme0n1";
+       device = "/dev/sda";
        content = {
          type = "gpt";
          partitions = {
+           boot = {
+             size = "1M";
+             type = "EF02";
+           };
-           ESP = {
+           esp = {
-             size = "1G";
+             size = "500M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
-               mountOptions = [ "nofail" ];
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
> For the partition types, I'm referencing the arch (btw) [wiki](https://wiki.archlinux.org/title/GPT_fdisk#Partition_type).
> The `type` here refers to the `gdisk` code!

The next part is the `disko.devices.zpool`, and this is where we can define
our ZFS pool. We can mostly leave it as is but we have to comment out the
encryption-related attributes first. I also prefer to remove swap but this would
be entirely up to you! Let's also disable `atime` for [performance reasons](https://www.unixtutorial.org/zfs-performance-basics-disable-atime/).

```diff
# modules/hetzner/disk-config.nix
{
  disko.devices = {
### FOLD_START
    disk = {
      root = {
        type = "disk";
        device = "/dev/sda";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              size = "1M";
              type = "EF02";
            };
            esp = {
              size = "500M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
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
        };
        options.ashift = "12";
        datasets = {
          "root" = {
            type = "zfs_fs";
            options = {
-             encryption = "aes-256-gcm";
-             keyformat = "passphrase";
-             #keylocation = "file:///tmp/secret.key";
-             keylocation = "prompt";
+             #encryption = "aes-256-gcm";
+             #keyformat = "passphrase";
+             #keylocation = "prompt";
            };
            mountpoint = "/";
-
          };

### FOLD_START
          "root/nix" = {
            type = "zfs_fs";
            options.mountpoint = "/nix";
            mountpoint = "/nix";
### FOLD_END
          };
-
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
-         };
        };
      };
    };
  };
}
```

And then update the Hetzner module

```diff
# modules/hetzner/default.nix
{ modulesPath, operatorPublicKeys, extraGroups }: {
- # TODO(1): Add disk configuration
  imports = [
    ./hardware-configuration.nix
+   ./disk-config.nix
  ];

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
  };

  security.sudo.wheelNeedsPassword = false;

  users.users = {
    operator = {
      isNormalUser = true;
      uid = 1000;
      home = "/home/operator";
      extraGroups = [ "wheel" "networkmanager" ] ++ extraGroups;
      group = "users";
      openssh.authorizedKeys.keys = operatorPublicKeys;
    };
  };

  boot = {
    loader.grub = {
      enable = true;
      efiSupport = true;
      efiInstallAsRemovable = true;
    };
  };
}
```

> [!WARNING]
If you plan to have varying disk configurations per host, then it would be better
to remove `disk-config.nix` from the Hetzner module, and instead add it to the
server's modules instead. e.g [`disko` fresh install](https://github.com/nix-community/disko/blob/f64ab1525b34d5d9202f5801db36f364075abde1/docs/disko-install.md#fresh-installation)

<h3 id="wiring-them-all-up">
    <a href="#wiring-them-all-up">3d. Wiring them all up</a>
</h3>

Let's wire the Hetzner module, `disko`, and the `server-a` configurations!

```diff
# flake.nix
{
  inputs = {
     nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
+    disko.url = "github:nix-community/disko/latest";
+    disko.inputs.nixpkgs.follows = "nixpkgs";
  };

- outputs = { self, nixpkgs }:
+ outputs = { self, nixpkgs, disko }:
  let
    system = "x86_64-linux";
    pkgs = import nixpkgs { inherit system; };
  in
  {
+   nixosModules = {
+     hetzner = import ./modules/hetzner/default.nix;
+   };
+
+   nixosConfigurations = {
+     server-a = nixpkgs.lib.nixosSystem {
+       system = "x86_64-linux";
+       modules = [
+         disko.nixosModules.disko
+         self.nixosModules.hetzner
+         ./hosts/server-a/configuration.nix
+       ];
+       specialArgs = {
+         inherit self;
+         operatorPublicKeys = [ "<USER_A_PUBLIC_SSH_KEY_HERE>" ];
+         extraGroups = [];
+       };
+     };
+   };
+
    devShells.${system}.default = pkgs.mkShell {
      buildInputs = with pkgs; [ nixd nixpkgs-fmt ];
    };
  };
}
```

- A NixOS system (like `server-a`) can have a list of modules that each may
configure the overall system.
- `nixosSystem.specialArgs`: allows us to pass along specific arguments to its
modules and configurations. `modules/hetzner/default.nix`, `operatorPublicKeys`
and `extraGroups` will be passed along to the Hetzner module to configure the
`operator` user.

```sh
$ nix flake show
git+file:///home/sekun/Projects/sekun.net?dir=examples/nixos-on-hetzner
├───devShells
│   └───x86_64-linux
│       └───default: development environment 'nix-shell'
├───nixosConfigurations
│   └───server-a: NixOS configuration
└───nixosModules
    └───hetzner: NixOS module
```

Okay, let's try doing a test installation! We'll be using `nixos-anywhere` to
target the host, and install NixOS!

> [!NOTE]
> **Why nixos-anywhere**?
A few years back, I used `nixos-infect` to do the installations for me, and
while it worked, it required me to manually move things around the configuration
files it generated. Then came along `nixos-anywhere` where it allowed me to use
an existing NixOS configuration and even had support for `disko` and other conveniences.
It allowed for a more seamless and more integrated installation process.

<h3 id="test-end-to-end-setup-1">
    <a href="#test-end-to-end-setup-1">3e. Test end-to-end setup #1</a>
</h3>

We need to run this against an actual Hetzner server just to verify that it all
works as intended.

Add `hcloud` (Hetzner Cloud's CLI), and `nixos-anywhere` (NixOS installer) to our
dev shell:

```diff
# flake.nix
{
  inputs = {
     nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
     disko.url = "github:nix-community/disko/latest";
     disko.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, disko }:
  let
    system = "x86_64-linux";
    pkgs = import nixpkgs { inherit system; };
  in
  {
### FOLD_START
    nixosModules = {
      hetzner = import ./modules/hetzner/default.nix;
### FOLD_END
    };

### FOLD_START
    nixosConfigurations = {
      server-a = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          disko.nixosModules.disko
          self.nixosModules.hetzner
          ./hosts/server-a/configuration.nix
        ];
        specialArgs = {
          inherit self;
          operatorPublicKeys = [ "<USER_A_PUBLIC_SSH_KEY_HERE>" ];
          extraGroups = [];
        };
      };
### FOLD_END
    };

    devShells.${system}.default = pkgs.mkShell {
-     buildInputs = with pkgs; [ nixd nixpkgs-fmt ];
+     buildInputs = with pkgs; [ nixd nixpkgs-fmt hcloud nixos-anywhere ];
    };
  };
}
```

Then you can [create](https://docs.hetzner.com/cloud/api/getting-started/generating-api-token/)
a Hetzner API token so that we can manage our project's resources programmatically,
and add it to our `hcloud` context:

```sh
$ hcloud context create test-project
Token: <PASTE_YOUR_HCLOUD_API_TOKEN_HERE>
Context test-project created and activated
```

Then we need to configure the server just a little bit, and this can be done through
`cloud-init`:

```yaml
#cloud-config
# user_data.yaml
timezone: UTC
# 1 - https://docs.cloud-init.io/en/latest/reference/yaml_examples/user_groups.html
users:
  - name: tmp
    groups:
      - users
      - admin
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      # TODO: Replace this with your actual public SSH key(s).
      - ssh-...
# 2 - https://docs.cloud-init.io/en/latest/reference/yaml_examples/package_update_upgrade.html#cce-update-upgrade
packages:
  - fail2ban
  - ufw
package_update: true
package_upgrade: true
# 3 - https://docs.cloud-init.io/en/latest/reference/yaml_examples/write_files.html
write_files:
  - path: /etc/ssh/sshd_config.d/ssh-hardening.conf
    content: |
      PermitRootLogin no
      PasswordAuthentication no
      KbdInteractiveAuthentication no
      ChallengeResponseAuthentication no
      AllowTcpForwarding no
      X11Forwarding no
      AllowAgentForwarding no
      AuthorizedKeysFile .ssh/authorized_keys
      MaxAuthTries 2
      AllowUsers tmp
# 4 - https://docs.cloud-init.io/en/latest/reference/modules.html#runcmd
runcmd:
  - printf "[sshd]\nenabled = true\nport = ssh, 22\nbanaction = iptables-multiport" > /etc/fail2ban/jail.local
  - systemctl enable fail2ban
  - ufw allow 22
  - ufw enable
  - reboot
```

> [!WARNING]
It is very important you include `#cloud-config` on the first line otherwise
it's not going to work!

Explanation time:

1. We need to create a non-root `sudo` user. This is what `nixos-anywhere` will
use during the entire NixOS installation process. It's a good idea to disable
`root` login, and instead create a user without that kind of privilege. We're
assigning it to the `users` group, and the `admin` group which is part of sudoers.
Then assign the public key so that you can login through `ssh` as this user.
2. Just some general package updating to make sure we're all up to date. We want
to add the `fail2ban` and `ufw` (firewall) packages as we'll use these for basic
hardening so that nobody can try anything during the setup process.
3. This is where we configure `sshd` to disable root login, password login,
and limiting the number of login retries to 2 failures. Stuff like `AllowUsers`
and `AuthorizedKeysFile` allows us to login as `tmp` using the `ssh` key.
4. Enables `fail2ban` and `ufw` so that we don't expose any more ports than necessary.

That's more or less the gist of it. If you want to read more about `cloud-init`,
I've linked it in the example for those specific sections. The docs aren't that
great but it...helps?

Add your SSH key to Hetzner

```sh
$ hcloud ssh-key create \
    --name user-a \
    --public-key-from-file ~/.ssh/id_ed25519.pub
SSH Key <SSH_KEY_ID> created
```

Then create the server!

```sh
# Check the server types available, and their locations.
# Right now CX23 is the cheapest.
$ hcloud server-type list
ID    NAME    CORES   CPU TYPE    ARCHITECTURE   MEMORY     DISK     LOCATION
22    cpx11   2       shared      x86            2.0 GB     40 GB    ash, hil
23    cpx21   3       shared      x86            4.0 GB     80 GB    ash, hil
24    cpx31   4       shared      x86            8.0 GB     160 GB   ash, hil
25    cpx41   8       shared      x86            16.0 GB    240 GB   ash, hil
26    cpx51   16      shared      x86            32.0 GB    360 GB   ash, hil
45    cax11   2       shared      arm            4.0 GB     40 GB    fsn1, nbg1, hel1
93    cax21   4       shared      arm            8.0 GB     80 GB    fsn1, nbg1, hel1
94    cax31   8       shared      arm            16.0 GB    160 GB   fsn1, nbg1, hel1
95    cax41   16      shared      arm            32.0 GB    320 GB   fsn1, nbg1, hel1
96    ccx13   2       dedicated   x86            8.0 GB     80 GB    fsn1, nbg1, hel1, ash, hil, sin
97    ccx23   4       dedicated   x86            16.0 GB    160 GB   fsn1, nbg1, hel1, ash, hil, sin
98    ccx33   8       dedicated   x86            32.0 GB    240 GB   fsn1, nbg1, hel1, ash, hil, sin
99    ccx43   16      dedicated   x86            64.0 GB    360 GB   fsn1, nbg1, hel1, ash, hil, sin
100   ccx53   32      dedicated   x86            128.0 GB   600 GB   fsn1, nbg1, hel1, ash, hil, sin
101   ccx63   48      dedicated   x86            192.0 GB   960 GB   fsn1, nbg1, hel1, ash, hil, sin
108   cpx12   1       shared      x86            2.0 GB     40 GB    sin
109   cpx22   2       shared      x86            4.0 GB     80 GB    fsn1, nbg1, hel1, sin
110   cpx32   4       shared      x86            8.0 GB     160 GB   fsn1, nbg1, hel1, sin
111   cpx42   8       shared      x86            16.0 GB    320 GB   fsn1, nbg1, hel1, sin
112   cpx52   12      shared      x86            24.0 GB    480 GB   fsn1, nbg1, hel1, sin
113   cpx62   16      shared      x86            32.0 GB    640 GB   fsn1, nbg1, hel1, sin
114   cx23    2       shared      x86            4.0 GB     40 GB    fsn1, nbg1, hel1
115   cx33    4       shared      x86            8.0 GB     80 GB    fsn1, nbg1, hel1
116   cx43    8       shared      x86            16.0 GB    160 GB   fsn1, nbg1, hel1
117   cx53    16      shared      x86            32.0 GB    320 GB   fsn1, nbg1, hel1

# Creates a server along with a non-root sudo user `tmp`.
$ hcloud server create \
    --image ubuntu-24.04 \
    --name server-a \
    --ssh-keys user-a \
    --type cx23 \
    --location nbg1 \
    --user-data-from-file ./user_data.yaml
 ✓ Waiting for create_server       100% 28s (server: <SERVER_ID>, image: <IMAGE_ID>)
 ✓ Waiting for start_server        100% 28s (server: <SERVER_ID>)
Server <SERVER_ID> created
IPv4: <IPV4_ADDRESS>
IPv6: <IPV6_ADDRESS>
IPv6 Network: <IPV6_NETWORK>
```

> [!WARNING]
Even if 26.04 is the latest Ubuntu LTS, I ran into an [odd error](https://bsky.app/profile/sekun.net/post/3mnn2yvuvks2r)
with `kexec` when installing NixOS. Works fine for 24.04 though. You could also
use a beefier VM like `cx33` to avoid the `kexec_file_load failed: Address not available`
error.

<br>

> [!NOTE]
Technically we don't need the `root` user to have an SSH key because we're not
allowing `root` logins anyway but if this isn't provided then Hetzner will assign
it a password which I don't want.

```sh
$ IPV4=<SERVER_IPV4>

# Run the installation
$ nix run github:nix-community/nixos-anywhere -- \
      --print-build-logs \
      --flake .#server-a \
      --target-host tmp@$IPV4 \
      -i /path/to/private/ssh/key \
      --generate-hardware-config nixos-generate-config ./modules/hetzner/hardware-configuration.nix
```

- `--print-build-logs` is a purely debugging thing. I usually disable this after
I know the installation goes well once.
- `--flake .#server-a` uses the `server-a` configuration
- `-i /path/to/private/ssh/key`: since we restricted the `MaxAuthRetries` to 2,
we need to specify which SSH key we want to use otherwise `ssh` will try every
single key in `~/.ssh`.
- `--generate-hardware-config` generates the hardware configuration that we
needed earlier.

You'll see something like this if it all goes well:

```sh
# ...
SSH COMMAND: ssh -t -o IdentitiesOnly=yes -i /tmp/tmp.o3owFaxvfz/nixos-anywhere -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root@<SERVER_IP>
9 sh

Pseudo-terminal will not be allocated because stdin is not a terminal.
Warning: Permanently added '<SERVER_IP>' (ED25519) to the list of known hosts.
umount: /mnt/nix (zroot/root/nix) unmounted
umount: /mnt/boot unmounted
umount: /mnt (zroot/root) unmounted
+ step Waiting for the machine to become unreachable due to reboot
+ echo '### Waiting for the machine to become unreachable due to reboot ###'
### Waiting for the machine to become unreachable due to reboot ###
+ runSshTimeout -- exit 0
+ timeout 10 ssh -o IdentitiesOnly=yes -i /tmp/tmp.o3owFaxvfz/nixos-anywhere -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no tmp@<SERVER_IP> -
- exit 0
Warning: Permanently added '<SERVER_IP>' (ED25519) to the list of known hosts.
+ sleep 1
+ runSshTimeout -- exit 0
+ timeout 10 ssh -o IdentitiesOnly=yes -i /tmp/tmp.o3owFaxvfz/nixos-anywhere -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no tmp@<SERVER_IP> -
- exit 0
Warning: Permanently added '<SERVER_IP>' (ED25519) to the list of known hosts.
+ sleep 1
+ runSshTimeout -- exit 0
+ timeout 10 ssh -o IdentitiesOnly=yes -i /tmp/tmp.o3owFaxvfz/nixos-anywhere -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no tmp@<SERVER_IP> -
- exit 0
Warning: Permanently added '<SERVER_IP>' (ED25519) to the list of known hosts.
+ sleep 1
+ runSshTimeout -- exit 0
+ timeout 10 ssh -o IdentitiesOnly=yes -i /tmp/tmp.o3owFaxvfz/nixos-anywhere -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no tmp@<SERVER_IP> -
- exit 0
Warning: Permanently added '<SERVER_IP>' (ED25519) to the list of known hosts.
+ sleep 1
+ runSshTimeout -- exit 0
+ timeout 10 ssh -o IdentitiesOnly=yes -i /tmp/tmp.o3owFaxvfz/nixos-anywhere -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no tmp@<SERVER_IP> -
- exit 0
ssh: connect to host <SERVER_IP> port 22: Connection refused
+ step 'Done!'
+ echo '### Done! ###'
### Done! ###
+ rm -rf /tmp/tmp.o3owFaxvfz
```

```sh
$ ssh operator@<SERVER_IP>
The authenticity of host '<SERVER_IP> (<SERVER_IP>)' can't be established.
ED25519 key fingerprint is: <FINGERPRINT>
This key is not known by any other names.
Are you sure you want to continue connecting (yes/no/[fingerprint])? yes
Warning: Permanently added '<SERVER_IP>' (ED25519) to the list of known hosts.

[operator@server-a:~]$ echo hi
hi

[operator@server-a:~]$ curl localhost:8080
hello, world!
```

So now we have our operator user! Our `caddy` service is also running. If we try
to login as `root`, it'll kick us out:

```sh
$ ssh root@<SERVER_IP>
root@<SERVER_IP>: Permission denied (publickey,keyboard-interactive).
```

<h2 id="encrypting-the-zfs-root">
    <a href="#encrypting-the-zfs-root">4. Encrypting the ZFS root</a>
</h2>

`disko` also allows us to encrypt the ZFS root, and to set the disk key from a
file. Let's uncomment the relevant options that we commented out earlier:

```diff
# modules/hetzner/disk-config.nix
{
  disko.devices = {
### FOLD_START
    disk = {
      root = {
        type = "disk";
        device = "/dev/sda";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              size = "1M";
              type = "EF02";
            };
            esp = {
              size = "500M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
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
        };
        options.ashift = "12";
        datasets = {
          "root" = {
            type = "zfs_fs";
            options = {
-             #encryption = "aes-256-gcm";
-             #keyformat = "passphrase";
-             #keylocation = "prompt";
+             encryption = "aes-256-gcm";
+             keyformat = "passphrase";
+             keylocation = "file:///persist/secrets/disk-key";
            };
            mountpoint = "/";
-
          };

### FOLD_START
          "root/nix" = {
            type = "zfs_fs";
            options.mountpoint = "/nix";
            mountpoint = "/nix";
### FOLD_END
          };

          # README MORE: https://wiki.archlinux.org/title/ZFS#Swap_volume
### FOLD_START
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
### FOLD_END
          };
        };
      };
    };
  };
}
```

- `encryption`: The type of encryption we're using for the root dataset
- `keyformat`: Set to passphrase as we're sourcing the disk key from a file.
- `keylocation`: Path of the disk key. This must be available before the ZFS pool
is made available during boot to unlock the pool.

Since it needs to check `/persist/secrets` for the disk key, we need to create
a dataset for that as well. I'm also removing swap cause I don't really need
it but if you feel that you'll need it then read the wiki link first.

```diff
# modules/hetzner/disk-config.nix
{
  disko.devices = {
### FOLD_START
    disk = {
      root = {
        type = "disk";
        device = "/dev/sda";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              size = "1M";
              type = "EF02";
            };
            esp = {
              size = "500M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
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
        };
        options.ashift = "12";
        datasets = {
          "root" = {
            type = "zfs_fs";
            options = {
              encryption = "aes-256-gcm";
              keyformat = "passphrase";
              keylocation = "file:///persist/secrets/disk-key";
            };
            mountpoint = "/";
          };

### FOLD_START
          "root/nix" = {
            type = "zfs_fs";
            options.mountpoint = "/nix";
            mountpoint = "/nix";
### FOLD_END
          };

+         "root/persist" = {
+           type = "zfs_fs";
+           mountpoint = "/persist";
+         };
-
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
-         };
        };
      };
    };
  };
}
```

Now that we have our disk configuration in place, we can add it to our Hetzner
module's imports so that it's aware of it. Since we need the disk key to be
available before the ZFS pool is unlocked, we need to copy it over to `initrd`.

```diff
# modules/hetzner/default.nix
{ modulesPath, operatorPublicKeys, extraGroups }: {
  imports = [
    ./hardware-configuration.nix
    ./disk-config.nix
  ];

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
  };

  security.sudo.wheelNeedsPassword = false;

  users.users = {
    operator = {
      isNormalUser = true;
      uid = 1000;
      home = "/home/operator";
      extraGroups = [ "wheel" "networkmanager" ] ++ extraGroups;
      group = "users";
      openssh.authorizedKeys.keys = operatorPublicKeys;
    };
  };

  boot = {
    loader.grub = {
      enable = true;
      efiSupport = true;
      efiInstallAsRemovable = true;
    };
+
+   initrd.secrets."/persist/secrets/disk-key" = "/persist/secrets/disk-key";
+   zfs.requestEncryptionCredentials = true;
  };
}
```

<h3 id="managing-our-first-secret">
    <a href="#managing-our-first-secret">4a. Managing our first secret</a>
</h3>

We ran into our first secret! Now what?

I wrote a post [_Manage secrets in NixOS_](/blog/manage-secrets-in-nixos/) a while
back that uses `agenix` but I've explored a few options since. Admittedly, it
was pretty tedious and confusing. I was able to try out [`sops-nix`](https://github.com/Mic92/sops-nix)
recently, and I've come to greatly prefer the ergonomics of it so it's what I will use here.

The main challenges I ran into with `agenix` back then were:

1. I had to manually send the secrets over to the host machines. This was okay
if I used something like `colmena` but I don't think my use case quite fits it
at the moment. That left me with manually `scp`-ing them over which was suboptimal.
Whereas `sops-nix` allows me to define those secrets, and automatically sends them
over to the host machines.
2. It was just confusing. `sops-nix`'s way of accessing secrets just fits my mental
model more than `agenix` did. This is more subjective of course. I don't expect
everyone to agree with this!

Anyway, this step is probably the most tedious part as it requires some setup before we
can use it. But it's somehow still less tedious than dealing with a separate service
for secrets, and my use case does not require complex access permissions to justify
those at the moment.

Let's add `sops` and `ssh-to-age` to the dev shell first.

```diff
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
  };

  outputs = { self, nixpkgs }:
  let
    system = "x86_64-linux";
    pkgs = import nixpkgs { inherit system; };
  in
  {
    nixosModules = {
      hetzner = import ./modules/hetzner/default.nix;
    };

    devShells.${system}.default = pkgs.mkShell {
-     buildInputs = with pkgs; [ nixd nixpkgs-fmt ];
+     buildInputs = with pkgs; [
+       nixd
+       nixpkgs-fmt
+       sops
+       ssh-to-age
+     ];
    };
  };
}
```

With `sops-nix` you can define who/what can read/manage secrets, and this is
defined in the `.sops.yaml` file. For this chapter, we only need `user_a` and it
should be able to access the glob `hosts/server_a/secrets/[^/]+\.(yaml|json|env|ini)$`.
We're assuming that we are this user as we need to be able to access, and decrypt
keys as well.

```yaml
# .sops.yaml
keys:
  - &user_a <REPLACE_WITH_YOUR_USER_AGE_KEY>
creation_rules:
  - path_regex: hosts/server-a/secrets/[^/]+\.(yaml|json|env|ini)$
    key_groups:
    - age:
      - *user_a
```

If you haven't already, you need to [create](<a href="https://git-scm.com/book/en/v2/Git-on-the-Server-Generating-Your-SSH-Public-Key" target="_blank">create</a>)
an SSH key for your user (`user_a`). Then we can run `ssh-to-age` that we added to
our dev shell earlier to create our age keys.

```sh
$ cat /absolute/path/to/ssh/id_user-a.pub | ssh-to-age
age<USER_A_KEY>
```

Then we can add our disk key secret, and read off of it:

```sh
$ mkdir -p hosts/server-a/secrets
$ sops --set '["disk-key"] "my-secret-disk-key-1"' hosts/server-a/secrets/init.yaml
$ sops decrypt --extract '["disk-key"]' hosts/server-a/secrets/init.yaml
my-secret-disk-key-1
```

The raw `init.yaml` is encrypted and only your user can decrypt it.

> [!WARNING]
For obvious reasons replace the key with an actual secret. :)

<h3 id="test-end-to-end-setup-2">
    <a href="#test-end-to-end-setup-2">4b. Test end-to-end setup #2</a>
</h3>

Let's recreate the server again.

```sh
# Delete the server
$ hcloud server delete server-a

# Create the server
$ hcloud server create \
    --image ubuntu-24.04 \
    --name server-a \
    --ssh-keys user-a \
    --type cx23 \
    --location nbg1 \
    --user-data-from-file ./user_data.yaml
 ✓ Waiting for create_server       100% 28s (server: <SERVER_ID>, image: <IMAGE_ID>)
 ✓ Waiting for start_server        100% 28s (server: <SERVER_ID>)
Server <SERVER_ID> created
IPv4: <IPV4_ADDRESS>
IPv6: <IPV6_ADDRESS>
IPv6 Network: <IPV6_NETWORK>
```

Then install!

```sh
# Create a temporary directory for the files we want to move to the server.
$ TMP_HOST_DIR=`echo $(mktemp -d)`
$ IPV4=<IPV4>

# 3. Decrypt and copy server-a's disk key
$ sops decrypt --extract '["disk-key"]' \
    hosts/server-a/secrets/init.yaml > $TMP_HOST_DIR/persist/secrets/disk-key

# Run the installation
$ nix run github:nix-community/nixos-anywhere -- \
      --print-build-logs \
      --flake .#server-a \
      --target-host tmp@$IPV4 \
      -i /path/to/private/ssh/key \
      --generate-hardware-config nixos-generate-config ./modules/hetzner/hardware-configuration.nix \
      --disk-encryption-keys /persist/secrets/disk-key "$TMP_HOST_DIR/persist/secrets/disk-key"
```

- `--disk-encryption-keys <REMOTE_PATH> <LOCAL_PATH>`: Copies our disk key over
to the remote path so that we don't need to manually SSH.

When the installation is complete, we can verify that ZFS actually encrypted
our datasets:

```sh
$ ssh operator@<SERVER_IPV4>
The authenticity of host '<SERVER_IPV4> (<SERVER_IPV4>)' can't be established.
ED25519 key fingerprint is: SHA256:<FINGERPRINT>
This key is not known by any other names.
Are you sure you want to continue connecting (yes/no/[fingerprint])? yes
Warning: Permanently added '<SERVER_IPV4>' (ED25519) to the list of known hosts.

[operator@server-a:~]$ zfs get encryption
NAME                PROPERTY    VALUE        SOURCE
zroot               encryption  off          default
zroot/root          encryption  aes-256-gcm  -
zroot/root/nix      encryption  aes-256-gcm  -
zroot/root/persist  encryption  aes-256-gcm  -

[operator@server-a:~]$ zfs list
NAME                 USED  AVAIL  REFER  MOUNTPOINT
zroot               1.36G  35.0G    96K  none
zroot/root          1.36G  35.0G  2.04M  /
zroot/root/nix      1.36G  35.0G  1.36G  /nix
zroot/root/persist   204K  35.0G   204K  /persist
```


Verify that our disk key is where we want it to be.

```sh
[operator@server-a:~]$ ls -la /persist/secrets
total 22
drwxr-xr-x 2 root root  3 Jun  7 13:44 .
drwxr-xr-x 3 root root  3 Jun  7 13:44 ..
-rw-r--r-- 1 root root 20 Jun  7 13:44 disk-key
```

And we can still `curl` our endpoint

```sh
[operator@server-a:~]$ curl localhost:8080
hello, world!
```

Awesome!

<h2 id="summary">
    <a href="#summary">5. Summary</a>
</h2>

Phew. Well that was a lot. We got our feet wet with a bunch of things including
secrets management. Let's cover the pros and cons so far:

- Pros
    1. Declare the outcome you want, not the steps to get there.
    2. Destroying and reconstructing servers is trivial once all set up.
- Cons
    1. Tedious initial setup.
    2. Some of the steps such as the initial provisioning of the server are still
    imperative.

What about integrating secrets with NixOS services? Does
that mean we need to do that tedious work over and over again for each one? Well, no!

But some of the imperative steps can be mitigated further through `terraform`.
Let's see how we can improve it! Chapter 2: Terraforming NixOS _(soon)_.

> [!NOTE]
All the source files can be found on [github.com/sekunho/www](https://github.com/sekunho/www/tree/main/examples/declarative-nixos-servers-on-hetzner).

<br>

<img style="width: 8rem;" src="/assets/images/not-by-ai.png">
