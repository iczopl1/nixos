# TODO – lista zadań

> Format: `[ ]` do zrobienia · `[~]` w trakcie · `[x]` zrobione · `[-]` pominięte
> Jeden podpunkt = jeden commit. Kolejność zatwierdza użytkownik (MASTER §17).
> Gdzie skończyliśmy: patrz sekcja na dole.

---

## P0 – Krytyczne / bezpieczeństwo

- [x] **T0.1** security.nix – SSH off, firewall jawny, syncthing explicit ports
- [x] **T0.2** allowUnfreePredicate zamiast allowUnfree = true
- [x] **T0.3** hardware-configuration.nix – swap + /boot/efi opcje; /dane → local.nix (ntfs3, nofail, uid/gid)

---

## P1 – Ważne / blokujące inne

- [x] **T1.1** kernel zen w system.nix
- [x] **T1.2** Claude Code w programs.nix (MASTER §0 – zasada najważniejsza)
- [x] **T1.7** agy (antigravity-cli z unstable) w programs_minimal.nix (MASTER §0/§16)
- [x] **T1.3** ros2.nix przeniesiony do local.nix per-maszyna (nie zawsze importowany)
- [x] **T1.4** rebuild.sh + make-zip.sh + .gitignore
- [x] **T1.5** Podział na profil minimal i full (`configuration_minimal.nix` + `configuration.nix`)
        – minimal: boot, sieć, GUI, nvim, przeglądarka, KeePass, Claude Code, terminal, git
        – full: wszystko z minimal + crafts, python ciężki, android-studio, maltego, ros2 (via local)
        – python.nix: ciężkie biblioteki tylko do full (numpy/scipy zostają, casadi do sprawdzenia)
- [x] **T1.6** auto.sh – instalator na nową maszynę (MASTER §2)
        – wykrywa nową maszynę po UUID /
        – pyta minimal/full, pokazuje GB do pobrania
        – najpierw stawia minimal, potem full w tle
- [ ] **T1.11** Napraw Super+D (hintd) – nakładka klikalnych elementów
        – cel: Super+D pokazuje litery nad każdym miejscem gdzie można kliknąć myszką
          (linki, przyciski, pola, zakładki, itp.) – jak Vimium ale systemowo
        – priorytet: działać w Brave (Chromium/Wayland) – tam najważniejsze
        – sprawdzić dlaczego hintd nie wykrywa elementów w Brave:
          a) hintd może nie obsługiwać protokołu accessibility w Chromium (at-spi2)
          b) alternatywa dla Brave: wymusić Vimium/Vimium-C jako rozszerzenie
             (ManagedExtensions w brave.nix – obok KeePassXC)
          c) jeśli hintd działa tylko w GTK/Qt – rozważyć zastąpienie lub uzupełnienie
             czymś co obsługuje Chromium (np. xdotool-based lub at-spi2)
        – sprawdzić też czy hintd startuje poprawnie (logi: journalctl --user -u hintd)
- [x] **T1.8** Thunderbird – klient e-mail
        – `thunderbird` z nixpkgs (full); unfree: nie (jest wolny)
- [x] **T1.9** Beeper – komunikator all-in-one (Signal, WhatsApp, Telegram, iMessage…)
        – jest w nixpkgs (unfree beeper 4.2.808); dodano do allowUnfreePredicate
- [x] **T1.10** Grayjay – agregator wideo (YouTube, Twitch, Nebula…) by FUTO
        – jest w nixpkgs (unfree grayjay 17); dodano do allowUnfreePredicate
