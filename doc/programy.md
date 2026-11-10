# Programy

Wszystko jest instalowane systemowo (`environment.systemPackages`) – nie ma pakietów per użytkownik.
Unfree włączone w `configuration.nix` (`nixpkgs.config.allowUnfree = true`).

## `programs.nix`

| Kategoria | Programy |
|---|---|
| Pulpit Wayland | quickshell, alacritty, foot, kitty, waybar, rofi, wofi, grim, slurp, wl-clipboard, cliphist, swww, mako, dunst, brightnessctl, pavucontrol, networkmanagerapplet, wvkbd, yad, ydotool, glava, eww, pywal |
| Terminal | jq, fzf, zoxide, btop, socat, ripgrep, procps, gawk, coreutils, wget, curl, git, p7zip, tree, fastfetch, mpc, mpv, cava |
| Przeglądarki / komunikacja | brave, google-chrome, discord, anydesk |
| Edytory / IDE | neovim, vscodium, android-studio, android-tools, flutter, mesa-demos |
| Programowanie | gcc, clang (niższy priorytet), clang-tools, cmake, ninja, gnumake, gdb, lldb, jdk17, jdk21 (niższy priorytet), maven, gradle, kotlin, go, nodejs, yarn, prettier, eslint, markdownlint-cli, grip |
| AI | gemini-cli |
| Biuro / grafika / dokumenty | libreoffice-fresh, gimp, krita, texliveFull, texlab, pandoc, graphviz, imagemagick, hunspell (+ słowniki en_US, pl_PL) |
| Neovim – LSP / formatery / narzędzia (zamiast Masona) | lua-language-server, stylua, google-java-format, java-language-server, zathura, glow (+ clang-tools, lldb, texlab, pyright, black, debugpy) |
| Hasła | keepassxc |
| Gry | prismlauncher |
| Bezpieczeństwo | maltego |
| Biblioteki dla binarek spoza Nix | stdenv.cc.cc.lib, zlib, glib, dbus, fontconfig, freetype, libGL, xorg (libX11, libXext, libXrender, libxcb, xcbutil*), libxkbcommon, wayland |

Do tego w tym pliku:

| Opcja | Co robi |
|---|---|
| `hardware.opentabletdriver.enable` | sterownik tabletów graficznych |
| `hardware.uinput.enable`, `boot.kernelModules = [ "uinput" ]` | wirtualne urządzenia wejścia (tablet, ydotool) |
| `programs.hyprlock.enable` | blokada ekranu hyprlock + usługa PAM |
| `programs.thunar.enable`, `programs.xfconf.enable` | menedżer plików Thunar |
| `programs.mtr.enable` | mtr (traceroute) |
| `programs.gnupg.agent` (z SSH) | agent GPG/SSH |
| `programs.nix-ld.enable` | uruchamianie binarek spoza Nix (Android SDK, Mason) |
| `NIXOS_OZONE_WL=1`, `XDG_SESSION_TYPE=wayland` | aplikacje Electron/Chromium natywnie na Waylandzie |
| `JAVA_HOME` = jdk17, `CHROME_EXECUTABLE` = google-chrome | dla Androida / Fluttera |

Wersje domyślne przy kolizjach: `java` → jdk17, `cc` → gcc.

## `python.nix`

Python **3.11** (`python3`) z pakietami:

| Grupa | Pakiety |
|---|---|
| Narzędzia | pip, virtualenv, setuptools, wheel, ipython, jupyterlab |
| Jakość kodu | black, debugpy, mypy, pytest, ruff |
| Nauka / dane | numpy, scipy, sympy, pandas, statsmodels |
| Wykresy | matplotlib, seaborn, plotly |
| Optymalizacja / robotyka | casadi, control, ortools, pinocchio |
| GUI / gry | pyqt5, tkinter, pygame |
| Obraz / sprzęt | pillow, opencv4, scikit-image, pyserial, pyusb |
| Pomocnicze | pyyaml, requests, rich, tqdm |

Poza tym: `pyright`, `pyenv` i biblioteki do budowania CPythona przez pyenv (bzip2, libffi, ncurses, openssl, readline, sqlite, tk, xz, zlib).
Zmienne: `PYENV_ROOT=$HOME/.pyenv`, `PYTHON` = ten interpreter.

## Moduły z nixos-selected

| Plik | Programy |
|---|---|
| `mango.nix` | mango (z `unstable`, łatka slidefade), xdg-desktop-portal-wlr, xdg-desktop-portal-gtk |
| `keyboard-mouse.nix` | wl-kbptr (łatka vimium), hintd, signal-desktop (z `unstable`, z a11y), ferdium (z a11y), czcionka barlow, ydotool (`programs.ydotool`) |
| `ros2.nix` | podman (z `dockerCompat`), distrobox, podman-compose |
| `crafts.nix` | photocraft, vectorcraft, filmcraft, lightcraft, pdfcraft, effectcraft, designcraft, gridcraft, cadcraft, deckcraft, soundcraft, wordcraft |
| `clev.nix` | clev, clev-goal – **nieimportowany** |

## `tts-mako.nix` (gdy włączony)

piper-tts, libnotify, ttsmako-listen, ttsmako-toggle, ttsmako-skip, ttsmako-install-voices, ttsmako-avrcp-watch.

## `fonts.nix`

fira-code, fira-code-symbols, font-awesome, jetbrains-mono, nerd-fonts (fira-code, jetbrains-mono, symbols-only), noto-fonts, noto-fonts-color-emoji. Barlow dodaje `keyboard-mouse.nix`.

## Usunięte (Hyprland)

hyprland, hypridle, iio-hyprland, xdg-desktop-portal-hyprland. (hyprlock zostaje jako blokada ekranu.)
