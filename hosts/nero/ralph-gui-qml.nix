{
  config,
  inputs,
  pkgs,
  ...
}:
let
  forgejoUrl = "http://${config.services.forgejoSite.http.address}:${toString config.services.forgejoSite.http.port}";
in
{
  sops.secrets.ralph-gui-qml-webhook-secret = {
    owner = config.services.ralph.user;
    mode = "0400";
  };

  services.ralph.repositories.gui = {
    workers = 1;
    strategy = "gui";
    origin = "${forgejoUrl}/bitcoin-core/gui-qml.git";
    repository = "bitcoin-core/gui-qml";
    forgejoApi = "${forgejoUrl}/api/v1/repos/bitcoin-core/gui-qml";
    repositoryUrl = "https://git.fish.foo/bitcoin-core/gui-qml";
    webhookSecretFile = config.sops.secrets.ralph-gui-qml-webhook-secret.path;
    forgejoTokenFile = config.sops.secrets.forgejo-review-bot-token.path;
    githubRepository = "bitcoin-core/gui-qml";
    githubTokenFile = config.sops.secrets.ralph-github-api-key.path;
    githubPublication = "full";
    botLogin = "ralph";
    submodules.bitcoin = "https://github.com/bitcoin/bitcoin";
    writeVerifierEnvironment =
      inputs.will-nix.packages.${pkgs.stdenv.hostPlatform.system}.ralph-gui-verifier-env;
  };

  services.caddy.virtualHosts."review.fish.foo".extraConfig = ''
    @guiWebhook {
      method POST
      path /webhooks/gui-qml
    }
    handle @guiWebhook {
      rewrite * /webhooks/forgejo/gui
      reverse_proxy 127.0.0.1:8765
    }
    @guiBadge {
      method GET
      path_regexp ^/assets/bitcoin-core/gui-qml/[1-9][0-9]{0,18}\.png$
    }
    handle @guiBadge {
      reverse_proxy 127.0.0.1:8765
    }
    redir /gui-qml/stats /stats/repos/gui/
    handle_path /gui-qml/stats/* {
      redir * /stats/repos/gui{uri}
    }
    redir /gui-qml/traces /traces/gui/
    handle_path /gui-qml/traces/* {
      redir * /traces/gui{uri}
    }
  '';
}