- [x] **T1.11b** Quickshell – pin do nowszej wersji z GitHuba (full: kompilacja per MASTER §12)
        – 0.3.0 z nixpkgs brakuje: layer_animations, nowych API (ExclusionMode i in.), animacji
        – full: skompilować nowszą wersję ze źródeł (fetchFromGitHub + nix-build, bez flake'ów)
          wzorem obecnej derywacji Brave/Linksy; wersję z nixpkgs zostawić w minimal (bez kompilacji)
        – minimal: zostaje quickshell z nixpkgs (0.3.0), konfiguracja QML musi działać na obu
        – po aktualizacji: sprawdzić czy layer_animations/animacje baru działają
        – UWAGA: punkt powrotu przed kompilacją (tag git + działający pasek na 0.3.0)
        – GIT: quickshell – nixpkgs 0.3.0 nie ma animacji i nowych API; dodano: 2026-11-13
- [ ] **T1.12** Linksy – extended screen na Pixel 9 (zależności + auto-akceptacja)
        – sprawdzić które zależności systemowe są potrzebne do trybu „extended screen"
          (Linksy udostępnia ekran PC na telefonie lub odwrotnie przez Wi-Fi/USB)
        – dodać brakujące buildInputs do derywacji w programs.nix jeśli linksy-screen crashuje
        – skonfigurować auto-akceptację połączenia z Pixel 9:
          a) sprawdzić czy Linksy ma plik konfiguracyjny z listą zaufanych urządzeń
          b) dodać UUID/nazwę Pixel 9 do trusted devices (plik per-maszyna w local.nix lub ~/.config)
        – przetestować: linksy-screen na PC + Linksy app na telefonie (Para / ADB wireless)

---

## P2 – Usprawnienia użytkowe

### System / środowisko
- [x] **T2.1** Auto-montowanie USB/dysków → `udiskie` + `udisks2`
        – services.udisks2.enable, exec_once=udiskie --no-tray --notify w mango
- [x] **T2.2** Narzędzia diagnostyki dysków: `smartmontools`, `nvme-cli`, `hdparm` (minimal), `gsmartcontrol` (GUI, full)
- [x] **T2.3** Narzędzia sieciowe: `nmap`, `wireshark`, `iperf3`, `mtr`, `dig`, `tcpdump`, `bandwhich`, `nethogs`, `speedtest-cli`
        – wireshark: programs.wireshark.enable + grupa wireshark (full)
- [x] **T2.4** Drukarka HP LaserJet M175n – `hplip` + CUPS + Avahi mDNS w services.nix
- [x] **T2.5** Skrót wyłączenia ekranu: `bind=SUPER,F9,spawn_shell,wlopm --off`
- [x] **T2.6** KeePassXC zawsze na workspace 9 – autostart + window_rule w Mango
        – `window_rule=app_id:org.keepassxc.KeePassXC,tags:9`
- [x] **T2.7** Super+Tab – window switcher z wszystkich workspaces
        – `rofi -show window -theme ~/.config/rofi/rofi.rosi` (zastąpił focusstack,next)
- [x] **T2.8** Status Syncthing w barze – przez 1 min: liczba połączeń; potem: stan synchronizacji
        – syncthing-status.sh (polling REST API) + syncLabel widget w shell.qml (T2.8 było zrobione)

### Bar (Quickshell)
- [x] **T2.25** Bar – prawa strona: CPU%, RAM%, bateria, prędkość sieci (↓↑ KB/s lub MB/s)
        – cpu/ram: timer 2–3s, diff /proc/stat i /proc/meminfo; bat: timer 30s
        – sieć: /proc/net/dev, pierwszy interfejs non-lo, diff bajtów co 2s
        – Kolejność: cpu XX% | ram XX% | vol XX% | bat XX% | ↓X ↑X

### Brave
- [x] **T2.9** Brave – managed policies w `/etc/brave/policies/managed/policy.json`:
        – BraveAIChatEnabled=false, MetricsReportingEnabled=false, PasswordManagerEnabled=false
        – AutofillAddress/CreditCard=false, DefaultSearchProvider=DuckDuckGo, BraveRewardsEnabled=false
        – Pominięte: PgUp/PgDown 0.5× (brak polityki), Enter=szukaj/Tab=uzupełnij (brak polityki)
