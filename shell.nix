# Shell: bash aliasy/funkcje, zoxide, fzf, symlinki dotfiles (systemd-tmpfiles).
{ lib, ... }:

let
  # Ścieżka do folderu dotfiles OBOK tego pliku (np. /etc/nixos/dotfiles).
  # toString nie kopiuje do /nix/store, więc pliki zostają edytowalne
  # (np. nvim może zapisywać lazy-lock.json, jeśli masz prawa zapisu).
  dotfiles = toString ./dotfiles;
in
{
  programs.zoxide = {
    enable = true;
    enableBashIntegration = true;
  };

  programs.fzf = {
    keybindings = true;
    fuzzyCompletion = true;
  };

  programs.bash = {
    completion.enable = true;

    shellAliases = {
      # Przebudowa systemu – agenci używają rebuild.sh (tryb boot), użytkownik może switch.
      rebuild = "cd ~/nix_conf && ./rebuild.sh";
      rebuild-dry = "cd ~/nix_conf && ./rebuild.sh -n";
      update = "sudo nixos-rebuild switch";   # użytkownik: szybki switch bez commitu
      update-boot = "sudo nixos-rebuild boot"; # użytkownik: bezpieczny boot

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
      agent   = "bash ~/.config/scripts/agent.sh";       # T2.21: info dla AI agentów
      effects = "bash ~/.config/scripts/toggle-effects.sh"; # T3.12: toggle efektów
    };

    # Funkcje bash.
    interactiveShellInit = ''
      export FZF_DEFAULT_OPTS="--height=40% --layout=reverse --border"

      if command -v pyenv >/dev/null 2>&1; then
        export PYENV_ROOT="$HOME/.pyenv"
        eval "$(pyenv init - bash)"
      fi

      uu() {
        local count=''${1:-1}
        local dir=""
        local i
        for i in $(seq 1 "$count"); do
          dir="../$dir"
        done
        cd "$dir" || return
      }

      u() {
        if [[ "$1" =~ ^[0-9]+$ ]]; then
          uu "$1"
          return
        fi

        local current="$PWD"
        local parents=()
        while [[ "$current" != "/" ]]; do
          parents+=("$current")
          current="''${current%/*}"
          [[ -z "$current" ]] && current="/"
        done
        parents+=("/")

        local target
        if command -v fzf >/dev/null 2>&1; then
          target="$(printf '%s\n' "''${parents[@]}" | fzf --prompt='up> ')" || return
        else
          printf '%s\n' "''${parents[@]}"
          return
        fi
        cd "$target" || return
      }

      _histpick() {
        local selected
        if command -v fzf >/dev/null 2>&1; then
          selected="$(history | fzf --tac --no-sort --prompt='history> ' | sed 's/^ *[0-9]\+ *//')" || return
          [[ -z "$selected" ]] && return
          printf '%s\n' "$selected"
          eval "$selected"
        else
          history
        fi
      }

      # source ~/.bash/z_function.sh
      # source ~/.bash/fzf_history_widget.sh
    '';
  };

  # Dotfiles (dawne home.file). Typ "L" tworzy link tylko gdy celu jeszcze nie ma -
  # jeśli masz już np. ~/.config/nvim, usuń/przenieś go i zaloguj się ponownie
  # (albo: systemctl --user restart systemd-tmpfiles-setup).
  # ~/.config/hypr celowo pominięte (Hyprland usunięty).
  systemd.user.tmpfiles.users.iczo.rules = [
    "d %h/.config 0755 - - -"
    "d %h/.ssh 0700 - - -"
    "L %h/.config/mango - - - - ${dotfiles}/mango"
    "L %h/.config/quickshell - - - - ${dotfiles}/quickshell"
    "L %h/.config/waybar - - - - ${dotfiles}/waybar"
    "L %h/.config/rofi - - - - ${dotfiles}/rofi"
    "L %h/.config/cava - - - - ${dotfiles}/cava"
    "L %h/.config/nvim - - - - ${dotfiles}/nvim"
    "L %h/.config/scripts - - - - ${dotfiles}/scripts"
    "L %h/.bash - - - - ${dotfiles}/bash"
    "L %h/.ssh/config - - - - ${dotfiles}/ssh/config"
  ];
}
