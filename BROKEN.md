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
 
### OpenCV dla Pythona (kompilowany ze źródeł)
- Kiedy: przed 2026-11-10 (dokładna data i wersja nixpkgs nieznane)
- Profil: kompilowany podczas instalacji, przed postawieniem działającego systemu
- Objaw: kompilacja trwała bardzo długo i kończyła się błędami. Instalacja stanęła w chroot, bootloader nie był zainstalowany, system nie wstawał.
- Przyczyna: nieustalona; prawdopodobnie kompilacja ze źródeł zamiast pobrania z cache (np. przez override/flagi budowania)
- Status: zablokowane w minimal; w full dopuszczalne tylko budowane z działającego systemu
- Obejście: tylko w `program.nix` (full). Najpierw sprawdzić dry-buildem, czy przychodzi z cache, i nie stosować override'ów zmieniających flagi.
 