- [x] **T2.10** Brave – zakładki zarządzane (ManagedBookmarks w policy.json):
        – folder AI: Claude, ChatGPT, Gemini, Le Chat, Perplexity
        – folder Google: Drive, Gmail, Mega.nz
        – folder Local: Syncthing :8384

### nvim
- [x] **T2.11** nvim – relative line numbers: `o.relativenumber = true` w options.lua
- [x] **T2.12** nvim – auto-detect venv dla Python (pyright): `.venv`, `venv`, `$VIRTUAL_ENV` w lsp.lua
- [x] **T2.13** nvim – auto-format po zapisaniu (conform.nvim):
        – lua, python, c/cpp, java, nix (nixfmt-rfc-style), js/ts/json/css/html (prettier)
- [x] **T2.14** nvim – clipboard=unnamedplus już w options.lua; Super+V = cliphist w mango
- [x] **T2.15** nvim – zmiana rozmiaru czcionki: Ctrl+= / Ctrl+- / Ctrl+0 natywnie w Alacritty
- [x] **T2.16** nvim – LaTeX (vimtex): zathura + latexmk, skróty `<leader>l*`
- [x] **T2.17** nvim – skróty buffer (Tab/S-Tab), tab (A-l/A-j), terminal (Esc+Esc, A-h/v/i)
- [x] **T2.18** nvim – layout startowy: `nvim .` otwiera NvimTree + pusty bufor + terminal (tło)
        – implementacja w autocmds.lua (VimEnter, argc==1, isdirectory)
- [x] **T2.19** nvim – DAP: Python (debugpy), C/C++ (lldb-dap), STM32 (OpenOCD)
- [x] **T2.20** Zmiana rozmiaru czcionki w terminalu – Alacritty Ctrl+= / Ctrl+- natywne
        – Alacritty/Kitty/Foot obsługują natywnie, sprawdzić który jest domyślny
- [x] **T2.26** nvim – pluginy produktywności (lua/plugins/):
        – `nvim-surround` (tpope/vim-surround fork): cs"' zmień, ys dodaj, ds usuń otoczenie
        – `flash.nvim`: szybka nawigacja po ekranie (skróty s/S/r)
        – `trouble.nvim`: panel błędów LSP/diagnostics/quickfix (<leader>xx)
        – `noice.nvim`: ładniejsze powiadomienia, cmdline, messages
        – `todo-comments.nvim`: podświetla TODO/FIXME/NOTE + Telescope (<leader>ft)
- [x] **T2.27** nvim – pluginy workflow:
        – `oil.nvim`: edytor plików jak bufor tekstu (zmień nazwę, przesuń, usuń)
        – `lazygit.nvim`: lazygit w float window (<leader>gg)
        – `git-blame.nvim`: inline blame (kto/kiedy napisał linię)
        – `mini.splitjoin`: gS/gJ split/join argumentów funkcji
- [x] **T2.28** nvim – UI:
        – `dashboard-nvim` lub `alpha-nvim`: ekran startowy
        – `zen-mode.nvim`: tryb skupienia (<leader>z)
        – `nvim-colorizer.lua`: podgląd kolorów hex/rgb w edytorze

- [ ] **T2.29** Super+F11 – naprawa toggle baru (ghost bar + brak przełączania)
        – obecny problem: pkill quickshell nie usuwa warstwy wlr-layer-shell od razu;
          stary bar zostaje widoczny przez chwilę lub na stałe (ghost surface)
        – przy ponownym starcie może uruchomić się drugi egzemplarz na tej samej warstwie
        – cel: SUPER+F11 = czyste hide/show baru bez artefaktów
        – propozycja: użyć `quickshell -n` (--no-duplicate) przy starcie autorun,
          toggle przez SocketServer w QML zamiast kill/restart procesu (jak Shortcuts/Particles),
          lub: `mmsg dispatch focusmon,…` + warunkowe `visible: false` na PanelWindow w QML

### Inne
- [x] **T2.21** Komenda `agent` w terminalu (alias w shell.nix → dotfiles/scripts/agent.sh)
        – wypisuje: system, narzędzia deweloperskie, Python/LaTeX/nvim/AI, serwisy lokalne
