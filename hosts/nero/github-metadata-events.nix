{ inputs, pkgs, ... }:
let
  package =
    inputs.b10c-nix.packages.${pkgs.stdenv.hostPlatform.system}.github-metadata-backup.overrideAttrs
      (old: {
        patches = (old.patches or [ ]) ++ [ ./patches/github-metadata-backup-raw-timeline.patch ];
        # Octocrab initializes its TLS roots even for the loopback HTTP test.
        preCheck = (old.preCheck or "") + ''
          export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
        '';
      });
in
{
  # GitHub adds timeline event kinds independently of the API client's releases.
  # Archive their original JSON so one new event cannot stop metadata syncing.
  services.github-metadata-backup.bitcoin.package = package;
  services.github-metadata-backup.gui-qml.package = package;
}
