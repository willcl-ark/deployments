{ inputs, pkgs, ... }:
let
  package =
    inputs.b10c-nix.packages.${pkgs.stdenv.hostPlatform.system}.github-metadata-backup.overrideAttrs
      (old: {
        cargoDeps = pkgs.applyPatches {
          name = "github-metadata-backup-vendor-blocked-by";
          src = old.cargoDeps;
          patches = [ ./patches/octocrab-blocked-by-added.patch ];
        };
        postPatch = (old.postPatch or "") + ''
          mkdir -p tests
          cp ${./patches/octocrab-blocked-by-added-test.rs} tests/blocked_by_added.rs
          cp ${./patches/octocrab-blocked-by-added.json} tests/octocrab-blocked-by-added.json
        '';
      });
in
{
  # Octocrab 0.50 omits the blocked_by_added event returned for GUI issue 753.
  # Keep typed timeline decoding and preserve the blocking issue relationship.
  services.github-metadata-backup.bitcoin.package = package;
  services.github-metadata-backup.gui-qml.package = package;
}
