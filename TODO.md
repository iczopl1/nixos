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
- [ ] **T3.3** nvim – tutorial/cheatsheet skrótów (which-key lub własny overlay)
- [x] **T3.4** nvim – obsługa wszystkich popularnych języków (treesitter + LSP)
- [ ] **T3.5** nvim – animacja pisania (kolor okna ↑ przy szybszym pisaniu, 1–90 wpm)
- [ ] **T3.6** AltGr+Ctrl jako drugi Super (xkb remap)
- [ ] **T3.7** Status telefonu GrapheneOS (Tailscale + BT headset switch PC↔telefon)
- [x] **T3.8** Brave – KeePassXC extension auto-install (ExtensionInstallForcelist w brave.nix)
- [ ] **T3.9** Kalendarz + plan zajęć PRz (A3S, A3S-L3) z synchronizacją z telefonem
        – scraper `https://pei.prz.edu.pl/as/Zima2026_groups_days_horizontal.html`
- [x] **T3.10** Embedded: platformio (ESP32), esptool dodane; STM32/nRF/arm-none-eabi/openocd już były
- [ ] **T3.11** Ograniczanie prędkości internetu per-aplikacja (tc/wondershaper/sqm)
- [x] **T3.12** Efekty graficzne: toggle-effects.sh (blur/animacje), bind=SUPER+F8, alias `effects`

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

**Następne w kolejce:**
- T3.1: Super+H overlay z dokumentacją skrótów (Quickshell QML)
- T2.23: JDownloader 2 (brak w nixpkgs, ręczna instalacja lub własna derywacja)
- T3.9: Kalendarz PRz (scraper planu zajęć)

**Uwagi:**
- NvChad backup: ~/.config/nvim.nvchad-backup-20261112, ~/.local/share/nvim.nvchad-backup-20261112
- nvim: 31 pluginów, startuje bez warningów/błędów (exit 0, puste messages i stderr)
- Syncthing: folder Dane sync w toku (pixel9: ~68%, 929 MB do odebrania, brak błędów)
