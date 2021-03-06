{ lib, config, ... }:
{
  imports = [
    ./modules.nix
    ./morph.nix
    ./nix-path.nix
    ./nix.nix
    ./acme.nix
  ];

  users.users.andi = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keyFiles = [
      ./andi.pub
    ];
  };

  h4ck.ssh-unlock = {
    enable = config.boot.initrd.luks.devices != { };
    authorizedKeys = lib.splitString "\n" (builtins.readFile ./andi.pub);
  };

  # there are no passwords
  security.sudo.wheelNeedsPassword = false;

  # users aren't mutable, I shouldn't ever need to login to any of them to
  # mutate stuff..
  users.mutableUsers = false;

  # Remind myself that this system is maintained using morph and local changes do not have any effect
  users.motd = ''
    ******
    This system is maintained using morph.

    Local changes will not persist.

    The code for this host can be found at https://github.com/andir/infra.git
    ******
  '';

  time.timeZone = "UTC";
}