- [x] **T2.22** Mega.nz – `megatools` w programs.nix (megaput, megaget, megals, megacopy…)
- [x] **T2.23** JDownloader 2 – nie ma w nixpkgs; własna derywacja z oficjalnym Setup jarem
        – `writeShellScriptBin "jdownloader"` w programs.nix; Setup jar z fetchurl (sha256 przypięty)
        – pierwsze uruchomienie: GUI instalator → ~/JDownloader2/; dalej startuje bezpośrednio

---

## P3 – Na kiedyś / niski priorytet

- [x] **T3.1** Skrót Super+H – overlay z dokumentacją skrótów klawiszowych (Quickshell QML)
- [x] **T3.2** `setn.sh` – post-install: Tailscale, SSH key, Syncthing, KeePassXC, profil NixOS
- [x] **T3.3** nvim – tutorial/cheatsheet skrótów (which-key lub własny overlay)
        – rozbudowane grupy spec (g, [, ], leader-grupy LSP/kodu/termina), <leader>? = WhichKey
- [x] **T3.4** nvim – obsługa wszystkich popularnych języków (treesitter + LSP)
- [x] **T3.5** nvim – animacja pisania (kolor okna ↑ przy szybszym pisaniu, 1–90 wpm)
        – CursorLine bg: spoczynek→błękit→bursztyn→czerwień wg WPM; licznik w lualine (tryb insert)
- [x] **T3.6** AltGr+Ctrl jako drugi Super (xkb remap)
        – services.keyd: rightalt=layer(altgr), altgr/{left,right}control=leftmeta (system.nix)
- [x] **T3.7** Status telefonu GrapheneOS (Tailscale + BT headset switch PC↔telefon)
        – phone-status.sh: tailscale status --json | grep pixel; wskaźnik ph ●/○ w QS barze
        – bt-headset.sh: toggle connect/disconnect (MAC z ~/.config/bt-headset-mac); SUPER+F7
- [x] **T3.8** Brave – KeePassXC extension auto-install (ExtensionInstallForcelist w brave.nix)
- [x] **T3.9** Kalendarz + plan zajęć PRz (A3S, A3S-L3) z synchronizacją z telefonem
        – scraper `https://pei.prz.edu.pl/as/Zima2026_groups_days_horizontal.html`
        – zaimplementowany w dotfiles/scripts/prz-schedule.py (z opcją --ics)
- [x] **T3.10** Embedded: platformio (ESP32), esptool dodane; STM32/nRF/arm-none-eabi/openocd już były
- [x] **T3.11** Ograniczanie prędkości internetu per-aplikacja (tc/wondershaper/sqm)
        – skrypt dotfiles/scripts/throttle.sh (HTB qdisc + IFB dla ingress); alias `throttle` w shell.nix
- [x] **T3.12** Efekty graficzne: toggle-effects.sh (blur/animacje), bind=SUPER+F8, alias `effects`
- [x] **T3.13** Obramówka aktywnego okna zmienia kolor z prędkością pisania (WPM)
        – spoczynek→błękit→bursztyn→czerwień (jak T3.5 w lualine, ale border_color w mango)
        – skrypt wpm-border.sh: czyta WPM z pipe/socket od typing_speed.lua, ustawia kolor przez mmsg
        – kolory: 0–20 wpm: #9eeaf9 (spokój), 20–50: #e0af68 (amber), 50–80: #f7768e (czerwień)
        – aktywny tylko w trybie insert nvim (sygnał od autocmd InsertEnter/Leave)
        – wyłącznik: ten sam co T3.12 (toggle-effects.sh) albo osobny flag plik
