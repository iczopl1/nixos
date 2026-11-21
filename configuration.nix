# Profil full NixOS 25.11 = minimal + moduły tylko dla full.
# full ⊃ minimal jest zagwarantowane strukturą plików (MASTER §1).
# Sesja graficzna: Mango. Pasek: Quickshell.
# Instalacja: ./rebuild.sh "opis"  lub skopiuj folder do /etc/nixos/.
{ ... }:

{
  imports = [
    ./configuration_minimal.nix  # full ⊃ minimal (MASTER §1)
    ./tailnet-b.nix              # drugi Tailscale w namespace (tailnet B)
    ./crafts.nix                 # aplikacje Rust budowane ze źródeł (PhotoCraft, VectorCraft, itp.)
    ./brave.nix                  # Brave Browser (binarka z GitHub Releases – nixpkgs 26.05 usunął)
    ./programs.nix               # programy tylko dla full (IDE, biuro, grafika, Java)
    ./python.nix                 # Python 3.13 + pakiety naukowe (numpy, scipy, casadi)
    ./webots.nix                 # Symulator Webots (Khepera III – ćwiczenie logiki rozmytej)
    ./ros2.nix                   # Podman/Distrobox i porty DDS dla środowisk ROS 2 (tylko full)
  ];
}
