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
- [ ] **T2.4** Drukarka HP LaserJet M175n – `hplip`, `cups`, auto-wykrycie przewodowej
- [x] **T2.5** Skrót wyłączenia ekranu: `bind=SUPER,F9,spawn_shell,wlopm --off`
- [x] **T2.6** KeePassXC zawsze na workspace 9 – autostart + window_rule w Mango
        – `window_rule=app_id:org.keepassxc.KeePassXC,tags:9`
- [x] **T2.7** Super+Tab – window switcher z wszystkich workspaces
        – `rofi -show window -theme ~/.config/rofi/rofi.rosi` (zastąpił focusstack,next)
- [ ] **T2.8** Status Syncthing w barze – przez 1 min: liczba połączeń; potem: stan synchronizacji
        – skrypt polling SyncthingAPI (port 8384 lokalny), widget w Quickshell

### Bar (Quickshell)
- [ ] **T2.25** Bar – prawa strona: CPU%, RAM%, bateria, prędkość sieci (↓↑ KB/s lub MB/s)
        – CPU: `/proc/stat` (diff między próbkami, timer 2s)
        – RAM: `/proc/meminfo` (MemTotal - MemAvailable)
        – Bateria: `/sys/class/power_supply/BAT0/` capacity + status (już jest, poprawić widoczność)
        – Sieć: `/proc/net/dev` (diff bajtów RX/TX między próbkami, wybrany interfejs: eth0/wlan0/wlp*)
        – Kolejność: cpu XX% | ram XX% | bat XX% | ↓X ↑X

### Brave
- [ ] **T2.9** Brave – paczka ustawień przez `programs.brave` lub managed policies:
        – wyłącz AI (Leo), wyłącz Google jako domyślna wyszukiwarka
        – wyłącz autouzupełnianie bez Tab (Enter = szukaj, Tab = uzupełnij)
        – wyłącz proponowanie zapisania hasła
        – wyłącz telemetrię / opcjonalne dane
        – PgUp/PgDown 0.5× standardowego kroku
- [ ] **T2.10** Brave – zakładki (bookmarks policy):
        – folder AI: ChatGPT, Gemini, Le Chat, Claude, Perplexity
        – folder Google: Drive, Gmail, Mega.nz
        – folder Local: lokalne usługi z tej konfiguracji (Syncthing :8384, itp.)

### nvim
- [ ] **T2.11** nvim – relative line numbers: `5,4,3,2,1,{nr},1,2,3,4,5`
        – `set number relativenumber` w init.lua
- [ ] **T2.12** nvim – auto-detect venv / środowiska per język:
        – Python: .venv, venv, .v, v → pyright/pylsp czyta biblioteki stamtąd
        – Node: node_modules lokalne
        – Rust: Cargo.toml → rust-analyzer
- [ ] **T2.13** nvim – auto-format po zapisaniu (conform.nvim lub LSP format on save)
        – Python: black/ruff, Lua: stylua, C/C++: clang-format, Nix: nixfmt, JS: prettier
- [ ] **T2.14** nvim – synchronizacja schowka: `y`/`p` ↔ schowek systemowy bez kombinacji
        – `set clipboard=unnamedplus`; Super+V → historia schowka przez cliphist + rofi
- [ ] **T2.15** nvim – skrót zmiany rozmiaru czcionki (jak w terminalu)
- [ ] **T2.16** nvim – pełna obsługa LaTeX (vimtex) + skrót `tex` w terminalu:
        – kompilacja z minted (shell-escape, latexmk), czyszczenie plików pomocniczych
        – podgląd PDF w zathurze (już zainstalowany)
- [ ] **T2.17** nvim – skróty buffer/tab/terminal:
        – otwórz/zamknij bufor, przejście między tabami bez blokady przez terminal
        – wyjście z terminala jedną kombinacją
- [ ] **T2.18** nvim – layout startowy:
        – tab 0: pliki projektu (neo-tree/oil)
        – tab 1: terminal + terminal z claude
        – tab 2: lazygit lub fugitive (obsługa git)
