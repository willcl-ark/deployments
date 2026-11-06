{ host, lib, ... }:

{
  disko.devices.disk.main = {
    type = "disk";
    device = host.hardware.disk;
    content = {
      type = "gpt";
      partitions = {
        boot = lib.mkIf (host.hardware.bootMode == "bios") {
          size = "1M";
          type = "EF02";
        };
        ESP = lib.mkIf (host.hardware.bootMode == "uefi") {
          size = "512M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
}
