# BROKEN – rzeczy, które wywaliły build lub system
 
> Sprawdzaj przed dodaniem każdego pakietu (MASTER.md, pkt 10).
> Status: **zablokowane** (nie dodawać) / **obejście** (działa tylko w opisany sposób) / **rozwiązane** (można używać).
 
## Szablon wpisu
 
```
### <pakiet / opcja / override>
- Kiedy: RRRR-MM-DD, nixpkgs: <kanał / commit>
- Profil: minimal / full
- Objaw: <błąd, ile trwał build, co przestało działać>
- Przyczyna: <jeśli znana>
- Status: zablokowane / obejście / rozwiązane
- Obejście: <co zrobić zamiast>
```
 
---
 
## Wpisy

### webots – bundlowany plugin Qt6 "xcb" (QT_QPA_PLATFORM=xcb wymuszony przez launcher)
- Kiedy: 2026-11-16, nixpkgs: 26.05 (unstable dla buildInputs webots.nix)
- Profil: full
- Objaw: `webots` startuje przez `webots/webots` (launcher bash), który bezwarunkowo
  robi `export QT_QPA_PLATFORM="xcb"`. Na Mango (czysty wlroots, bez XWayland forsowanego
  explicite) kończy się: `Warning: ... xcb-cursor0 or libxcb-cursor0 is needed...` →
  `Fatal: ... no Qt platform plugin could be initialized` → `Aborted (core dumped)`.
  Plik `libxcb-cursor.so.0` FAKTYCZNIE jest bundlowany w `lib/webots/` i ma poprawny RPATH
  (sprawdzone `readelf -d`) – to nie brak pliku, tylko prawdopodobny mismatch ABI między
  bundlowanym `libxcb-cursor.so.0` (zbudowanym przez Cyberbotics pod starszy `libxcb`)
  a `libxcb` z nixpkgs (buildInputs webots.nix), którego linkuje przez autoPatchelf.
- Przyczyna: wymuszanie XWayland przez launcher ("dla kompatybilności") zamiast natywnego
  Wayland, mimo że tarball zawiera też bundlowany, sprawny plugin `wayland-egl`.
- Status: **obejście** (działa) – `substituteInPlace` w `webots.nix` zmienia
  `export QT_QPA_PLATFORM="xcb"` na `export QT_QPA_PLATFORM="''${QT_QPA_PLATFORM:-wayland}"`
  (default wayland, ale nadal nadpisywalne zmienną środowiskową, gdyby ktoś jednak
  potrzebował wymusić xcb). Zweryfikowane: `nix-build` + realny `result/bin/webots --minimize`
  bez ręcznych exportów – proces startuje i żyje, log pusty, zero crashy.
- Obejście: n/d (naprawione w kodzie, commit po tej sesji). Jeśli po aktualizacji Webots
  (nowa wersja tarballa) problem z xcb zniknie – można usunąć ten substituteInPlace i wrócić
  do oryginalnego launchera.

### android-studio
- Kiedy: 2026-11-11, nixpkgs: 26.11pre
- Profil: full
- Objaw: `cannot download android-studio-rabbit2-linux.tar.gz from any mirror` (connection reset by peer)
- Przyczyna: serwery Google nie udostępniają już tej wersji (2026.2.2.8 / rabbit2); nixpkgs nie nadążył z hashem
- Status: zablokowane
- Obejście: pobrać ręcznie z https://developer.android.com/studio i rozpakować do ~/android-studio; nie instalować przez nixpkgs do czasu aktualizacji paczki
 
### brave (przeglądarka)
- Kiedy: 2026-11-11, nixpkgs: 26.05
- Profil: minimal i full
- Objaw: `error: brave has been removed from nixpkgs, as there were no committers among its maintainers to unblock security issues`
- Przyczyna: usunięty z nixpkgs przez brak maintainerów zdolnych do obsługi CVE
- Status: zablokowane (nixpkgs); obejście: oficjalna binarka z Brave Releases
- Obejście: pobrać `.tar.gz` z oficjalnych GitHub Releases, spakować przez `autoPatchelfHook` (do zrobienia). Tymczasowo: firefox w minimal, google-chrome w full.

