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

- [x] **T1.13** zramSwap – swap w RAM (MASTER §3; `zramSwap.enable` w nixos-base.nix)
        – zmniejsza przycinanie przy buildach w tle na 8 GB RAM
- [x] **T1.14** TLP + progi ładowania baterii ThinkPad X250
        – `services.tlp.enable` + `START_CHARGE_THRESH_BAT0=40 STOP=80`
        – wydłuża żywotność ogniw; per-maszyna przez local.nix lub bezpośrednio w services.nix
- [x] **T1.15** throttled (lenovo-throttling-fix) dla X250
        – BIOS celowo dławuje CPU przez PL1/PL2; throttled przywraca pełną wydajność
        – `services.throttled.enable` w services.nix (tylko minimal, lekki daemon)

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
- [x] **T1.11** Napraw Super+D (hintd) – nakładka klikalnych elementów
        – AT-SPI2: services.gnome.at-spi2-core.enable w services.nix
        – Brave: --force-renderer-accessibility w brave.nix (makeWrapper, linia 91)
        – wymaga rebuild żeby nowa binarka Brave weszła w życie
- [x] **T1.8** Thunderbird – klient e-mail
        – `thunderbird` z nixpkgs (full); unfree: nie (jest wolny)
- [x] **T1.9** Beeper – komunikator all-in-one (Signal, WhatsApp, Telegram, iMessage…)
        – jest w nixpkgs (unfree beeper 4.2.808); dodano do allowUnfreePredicate
- [x] **T1.10** Grayjay – agregator wideo (YouTube, Twitch, Nebula…) by FUTO
        – nixpkgs `grayjay` kompiluje JustCef (CEF) ze źródeł – zablokowane (patrz BROKEN.md)
        – obejście: własna derywacja w programs.nix, ZIP z updater.grayjay.app (CEF bundlowany, nie kompilowany)
        – wyeksportowany do drun przez `.desktop` entry; wymaga rebuild
