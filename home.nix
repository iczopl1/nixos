{ config, pkgs, ... }:

{
  # You can add your Home Manager configurations here
  home.packages = with pkgs; [
    zoxide
    fzf
    brave
    vscodium
    (python311.withPackages (ps: with ps; [
      pyqt5
      tkinter
    ]))
    jdk21
    #intellij-idea-community
    maven
    gradle
    clang
    cmake
    ninja
    #qtcreator
    #qt6.qtbase
    #gtk4
    gdb
    lldb
    kotlin
    go
    nodejs
    yarn
    prettier
    eslint
    jq
    #json-tools
    pandoc
    markdownlint-cli
    grip
  ];
  # Let Home Manager manage your dotfiles
  programs.home-manager.enable = true;

  home.file = {
    ".config/hypr" = {
      source = ./dotfiles/hypr;
      recursive = true;
      force = true;
    };
    ".config/waybar" = {
      source = ./dotfiles/waybar;
      recursive = true;
      force = true;
    };
    ".config/rofi" = {
      source = ./dotfiles/rofi;
      recursive = true;
      force = true;
    };
    ".config/cava" = {
      source = ./dotfiles/cava;
      recursive = true;
      force = true;
    };
    ".config/nvim" = {
      source = ./dotfiles/nvim;
      recursive = true;
      force = true;
    };
  };

  programs.zoxide = {
    enable = true;
    enableBashIntegration = true;
  };

  programs.bash = {
    enable = true;
    enableCompletion = true;
    shellAliases = {
      update = "sudo nixos-rebuild switch --flake /home/iczo/git/nixos#ThinkPadNIX";
      update-test = "sudo nixos-rebuild test --flake /home/iczo/git/nixos#ThinkPadNIX";
      update-build = "nix --extra-experimental-features nix-command --extra-experimental-features flakes build /home/iczo/git/nixos#nixosConfigurations.ThinkPadNIX.config.system.build.toplevel";

      ls = "ls --color=auto";
      ll = "ls -alF --color=auto";
      la = "ls -A --color=auto";
      l = "ls -CF --color=auto";
      ".." = "cd ..";
      "..." = "cd ../..";
      home = "cd ~";

      s = "git status --short";
      gs = "git status --short";
      ga = "git add";
      gaa = "git add --all";
      gc = "git commit";
      gcm = "git commit -m";
      gd = "git diff";
      gl = "git log --oneline --graph --decorate -20";
      gp = "git push";
      gpl = "git pull --ff-only";
      gsw = "git switch";
      gb = "git branch";

      n = "nvim";
      py = "python3";
      venv = "python3 -m venv .venv";
      va = "source .venv/bin/activate";
      pipup = "python3 -m pip install --upgrade pip";
      p7 = "7z";
      "7zl" = "7z l";
      "7zx" = "7z x";
      "7za" = "7z a";
      th = "thunar . >/dev/null 2>&1 &";
      h = "_histpick";
      hist = "history";
    };
    initExtra = ''
      export FZF_DEFAULT_OPTS="--height=40% --layout=reverse --border"

      uu() {
        local count=$${1:-1}
        local dir=""
        for i in $(seq 1 $count); do
          dir="../$$dir"
        done
        cd "$$dir" || return
      }

      u() {
        if [[ "$$1" =~ ^[0-9]+$ ]]; then
          uu "$$1"
          return
        fi

        local current="$$PWD"
        local parents=()
        while [[ "$$current" != "/" ]]; do
          parents+=("$$current")
          current="$${current%/*}"
          [[ -z "$$current" ]] && current="/"
        done
        parents+=("/")

        local target
        if command -v fzf >/dev/null 2>&1; then
          target="$(printf '%s\n' "$${parents[@]}" | fzf --prompt='up> ')" || return
        else
          printf '%s\n' "$${parents[@]}"
          return
        fi
        cd "$$target" || return
      }

      z() {
        local query="$${1:-}"
        if [[ -z "$$query" ]]; then
          if command -v fzf >/dev/null 2>&1; then
            local selected_dir
            selected_dir="$(find . -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | fzf --prompt='sub-dir> ')"
            if [[ -n "$$selected_dir" ]]; then
              cd "$$selected_dir" || return
              command -v zoxide >/dev/null 2>&1 && zoxide add "$$PWD" >/dev/null 2>&1 || true
              return
            else
              return # No directory selected, so don't change directory.
            fi
          else
            cd "$${HOME}" || return
            return
          fi
        fi

        local target
        target="$(find . -mindepth 1 -type d -name "$${query}*" -print 2>/dev/null | sort | head -n 1)"
        if [[ -n "$$target" ]]; then
          cd "$$target" || return
          command -v zoxide >/dev/null 2>&1 && zoxide add "$$PWD" >/dev/null 2>&1 || true
          return
        fi

        target="$(zoxide query -- "$$@" 2>/dev/null)" && cd "$$target"
      }

      _histpick() {
        local selected
        if command -v fzf >/dev/null 2>&1; then
          selected="$(history | fzf --tac --no-sort --prompt='history> ' | sed 's/^ *[0-9]\+ *//')" || return
          [[ -z "$$selected" ]] && return
          printf '%s\n' "$$selected"
          eval "$$selected"
        else
          history
        fi
      }

      # Source FZF history search widget
      source ~/.config/bash/fzf_history_widget.sh
    '';
  };
#do hyprlock niezbedne
  wayland.windowManager.hyprland.systemd.enable = false;
  home.stateVersion = "25.11"; # Please adjust to your NixOS version
}