### OpenCV dla Pythona (kompilowany ze źródeł)
- Kiedy: przed 2026-11-10 (dokładna data i wersja nixpkgs nieznane)
- Profil: kompilowany podczas instalacji, przed postawieniem działającego systemu
- Objaw: kompilacja trwała bardzo długo i kończyła się błędami. Instalacja stanęła w chroot, bootloader nie był zainstalowany, system nie wstawał.
- Przyczyna: nieustalona; prawdopodobnie kompilacja ze źródeł zamiast pobrania z cache (np. przez override/flagi budowania)
- Status: zablokowane w minimal; w full dopuszczalne tylko budowane z działającego systemu
- Obejście: tylko w `program.nix` (full). Najpierw sprawdzić dry-buildem, czy przychodzi z cache, i nie stosować override'ów zmieniających flagi.

### Grayjay (agregator wideo by FUTO) – nixpkgs
- Kiedy: 2026-11-13, nixpkgs: 26.05
- Profil: full
- Objaw: `nixpkgs.grayjay` klonuje submoduły FUTO.MDNS, Grayjay.Engine, JustCef (Chromium Embedded Framework) – ogromna kompilacja CEF; build przerwany przez użytkownika
- Przyczyna: pakiet w nixpkgs kompiluje ze źródeł, nie dostarcza gotowej binarki z cache
- Status: **obejście** – używamy oficjalnej binarki ZIP zamiast nixpkgs
- Obejście: własna derywacja `grayjay` w `programs.nix` – pobiera oficjalny ZIP z `updater.grayjay.app`, CEF już bundlowany w ZIP (nie kompilujemy). Eksportuje `.desktop` do drun.

### nvim-treesitter (markdown_inline) – crash przy otwieraniu .md
- Kiedy: 2026-11-13, nvim-treesitter branch `master` @ `cf12346a`
- Profil: nvim (dotfiles/nvim) – oba profile, każda maszyna z tym repo
- Objaw: otwarcie pliku `.md` (zaobserwowane na `readme.md` projektu linefolower) czasem rzuca
  błąd: `vim.schedule callback: .../treesitter/languagetree.lua:215: .../treesitter.lua:197: attempt to call`
  (stack: `tcall` → `languagetree.lua:596`). Intermittentny – nie reprodukuje się w każdej sesji;
  headless (`nvim --headless`) go NIE łapie, bo wymaga realnego redraw (highlighter działa tylko
  na faktycznym repaintcie). `marksman` (LSP) jest przy tym czysty – to NIE błąd LSP, tylko crash
  silnika treesitter podczas parsowania wstrzykniętego języka `markdown_inline` w `markdown`.
- Przyczyna: prawdopodobnie regresja/race w async parserze treesitter dla injected languages.
  Próba "naprawy przez update": `nvim-treesitter` branch `master` jest **zamrożony od 2026-03-23**
  (`cf12346a3414fa1b06af75c79faebe7f76df080a` = tip origin/master, zero nowych commitów od miesięcy).
  Cała aktywność deweloperska przeniosła się na branch `main` z **innym, niekompatybilnym API**
  (nowa architektura, inny sposób `ensure_installed`/`highlight` – nasza konfiguracja w
  `lua/plugins/treesitter.lua` używa starego `require("nvim-treesitter.configs").setup{...}`,
  które na `main` już nie istnieje). Migracja na `main` = osobny, większy projekt, nie quick-fix.
  UWAGA przy próbie: `:Lazy! update nvim-treesitter` (z `!`) zaktualizował też NIEZWIĄZANE wtyczki
  (gitsigns.nvim, mini.splitjoin, vimtex) – wycofane (`git checkout -- lazy-lock.json`).
  Do aktualizacji JEDNEJ wtyczki: `:Lazy update nvim-treesitter` BEZ `!`.
