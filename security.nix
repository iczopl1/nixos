# Bezpieczeństwo: SSH wyłączony, firewall włączony, otwarte porty tylko za zgodą.
# MASTER.md §8
{ pkgs, ... }:

{
  # Serwer SSH całkowicie wyłączony. Klient SSH działa normalnie (git, ssh do serwerów).
  services.openssh.enable = false;

  # T2.38: dnscrypt-proxy – DNS over HTTPS (szyfrowany, blokada reklam/trackerów)
  # Nasłuchuje na 127.0.0.1:53; NetworkManager przekierowany na localhost.
  # Lista blokad: odblokowane – pozwolone domeny (syncthing, tailscale, avahi pracują normalnie).
  services.dnscrypt-proxy2 = {
    enable = true;
    settings = {
      listen_addresses   = [ "127.0.0.1:53" ];
      ipv6_servers       = false;    # X250 zwykle IPv4; włącz jeśli sieć wspiera IPv6
      require_dnssec     = true;
      block_ipv6         = false;

      # Szyfrowane serwery z filtrami reklam (bez logowania)
      server_names = [ "cloudflare" "nextdns" "quad9-dnscrypt-ip4-filter-pri" ];

      # Lokalne blokowanie reklam i trackerów (lista z nixpkgs)
      blocked_names = {
        blocked_names_file = "${pkgs.stevenblack-blocklist}/hosts";
      };
    };
  };

  # NetworkManager wysyła zapytania DNS do localhost (dnscrypt-proxy)
  networking.nameservers = [ "127.0.0.1" ];

  networking.firewall = {
    enable = true;

    # Syncthing – synchronizacja z telefonem i PC (MASTER §8: każdy port jawnie)
    allowedTCPPorts = [ 22000 ];              # protokół synchronizacji
    allowedUDPPorts = [ 22000 21027 47200 ];  # Syncthing QUIC + discovery + Linksy

    # Tailscale (tailscale0) – moduł NixOS sam otwiera potrzebne porty UDP.
    # tailnet-b.nix obsługuje swoje reguły przez extraCommands.

    # ROS2 DDS (UDP 7400-7500) otwierane w ros2.nix – tylko gdy ROS jest aktywny.

    allowPing = false;
    logRefusedConnections = true;
  };
}
