# Temporary: review pull requests on willcl-ark/bitcoin.
{ config, ... }:
{
  sops.secrets.ralph-fork-webhook-secret = {
    owner = config.services.ralph.user;
    mode = "0400";
  };

  services.ralph.repositories.fork = {
    workers = 1;
    origin = "https://github.com/willcl-ark/bitcoin.git";
    repository = "willcl-ark/bitcoin";
    # GitHub serves the pull request endpoints Ralph reads from Forgejo.
    forgejoApi = "https://api.github.com/repos/willcl-ark/bitcoin";
    repositoryUrl = "https://github.com/willcl-ark/bitcoin";
    webhookSecretFile = config.sops.secrets.ralph-fork-webhook-secret.path;
    forgejoTokenFile = config.sops.secrets.ralph-github-api-key.path;
    githubRepository = "willcl-ark/bitcoin";
    githubTokenFile = config.sops.secrets.ralph-github-api-key.path;
    # "off" would publish the Forgejo comment through the GitHub API.
    githubPublication = "full";
    botLogin = "ralph";
  };

  services.caddy.virtualHosts."review.fish.foo".extraConfig = ''
    @forkWebhook {
      method POST
      path /webhooks/willcl-ark/bitcoin
    }
    handle @forkWebhook {
      rewrite * /webhooks/forgejo/fork
      reverse_proxy 127.0.0.1:8765 {
        header_up X-Forgejo-Event {header.X-GitHub-Event}
        header_up X-Forgejo-Signature {header.X-Hub-Signature-256}
      }
    }
  '';
}
