{ config, ... }:
let
  cfg = config.services.ralph.instances.gui-qml;
  forgejoUrl = "http://${config.services.forgejoSite.http.address}:${toString config.services.forgejoSite.http.port}";
  readyFile = "${config.services.cli-proxy-api.dataDir}/ralph-gui-qml-enabled";
in
{
  sops.secrets.ralph-gui-qml-webhook-secret = {
    owner = cfg.user;
    mode = "0400";
  };
  sops.secrets.ralph-gui-qml-forgejo-token = {
    key = "forgejo-review-bot-token";
    owner = cfg.user;
    mode = "0400";
  };
  sops.secrets.ralph-gui-qml-proxy-key = {
    key = "cli-proxy-api-key";
    owner = cfg.user;
    mode = "0400";
  };

  services.ralph.instances.gui-qml = {
    enable = true;
    port = 8766;
    workers = 1;
    origin = "${forgejoUrl}/bitcoin-core/gui-qml.git";
    repository = "bitcoin-core/gui-qml";
    forgejoApi = "${forgejoUrl}/api/v1/repos/bitcoin-core/gui-qml";
    repositoryUrl = "https://git.fish.foo/bitcoin-core/gui-qml";
    webhookSecretFile = config.sops.secrets.ralph-gui-qml-webhook-secret.path;
    forgejoTokenFile = config.sops.secrets.ralph-gui-qml-forgejo-token.path;
    openaiApiBase = "http://127.0.0.1:8317/v1";
    openaiKeyFile = config.sops.secrets.ralph-gui-qml-proxy-key.path;
    githubPostMajorFindings = false;
    githubTokenFile = null;
    telegram.enable = false;
    botLogin = "ralph";
    reportDir = "/var/lib/ralph-gui-qml-reports";
    reportBaseUrl = "https://review.fish.foo/gui-qml/traces";
  };

  # Create this marker only after mirror and webhook validation is complete.
  systemd.services.ralph-gui-qml = {
    after = [ "sops-install-secrets.service" "cli-proxy-api.service" ];
    wants = [ "sops-install-secrets.service" ];
    requires = [ "cli-proxy-api.service" ];
    unitConfig.ConditionPathExists = readyFile;
  };
  systemd.services.ralph-gui-qml-stats.unitConfig.ConditionPathExists = readyFile;
  systemd.services.ralph-gui-qml-followup.unitConfig.ConditionPathExists = readyFile;

  services.caddy.virtualHosts."review.fish.foo".extraConfig = ''
    @guiWebhook {
      method POST
      path /webhooks/gui-qml
    }
    handle @guiWebhook {
      rewrite * /webhooks/forgejo
      reverse_proxy 127.0.0.1:8766
    }
    @guiBadge {
      method GET
      path_regexp ^/assets/bitcoin-core/gui-qml/[1-9][0-9]{0,18}\.png$
    }
    handle @guiBadge {
      reverse_proxy 127.0.0.1:8766
    }
    redir /gui-qml/stats /gui-qml/stats/
    handle_path /gui-qml/stats/* {
      root * ${cfg.reportDir}/stats
      header {
        Content-Security-Policy "default-src 'none'; style-src 'unsafe-inline'; script-src 'self'; connect-src 'self'"
        X-Content-Type-Options nosniff
        Cache-Control "no-cache"
      }
      file_server
    }
    redir /gui-qml/traces /gui-qml/traces/
    handle_path /gui-qml/traces/* {
      root * ${cfg.reportDir}
      header X-Content-Type-Options nosniff
      @guiHistory path_regexp ^/(?:[0-9]+/(?:index[.]html)?|index[.]html)?$
      header @guiHistory Content-Security-Policy "default-src 'none'; style-src 'unsafe-inline'; script-src 'self'; connect-src 'self'"
      @guiReport not path_regexp ^/(?:[0-9]+/(?:index[.]html)?|index[.]html)?$
      header @guiReport Content-Security-Policy "default-src 'none'; style-src 'unsafe-inline'; script-src 'self'"
      file_server
    }
  '';
}
