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
- Status: **zablokowane** (update na `master` nic nie da – nie ma nowszego commita)
- Obejście: do zrobienia – wyłączyć highlight dla `markdown_inline` (albo całego `markdown`) w
  `treesitter.lua` (`highlight.disable`), żeby uniknąć ścieżki crashującego parsera, kosztem
  utraty kolorowania inline (bold/italic/linki) albo całego kolorowania .md.
  Migracja na branch `main` (nowe API) – do rozważenia jako osobne zadanie, nie na szybko.