- [x] **T1.11b** Quickshell – pin do nowszej wersji z GitHuba (full: kompilacja per MASTER §12)
        – 0.3.0 z nixpkgs brakuje: layer_animations, nowych API (ExclusionMode i in.), animacji
        – full: skompilować nowszą wersję ze źródeł (fetchFromGitHub + nix-build, bez flake'ów)
          wzorem obecnej derywacji Brave/Linksy; wersję z nixpkgs zostawić w minimal (bez kompilacji)
        – minimal: zostaje quickshell z nixpkgs (0.3.0), konfiguracja QML musi działać na obu
        – po aktualizacji: sprawdzić czy layer_animations/animacje baru działają
        – UWAGA: punkt powrotu przed kompilacją (tag git + działający pasek na 0.3.0)
        – GIT: quickshell – nixpkgs 0.3.0 nie ma animacji i nowych API; dodano: 2026-11-13
- [x] **T1.12** Linksy – extended screen na Pixel 9 (zależności + auto-akceptacja)
        – GStreamer (base/good/bad + pipewire) bundlowany w binarce – brak potrzeby dodatkowych deps
        – XDG ScreenCast + RemoteDesktop portal: skonfigurowane w mango.nix (xdg-desktop-portal-wlr)
        – auto-akceptacja: Pixel 9 już w trusted.json + potwierdzony w terminal.json (confirmed)
        – v4l2loopback dodany do programs.nix (boot.extraModulePackages) – wymagany dla `linksy camera`
        – Użycie: `linksy extend <nazwa>` (telefon jako drugi monitor), `linksy camera <nazwa>` (wirtualna kamera)
        – wymaga rebuild żeby v4l2loopback wszedł w życie

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
- [x] **T2.39** nvim-treesitter: crash przy .md – `highlight.disable = {"markdown_inline"}`
        – Powód: crash treesitter przy otwieraniu .md (injected `markdown_inline`,
          `languagetree.lua:215`/`treesitter.lua:197` "attempt to call"; intermittentny,
          nie łapie się headless, trzeba PTY – patrz BROKEN.md, wpis 2026-11-13). `marksman`
          (LSP) czysty, to crash silnika treesitter, nie LSP.
        – ZMIANA PLANU (po researchu): migracja branch `master`→`main` **nie naprawiłaby tego**
          – sprawdzone w kodzie `main`: cały faktyczny parsing wstrzykiwanych języków to kod
          wbudowany w Neovima (core runtime `vim/treesitter/*`), identyczny niezależnie od
          brancha wtyczki. Migracja = tylko przepisanie na niekompatybilne API, bez naprawy.
          Branch `master` dodatkowo zamrożony od 2026-03-23 (`cf12346a`) – nic nowego do update.
        – Realny fix: `highlight.disable = { "markdown_inline" }` w `treesitter.lua` (commit
          `180eaff`) – parser instaluje się, ale nie jest używany do highlight, więc crashująca
          ścieżka async-parse nigdy się nie odpala. `markdown` (nagłówki/kod/listy) koloruje się
          normalnie, strata: kolorowanie inline (bold/italic/linki).
        – Zweryfikowane: 14 plików .md w projekcie linefolower + wielokrotne przebiegi PTY
          (`script`, nie headless) – zero crashy. Headless sanity check (`nvim configuration.nix`)
          – czysto.
        – Migracja na `main` (nowe API, lepsze wsparcie upstream) zostaje jako możliwe zadanie
          na kiedyś, ale bez obietnicy naprawy tego konkretnego crasha – patrz BROKEN.md.

- [x] **T2.29** Super+F11 – naprawa toggle baru (ghost bar + brak przełączania)
        – obecny problem: pkill quickshell nie usuwa warstwy wlr-layer-shell od razu;
          stary bar zostaje widoczny przez chwilę lub na stałe (ghost surface)
        – przy ponownym starcie może uruchomić się drugi egzemplarz na tej samej warstwie
        – cel: SUPER+F11 = czyste hide/show baru bez artefaktów
        – propozycja: użyć `quickshell -n` (--no-duplicate) przy starcie autorun,
          toggle przez SocketServer w QML zamiast kill/restart procesu (jak Shortcuts/Particles),
          lub: `mmsg dispatch focusmon,…` + warunkowe `visible: false` na PanelWindow w QML

### System
- [x] **T2.30** nix.gc.automatic – automatyczne czyszczenie starych generacji (cotygodniowo, keep 5)
- [x] **T2.31** direnv + nix-direnv – auto `nix-shell` przy wejściu do katalogu projektu
        – `direnv allow` w katalogu z `.envrc`; `nix-direnv` cache'uje env, nie przebudowuje każdorazowo
- [x] **T2.32** podman – kontenery bez roota (full; `virtualisation.podman.enable`)
- [x] **T2.37** age – nowoczesne szyfrowanie plików (`age -r`, kompatybilne z SSH keys; minimal)
- [x] **T2.38** dnscrypt-proxy – DNS over HTTPS (blokada reklam/trackerów systemowo; ustalić wyjątek firewall)
- [ ] **T2.40** Program throttlujący CPU przy przegrzaniu: 85°C → ogranicz moc, aż spadnie do 70°C
        – Powód: X250 pod długim obciążeniem (np. build full, kompilacja) może grzać się mocno
          mimo `services.throttled` (T1.15 – throttled naprawia tylko BIOS-owe PL1/PL2, nie
          chroni przed przegrzaniem przy realnym długim 100% obciążeniu). To osobny mechanizm:
          nie "napraw sztuczne dławienie", a "aktywnie dław, gdy naprawdę gorąco".
        – a) Odczyt temperatury: `/sys/class/thermal/thermal_zone*/temp`, najwyższa ze stref
          (ten sam wzorzec co bar T2.33 – `dotfiles/quickshell` ma już tę logikę, do podglądu).
        – b) Throttle: `/sys/devices/system/cpu/intel_pstate/max_perf_pct` – obniżyć (np. do
          ~50%) gdy temp ≥ 85°C. NIE to samo co `no_turbo` (TURBO_OFF_BUILD w rebuild.sh) –
          max_perf_pct ogranicza częstotliwość ogólnie, no_turbo tylko wyłącza boost.
        – c) Histereza: trzymać ograniczenie, dopóki temp nie spadnie ≤ 70°C, potem przywrócić
          max_perf_pct=100 (poprzedni stan, nie na sztywno 100 – jeśli user/TLP coś tam ustawił).
        – d) Koordynacja z istniejącym: `services.throttled` (T1.15) i `TURBO_OFF_BUILD`
          (rebuild.sh, tylko na czas buildu full) – nowy program nie może nadpisywać ich zmian
          w złym momencie; polling co few sekund (np. 5s), lekki demon (wzorzec jak throttled.py).
        – e) Miejsce: systemd service w `services.nix` (full – dotyczy głównie starszego
          sprzętu jak X250) albo prosty skrypt bash + systemd timer/service, do ustalenia.
        – f) Log aktywacji throttla (np. do journalu) – żeby było widać kiedy i jak często
          się odpalał (przydatne do oceny, czy progi 85/70°C mają sens na tej maszynie).
        – Priorytet: proponuję **P2** (bezpieczeństwo termiczne sprzętu, ale nie blokuje innych
          zadań, X250 ma już throttled+TLP+turbo-off-przy-buildzie jako warstwy ochrony).
          Do potwierdzenia/zmiany przez użytkownika.

