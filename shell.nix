# Shell: bash aliasy/funkcje, zoxide, fzf, symlinki dotfiles (systemd-tmpfiles).
{ lib, ... }:

let
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
      # --- System / przebudowa ---
      rebuild     = "cd ~/nix_conf && ./rebuild.sh";
      rebuild-dry = "cd ~/nix_conf && ./rebuild.sh -n";
      # active-configuration.nix to symlink tworzony przez rebuild.sh → właściwy profil.
      # Po pierwszym rebuild.sh z tą zmianą: nixos-rebuild switch działa bez flag.
      update      = "sudo nixos-rebuild switch -I nixos-config=/etc/nixos/active-configuration.nix";
      update-boot = "sudo nixos-rebuild boot   -I nixos-config=/etc/nixos/active-configuration.nix";

      # --- Nawigacja ---
      ".."  = "cd ..";
      "..." = "cd ../..";

      # --- ls → eza ---
      ls = "eza --group-directories-first";
      ll = "eza -l --git --group-directories-first";
      l  = "eza -la --git --group-directories-first";

      # --- Pliki (bezpieczniejsze) ---
      cp = "cp -i";
      mv = "mv -i";
      rm = "rm -i";

      # --- Dysk ---
      df = "df -h";
      du = "du -h --max-depth=1";

      # --- Narzędzia ---
      "3"  = "tree";
      "]"  = "bc -l";
      b    = "btop";
      c    = "clear";
      ch   = "bat";
      ff   = "fastfetch";
      g    = "rg -i";
      i    = "ping";
      k    = "pkill -f";
      n    = "nmtui";
      y    = "wl-copy";

      # --- Git ---
      s   = "git status -sb";
      gs  = "git status -sb";
      ga  = "git add";
      gaa = "git add --all";
      gc  = "git commit";
      gcm = "git commit -m";
      gd  = "git diff";
      gl  = "git pull";
      gp  = "git push";
      gpl = "git pull --ff-only";
      gll = "git log --oneline --graph --decorate -20";
      gsw = "git switch";
      gb  = "git branch";
      gt  = "git";

      # --- Tailscale ---
      t   = "sudo tailscale up";
      tt  = "sudo tailscale down";
      ta  = "tailscale";
      ts  = "tailscale status";
      t1  = "sudo tailscale switch personal";
      t2  = "sudo tailscale switch work";

      # --- Python ---
      venv  = "python3 -m venv .venv";
      va    = "source .venv/bin/activate";
      pipup = "python3 -m pip install --upgrade pip";

      # --- Misc ---
      p7    = "7z";
      "7zl" = "7z l";
      "7zx" = "7z x";
      "7za" = "7z a";
      hist  = "history";

      # --- Własne skrypty ---
      agent    = "bash ~/.config/scripts/agent.sh";
      effects  = "bash ~/.config/scripts/toggle-effects.sh";
      throttle = "bash ~/.config/scripts/throttle.sh";  # T3.11: ograniczanie prędkości (tc)
    };

    interactiveShellInit = ''
      export FZF_DEFAULT_OPTS="--height=40% --layout=reverse --border"

      # cd → zoxide (z), z bez arg otwiera fzf picker
      cd() {
        if [ $# -eq 0 ]; then
          builtin cd ~ || return
        else
          z "$@" 2>/dev/null || builtin cd "$@"
        fi
      }

      # h – ostatnie 50 wierszy historii
      h() { history 50; }

      # d – wybierz stare polecenie z historii i uruchom
      d() {
        local cmd
        cmd=$(history | fzf --tac --no-sort --prompt='run> ' | sed 's/^ *[0-9]\+ *//') || return
        [ -n "$cmd" ] && eval "$cmd"
      }

      # a – szukaj tekstu (rg), wybierz pasujący wiersz, otwórz nvim w tym miejscu
      a() {
        local sel file lnum
        sel=$(rg -i --line-number "''${1:-.}" 2>/dev/null \
          | fzf --delimiter=: \
                --preview 'bat --style=numbers --color=always {1} --highlight-line {2}' \
                --preview-window 'up,60%,border-bottom,+{2}+3/3,~3' \
                --prompt='match> ') || return
        file=$(echo "$sel" | cut -d: -f1)
        lnum=$(echo "$sel" | cut -d: -f2)
        [ -n "$file" ] && nvim "$file" +"$lnum"
      }

      # e – edytuj plik; bez arg: fzf picker w bieżącym folderze
      e() {
        if [ -n "$1" ]; then
          nvim "$1"
        else
          local f
          f=$(fd --type f --hidden --exclude .git 2>/dev/null \
            | fzf --prompt='edit> ' \
                  --preview 'bat --style=numbers --color=always {}') || return
          [ -n "$f" ] && nvim "$f"
        fi
      }

      # fe – znajdź plik pod ~ i edytuj
      fe() {
        local f
        f=$(fd --type f --hidden --exclude .git . ~ 2>/dev/null \
          | fzf --prompt='edit> ' \
                --preview 'bat --style=numbers --color=always {}') || return
        [ -n "$f" ] && nvim "$f"
      }

      # fo – znajdź cokolwiek pod ~ i otwórz (xdg-open)
      fo() {
        local f
        f=$(fd --hidden --exclude .git . ~ 2>/dev/null \
          | fzf --prompt='open> ') || return
        [ -n "$f" ] && xdg-open "$f"
      }

      # o – otwórz plik; bez arg: fzf picker
      o() {
        if [ -n "$1" ]; then
          xdg-open "$1"
        else
          local f
          f=$(fd --type f --hidden --exclude .git 2>/dev/null \
            | fzf --prompt='open> ') || return
          [ -n "$f" ] && xdg-open "$f"
        fi
      }

      # m – utwórz folder i wejdź do niego
      m() {
        mkdir -p "$1" && cd "$1" || return
      }

      # p – przeglądaj procesy w fzf
      p() {
        ps aux | fzf --header-lines=1 --prompt='proc> '
      }

      # pk – wybierz proces i zabij go
      pk() {
        local pid
        pid=$(ps aux | fzf --header-lines=1 --prompt='kill> ' | awk '{print $2}') || return
        [ -n "$pid" ] && kill "$pid" && echo "Zabito PID $pid"
      }

      # pp – testowe powiadomienie mako
      pp() {
        notify-send "Test" "Mako powiadomienie $(date +%T)"
      }

      # py – python z venv projektu lub globalny
      py() {
        if [ -f .venv/bin/python ]; then
          .venv/bin/python "$@"
        elif [ -f venv/bin/python ]; then
          venv/bin/python "$@"
        else
          python3 "$@"
        fi
      }

      # q – claude; w ~ bez arg: picker projektu
      q() {
        if [ "$PWD" = "$HOME" ] && [ $# -eq 0 ]; then
          local proj
          proj=$(fd --type d --max-depth 3 . ~ 2>/dev/null \
            | fzf --prompt='claude project> ') || return
          [ -n "$proj" ] && builtin cd "$proj" && claude
        else
          claude "$@"
        fi
      }

      # qs – restart paska Quickshell
      qs() {
        pkill -f quickshell 2>/dev/null || true
        sleep 0.5
        quickshell &
        disown
        echo "Quickshell zrestartowany"
      }

      # rd – Moonlight remote desktop do pc2
      rd() {
        if command -v moonlight &>/dev/null; then
          moonlight stream pc2
        else
          echo "moonlight-qt nie zainstalowany (brak w nixpkgs – pobierz ręcznie)"
        fi
      }

      # br – ustaw jasność (sudo brightnessctl set)
      br() {
        if [ -z "$1" ]; then
          echo "Użycie: br <wartość>  (np. br 50%, br +10%, br 200)"
          brightnessctl
          return
        fi
        sudo brightnessctl set "$1"
      }

      # ns – ignoruj następne zamknięcie klapy (1 h)
      ns() {
        local sec=''${1:-3600}
        systemd-inhibit --what=handle-lid-switch --who="ns" \
          --why="ignore lid" sleep "$sec" &
        disown
        echo "Zamknięcie klapy ignorowane przez $((sec/60)) min (kill $! żeby anulować)"
      }

      # nn – netbird up
      nn() {
        if command -v netbird &>/dev/null; then
          sudo netbird up "$@"
        else
          echo "netbird nie zainstalowany"
        fi
      }

      # th – przeglądarka folderów (skrypt lub Thunar)
      th() {
        if [ -x ~/.local/bin/th ]; then
          ~/.local/bin/th "$@"
        else
          thunar "''${1:-.}" >/dev/null 2>&1 &
        fi
      }

      # w – wybierz zapisaną sieć Wi-Fi i połącz się
      w() {
        local ssid
        ssid=$(nmcli -t -f SSID,SIGNAL,SECURITY dev wifi list 2>/dev/null \
          | sort -t: -k2 -rn \
          | fzf --prompt='wifi> ' --delimiter=: --with-nth=1,3 \
          | cut -d: -f1) || return
        [ -n "$ssid" ] && nmcli dev wifi connect "$ssid"
      }

      # x – wejdź do podfolderu wybranego przez fzf (x 2 = max 2 poziomy)
      x() {
        local depth=''${1:-3}
        local d
        d=$(find . -maxdepth "$depth" -type d \
              -not -path '*/.git/*' -not -name '.git' 2>/dev/null \
            | fzf --prompt='cd> ') || return
        [ -n "$d" ] && cd "$d" || return
      }

      # u – wejdź do folderu nadrzędnego (fzf picker lub u 2 = dwa poziomy w górę)
      u() {
        if [[ "$1" =~ ^[0-9]+$ ]]; then
          local dir=""
          for _ in $(seq 1 "$1"); do dir="../$dir"; done
          cd "$dir" || return
          return
        fi
        local current="$PWD" parents=()
        while [[ "$current" != "/" ]]; do
          parents+=("$current")
          current="''${current%/*}"
          [[ -z "$current" ]] && current="/"
        done
        parents+=("/")
        local target
        target="$(printf '%s\n' "''${parents[@]}" | fzf --prompt='up> ')" || return
        cd "$target" || return
      }

      # zx – alias zi (picker zoxide)
      zx() { zi "$@"; }

      if command -v pyenv >/dev/null 2>&1; then
        export PYENV_ROOT="$HOME/.pyenv"
        eval "$(pyenv init - bash)"
      fi
    '';
  };

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
    "L %h/.config/alacritty - - - - ${dotfiles}/alacritty"
  ];
}
