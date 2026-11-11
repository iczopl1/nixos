# Bezpieczeństwo: SSH wyłączony, firewall włączony, otwarte porty tylko za zgodą.
# MASTER.md §8
{ ... }:

{
  # Serwer SSH całkowicie wyłączony. Klient SSH działa normalnie (git, ssh do serwerów).
  services.openssh.enable = false;

  networking.firewall = {
    enable = true;

    # Syncthing – synchronizacja z telefonem i PC (MASTER §8: każdy port jawnie)
    allowedTCPPorts = [ 22000 ];       # protokół synchronizacji
    allowedUDPPorts = [ 22000 21027 ]; # QUIC + lokalne wykrywanie urządzeń

    # Tailscale (tailscale0) – moduł NixOS sam otwiera potrzebne porty UDP.
    # tailnet-b.nix obsługuje swoje reguły przez extraCommands.

    # ROS2 DDS (UDP 7400-7500) otwierane w ros2.nix – tylko gdy ROS jest aktywny.

    allowPing = false;
    logRefusedConnections = true;
  };
}
