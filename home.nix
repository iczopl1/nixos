{ config, pkgs, ... }:

{
  # You can add your Home Manager configurations here
  home.packages = with pkgs; [
    # firefox
    # git
    zoxide
    brave
  ];
  # Let Home Manager manage your dotfiles
  programs.home-manager.enable = true;

  programs.zoxide = {
    enable = true;
    enableBashIntegration = true;
  };

  programs.bash = {
    enable = true;
    shellAliases = {
      ll = "ls -alF";
      la = "ls -A";
      l = "ls -CF";
      s = "git status";
      g = "gemini";
      n = "nvim";
      h = "cd ~"; # Go to home directory
      # Add more aliases as needed
    };
    initExtra = ''
      # Function for going up multiple directories
      uu() {
        local count=$${1:-1}
        local dir=""
        for i in $(seq 1 $count); do
          dir="../$$dir"
        done
        cd "$$dir" || return
      }
    '';
  };
#do hyprlock niezbedne
  wayland.windowManager.hyprland.systemd.enable = false;
  home.stateVersion = "25.11"; # Please adjust to your NixOS version
}
