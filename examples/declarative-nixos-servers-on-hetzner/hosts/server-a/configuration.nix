{ self, config, ... }: {
  networking = {
    hostName = "server-a";
    hostId = "97f2c756";

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
