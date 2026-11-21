# Programy i profile

Listy pakietów są w `programs_minimal.nix`, `programs.nix` i `python.nix`.
To one są źródłem prawdy; ta strona grupuje najważniejsze narzędzia.

## Minimal

`configuration_minimal.nix` dostarcza podstawowy system graficzny i narzędzia
potrzebne do odzyskiwania systemu:

- Mango, Quickshell, Alacritty, Foot, rofi, mako, zrzuty ekranu, schowek,
  regulację jasności i narzędzia audio;
- Firefox/LibreWolf, KeePassXC, Neovim, Claude Code oraz Antigravity CLI (`agy`);
- Git, narzędzia terminalowe i sieciowe, `python3`, direnv/nix-direnv;
- `mpv`, VLC, `pactl`/`paplay`, nagrywanie ekranu i adnotacje;
- MTR, narzędzia SMART/NVMe, `age` i klient SSH.

Serwer OpenSSH jest wyłączony. Klient SSH pozostaje dostępny.

## Full

`configuration.nix` importuje minimal, następnie dodaje moduły full. Są wśród
nich narzędzia programistyczne i IDE, LibreOffice, GIMP/Krita, LaTeX, Android/
Flutter, narzędzia embedded, kontenery, komunikatory i aplikacje z własnymi
opakowaniami. Symulator Webots jest w `webots.nix`; Brave w `brave.nix`.

`keyboard-mouse.nix` i `dotfiles/syshelp/hintdrive/clev.nix` dostarczają hintd,
wl-kbptr oraz polecenia clev. `programs.nix` obejmuje m.in. VSCodium, clang/LLDB, JDK 17, Node.js, Go,
Arduino/PlatformIO, OpenOCD, CHIRP, MegaTools, JDownloader, Moonlight i
Wireshark. `keyboard-mouse.nix` dodaje dostępność Signal/Ferdium. `crafts.nix`
buduje aplikacje Craft. `tailnet-b.nix` uruchamia drugą
instancję Tailscale w odizolowanym namespace.

`ros2.nix` jest importowany przez `configuration.nix`, więc środowisko ROS,
Podman/Distrobox i porty DDS trafiają do full, nie do minimal. Polecenie
`ros2-humble` uruchamia odizolowany shell ROS 2 Humble z `ros-base`, CycloneDDS,
`colcon`, RViz, Xacro i narzędziami do opisu robota. Pakiety ROS pochodzą z
przypiętego nix-ros-overlay i jego cache; nie mieszają się z systemowym nixpkgs.
Przykład dla checkoutu Unitree:

```bash
cd /dane/sync/Dane/projekty/unitree_ros2/cyclonedds_ws
UNITREE_ROS_INTERFACE=enp3s0 ros2-humble
colcon build
ros2 topic list
```

Zastąp `enp3s0` nazwą interfejsu Ethernetu podłączonego do G1. W shellu
`ros2-humble` środowisko lokalnego workspace `install/setup.bash` jest
dołączane automatycznie po jego zbudowaniu. Nie używaj checkoutowego
`setup.sh`, bo wskazuje na `/opt/ros/foxy`. `local.nix` pozostaje wspólny dla
obu profili. `clev.nix` nie jest importowany, ponieważ brakuje katalogu źródeł
`hintdrive`.

## Python (full)

`python.nix` dostarcza Python 3.13 jako `python3`, `pyright`, `pyenv` i pakiety
do nauki, analizy danych, robotyki, obrazów oraz pracy z G1-Prz-Controll. W tym
ostatnim zakresie są `numpy`, `pillow`, `paramiko`, `scp`, `pygame` i Tkinter.
W venv projektu G1 włącz `include-system-site-packages = true`; nie instaluj
kopii NumPy ani Pillow przez pip. `ffmpeg` i `ffprobe` pochodzą z pakietu
systemowego `ffmpeg`, a `pactl` i `paplay` z pakietu `pulseaudio`. PipeWire ma
włączoną zgodność PulseAudio.

Pozostałe grupy Python:

| Zastosowanie | Pakiety (przykłady) |
|---|---|
| narzędzia | pip, virtualenv, setuptools, wheel, IPython, JupyterLab |
| jakość kodu | black, debugpy, mypy, pytest, ruff |
| nauka i dane | numpy, scipy, sympy, pandas, networkx, scikit-fuzzy, statsmodels |
| wykresy | matplotlib, seaborn, plotly |
| optymalizacja i robotyka | casadi, control, ortools |
| obrazy i urządzenia | pillow, scikit-image, pyserial, pyusb |
| dodatki projektu | pyyaml, requests, rich, tqdm, paramiko, scp, pygame |

## Usługi pomocnicze

- `tts-mako.nix` definiuje czytanie powiadomień; `services.ttsMako.enable` jest
  ustawione na `false` w `services.nix`.
- Czcionki systemowe są w `fonts.nix`; Barlow dodaje `keyboard-mouse.nix`.
- Hyprlock jest używany wyłącznie jako blokada ekranu w sesji Mango.

## Pakiety wymagające uwagi

Przed dodaniem pakietu sprawdź [BROKEN.md](../BROKEN.md). Przykładowo Grayjay
korzysta z oficjalnej binarki zamiast nixpkgs, które buduje CEF, a Android Studio
ma problem z niedostępnym archiwum upstream. Nie dodawaj niepotrzebnych źródeł
GitHub ani ciężkich kompilacji do profilu minimal.
