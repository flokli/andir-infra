{ pkgs, config, lib, ... }:
{
  services.unifi = {
    enable = true;
    unifiPackage = pkgs.unifiStable.overrideAttrs (
      _: rec {
        version = "6.0.23";
        src = pkgs.fetchurl {
          url = "https://dl.ubnt.com/unifi/${version}/unifi_sysvinit_all.deb";
          sha256 = "0yiwg5bpnmfk922grjd7k80fg655w1j2sv97gg00j2il95839yxp";
        };
      }
    );
  };

  services.nginx = {
    # disabled since unifi seems to request logins for unknown reason..
    #enable = true;
    #virtualHosts."unifi.epsilon.rammhold.de" = {
    #  locations."/" = {
    #    proxyPass = "https://localhost:8443";
    #    proxyWebsockets = true;
    #    extraConfig = let
    #      networks = lib.flatten (
    #        map (
    #          iface:
    #            (
    #              map
    #                (addr: addr.address + "/${toString addr.prefixLength}")
    #                (iface.v4Addresses ++ iface.v6Addresses)
    #            )
    #        ) config.router.downstreamInterfaces
    #      );
    #    in
    #      ''
    #        ${lib.concatMapStringsSep "\n" (addr: "allow ${addr};") networks}
    #        deny   all;
    #      '';
    #  };
    #};
  };
}