- [ ] **T2.19** nvim – skróty build/debug per język:
        – make build/debug, DAP dla Python/Java/Rust/Go/Lua/C++
- [ ] **T2.20** Zmiana rozmiaru czcionki w terminalu skrótem (Ctrl+= / Ctrl+-)
        – Alacritty/Kitty/Foot obsługują natywnie, sprawdzić który jest domyślny

### Inne
- [ ] **T2.21** `agent.md` – komenda w terminalu zwracająca info dla AI agentów:
        – zainstalowane narzędzia, wersje, konfiguracja Python/LaTeX/nvim
- [ ] **T2.22** Mega.nz manager – `megatools` lub `megacmd` w programs.nix
- [ ] **T2.23** JDownloader 2 – autostart, szybkie toggle zbierania linków, obsługa torrentów
        – sprawdzić czy jest gotowa binarka NixOS (AUR-style)

---

## P3 – Na kiedyś / niski priorytet

- [ ] **T3.1** Skrót Super+H – overlay z dokumentacją skrótów klawiszowych (Quickshell QML)
- [ ] **T3.2** `setn` – interaktywny skrypt post-install: Syncthing, Tailscale, SSH key, itp.
- [ ] **T3.3** nvim – tutorial/cheatsheet skrótów (which-key lub własny overlay)
- [ ] **T3.4** nvim – obsługa wszystkich popularnych języków (treesitter + LSP)
- [ ] **T3.5** nvim – animacja pisania (kolor okna ↑ przy szybszym pisaniu, 1–90 wpm)
- [ ] **T3.6** AltGr+Ctrl jako drugi Super (xkb remap)
- [ ] **T3.7** Status telefonu GrapheneOS (Tailscale + BT headset switch PC↔telefon)
- [ ] **T3.8** Brave – auto-instalacja rozszerzenia KeePassXC
- [ ] **T3.9** Kalendarz + plan zajęć PRz (A3S, A3S-L3) z synchronizacją z telefonem
        – scraper `https://pei.prz.edu.pl/as/Zima2026_groups_days_horizontal.html`
- [ ] **T3.10** Środowiska embedded: STM32, ESP32, nRF, Arduino (platformio, arm-none-eabi, openocd)
- [ ] **T3.11** Ograniczanie prędkości internetu per-aplikacja (tc/wondershaper/sqm)
- [ ] **T3.12** Profil efektów graficznych: minimal/medium/full przełączany w locie
        – X250 domyślnie minimal, PC z RTX domyślnie full

---

## [-] Pominięte

- [-] **CpDev / TwinCAD 3 / CodeSys 3** – Wine + zawasowane sterowniki na X250 to zabójcze. Brak sensu.

---

## Gdzie skończyliśmy (2026-11-12)

**Zrobione w tej sesji:**
- rebuild.sh: nix-build zamiast nixos-rebuild-ng (fix kompatybilności z modułami NixOS)
- auto.sh: auto-generowanie commitu, prompt minimal/full przy braku PROFILE
- brave.nix: fix Exec= w .desktop (brave-stable → brave)
- T2.1: udiskie + udisks2 (programs_minimal.nix + services.nix + mango)
- T2.2: smartmontools, nvme-cli, hdparm (minimal), gsmartcontrol (full)
- T2.3: nmap, wireshark, iperf3, mtr, dig, tcpdump, bandwhich, nethogs, speedtest-cli
- T2.5: wlopm + bind SUPER+F9 w mango
- T2.6: keepassxc autostart + window_rule tag 9 w mango

**Następne w kolejce:**
- T2.7: Super+Tab window switcher (rofi -show window)
- T2.25: Bar prawa strona CPU%/RAM%/bat/sieć (QML w shell.qml)
- T2.9/T2.10: Brave policies/zakładki

**Uwagi:**
- T2.9 (Brave policies) – wymaga sprawdzenia czy NixOS ma `programs.chromium`/managed policies.
- Zmiany T2.1–T2.6 są w working tree; uruchom `! ./auto.sh` żeby zbudować i commitować.
