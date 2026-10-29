{
  ci,
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  ciHome = ci.home;
  ccacheDir = ci.ccache.dir;
  workDir = ci.workDir;
  queueDir = ci.queueDir;
  runnerConfig = pkgs.writeText "ci-runner-jobs.json" (
    builtins.toJSON {
      jobs = config.ci.runner.jobs;
    }
  );
  ciRunner = pkgs.writeTextFile {
    name = "ci-runner";
    executable = true;
    destination = "/bin/ci-runner";
    text =
      "#!${pkgs.python3}/bin/python3\n"
      + builtins.readFile (inputs.bitcoin-core-ci.outPath + "/runner/ci_runner.py");
  };
in
{
  options.ci.runner.jobs = lib.mkOption {
    type = lib.types.attrs;
    default = { };
    description = "CI queue runner job definitions.";
  };

  config = {
    _module.args = { inherit ciRunner; };

    users.groups.ci-runner = { };
    users.users.ci-runner = {
      isSystemUser = true;
      group = "ci-runner";
      home = ciHome;
      createHome = true;
    };

    environment.systemPackages = [ ciRunner ];

    systemd.tmpfiles.rules = [
      "d ${ciHome} 0750 ci-runner ci-runner -"
      "d /var/cache/ci-runner 0750 ci-runner ci-runner -"
      "d ${ccacheDir} 0750 ci-runner ci-runner -"
      "d ${workDir} 0750 ci-runner ci-runner -"
      "d ${queueDir} 0750 ci-runner ci-runner -"
      "d ${queueDir}/pending 0750 ci-runner ci-runner -"
      "d ${queueDir}/running 0750 ci-runner ci-runner -"
      "d ${queueDir}/done 0750 ci-runner ci-runner -"
      "d ${queueDir}/failed 0750 ci-runner ci-runner -"
      "d ${queueDir}/watch 0750 ci-runner ci-runner -"
    ];

    systemd.services.ci-runner = {
      description = "CI queue runner";
      reloadIfChanged = true;
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      path = with pkgs; [
        bash
        cmake
        coreutils
        curl
        findutils
        getent
        git
        gnumake
        gnused
        gnutar
        guix
        nix
        python3
        sudo
      ];
      serviceConfig = {
        Type = "simple";
        User = "ci-runner";
        Group = "ci-runner";
        WorkingDirectory = ciHome;
        ExecStart = "${ciRunner}/bin/ci-runner --queue-dir ${queueDir} run --config ${runnerConfig}";
        ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
        Restart = "always";
        RestartSec = "10";
      };
    };
  };
}