- Status: **obejście** (2026-11-13, commit `180eaff`): `highlight.disable = { "markdown_inline" }`
  w `treesitter.lua` – parser `markdown_inline` zostaje zainstalowany, ale nie jest używany do
  highlight → crashująca ścieżka async-parse nigdy się nie odpala. `markdown` (nagłówki/blok
  kodu/listy) koloruje się normalnie; stracone jest tylko kolorowanie inline (bold/italic/linki).
  Zweryfikowane: 14 plików .md (projekt linefolower) + kilka przebiegów przez PTY (`script`,
  nie headless – headless nie łapie tego crasha, bo wymaga realnego redraw) – zero crashy.
- WAŻNE (poprawka wcześniejszego wniosku): migracja nvim-treesitter branch `master` → `main`
  **NIE naprawiłaby tego** – sprawdzone w kodzie `main`: cały faktyczny parsing wstrzykiwanych
  języków (`languagetree.lua`, `treesitter.lua`) to kod **wbudowany w Neovima** (core runtime,
  `/nix/store/.../neovim-0.12.4/share/nvim/runtime/lua/vim/treesitter/...`), identyczny
  niezależnie od brancha wtyczki nvim-treesitter (ta tylko instaluje parsery/query, main branch
  też w pełni deleguje do `vim.treesitter.*` core). Zanim próbować migracji ponownie w innym
  celu (nowe API, lepsze wsparcie) – to nie naprawi żadnego crasha w core, tylko przepisze
  config na nowszy, ale nie-kompatybilny interfejs.

### wpm-global ustawiał focus_color równolegle z WpmBorder.qml
- Kiedy: 2026-11-14
- Profil: full (programs.nix), Quickshell (dotfiles/quickshell)
- Objaw: `effects wpm-color`/`wpm-move`/`wpm-count` (Quickshell, dodane 2026-11-13) nie dawały
  żadnej kontroli – obramówka zmieniała kolor niezależnie od stanu togglów, "jakby nie było
  wpływu na ustawienia". Przy debugowaniu wczoraj `wpm-global` akurat nie działał (crash),
  dlatego konflikt nie był widoczny – dopiero po restarcie systemu (2026-11-14, exec_once
  wystartował go na nowo) ujawnił się w pełni.
- Przyczyna: DWIE niezależne, nic o sobie nie wiedzące implementacje liczenia WPM i ustawiania
  `focus_color` przez `mmsg dispatch setoption,focus_color,...`:
  1. `WpmBorder.qml` (Quickshell, EvtestReader) – ma togle (`qs-wpm-color/move/count`)
  2. `wpm-global` (C, `exec_once` w mango-autostart, PID zawsze żyje) – **bez żadnego toggla**
  `wpm-global` nadpisywał/ścigał się z WpmBorder.qml o ten sam `focus_color`, całkowicie poza
  zasięgiem `effects-ctl.sh`.
- Status: **rozwiązane** – `wpm-global.c` już NIE ustawia koloru (usunięte `set_color()`,
  `wpm_to_color()`, tabela `STOPS`). Zostaje tylko zapis `/tmp/nvim-wpm-$UID` dla
  `typing_speed.lua` w nvim (T3.5, licznik w lualine) – to jedyna unikalna funkcja tego
  binarnego, nie zduplikowana przez WpmBorder.qml, więc program NIE może być usunięty całkiem.
  Kolor i "ruszanie się" okna – wyłącznie `WpmBorder.qml`, z pełną kontrolą przez `effects`.
- Obejście: n/d (naprawione w kodzie, commit `37e04ed`). Po `boot`-rebuildzie wymagany restart
  systemu, żeby `exec_once=wpm-global` załadował nową binarkę z nowej generacji (albo ręcznie
  podmienić żywy proces na binarkę z `/nix/store/.../wpm-global-0.1.0/bin/wpm-global` – zrobione
  tego dnia, żeby nie czekać do reboota).