### Bar (Quickshell)
- [x] **T2.33** Bar – temperatura CPU (°C) przed/po fps
        – `/sys/class/thermal/thermal_zone*/temp`, najwyższa ze stref; timer 3s; kolor: <70°C szary, 70–85°C amber, >85°C czerwień
- [x] **T2.34** Bar – media player (playerctl + MPRIS)
        – `playerctl metadata --format '{{artist}} – {{title}}'`; przyciski ◀ ▶ ▮▮ klikalne
        – widoczny tylko gdy coś gra; znika gdy brak odtwarzacza

### Narzędzia
- [x] **T2.35** wl-screenrec lub wf-recorder – nagrywanie ekranu Wayland
        – bind `SUPER+F5` = start/stop; zapis do `~/Videos/`
- [x] **T2.36** satty – adnotacje na screenshotach (strzałki, tekst, blur obszaru)
        – pipe z grim: `grim -g "$(slurp)" - | satty -f -`; zastępuje dotychczasowe `grim | wl-copy`

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
- T1.10: Grayjay ZABLOKOWANE (nixpkgs kompiluje JustCef/CEF) – wpis BROKEN.md
- T3.11: throttle.sh (tc HTB+IFB) + alias `throttle` w shell.nix
- Quickshell: animacje włączone (config.conf), Particles.qml fix ExclusionMode→exclusiveZone, shell.qml fix Singleton
- T1.11: Brave --force-renderer-accessibility + at-spi2-core (w kodzie, wymaga rebuild)
- T1.12: v4l2loopback dla Linksy camera; XDG portal + trusted.json Pixel 9 OK

**Gdzie skończyliśmy (2026-11-13 sesja 5):**
Wszystkie nowe zadania T1.13–T1.15 i T2.30–T2.38 wdrożone i zcommitowane.
Lista `[ ]` pusta. Gotowe do `./rebuild.sh`.

**Sesja 6 (2026-11-13, ad-hoc poza TODO – Beeper workspace 8, sudoers NOPASSWD dla agenta,
Grayjay icu fix, Linksy udev+gtk4paintablesink, effects-ctl.sh, STM32 nvim LSP/DAP, lualine
theme fix):** wszystko zcommitowane (zob. `git log`). Jedyne niezrobione: **T2.39** (nowe,
zrobione: fix) – crash treesitter przy .md, `highlight.disable markdown_inline`, patrz BROKEN.md.

