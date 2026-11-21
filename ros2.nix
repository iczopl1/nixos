{ pkgs, ... }:

let
  # ROS Humble nie występuje w systemowym nixpkgs 26.05. Używamy osobnego,
  # przypiętego nix-ros-overlay; jego flake.lock przypina zgodny nixpkgs.
  rosOverlay = builtins.fetchTree {
    type = "github";
    owner = "lopsided98";
    repo = "nix-ros-overlay";
    rev = "2d52dc94f1eeb1465195d1f909b5a10006c8fafd";
    narHash = "sha256-vYTYv1PoGG/Q6afrKnj7fdT+h2f4b1auOdXmQZTaldU=";
  };

  # Osobny nix-shell buduje/udostępnia ROS dopiero przy uruchomieniu.
  # Nie miesza zależności ROS z systemowym nixpkgs i profilem minimal.
  rosHumbleShell = pkgs.writeText "ros2-humble-shell.nix" ''
    { pkgs ? import ${rosOverlay.outPath} { } }:
    let
      humble = pkgs.rosPackages.humble;
    in
    pkgs.mkShell {
      packages = [
        pkgs.colcon
        (humble.buildEnv {
          paths = with humble; [
            ros-base
            rviz2
            rmw-cyclonedds-cpp
            rosidl-generator-dds-idl
            robot-state-publisher
            joint-state-publisher-gui
            xacro
            tf2-tools
          ];
        })
      ];

      shellHook = "export ROS_DISTRO=humble\n"
        + "export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp\n"
        + "if [ -n \"$UNITREE_ROS_INTERFACE\" ]; then\n"
        + "  printf -v CYCLONEDDS_URI '<CycloneDDS><Domain><General><Interfaces><NetworkInterface name=\"%s\" priority=\"default\" multicast=\"default\" /></Interfaces></General></Domain></CycloneDDS>' \"$UNITREE_ROS_INTERFACE\"\n"
        + "  export CYCLONEDDS_URI\n"
        + "fi\n"
        + "if [ -f \"$PWD/install/setup.bash\" ]; then\n"
        + "  source \"$PWD/install/setup.bash\"\n"
        + "fi\n";
    }
  '';

  rosHumbleCommand = pkgs.writeShellScriptBin "ros2-humble" ''
    exec ${pkgs.nix}/bin/nix-shell \
      --option extra-substituters https://ros.cachix.org \
      --option extra-trusted-public-keys ros.cachix.org-1:dSyZxI8geDCJrwgvCOHDoAfOm5sV1wCPjBkKL+38Rvo= \
      ${rosHumbleShell} "$@"
  '';
in

{
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    defaultNetwork.settings.dns_enabled = true;
  };

  environment.systemPackages = with pkgs; [
    distrobox
    podman-compose
  ] ++ [ rosHumbleCommand ];

  # Cache dla przypiętego nix-ros-overlay (ROS nie powinien kompilować się
  # godzinami przy każdym nowym środowisku).
  nix.settings = {
    substituters = [ "https://ros.cachix.org" ];
    trusted-public-keys = [
      "ros.cachix.org-1:dSyZxI8geDCJrwgvCOHDoAfOm5sV1wCPjBkKL+38Rvo="
    ];
  };

  # ROS 2 DDS discovery (multicast + unicast) on the LAN
  networking.firewall.allowedUDPPortRanges = [
    { from = 7400; to = 7500; }
  ];
}
