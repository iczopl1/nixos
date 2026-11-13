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

### Grayjay (agregator wideo by FUTO)
- Kiedy: 2026-11-13, nixpkgs: 26.05
- Profil: full
- Objaw: `nixpkgs.grayjay` klonuje submoduły FUTO.MDNS, Grayjay.Engine, JustCef (Chromium Embedded Framework) – ogromna kompilacja CEF; build przerwany przez użytkownika
- Przyczyna: pakiet w nixpkgs kompiluje ze źródeł, nie dostarcza gotowej binarki z cache
- Status: zablokowane
- Obejście: pobrać AppImage z oficjalnej strony FUTO (https://grayjay.app) i uruchomić przez `appimage-run` albo poczekać aż nixpkgs doda prebuilt binarkę

