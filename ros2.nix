{ pkgs, ... }:

{
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    defaultNetwork.settings.dns_enabled = true;
  };

  environment.systemPackages = with pkgs; [
    distrobox
    podman-compose
  ];

  # ROS 2 DDS discovery (multicast + unicast) on the LAN
  networking.firewall.allowedUDPPortRanges = [
    { from = 7400; to = 7500; }
  ];
}
