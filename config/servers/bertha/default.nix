{
  imports = [
    # custom nixpkgs since I need a very specific version of systemd-networkd
    # and newer NixOS options for the same.
    ./nixpkgs.nix
    ./router.nix
    ../../profiles/server.nix
  ];

  boot.loader.grub = {
    enable = true;
    version = 2;
    extraConfig = ''
      serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1
      terminal_input serial;
      terminal_output serial;
    '';
    devices = [ "/dev/sda" "/dev/sdb" ];
  };

  boot.kernelParams = [ "console=ttyS0,115200" ];

  deployment = {
 #   targetHost = "2a00:e67:1a6:0:20d:b9ff:fe41:6546";
    targetHost = "10.250.11.79";
    targetUser = "root";
    substituteOnDestination = false;
  };


  systemd.network.links = {
    "00-uplink" = {
      matchConfig.Path = "pci-0000:03:00.0";
      linkConfig = {
        NamePolicy = false;
        Name = "uplink";
      };
    };
  };
  systemd.network.netdevs = {
    "00-internal-bond" = {
      netdevConfig = {
        Name = "internal";
        Kind = "bond";
      };
    };

    "00-lan-vlan" = {
      netdevConfig = {
        Name = "lan";
        Kind = "vlan";
      };
      vlanConfig = {
        Id = 40;
      };
    };

    "00-oldlan-vlan" = {
      netdevConfig = {
        Name = "oldlan";
        Kind = "vlan";
      };
      vlanConfig = {
        Id = 11;
      };
    };

    "00-mgmt-vlan" = {
      netdevConfig = {
        Name = "mgmt";
        Kind = "vlan";
      };
      vlanConfig = {
        Id = 30;
      };
    };

  };

  systemd.network.networks = {
    "00-internal-bond" = {
      matchConfig = {
        Name = "internal";
      };
      vlan = [ "oldlan" "lan" "mgmt" ];
    };
    "00-bond0-1" = {
      matchConfig = {
        Path = "pci-0000:01:00.0";
      };
      networkConfig = {
        Bond = "internal";
      };
    };
    "00-bond0-2" = {
      matchConfig = {
        Path = "pci-0000:02:00.0";
      };
      networkConfig = {
        Bond = "internal";
      };
    };
    "00-oldlan" = {
      networkConfig.DHCPServer = false;
    };
   # "00-enp3s0" = {
   #   matchConfig = {
   #     Name = "enp3s0";
   #   };
   #   networkConfig = {
   #     DHCP = "yes";
   #   };
   # };
  };

  # router networkd configuration that actually puts addresses on interfaces,
  # configures the upstream interfaces, requests PD, …
  router = {
    enable = true;
    upstreamInterfaces = [ "uplink" ];
    downstreamInterfaces = [
      {
        interface = "lan";
        v4Addresses = [
          { address = "172.20.24.1"; prefixLength = 24; }
        ];
        v6Addresses = [
          { address = "fd21:a07e:735e:ff00::"; prefixLength = 64; }
        ];
      }
      {
        interface = "oldlan";
        v4Addresses = [
          { address = "10.250.11.254"; prefixLength = 24; }
        ];
        v6Addresses = [
          { address = "fd21:a07e:735e:ff01::"; prefixLength = 64; }
        ];
      }
      {
        interface = "mgmt";
        v4Addresses = [
          { address = "10.250.30.254"; prefixLength = 24; }
        ];
        v6Addresses = [
          { address = "fd21:a07e:735e:ff01::"; prefixLength = 64; }
        ];
      }

    ];
  };

  networking.firewall.enable = false;
  networking.nftables.enable = true;
  networking.nftables.ruleset = ''
    table inet filter {

      chain input {
        type filter hook input priority filter;

        iifname lo accept

        ct state {established, related} accept

        ip6 nexthdr icmpv6 icmpv6 type { destination-unreachable, packet-too-big, time-exceeded, parameter-problem, nd-router-advert, nd-neighbor-solicit, nd-neighbor-advert } accept
        ip protocol icmp icmp type { destination-unreachable, time-exceeded, parameter-problem } accept

        ip6 nexthdr icmpv6 icmpv6 type echo-request accept
        ip protocol icmp icmp type echo-request accept

        tcp dport { 22, 80, 443 } accept

        iifname lan jump lan_input
        iifname mgmt accept;
        # iifname mgmt jump lan_input # FIXME: mgmt input should be handled differently
        iifname uplink jump upstream_input


        counter log prefix "blocked incoming: " drop
      }

      chain lan_input {
        ip protocol icmp accept
        ip6 nexthdr icmpv6 accept
        udp sport bootpc udp dport bootps accept comment "DHCP clients"
        udp dport { domain, domain-s } accept
        tcp dport { domain, domain-s } accept
      }

      chain upstream_input {
        # make dhcp client and ipv6 ra work on the uplink interface
        udp sport bootps udp dport bootpc accept
        udp sport bootps udp dport bootpc accept
        ip6 nexthdr icmpv6 icmpv6 type { nd-router-advert } accept
        ip6 nexthdr tcp tcp sport dhcpv6-server tcp dport dhcpv6-client accept
      }

      chain output {
        type filter hook output priority filter; policy accept;
        accept
      }

      chain forward {
        type filter hook forward priority filter;

        iif lo accept

        ct state {established, related} accept

        # everything can go out
        oifname uplink accept

        oifname lan jump forward_to_lan
        oifname mgmt jump forward_to_mgmt

        log prefix "not forwarding: " reject
      }

      chain forward_to_lan {
        tcp dport { 22 } accept
        reject
      }

      chain forward_to_mgmt {
        reject
      }
    }
    table ip nat {
      chain prerouting {
         type nat hook prerouting priority dstnat;
         #tcp dport { 4001 } dnat to $somewhere
      }
      chain postrouting {
         type nat hook postrouting priority srcnat;
         oifname uplink masquerade
      }
    }
  '';

  # allow local unbound-control invocations
  systemd.tmpfiles.rules = [
    "d /run/unbound 550 unbound nogroup - "
  ];
  services.unbound.extraConfig = ''
    remote-control:
      control-enable: yes
      control-interface: /run/unbound/unbound.ctl
  '';
  users.users.root.initialPassword = "password";
}