**Po następnym rebuild sprawdzić:**
- Super+F11 toggle baru (bez ghost surface)
- Super+D w Brave (hintd + --force-renderer-accessibility)
- linksy extend / linksy camera (v4l2loopback)
- Thunderbird, Beeper (nowe pakiety)

**Uwagi:**
- NvChad backup: ~/.config/nvim.nvchad-backup-20261112, ~/.local/share/nvim.nvchad-backup-20261112
- nvim: 31 pluginów, startuje bez warningów/błędów (exit 0, puste messages i stderr)
- Quickshell: animacje i layer_animations=1 w config.conf; `quickshell -n` w exec_once

**Sesja 7 (2026-11-14, ad-hoc poza TODO – particles leaves/rain/snow naprawione (warstwa
background zajęta przez cava-bg/awww, przeniesione na bottom/overlay), cursor particles 10x
+ limit 10, effects wpm-color/wpm-move/wpm-count rozdzielone, cava toggle, naprawiony konflikt
wpm-global vs WpmBorder.qml o focus_color – patrz BROKEN.md):** wszystko zcommitowane.
Jedyne niezrobione: **T2.40** (nowe, czeka na zatwierdzenie priorytetu) – throttle CPU przy 85°C.

**Sesja 8 (2026-11-16, ad-hoc poza TODO – środowisko do ćwiczenia 2 "Sterowanie robotem
Khepera III logiką rozmytą", full):**
- Python (python.nix): `pyserial` i `scikit-fuzzy` już były w `pythonWithAiRPackages` –
  nic nie trzeba było dodawać do listy pakietów.
- **Znaleziony i naprawiony bug:** `programs_minimal.nix` instaluje gołe `python3`, a
  `python.nix` (full) dokłada `pythonWithAiRPackages` – obie derywacje dają `bin/python3`
  z tym samym domyślnym priorytetem. Na żywym systemie (`/run/current-system`) wygrywał
  goły python3 bez numpy/pyserial/scikit-fuzzy – potwierdzone empirycznie
  (`readlink -f $(which python3)` → plain `python3-3.13.17`, `import numpy` ⇒ ModuleNotFoundError).
  Fix: `(lib.hiPrio pythonWithAiRPackages)` w `python.nix` (ten sam wzorzec co
  `lib.hiPrio unstable.quickshell` w programs.nix dla analogicznej kolizji).
- **webots.nix (nowy plik, full):** symulator Webots R2025a – nie ma w nixpkgs (sprawdzone:
  `pkgs.webots` nie istnieje), Apache-2.0 (bez unfree). Oficjalna binarka z GitHub Releases
  (`.tar.bz2`, ~150 MB), MASTER §13 kolejność 2. Zależności ustalone realnym `readelf -d`
  na webots-bin + bundlowanych `.so` (Qt6/ODE/assimp/OpenAL/OIS bundlowane – autoPatchelf
  znajduje je sam w `$out`, nie w buildInputs). Zweryfikowane lokalnym `nix-build` +
  uruchomieniem `webots-bin --help` – ładuje się i działa; autoPatchelf ignoruje tylko
  opcjonalne pluginy (motyw GTK3, druk CUPS, SSH/gcrypt, OpenEXR – żaden nie blokuje
  symulatora). `WEBOTS_HOME` ustawiony systemowo (`environment.variables`) – wymagany przez
  `from controller import Robot` (czyste ctypes w `lib/controller/python`, bez kompilowanego
  rozszerzenia per-wersja Pythona, więc działa z dowolnym python3).
- Zaimportowany do `configuration.nix` (full, nowa linia `./webots.nix`).
- Użytkownik ręcznie zsynchronizował `/etc/nixos` i zrobił `sudo nixos-rebuild switch` –
  build przeszedł (tylko ostrzeżenia: `xorg.libX11`/`xorg.libxcb` deprecated – poprawione na
  `libx11`/`libxcb`; `services.dnscrypt-proxy2` deprecated – niezwiązane z tą sesją, już
  wcześniej w `security.nix`, oba tylko warningi, nie błędy).
- **Pasek Quickshell padł po switchu** (zero procesów `quickshell`, stare gniazda `qs-*.sock`
  po martwym procesie) – `nixos-rebuild switch` nie restartuje procesów z `exec_once` Mango.
  Niezwiązane z tą sesją (webots.nix/python.nix nie dotykają Quickshell). Odpalony ręcznie
  tą samą komendą co autostart (`quickshell -n`) – wstał czysto, `Configuration Loaded`,
  zero błędów.
- Użytkownik uruchomił `./rebuild.sh` samodzielnie – build `boot` przeszedł, auto-commit
  `a37e1b9` (2026-11-16 13:14), `/etc/nixos` zsynchronizowane. To generacja 35 – **nieaktywna
  do restartu** (`/run/current-system` to wciąż gen. 34, sprzed tej sesji, bez webots/fixa
  pythona – `nixos-rebuild boot` nie przełącza działającego systemu, tylko ustawia domyślny
  wpis GRUB-a na następny start, zgodnie z MASTER). Po restarcie: sprawdzić że działa.
- **Po rebuildzie sprawdzić:** `webots` odpala się z drun/terminala, otwiera scenę
  `khepera3.wbt`, kontroler Python (`from controller import Robot`) działa bez ręcznego
  ustawiania `WEBOTS_HOME`.
- **Dogrywka (ten sam dzień, po restarcie na gen. 35):** `webots` faktycznie crashował
  (`Fatal: no Qt platform plugin` – xcb plugin, ABI mismatch libxcb-cursor, launcher wymuszał
  XWayland na czystym Wayland/Mango) – patrz BROKEN.md. Naprawione: `substituteInPlace`
  w `webots.nix`, default `QT_QPA_PLATFORM=wayland` (nadpisywalny). Zweryfikowane lokalnym
  `nix-build` + realnym uruchomieniem wrappera (`result/bin/webots --minimize`, zero ręcznych
  exportów) – proces startuje i żyje, zero crashy. Wymaga kolejnego `./rebuild.sh` +
  restartu żeby trafić na żywy system (nie zrobione przeze mnie – brak sudo w tej sesji).

**Sesja 9 (2026-11-16, ad-hoc poza TODO – login w TTY + logout manager, CHIRP dla Baofenga):**
- **Login w TTY (zamiast auto-startu Mango przez greetd):** `services.nix` –
  `services.greetd.enable = false` (był `true`, odpalał Mango bezpośrednio jako `iczo`).
  System wraca do standardowego `getty@tty1` – login/password prompt w konsoli przy starcie.
- **Auto-start Mango po zalogowaniu:** `shell.nix` – nowy `programs.bash.loginShellInit`:
  jeśli brak `$WAYLAND_DISPLAY`/`$DISPLAY` i tty to `/dev/tty1` → `exec mango` (klasyczny
  wzorzec `.bash_profile: exec startx`; `exec` podstawia proces Mango pod shella, więc po
  wylogowaniu wracamy prosto do login prompta na tty1, bez zombie-shella). Dotyczy TYLKO
  login shelli (tty), nie każdego nowego terminala w Mango (`interactiveShellInit` to
  osobne pole, bez zmian).
- **Logout manager – SUPER+Escape:** `wlogout` (GTK layer-shell, ~140 KiB, czysto z cache –
  zweryfikowane dry-buildem obu profili) dodany do `programs_minimal.nix` (działa w obu
  profilach, nie tylko full). Bind w `dotfiles/mango/config.conf`:
  `bind=SUPER,Escape,spawn,wlogout`. **SUPER+L zostaje bez zmian** (`focusdir,right`) –
  użytkownik zdecydował nie przenosić go.
- Własny layout `dotfiles/wlogout/layout` (symlink przez `dotfiles.nix`) – przycisk „lock”
  woła `hyprlock` bezpośrednio (domyślne `loginctl lock-session` nic by nie zrobiło – Mango
  nie obsługuje sygnału Lock z logind). Reszta (logout/suspend/hibernate/reboot/shutdown)
  jak w domyślnym layout wlogout. **`style.css` NIE skopiowany** – zostaje domyślny z pakietu
  (ikony wskazują na własny `/nix/store/.../wlogout-.../share/...`, więc zawsze zgodny
  z zainstalowaną wersją; kopia starego style.css groziłaby złym hashem po aktualizacji).
- **CHIRP (programowanie Baofeng/radiotelefonów przez USB-serial):** `pkgs.chirp` dodany do
  `programs.nix` (full) – w nixpkgs, 29 MiB download, zero kompilacji lokalnej (dry-build
  zweryfikowany). Dostęp do `/dev/ttyUSB*` już jest przez grupę `dialout`
  (`nixos-base.nix`, użytkownik `iczo` już w tej grupie od T3.10) – żadna nowa reguła udev
  nie była potrzebna.
- Zweryfikowane: składnia (`nix-instantiate --parse`) wszystkich zmienionych plików, `statix`/
  `deadnix` (same stare, niezwiązane ostrzeżenia – zero nowych od tych zmian), dry-build
  `configuration_minimal.nix` i `configuration.nix` (oba: wszystko z cache, zero nowych
  lokalnych kompilacji poza standardowymi małymi derywacjami systemowymi jak przy każdym
  rebuildzie).
- **NIE zrobione przeze mnie – brak sudo w tej sesji (`sudo -n true` → "a password is
  required"):** `./rebuild.sh` (build `boot` + commit + kopiowanie do `/etc/nixos`).
  Zmiany leżą tylko w working tree repo, nie commitowane (MASTER §6 – bez buildu nie
  commitujemy). **Do zrobienia przez użytkownika:** `./rebuild.sh "tty login + wlogout
  (SUPER+Escape) + chirp"`, potem restart żeby auto-login-w-TTY i wlogout faktycznie
  zadziałały (obecny `/run/current-system` wciąż ma stare `greetd`).
- **Po rebuildzie i restarcie sprawdzić:** boot pokazuje tty1 login prompt (nie GUI), login
  → Mango startuje automatycznie, SUPER+Escape otwiera wlogout, przycisk „Lock” w wlogout
  faktycznie odpala hyprlock, „Logout” wraca do login prompta na tty1, `chirp` odpala się
  z terminala/drun i widzi kabel USB-serial do Baofenga.

**Sesja 10 (2026-11-16, ad-hoc poza TODO – fix `dotfiles/mango/config.conf` (błąd "invalid
line format" linia 52 – wieloliniowy komentarz bez `#` na każdej linii, sprzed tej sesji),
diagnoza i fix crasha Discorda, diagnoza USB Linksy↔telefon):**
- **Mango config fix:** `dotfiles/mango/config.conf` – komentarz nad `mango-effects-restore.sh`
  rozbity na 5 linii, tylko pierwsza miała `#`; mango parsuje każdą linię osobno i linie
  52-55 nie zaczynały się od `#` → "invalid line format". Scalone w jeden 3-liniowy komentarz
  nad `exec_once`. Błąd istniał od dawna (niezależny od zmian z tej sesji), po prostu nikt
  wcześniej nie zrestartował configu żeby go zobaczyć.
- **Discord – crash "Cannot find module 'discord_desktop_core'" (napraw w `programs.nix`,
  derywacja `discord-latest`):** Pierwsza hipoteza (SKIP_MODULE_UPDATE / module_data) okazała
  się błędna po realnym teście (zweryfikowano: symlinkowanie modułów do `~/.config/discord/
  module_data/*` NIE naprawiało crasha). Prawdziwa przyczyna znaleziona przez ręczne
  rozpakowanie `app.asar` (własny mini-parser formatu Pickle w Pythonie, `node` do przeszukania
  `bundle.js`) i śledzenie realnego kodu: `requireNative("discord_desktop_core")` (webpack id
  23505) tworzy `Module` z `paths=[]` – require nie ma czego przeszukać, więc zawodzi
  natychmiast, bez żadnego dostępu do dysku (stąd `strace` nic nie łapał). Jedyna droga,
  by to zadziałało: `registerLocalModulePaths(buildInfo)` (webpack id 84237) dodaje katalog
  modułów do `Module.globalPaths` – ale TYLKO gdy `buildInfo.localModulesRoot` jest ustawione
  w `resources/build_info.json`. Oficjalny `build_info.json` (ten sam, który pobiera
  `discord/update.py` z nixpkgs) tego pola nie ma – jest przewidziane właśnie dla pakietów
  dystrybucyjnych typu ten z nixpkgs, ale nixpkgs go nie ustawia. Fix: `overrideAttrs` z
  `postInstall`, który dopisuje `"localModulesRoot":"$out/opt/Discord/modules"` do
  `build_info.json` (`substituteInPlace`, zamiana jedynego `}` w pliku). **Zweryfikowane
  realnie** – osobny `nix-build` w scratchpadzie + odpalenie binarki na żywym Wayland/Mango:
  bez fixa zawsze `Cannot find module 'discord_desktop_core'` (świeży, pusty `$HOME` też –
  to NIE był problem starego/zepsutego profilu); z fixem Discord faktycznie dochodzi do
  załadowania treści z `discordapp.com` (CSP-log webpacka to dowód, że JS apki się odpalił),
  dalej leci dopiero na GPU w tym konkretnym sandboxie bez `/dev/dri` – nieistotne dla realnego
  systemu, gdzie GPU działa (ten sam `vaapi` warning już wcześniej był tylko warningiem, nie
  fatalnym crashem).
  **Efekt uboczny tej sesji:** podczas testów usunięty `~/.config/discord/module_data`
  (prawdziwy profil użytkownika, nie tylko scratchpad) – to tylko cache natywnych modułów
  bez znaczenia po tym fixie (nieużywany), ale celowo zaznaczam że to się stało bez pytania.
- **Linksy↔telefon (Pixel 9, GrapheneOS) – diagnoza, NIE problem repo:** telefon widoczny na
  USB (`idVendor=18d1 idProduct=4ee2`), reguła udev z `programs.nix` działa (`uaccess` się
  przykleja, `ID_USB_INTERFACES` dokładnie pasuje do wzorca). `adb devices` → `unauthorized`
  (brak zaakceptowanego klucza RSA tego PC). Kluczowe: binarka `linksyd` (sprawdzona przez
  `strings`) NIE używa MTP/libmtp/gvfs/ADB do transferu – szuka dedykowanego interfejsu
  **AOA (Android Open Accessory)**, czyli `idProduct` z zakresu `18d1:2d0[0-5]` (stąd ta
  gałąź w regule udev). `journalctl -k` potwierdza, że telefon migrował między `4ee2`/`4ee7`
  (zwykłe MTP+ADB) i nigdy nie osiadł na `2d0[0-5]` – negocjacja AOA się nie udała. **Do
  zrobienia na telefonie (nie w repo):** odblokować ekran w momencie podłączania (Android
  blokuje zmiany USB przy zablokowanym ekranie), zaakceptować systemowy dialog Androida
  o otwarciu Linksy dla urządzenia USB (jeśli się nie pojawia, sprawdzić w GrapheneOS
  ograniczenia dostępu USB), zaakceptować/odświeżyć "Zezwól na debugowanie USB" z opcją
  "Zawsze zezwalaj z tego komputera". `sudo linksy-system-setup usb` NIE jest potrzebne
  (i zawsze się wywali na NixOS – `/etc` jest read-only, reguła już jest deklaratywnie).
- **Do zrobienia przez użytkownika:** `./rebuild.sh "fix mango config.conf linia 52 + discord
  localModulesRoot fix"` (budowanie `boot`, commit, kopiowanie do `/etc/nixos`) – brak sudo
  w tej sesji. Discord po rebuildzie powinien normalnie wstawać.