- [x] **T3.14** Efekty cząsteczkowe na tle ekranu (Quickshell QML)
        – kilka motywów do wyboru skrótem np. SUPER+F6: liście jesienne, kropelki deszczu, śnieg, iskry
        – implementacja w Quickshell (WlrLayer.Background lub Overlay pod oknami), animacja przez Timer + Canvas
        – cząsteczki: pozycja/prędkość/opacity losowe, fizyka uproszczona (grawitacja, wiatr)
        – wydajność: max ~80 cząsteczek, Canvas tylko gdy warstwa aktywna; wyłączone domyślnie (MASTER §11)
        – motyw zapisany w ~/.config/particle-effect (plik z nazwą motywu lub "off")

---

## [-] Pominięte

- [-] **CpDev / TwinCAD 3 / CodeSys 3** – Wine + zawasowane sterowniki na X250 to zabójcze. Brak sensu.

---

## Gdzie skończyliśmy (2026-11-12)

**Zrobione (sesja 1):**
- rebuild.sh, auto.sh, brave.nix fix, T2.1–T2.7, T2.9/T2.10, T2.11–T2.22, T2.25
- T3.2, T3.8, T3.10, T3.12, T1.7 (agy)
- nvim: NvChad usunięty, nowa konfiguracja (dotfiles/nvim), lazy-lock.json wypełniony

**Zrobione (sesja 2):**
- Pamięć projektu zaktualizowana (memory/project_state.md, user_profile.md, feedback_workflow.md)
- T2.26: nvim – pluginy produktywności (nvim-surround, flash, trouble, noice, todo-comments)
- T2.27: nvim – pluginy workflow (oil.nvim, lazygit.nvim, git-blame.nvim, mini.splitjoin)
- T2.28: nvim – UI (alpha-nvim, zen-mode.nvim, nvim-colorizer.lua)

**Zrobione (sesja 3):**
- T3.1: Quickshell overlay Super+H (Shortcuts.qml + SocketServer + import Quickshell.Io)
- T2.23: JDownloader 2 (writeShellScriptBin + fetchurl Setup jar)
- T3.4: nvim LSP (cmake-language-server, bash/yaml/marksman + treesitter parsery)
- T2.26–T2.28: nvim pluginy (surround, flash, trouble, noice, todo-comments, oil, lazygit, git-blame, mini.splitjoin, alpha, zen-mode, colorizer)
- T3.6: AltGr+Ctrl = drugi Super (services.keyd w system.nix)

**Zrobione (sesja 4):**
- nixos-base.nix (renamed from system.nix – fix nixos-rebuild-ng)
- active-configuration.nix symlink w rebuild.sh (nix.nixPath profile-aware)
- T2.29: Super+F11 toggle baru przez SocketServer (ghost bar naprawiony)
- T1.11b: Quickshell unstable z lib.hiPrio w programs.nix
- T1.8: Thunderbird w programs.nix
- T1.9: Beeper w programs.nix + allowUnfreePredicate
- T1.10: Grayjay w programs.nix + allowUnfreePredicate
- T3.11: throttle.sh (tc HTB+IFB) + alias `throttle` w shell.nix
- Quickshell: animacje włączone (config.conf), Particles.qml fix ExclusionMode→exclusiveZone, shell.qml fix Singleton

**Następne w kolejce:**
- T1.12: Linksy extended screen (Pixel 9, zależności + auto-akceptacja) [wymaga rebuild]
- T1.11: hintd/Super+D fix (AT-SPI2 + Brave --force-renderer-accessibility) [wymaga rebuild]
- **REBUILD WYMAGANY** dla: T1.8/T1.9/T1.10/T1.11b (thunderbird, beeper, grayjay, quickshell unstable)

**Uwagi:**
- NvChad backup: ~/.config/nvim.nvchad-backup-20261112, ~/.local/share/nvim.nvchad-backup-20261112
- nvim: 31 pluginów, startuje bez warningów/błędów (exit 0, puste messages i stderr)
- Syncthing: folder Dane sync w toku (pixel9: ~68%, 929 MB do odebrania, brak błędów)
- Quickshell: animacje i layer_animations=1 w config.conf; `quickshell -n` w exec_once
