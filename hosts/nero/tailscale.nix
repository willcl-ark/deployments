{ config, lib, ... }:
let
  tailscale = lib.getExe config.services.tailscale.package;
in
{
  sops.secrets.tailscale-auth-key.mode = "0400";

  services.tailscale = {
    enable = true;
    openFirewall = true;
    authKeyFile = config.sops.secrets.tailscale-auth-key.path;
    extraUpFlags = [ "--accept-dns=false" ];
  };

  systemd.services.tailscaled-autoconnect = {
    after = [ "sops-install-secrets.service" ];
    requires = [ "sops-install-secrets.service" ];
  };

  # GitHub CI reaches CLIProxyAPI here; Ralph connects directly over loopback.
  # Use a separate port so Caddy can keep its default wildcard HTTPS listener.
  systemd.services.tailscale-serve-cliproxy = {
    description = "Serve CLIProxyAPI privately over Tailscale HTTPS";
    wantedBy = [ "multi-user.target" ];
    after = [
      "tailscaled.service"
      "tailscaled-autoconnect.service"
      "cli-proxy-api.service"
    ];
    requires = [ "tailscaled-autoconnect.service" ];
    wants = [ "cli-proxy-api.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${tailscale} serve --bg --yes --https=8443 http://127.0.0.1:8317";
      ExecStop = "${tailscale} serve --yes --https=8443 off";
    };
  };

  systemd.services.tailscale-serve-netdata = {
    description = "Serve Netdata privately over Tailscale HTTPS";
    wantedBy = [ "multi-user.target" ];
    after = [
      "tailscaled.service"
      "tailscaled-autoconnect.service"
      "netdata.service"
    ];
    requires = [ "tailscaled-autoconnect.service" ];
    wants = [ "netdata.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${tailscale} serve --bg --yes --https=10000 http://127.0.0.1:19999";
      ExecStop = "${tailscale} serve --yes --https=10000 off";
    };
  };
}
