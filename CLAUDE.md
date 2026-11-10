# CLAUDE.md – instrukcje dla agenta w tym repo

@MASTER.md
@TODO.md
@BROKEN.md

**Na start każdej sesji:** przeczytaj `MASTER.md` (najwyższy priorytet), potem `TODO.md` (sekcja „Gdzie skończyliśmy”) i `BROKEN.md`.
Odpowiadaj po polsku.

Najważniejsze (szczegóły zawsze w `MASTER.md`):
- **Claude Code musi działać w minimal**, nigdy go z minimal nie usuwaj.
- Budujesz zawsze w trybie `boot`, nigdy `switch` na niesprawdzonej konfiguracji. Commit i kopiowanie do `/etc/nixos` robisz tylko po udanym buildzie (`rebuild.sh`).
- Minimal nie ma ciężkiej kompilacji. Full może kompilować, ale z git tylko z uzasadnieniem.
- Nie używasz flake'ów ani flag do zapamiętania. `hardware-configuration.nix` i `local.nix` leżą poza repo.
- Partycje Windowsa (w tym jego EFI) są nietykalne. GRUB instaluje się tylko na ESP Linuksa.
- nvim jest przypięty. Praca nad nim ma limit 1 h, potem rollback.
- Przy buildzie full na X250 turbo jest wyłączone (`TURBO_OFF_BUILD`) i zawsze przywracane po buildzie.
- Zmiany przy ROS idą w osobnych commitach `ros:`, z dodatkową weryfikacją.
- Zadania z `TODO.md`: najpierw przepisz, sprawdź zgodność z MASTER i nadaj priorytet (zatwierdza użytkownik). Potem wprowadzasz po kolei: jeden podpunkt = jeden commit, a po każdym aktualizujesz `TODO.md`.
- Użytkownik zawsze może powiedzieć „stop”. Wtedy cofasz zmiany do ostatniej działającej wersji.
- Po każdej zmianie zasad aktualizuj `MASTER.md` w repo – to jedyne źródło prawdy.
