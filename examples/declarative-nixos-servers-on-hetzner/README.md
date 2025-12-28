# Declarative Hetzner Cloud Servers With NixOS

Blog: [https://www.sekun.net/blog/declarative-hetzner-cloud-servers-with-nixos/#summary](https://www.sekun.net/blog/declarative-hetzner-cloud-servers-with-nixos/#summary)

The important scripts are in `Justfile` but you need to replace some things like
the public SSH key placeholders.

```sh
sed -i 's/<USER_A_PUBLIC_SSH_KEY>/<YOUR_SSH_KEY>/g' flake.nix
sed -i 's/<USER_A_PUBLIC_SSH_KEY>/<YOUR_SSH_KEY>/g' user_data.yaml
```

After initializing your `hcloud` context, you can run

```
just hetzner-server-create
just install-nixos tmp <SERVER_IPV4>
```
