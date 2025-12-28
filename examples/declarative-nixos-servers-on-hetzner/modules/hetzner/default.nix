{ modulesPath, operatorPublicKeys, extraGroups, ... }: {
  imports = [
    ./hardware-configuration.nix
    ./disk-config.nix
  ];

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
    initrd.secrets."/persist/secrets/disk-key" = "/persist/secrets/disk-key";

    loader.grub = {
      enable = true;
      efiSupport = true;
      efiInstallAsRemovable = true;
    };

    zfs = {
      requestEncryptionCredentials = true;
      forceImportRoot = false;
    };
  };
}
