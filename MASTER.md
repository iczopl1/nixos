# MASTER – najważniejsze zasady projektu NixOS Config
 
> Ten plik ma pierwszeństwo przed wszystkim innym w projekcie. Każda zmiana w konfiguracji musi być z nim zgodna.
> Cel nadrzędny: **nie wywalać systemu** i móc szybko postawić działającą maszynę od zera.
 
---
 
## 0. Złote reguły (zawsze)
 
**★ Zasada najważniejsza: Claude Code (i dostęp do czatów AI) musi działać w minimal.** Kiedy coś się posypie, pomoc AI ma być pod ręką od pierwszego uruchomienia systemu (pkt 16).
 
1. **Agent (Claude Code) używa wyłącznie `nixos-rebuild boot` lub `build` – nigdy `switch`.** Użytkownik może używać `switch` według własnego uznania. `rebuild.sh` zawsze buduje w trybie `boot` (patrz pkt 6).
2. **Każda działająca wersja = commit w git.** Bez commita nie kopiujemy niczego do `/etc/nixos`.
3. **Nie usuwamy starych generacji ręcznie**, dopóki nowa nie przeszła przynajmniej jednego restartu (zawsze jest do czego wrócić z menu bootloadera).
4. **`hardware-configuration.nix` jest per-maszyna** i nigdy nie jest nadpisywany plikiem z innej maszyny (patrz pkt 1).
5. **Najpierw system, który się uruchamia – potem reszta.** Bootloader musi być zainstalowany, a system bootowalny, zanim zacznie się cokolwiek ciężkiego lub ryzykownego. Nigdy więcej siedzenia w chroot z systemem, który nie wstaje, bo instalacja padła na kompilacji jakiegoś pakietu.
6. Minimal **może kompilować, ale tylko małe i pewne rzeczy** (szczegóły w pkt 4). Ciężkie i ryzykowne kompilacje idą wyłącznie do full.
7. **Bez flake'ów i bez flag do zapamiętania.** Żadnego `--flake .#host`, żadnych osobnych konfiguracji per maszyna wybieranych flagą. Pomylona lub zapomniana flaga = znikające programy albo nagle pobieranie ciężkich paczek. Wybór profilu robi skrypt, nie człowiek (pkt 6).
8. **Sprzęt: zawsze UEFI + GRUB 2, partycja EFI (FAT32) zawsze montowana w `/boot/efi`, os-prober włączony – dual boot wspierany, Windows i Linux całkowicie niezależne (osobne partycje EFI).** Żadnego trybu BIOS/legacy i żadnego systemd-boot (pkt 3).
9. **Kernel: zen (`linuxPackages_zen`)** – kernel nastawiony na responsywność desktopu, w obu profilach (pkt 3).
10. **W branchu `main` nie ma szyfrowania dysku.** Żadnego LUKS-a, `boot.initrd.luks.devices`, `enableCryptodisk` ani szyfrowanego swapa – ani w minimal, ani w full (pkt 3).
11. **Neovim ma pierwszeństwo.** Wersja nvim jest przypięta na sztywno, jej źródła/binarki leżą w projekcie, a każda praca agenta nad nvim ma limit 1 h i automatyczny rollback (pkt 7).
12. **SSH (serwer) całkowicie wyłączony, firewall zawsze włączony** i domyślnie nic nie wpuszcza. Każdy otwarty port tylko za zgodą użytkownika; wyjątki dla Tailscale i synchronizacji ustalane po przejrzeniu aktualnego configu (pkt 8).
13. **Repo ≤ 3 GB łącznie, wszystko lokalne w git; rdzeń konfiguracji zawsze mieści się w zipie na Discorda** (pkt 9).
14. **`BROKEN.md` sprawdzany przed dodaniem każdego pakietu** – co raz wywaliło build, nie wraca bez rozwiązania (pkt 10).
15. **Wydajność: full ma działać płynnie na ThinkPad X250.** Rozbudowa systemu nie może tego zepsuć; zaawansowane efekty graficzne są dozwolone tylko z przełącznikiem, który je wyłącza (pkt 11).
16. **Quickshell wszędzie, gdzie się da i ma to sens** – elementy interfejsu (pasek, widgety, zmiana tapety itd.) robimy w Quickshell zamiast osobnych programów (pkt 12).
17. **Full: najnowsze z GitHuba tylko z uzasadnieniem.** Pakiet budujemy z git/GitHuba tylko gdy wersja z nixpkgs przeszkadza (np. Discord wyłącza się na nieaktualnej wersji) albo pakietu w ogóle nie ma w nixpkgs. Reszta (np. office) – z nixpkgs. Kolejność: nixpkgs → oficjalna binarka z Releases → kompilacja ze źródeł. **nvim zawsze przypięty** (pkt 7). Minimal zostaje czysty: z cache, bez pobierania „najnowszego” (pkt 13).
18. **ROS = strefa bardzo delikatna.** Każda zmiana przy ROS: osobny commit (tylko ROS), dodatkowa weryfikacja i zgoda użytkownika przed commitem. ROS tylko w full, tylko na maszynie, która go potrzebuje, i odizolowany od reszty systemu (pkt 14).
19. **System zawsze na wspieranej wersji stabilnej NixOS.** Wersja po końcu wsparcia (brak łatek bezpieczeństwa) to błąd do naprawy, nie stan normalny (pkt 15).
20. **ThinkPad X250 i starsze: turbo procesora wyłączone na czas budowania full.** `rebuild.sh` sam wyłącza turbo przed buildem full i zawsze włącza je z powrotem po zakończeniu – także gdy build się wywali albo zostanie przerwany (pkt 5).
21. **TODO: najpierw przepisać, sprawdzić ze zgodnością z MASTER, nadać priorytet – potem wprowadzać po kolei, jeden podpunkt = jeden commit.** Postęp zapisywany w `TODO.md`, żeby każdą przerwaną pracę dało się szybko podjąć (pkt 17).
---
 
## 1. Struktura plików
 
Klasyczny układ NixOS (bez flake'ów): dwa pliki wejściowe + moduły tematyczne.
 
```
configuration_minimal.nix   ← profil minimal (wejście)
configuration.nix           ← profil full (wejście) = importuje configuration_minimal.nix + dodatki
modules/
  system.nix                ← bootloader (GRUB 2 EFI), kernel zen, locale, strefa czasu, użytkownicy, nix.settings
  services.nix              ← sieć (NetworkManager), dźwięk (PipeWire), bluetooth, zasilanie
  security.nix              ← firewall, SSH wyłączone (pkt 8)
  desktopmanager.nix        ← display manager / środowisko graficzne
  tilemanager.nix           ← tiling WM i jego konfiguracja
  nvim.nix                  ← Neovim – przypięta wersja z vendor/nvim (pkt 7)
  program_minimal.nix       ← programy niezbędne (przeglądarka, KeePassXC, terminal, git…)
  program.nix               ← programy tylko dla full (ciężkie, kompilowane, OpenCV, ML itd.)
  …                         ← kolejne moduły wg potrzeb, jeden temat = jeden plik
vendor/nvim/                ← źródła i gotowe binarki przypiętej wersji Neovima (pkt 7)
auto.sh                     ← instalator (pkt 2)
rebuild.sh                  ← przebudowa + commit + kopiowanie do /etc/nixos (pkt 6)
make-zip.sh                 ← zip rdzenia dla kolegi / Discord (pkt 9)
BROKEN.md                   ← lista rzeczy, które wywaliły build (pkt 10)
CLAUDE.md                   ← plik czytany automatycznie przez Claude Code: odsyła do MASTER.md (pkt 16)
TODO.md                     ← lista zadań: priorytety, status, miejsce przerwania pracy (pkt 17)
/etc/nixos/hardware-configuration.nix  ← per-maszyna, NIE w repo
```
 
### Zasady struktury
- **`configuration.nix` (full) importuje `configuration_minimal.nix`** i dokłada tylko moduły full. Dzięki temu minimal ⊂ full jest zagwarantowane przez samą budowę plików – nic z minimal nie może „zniknąć” w full.
- **Przy każdym imporcie komentarz, co ten plik daje / instaluje.** Patrząc na `imports` od razu widać zawartość profilu, np.:
  ```nix
  imports = [
    /etc/nixos/hardware-configuration.nix  # sprzęt tej maszyny (generowany przez instalator)
    ./modules/system.nix                   # GRUB 2 EFI, kernel zen, locale, użytkownik
    ./modules/services.nix                 # NetworkManager, PipeWire, bluetooth, zasilanie
    ./modules/desktopmanager.nix           # display manager + sesja graficzna
    ./modules/nvim.nix                     # Neovim
    ./modules/program_minimal.nix          # Firefox, KeePassXC, terminal, git, curl…
  ];
  ```
- **Każdy moduł zaczyna się komentarzem-nagłówkiem** z listą tego, co instaluje/włącza.
- Moduły **minimal nie importują modułów full**. Kierunek importu zawsze full → minimal, nigdy odwrotnie.
- Coś ciężkiego (kompilacja, duże GB) trafia do pliku z „full” w roli – nigdy do `*_minimal.nix` ani do wspólnych modułów importowanych przez minimal.
- **`hardware-configuration.nix` nie jest w repo** (w `.gitignore`). Konfiguracja importuje go ścieżką bezwzględną `/etc/nixos/hardware-configuration.nix`, więc to samo repo działa na każdej maszynie bez flag i bez plików per-host. Kopiowanie repo do `/etc/nixos` **nigdy go nie nadpisuje**.
---
 
## 2. Instalator (`auto.sh`) – minimal czy full
 
**Sposób użycia na nowej maszynie:** w chroot → `git clone <repo>` → `./auto.sh`. Dalej wszystko dzieje się samo, **z internetem**. Minimal ma się dać postawić także **bez internetu albo z ograniczonym** – wtedy korzysta z plików lokalnych w repo (`vendor/`), które są w git (pkt 9).
 
Instalator uruchamia się przy każdym wgrywaniu konfiguracji i sam decyduje, czy to **pierwsza instalacja na nowej maszynie**:
 
1. Generuje świeży hardware config (`nixos-generate-config --show-hardware-config`) do pliku tymczasowego.
2. Porównuje go z aktualnym `/etc/nixos/hardware-configuration.nix`.
3. **Kryterium decydujące: UUID partycji `/`** (`fileSystems."/".device`).
   - UUID się **zgadza** → to znana maszyna, zwykła aktualizacja (bez pytań o profil).
   - UUID się **nie zgadza** lub brak pliku → **nowa maszyna / pierwsza instalacja**, nowy plik hardware zapisuje się w `/etc/nixos`.
   - Pozostałe różnice (moduły kernela, swap, inne partycje itd.) **nie** decydują o nowej instalacji – można je tylko zgłosić jako ostrzeżenie.
4. Przy nowej maszynie instalator **zgaduje partycje EFI i swap** (szczegóły w pkt 3), pokazuje propozycję do potwierdzenia i **montuje partycję EFI w `/boot/efi` przed wygenerowaniem hardware configu** (żeby `nixos-generate-config` wpisał właściwy punkt montowania).
5. Przy pierwszej instalacji instalator pyta: **`minimal` czy `full`?** i przy każdej opcji pokazuje **przybliżoną ilość GB do pobrania**.
   - Rozmiar liczymy, a nie zgadujemy: dry-build danego pliku wejściowego wypisuje „will be fetched (X MiB download, Y MiB unpacked)”.
   - Instalator pokazuje też szacowany czas przy 8 MB/s oraz **listę pakietów „will be built”** (co będzie kompilowane lokalnie).
6. Wybrany profil instalator zapisuje w pliku-znaczniku **`/etc/nixos/PROFILE`** (`minimal` albo `full`). Od tego momentu skrypt przebudowy sam wie, którego pliku wejściowego użyć.
7. **Nawet przy wyborze `full` na nowej maszynie instalator najpierw stawia minimal** (bootowalny system z bootloaderem), a full buduje dopiero potem, z działającego systemu, w trybie `boot`. Błąd kompilacji w full nigdy nie zostawia maszyny bez działającego systemu.
8. Przy nowej maszynie instalator **sprawdza, czy to ThinkPad X250 albo starszy sprzęt** (pkt 5 – turbo off przy buildzie full) i proponuje ustawienie znacznika `/etc/nixos/TURBO_OFF_BUILD`; do potwierdzenia przez użytkownika.
---
 
## 3. Sprzęt: UEFI + GRUB 2, kernel zen, wykrywanie partycji
 
### Bootloader – zawsze GRUB 2 w trybie EFI, ESP w `/boot/efi`
W `modules/system.nix` (wspólne dla minimal i full):
```nix
boot.loader.grub.enable = true;
boot.loader.grub.efiSupport = true;
boot.loader.grub.device = "nodev";              # EFI – GRUB nie instaluje się do MBR
boot.loader.efi.canTouchEfiVariables = true;
boot.loader.efi.efiSysMountPoint = "/boot/efi"; # partycja EFI (FAT32) zawsze tutaj
boot.loader.grub.useOSProber = true;            # wykrywa inne systemy – dual boot
```
- **Układ:** partycja FAT32 (ESP) → `/boot/efi`, zawiera tylko plik EFI GRUB-a. Samo `/boot` (kernele, initrd, `grub.cfg`) leży na partycji `/`. Dzięki temu mała partycja EFI nie zapcha się kernelami przy wielu generacjach.
- Konsekwencja: GRUB musi umieć odczytać partycję `/` (ext4/btrfs – OK). Dlatego też **brak szyfrowania w `main`** (złota reguła 10) – niezaszyfrowane `/` GRUB czyta bez żadnej dodatkowej konfiguracji.
- W `hardware-configuration.nix` musi być `fileSystems."/boot/efi"` z `fsType = "vfat"` i UUID partycji EFI. Instalator **sprawdza to przed buildem** – jeśli ESP jest wpisana jako `/boot`, to błąd (niezgodność z `efiSysMountPoint`), nie idziemy dalej.
- Instalator **sprawdza, czy maszyna jest uruchomiona w trybie UEFI** (istnieje `/sys/firmware/efi`). Jeśli nie → stop z jasnym komunikatem (włączyć UEFI w BIOS-ie), a nie instalacja, która potem nie wstanie.
- Po instalacji instalator **weryfikuje bootloader**: czy w `/boot/efi/EFI/` jest GRUB i czy jest wpis w `efibootmgr`. Brak = instalacja nieudana, nie przechodzimy dalej (złota reguła 5).
- Opcjonalnie, dla maszyn z kapryśnym firmware: `boot.loader.grub.efiInstallAsRemovable = true` (wtedy `canTouchEfiVariables = false`) – instaluje GRUB-a w ścieżce domyślnej `/boot/efi/EFI/BOOT/BOOTX64.EFI`.
### Brak szyfrowania dysku w `main`
- W branchu `main` **nie ma żadnego szyfrowania dysku**: brak `boot.initrd.luks.devices`, `boot.loader.grub.enableCryptodisk`, szyfrowanego swapa (`swapDevices.*.randomEncryption`) i podobnych opcji – w żadnym module, w minimal ani w full.
- Instalator **sprawdza partycje**: jeśli `/` (albo inna montowana partycja) jest na LUKS-ie (`FSTYPE=crypto_LUKS` w `lsblk`) lub hardware config zawiera `boot.initrd.luks` → stop z komunikatem, że `main` nie obsługuje szyfrowania.
- `rebuild.sh` przed buildem przeszukuje konfigurację (`grep` po `luks` / `Cryptodisk` / `randomEncryption`) – znalezione = odmowa buildu w `main`.
- Szyfrowanie, jeśli kiedyś będzie potrzebne, robimy **wyłącznie w osobnym branchu** i nie mergujemy go do `main`.
### Dual boot – wspierany, systemy całkowicie niezależne
**Układ (stan na 2026-11-10):** Windows zainstalowany pierwszy, Linux całkowicie osobno – **osobne partycje, w tym osobne partycje rozruchowe (EFI)** dla Windowsa i NixOS (dużo partycji na jednym dysku, np. do `sda8`). Wspólna jest **tylko partycja na dane (NTFS)**. Jedyne powiązanie: wpis Windowsa w menu GRUB-a.
 
**Cel nadrzędny:** reinstalacja Windowsa nie uszkadza Linuksa, a reinstalacja Linuksa nie uszkadza Windowsa.
 
- `boot.loader.grub.useOSProber = true` w obu profilach – GRUB sam dodaje Windowsa do menu przy każdym buildzie (os-prober na chwilę montuje partycje tylko do odczytu, nic nie zmienia).
- **Partycje Windowsa (w tym jego EFI) są nietykalne:** instalator i skrypty nigdy ich nie formatują, nie montują na stałe, nie wpisują do `hardware-configuration.nix` i niczego na nich nie zapisują. GRUB instaluje się **wyłącznie na partycji EFI Linuksa**.
- **Po instalacji / migracji sprawdzamy, czy Windows jest w menu GRUB-a** (log buildu – os-prober wypisuje znalezione systemy). Uwaga: przy pierwszej instalacji z chroot os-prober często nie widzi Windowsa – po pierwszym uruchomieniu NixOS robimy zwykły `./rebuild.sh` i wpis się pojawia.
- **Po reinstalacji Windowsa:**
  - Windows zwykle ustawia siebie jako pierwszy przy starcie → menu startowe w BIOS-ie albo `efibootmgr` (GRUB z powrotem pierwszy); NixOS jest cały, nic nie reinstalujemy,
  - partycje Windowsa mogą mieć nowe UUID → `./rebuild.sh`, żeby os-prober odświeżył wpis w GRUB-ie.
- **Po reinstalacji Linuksa:** formatujemy tylko partycje Linuksa (w tym **jego** EFI); partycja EFI Windowsa i partycja danych zostają bez zmian.
- Ustawienia po stronie Windowsa – **zrobione:** hibernacja / szybkie uruchamianie wyłączone, zegar ustawiony, dodatkowe blokady wyłączone. NixOS zostaje na domyślnym zegarze (UTC).
### Wspólna partycja na dane (NTFS)
- Jedyna partycja Windowsa, którą NixOS montuje. Wpis **per maszyna w `/etc/nixos/local.nix`** (poza repo), nie w `hardware-configuration.nix` i nie w repo.
- **Montowanie nie może zablokować startu systemu** – zawsze z `nofail` i krótkim timeoutem:
  ```nix
  fileSystems."/mnt/dane" = {                      # wspólna partycja NTFS (dane)
    device = "/dev/disk/by-uuid/<UUID>";
    fsType = "ntfs3";                              # sterownik NTFS z kernela
    options = [ "nofail" "x-systemd.device-timeout=5s" "uid=1000" "gid=100" "umask=022" ];
  };
  ```
  Gdy partycji nie ma albo Windows zostawił ją w złym stanie → NixOS i tak normalnie wstaje, tylko bez `/mnt/dane`.
- Instalator przy nowej maszynie **pyta**, czy jest wspólna partycja na dane i gdzie ją montować – sam jej nie dopisuje.
### Kernel – zen
Kernel zen jest dostrojony pod desktop: lepiej reaguje na wejście użytkownika (mysz, klawiatura, przełączanie okien) pod obciążeniem. Na starym sprzęcie jak X250 – szczególnie podczas budowania full w tle – robi to realną różnicę.
 
W `modules/system.nix` (wspólne dla minimal i full):
```nix
boot.kernelPackages = pkgs.linuxPackages_zen;  # kernel zen – responsywność desktopu
```
- **Zen jest w oficjalnym nixpkgs i normalnie przychodzi gotowy z cache** – to NIE jest „własny kernel” z zakazu dla minimal, więc może być w obu profilach.
- **Nie robimy na nim overrides ani własnych patchy/configu** (`structuredExtraConfig`, `kernelPatches` itd.) – każda taka zmiana = kompilacja całego kernela lokalnie (na X250 to godziny).
- Dodatkowe moduły kernela zawsze z `config.boot.kernelPackages` (np. `boot.extraModulePackages = with config.boot.kernelPackages; [ ... ];`), żeby pasowały do zena.
- **Bezpiecznik:** jeśli dry-build pokazuje kernel zen na liście „will be built” (bo np. cache jeszcze go nie zbudował po aktualizacji nixpkgs), minimal **tymczasowo używa domyślnego kernela** (`pkgs.linuxPackages`), a zen wraca przy następnej aktualizacji. Kompilacja kernela nie może zablokować postawienia systemu.
- Dodatkowo pod responsywność (opcjonalnie, z cache, bez kompilacji): zram zamiast/obok swapa na dysku (`zramSwap.enable = true;`) – mniej przycinania przy braku RAM-u.
### Zgadywanie partycji EFI i swap
Skrypt próbuje sam ustalić partycje (`lsblk -o NAME,SIZE,FSTYPE,PARTTYPE,UUID,MOUNTPOINT` / `blkid`):
 
- **EFI (ESP) Linuksa → montowana w `/boot/efi`** – po kolei:
  1. jeśli jest już zamontowana w `/boot/efi` – ta,
  2. typ partycji GPT = EFI System (`c12a7328-f81f-11d2-ba4b-00a0c93ec93b`),
  3. jeśli brak: partycja FAT32 (`vfat`) o rozmiarze ok. 100 MB – 2 GB, najlepiej na dysku z `/`.
  - **Na dysku są dwie partycje EFI (Windows + Linux)** – instalator **nigdy nie wybiera ESP, na której jest `EFI/Microsoft`** (to partycja Windowsa). Wybiera tę z katalogiem GRUB-a/NixOS albo pustą. Gdy nie da się tego jednoznacznie ustalić → pokazuje zawartość każdej ESP i pyta użytkownika.
- **swap** – po kolei:
  1. typ partycji GPT = Linux swap (`0657fd6d-a4ab-43c4-84e5-0933c84b4f4f`) albo `FSTYPE=swap`,
  2. aktywny swap z `swapon --show`,
  3. jeśli nie ma żadnego – informacja „brak swapa” i propozycja swapfile/zram (nie blokuje instalacji).
- Partycje szukamy **najpierw na tym samym dysku co `/`**, dopiero potem na innych.
- **Skrypt nigdy nie formatuje ani nie zmienia partycji sam.** Tylko proponuje i montuje.
- Propozycję zawsze **pokazuje do potwierdzenia** (urządzenie, rozmiar, typ, UUID). Gdy kandydatów jest kilku albo żaden – pyta, którą partycję wybrać.
- W `hardware-configuration.nix` partycje wpisywane są **po UUID** (`/dev/disk/by-uuid/...`), nigdy po `/dev/sdX`.
---
 
## 4. Profil `minimal` (`configuration_minimal.nix`)
 
**Wymaganie:** na ThinkPad X250 system ma wstać **ok. 1 h od uruchomienia instalatora**, przy pobieraniu ~8 MB/s. Docelowo **~3 GB pobierania** (przy 8 MB/s to ok. 6–7 min – reszta czasu to rozpakowanie, ewentualne drobne buildy, instalacja i zapas).
 
### Kompilacja w minimal – co wolno, a czego nie
 
Kompilacja **jest dozwolona**, jeżeli pakiet spełnia wszystkie warunki:
- buduje się **szybko** (orientacyjnie: kilka minut na X250, łącznie wszystkie lokalne buildy minimal mieszczą się w budżecie 1 h),
- buduje się **pewnie** – był już zbudowany na tej konfiguracji bez błędów,
- jest **potrzebny do pracy od razu**, a nie „przyda się kiedyś”.
**Zakazane w minimal** (idą do `program.nix` / innych modułów full):
- **ciężkie biblioteki natywne i naukowe** – np. OpenCV dla Pythona, PyTorch/TensorFlow, CUDA, duże buildy C++,
- pakiety z **overrides/overlays**, które zmieniają flagi budowania (np. OpenCV z GTK/CUDA) – to zmienia hash i Nix kompiluje wszystko od zera zamiast pobrać z cache,
- **kompilowany lokalnie kernel** (własny, patchowany, z override'em configu) i moduły kernela budowane lokalnie – kernel zen z cache jest OK (pkt 3),
- wszystko, co **już kiedyś wywaliło build** lub budowało się bardzo długo,
- pakiety ważące pojedyncze GB (IDE typu JetBrains, pełny TeX Live, gry, maszyny wirtualne itp.).
**Sprawdzian przed commitem zmian w minimal:** dry-build `configuration_minimal.nix` i przegląd listy „will be built”. Wszystko poza drobnymi derywacjami samej konfiguracji (etc, unity systemd, skrypty) musi być świadomie dopuszczone wg reguł powyżej. Jeśli na liście pojawia się coś ciężkiego → przenieść do modułu full albo usunąć override.
 
### Co MUSI działać w minimal
- **GUI** – lekkie środowisko (`desktopmanager.nix` / `tilemanager.nix`, jeśli nie wymagają ciężkiej kompilacji; inaczej lekki zamiennik).
- **Neovim** (`nvim.nix`) – przypięta wersja z `vendor/nvim`, instalowana z lokalnego cache bez kompilacji (pkt 7). Wyjątek od reguł kompilacji: jeśli lokalnego cache brak, nvim wolno zbudować ze źródeł z `vendor/nvim` nawet w minimal.
- **Przeglądarka** – binarka z cache (np. Firefox).
- **KeePassXC**.
- **Claude Code** (`claude` w terminalu) – zasada najważniejsza (pkt 16). Do tego przeglądarka z czatami AI jako zapas.
- Do tego niezbędne minimum:
  - sieć: NetworkManager (+ applet / nmtui), Wi-Fi, Bluetooth opcjonalnie
  - terminal, menedżer plików, git, curl/wget, unzip
  - dźwięk (PipeWire), regulacja jasności i głośności
  - zarządzanie energią laptopa, obsługa zawieszania
  - podstawowe fonty (bez ogromnych pakietów fontów)
  - klient ssh (tylko wychodzące, np. do git – serwer SSH wyłączony), openssl, statix i deadnix (do sprawdzania konfiguracji), podstawowy toolchain do pisania kodu (np. python3 bez ciężkich bibliotek natywnych)
Cel: móc przeglądać internet, pisać trochę kodu i normalnie pracować, **w czasie gdy w tle buduje się full**.
 
---
 
## 5. Profil `full` (`configuration.nix`)
 
- `full` = **pełna konfiguracja**: wszystko z minimal + moduły full (tu trafia OpenCV, ML, ciężkie toolchainy itd.).
- Na X250 kompiluje się ok. **4 h** i pobiera bardzo dużo danych – to akceptowalne.
- Full **zawsze buduje się z działającego, uruchomionego systemu** (minimal albo poprzedni full), nigdy jako pierwszy krok w chroot instalatora.
- Typowy scenariusz: postaw minimal → pracuj → w tle zbuduj full w trybie `boot` → restart do full. Jeśli build full padnie, minimal dalej działa i można spokojnie szukać przyczyny.
- Żeby build w tle nie zamulał pracy: kernel zen + uruchamianie buildu z niskim priorytetem (np. `nix.daemonCPUSchedPolicy = "idle";` / `nix.daemonIOSchedClass = "idle";` w `system.nix`).
### Turbo off przy budowaniu full – ThinkPad X250 i starsze (złota reguła 20)
**Pomiar (2026-11-10, X250, build full):** z turbo procesor trzymał 2,7 GHz przy **84–86°C** przez kilka godzin dziennie, wentylator już na ~5470 obr./min (praktycznie maksimum w trybie auto). Po wyłączeniu turbo temperatura **od razu spadła do ~76°C**. Koszt: build wolniejszy o ok. 10–15%.
 
- **Kiedy:** każdy build **full** na maszynie oznaczonej znacznikiem **`/etc/nixos/TURBO_OFF_BUILD`** (plik per maszyna, poza repo – jak `PROFILE`; bez flag, złota reguła 7). Znacznik ustawia instalator dla ThinkPada X250 i starszego sprzętu (np. procesory Intel 5. generacji / Broadwell i starsze), po potwierdzeniu użytkownika. Minimal tego nie potrzebuje (prawie nic nie kompiluje).
- **Jak (w `rebuild.sh`):**
  ```bash
  NO_TURBO=/sys/devices/system/cpu/intel_pstate/no_turbo
  if [ "$PROFILE" = full ] && [ -f /etc/nixos/TURBO_OFF_BUILD ] && [ -w "$NO_TURBO" ]; then
    OLD_TURBO=$(cat "$NO_TURBO")
    trap 'echo "$OLD_TURBO" > "$NO_TURBO"' EXIT INT TERM   # przywrócenie zawsze – także po błędzie / Ctrl+C
    echo 1 > "$NO_TURBO"                                   # turbo off na czas buildu
    echo "Turbo wyłączone na czas buildu full (X250 / starszy sprzęt)"
  fi
  ```
  - Przywracamy **poprzedni stan**, a nie „na sztywno włącz” – jeśli turbo było wyłączone ręcznie, zostaje wyłączone.
  - Brak `intel_pstate` (inny sterownik / procesor AMD) → skrypt tylko wypisuje informację i buduje dalej, nie blokuje buildu.
- Ustawienie działa tylko do restartu i nie zmienia konfiguracji systemu – to wyłącznie zachowanie skryptu.
- Ręcznie, doraźnie (np. build uruchomiony poza skryptem): `echo 1 | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo`, powrót: to samo z `0`.
- Uzupełniająco (z cache, bez kompilacji): `services.thermald.enable = true;` i `lm_sensors` (`sensors`) do podglądu temperatury.
- Progi orientacyjne dla X250: do ~85°C pod obciążeniem OK, 85–95°C dużo (nie godzinami), ~100–105°C throttling / granica procesora.
- **Sprzęt X250 (do sprawdzenia przy okazji):** przy PTM i maksymalnych obrotach 84–86°C to sporo – sprawdzić, czy PTM jest **jedną** warstwą i czy zdjęto obie folie ochronne, oraz wyczyścić wentylator i radiator.
---
 
## 6. Workflow wdrażania zmian (obowiązkowy)
 
Pracujemy **w folderze projektu (repo git)**, nie bezpośrednio w `/etc/nixos`.
Całość robi **jeden skrypt w repo (`rebuild.sh`)** – żeby nie trzeba było pamiętać żadnych flag ani ścieżek.
 
```
./rebuild.sh "opis zmiany"
 
1. Czyta /etc/nixos/PROFILE → wybiera configuration_minimal.nix albo configuration.nix
   (pokazuje na ekranie, który profil buduje)
2. Szybkie sprawdzenia (sekundy, zanim ruszy długi build) – błąd = stop:
     a) składnia każdego pliku .nix (nix-instantiate --parse)
     b) lintery: statix check (antywzorce), deadnix (martwy kod) – ostrzeżenia pokazuje, błędy blokują
     c) w branchu main brak szyfrowania dysku (złota reguła 10)
     d) serwer SSH wyłączony, firewall włączony, brak nowych otwartych portów bez zgody (pkt 8)
     e) dodane pakiety nie są na liście BROKEN.md (pkt 10)
     f) rozmiar repo ≤ 3 GB i rdzeń mieści się w limicie zipa (pkt 9)
     g) przypomnienie o zaległym sprawdzeniu aktualizacji nvim (tylko informacja)
3. Full + znacznik /etc/nixos/TURBO_OFF_BUILD → turbo off na czas buildu,
   przywracane zawsze po zakończeniu, także po błędzie (pkt 5)
4. Build w trybie boot z folderu projektu (ścieżkę do pliku wejściowego podaje skrypt, nie człowiek)
5. Brak błędów?
     TAK → git add -A && git commit -m "opis zmiany"
           → cp konfiguracji do /etc/nixos (bez ruszania hardware-configuration.nix, PROFILE i TURBO_OFF_BUILD)
           → komunikat: zrestartuj i sprawdź
     NIE → stop: NIC nie commituje i NIC nie kopiuje
```
 
- Przejście z minimal na full: `./rebuild.sh --full "przejście na full"` – jedyny przypadek zmiany profilu; skrypt zmienia `PROFILE` dopiero po udanym buildzie.
- Opcjonalnie przed buildem: dry-build – szybki test bez dotykania bootloadera i podgląd, co będzie kompilowane/pobierane.
- Jeżeli po restarcie coś nie działa → wybór poprzedniej generacji w menu GRUB-a, `git revert` i znowu `./rebuild.sh`.
- `/etc/nixos` ma zawsze odpowiadać **ostatniemu commitowi**, który się poprawnie zbudował.
- Ponieważ `/etc/nixos/configuration.nix` po skopiowaniu zawsze odpowiada profilowi z `PROFILE` (dla minimal skrypt ustawia tam wejście minimal), nawet ręczne `sudo nixos-rebuild boot` bez flag zbuduje właściwy profil, a nie przypadkiem full.
- **Użytkownik może używać `sudo nixos-rebuild switch` bezpośrednio według własnego uznania** – zakaz `switch` dotyczy wyłącznie agenta (Claude Code) i skryptu `rebuild.sh`.
---
 
## 7. Neovim – pierwszeństwo
 
Neovim to główne narzędzie pracy. **Konfiguracja nvim (init.lua, pluginy itd.) to osobny projekt** – ten projekt NixOS odpowiada za to, żeby **binarka nvim i jej zależności** zawsze działały, i chroni konfigurację nvim przed zepsuciem przez aktualizacje.
 
### Przypięta wersja nvim – na sztywno, niezależnie od internetu
- W `nvim.nix` wersja nvim jest **przypięta na sztywno** do ostatniej wersji, która działa **bez żadnych ostrzeżeń i błędów** z aktualną konfiguracją nvim. Aktualizacja nixpkgs **nie zmienia** wersji nvim.
- Przypięcie obowiązuje **nawet jeśli oznacza kompilację od zera**.
- **Wszystko, co potrzebne do zbudowania tej wersji, leży w projekcie** w `vendor/nvim/`, żeby dało się ją postawić bez internetu i nawet wtedy, gdy kiedyś serwery przestaną tę wersję udostępniać:
  - tarball źródeł nvim w przypiętej wersji (+ sumy kontrolne),
  - źródła zależności, których nie ma gwarancji w nixpkgs (np. konkretne wersje tree-sitter, luajit, libuv – jeśli nvim ich wymaga w konkretnej wersji),
  - **lokalny binary cache** z gotowym, zbudowanym nvim i całym jego domknięciem (`nix copy --to file://…/vendor/nvim/cache`) – dzięki temu normalnie nic się nie kompiluje, instalacja idzie z dysku.
  - `nvim.nix` buduje nvim ze `src = ./vendor/nvim/…` (nigdy z `fetchurl`/`fetchFromGitHub` w czasie budowania).
- Duże pliki w `vendor/nvim` trzymamy w git LFS albo w folderze projektu poza historią git – ważne, żeby były zawsze razem z projektem (kopia zapasowa razem z repo).
- Wersje pluginów i parserów tree-sitter są przypięte w projekcie konfiguracji nvim (lockfile) – zmiana wersji nvim w tym projekcie zawsze idzie w parze ze sprawdzeniem z tym lockfile'em.
### Pluginy (lazy.nvim) – pierwsze uruchomienie bez 5 restartów i bez internetu
Obecnie lazy.nvim pobiera wszystko z sieci i przy pierwszym uruchomieniu trzeba odpalić nvim ok. 5 razy, zanim wszystko się dociągnie. Cel: **na nowej maszynie nvim działa w pełni przy pierwszym uruchomieniu, także offline.**
 
- **`lazy-lock.json`** (w projekcie konfiguracji nvim) to przypięcie wersji pluginów – commitowany zawsze razem z działającą konfiguracją.
- **Snapshot danych nvim w projekcie:** `vendor/nvim/data/` zawiera archiwum katalogu `~/.local/share/nvim` (pluginy lazy, skompilowane parsery tree-sitter, narzędzia Mason itp.) zrobione **tylko wtedy, gdy nvim spełnia kryterium „nvim działa”**. Nazwa snapshotu zawiera wersję nvim i hash `lazy-lock.json`, żeby było wiadomo, do czego pasuje.
- **Instalator / `rebuild.sh`:** jeśli na maszynie brak `~/.local/share/nvim` (albo nie pasuje do aktualnego `lazy-lock.json`) → rozpakowuje pasujący snapshot. Zero pobierania, zero restartów.
- **Gdy snapshotu brak** (np. po zmianie pluginów) → skrypt sam robi bootstrap w trybie headless, zamiast ręcznego odpalania nvim 5 razy:
  1. `nvim --headless "+Lazy! restore" +qa` – instaluje pluginy dokładnie w wersjach z `lazy-lock.json`,
  2. instalacja parserów tree-sitter i narzędzi Mason w trybie headless (synchronicznie),
  3. powtarza kroki 1–2 (max kilka razy), aż kryterium „nvim działa” jest spełnione,
  4. robi nowy snapshot do `vendor/nvim/data/`.
- Uwaga NixOS: binarki pobierane przez Mason (LSP, formattery) często nie działają na NixOS (inne ścieżki bibliotek). Najpewniej, gdy LSP/formattery i kompilator do parserów tree-sitter (`gcc`) instaluje Nix w `nvim.nix`, a Mason ich nie pobiera – do decyzji w projekcie konfiguracji nvim.
- **Rollback nvim obejmuje też snapshot danych:** razem z konfiguracją i wersją nvim przywracany jest snapshot `~/.local/share/nvim` z punktu powrotu.
### Kryterium „nvim działa”
nvim uruchamia się z pełną konfiguracją **bez żadnego warningu ani erroru** – w tym ostrzeżeń o przestarzałych/niewspieranych funkcjach (deprecated). Sprawdzenie automatyczne, np.:
```
nvim --headless "+redir! > /tmp/nvim_msgs | silent messages | redir END" +qa 2>/tmp/nvim_err
```
Oba pliki muszą być puste. Do tego ręczne odpalenie nvim i rzut oka.
 
### Praca agenta nad nvim – limit 1 h i automatyczny rollback
Dotyczy zmian **wersji nvim, pakietów, pluginów i innych zależności** (aktualizacja nixpkgs, podbicie nvim, nowa wersja pluginu itd.):
 
1. **Przed rozpoczęciem pracy** agent zapisuje punkt powrotu: tag/commit w obu repo (ten projekt + konfiguracja nvim), np. `nvim-ok-<data>`, oraz **godzinę startu**.
2. Jeżeli update powoduje, że nvim wyświetla ostrzeżenie o niewspieranej/przestarzałej funkcji **i nie istnieje alternatywa** → natychmiastowy rollback, bez kombinowania.
3. Jeżeli **po ponad 1 h od rozpoczęcia pracy przez agenta** nvim nadal nie wstaje bez warningów/errorów → **rollback** konfiguracji nvim (i przypiętej wersji nvim w `nvim.nix`) do punktu sprzed pracy agenta.
4. Po rollbacku agent zapisuje krótką notatkę: co próbował, jaki był warning, dlaczego się nie udało – żeby następna próba nie zaczynała od zera.
5. Nowa wersja nvim zostaje przypięta i trafia do `vendor/nvim` **dopiero po spełnieniu kryterium „nvim działa”**.
### Regularne sprawdzanie aktualizacji (bezpieczeństwo)
Przypięcie wersji chroni przed zepsuciem nvim, ale **nie może oznaczać siedzenia na starej, dziurawej wersji** – dziś luki (także zero-day) są znajdowane szybko, również przez AI. Dlatego aktualizacje nvim i pluginów są sprawdzane regularnie:
 
- **Kiedy – powiadomienie, nie przerwanie pracy:**
  - Sprawdzanie aktualizacji **nigdy nie przerywa bieżącej pracy**. Ważniejsze zadanie zawsze idzie pierwsze.
  - Gdy agent pracuje na plikach projektu, zagląda do `vendor/nvim/UPDATES.md`; jeśli od ostatniego sprawdzenia minęło **ponad 7 dni**, tylko **zgłasza to jednym zdaniem** użytkownikowi i pracuje dalej. Samo sprawdzenie robi **po skończeniu bieżącego zadania** albo gdy użytkownik powie.
  - `rebuild.sh` przy każdym uruchomieniu też wypisuje jednolinijkowe przypomnienie, jeśli sprawdzenie jest zaległe (nie blokuje buildu).
- **Selekcja – aktualizujemy tylko to, co coś daje:**
  - **poprawka bezpieczeństwa** → zgłoszona od razu (bez przerywania pracy), wdrażana zaraz po bieżącym zadaniu,
  - **poprawka błędu, który nas dotyczy, albo przydatna nowa funkcja** → wdrażana przy najbliższej okazji,
  - **nic istotnego dla nas** (kosmetyka, zmiany niedotyczące używanych funkcji) → **pomijamy**, tylko wpis w `UPDATES.md` „sprawdzone, pominięte – brak korzyści”.
- **Co sprawdza:**
  - nowe wydania Neovima (stabilne) i czy zawierają poprawki bezpieczeństwa,
  - aktualizacje pluginów względem `lazy-lock.json` (np. `nvim --headless "+Lazy! check" +qa` / porównanie commitów),
  - znane luki/advisories dla nvim i używanych pluginów.
- **Procedura aktualizacji** (zawsze na kopii, z punktem powrotu):
  1. zapisz punkt powrotu (tagi w obu repo + snapshot danych nvim) i godzinę startu,
  2. podbij wersję nvim w `vendor/nvim` i/lub zaktualizuj pluginy (`Lazy! update` → nowy `lazy-lock.json`),
  3. przy aktualizacji pluginów rzuć okiem na zmiany (changelog / diff) – aktualizacja pluginu też może przynieść złośliwy kod, nie tylko poprawki,
  4. sprawdź kryterium „nvim działa” (bez warningów i errorów),
  5. **przechodzi** → przypnij nową wersję, zrób nowy snapshot do `vendor/nvim/data/`, commit, wpis w `UPDATES.md`,
  6. **nie przechodzi** → zasady limitu 1 h i rollbacku poniżej.
- **Poprawki bezpieczeństwa mają priorytet:** jeśli aktualizacja łata lukę, a nie da się jej wdrożyć (rollback), agent **wyraźnie informuje użytkownika**, której luki dotyczy i co blokuje aktualizację – nie zostawia tego po cichu.
- Każde sprawdzenie (także „brak aktualizacji”) jest wpisywane do `vendor/nvim/UPDATES.md`: data, wersje, wynik, ewentualne problemy.
- Ta sama zasada dotyczy reszty systemu: nixpkgs (w tym openssh, kernel, przeglądarka) aktualizujemy regularnie zwykłym workflow z pkt 6 – przypięta jest tylko wersja nvim.
### Wyjątek: rozbudowa i zmiany graficzne
- Limit 1 h i automatyczny rollback **nie dotyczą** prac nad rozbudową konfiguracji nvim, zmianami wyglądu itp., które **nie są związane z wersją nvim, pakietów czy innych zależności**.
- Ale zawsze, przy każdej pracy nad nvim, **użytkownik może powiedzieć „stop”** → agent przerywa i robi **rollback do ostatniej działającej wersji** (punktu zapisanego przed rozpoczęciem pracy).
---
 
## 8. Bezpieczeństwo: SSH wyłączone, firewall
 
W `modules/security.nix` (wspólne dla minimal i full):
```nix
services.openssh.enable = false;          # serwer SSH całkowicie wyłączony
 
networking.firewall = {
  enable = true;                          # firewall zawsze włączony
  allowedTCPPorts = [ ];                  # domyślnie nic nie wpuszczamy
  allowedUDPPorts = [ ];
  allowPing = false;                      # nie odpowiadamy na ping z zewnątrz
  logRefusedConnections = true;           # odrzucone połączenia w logach
};
```
- Ruch **wychodzący** działa normalnie (przeglądarka, git, aktualizacje), **przychodzący** jest blokowany – poza odpowiedziami na połączenia, które sami nawiązaliśmy.
- **Klient** ssh zostaje (np. `git` po SSH) – wyłączony jest tylko **serwer**.
- Otwarcie jakiegokolwiek portu albo włączenie usługi nasłuchującej z sieci: **tylko za zgodą użytkownika**, z komentarzem w kodzie, po co i od kiedy.
### Jak faktycznie używany jest sprzęt (stan na 2026-11-10)
- **SSH:** laptop łączy się **do** zdalnego serwera (ruch wychodzący) – firewall tego nie blokuje, serwer SSH na laptopie nie jest potrzebny.
- **Tailscale:** używany na urządzeniach łączących się z serwerem – musi działać przy włączonym firewallu.
- **Synchronizacja z telefonem i synchronizacja plików:** usługi, które przyjmują połączenia przychodzące – przy firewallu „nic nie wpuszczamy” przestaną działać, więc potrzebują **wyjątków**.
### Wyjątki w firewallu – do ustalenia po przejrzeniu aktualnego configu
- Konkretne wyjątki (porty, interfejsy, np. zaufany interfejs Tailscale) **nie są jeszcze wpisane**, bo zależą od tego, co jest w obecnej konfiguracji.
- **Gdy użytkownik przekaże aktualny config**, agent najpierw sprawdza, jakie usługi są włączone i czego potrzebują od sieci (Tailscale, synchronizacja z telefonem, synchronizacja plików i inne), a potem **pyta użytkownika o każdy wyjątek**, zanim cokolwiek doda.
- Zasada dla wyjątków: najwęższy możliwy – konkretny port i protokół, a gdzie się da, tylko w sieci lokalnej albo tylko przez interfejs Tailscale, nie na cały internet.
- `rebuild.sh` odmawia buildu, jeśli znajdzie `services.openssh.enable = true` albo wyłączony firewall.
---
 
## 9. Repo: rozmiar, pliki lokalne i zip dla kolegi
 
- **Wszystkie pliki lokalne (w tym `vendor/`) są w git.** Klon repo = komplet do postawienia minimal, także bez internetu.
- **Łączny rozmiar repo ≤ 3 GB** – liczony razem z historią `.git`. Uwaga: każda nowa wersja dużego pliku w `vendor/` zostaje w historii na zawsze, więc snapshoty nvim podmieniamy rzadko (tylko po udanej aktualizacji), a gdy limit się zbliża – agent proponuje użytkownikowi wyczyszczenie starych wersji z historii.
- `rebuild.sh` sprawdza rozmiar i ostrzega przy ~2,5 GB, a powyżej 3 GB blokuje commit.
- **Rdzeń vs. ciężkie pliki:**
  - **rdzeń** = wszystkie pliki tekstowe: `.nix`, skrypty (`auto.sh`, `rebuild.sh`, `make-zip.sh`), `MASTER.md`, `BROKEN.md`, lockfile – to jest konfiguracja,
  - **ciężkie** = `vendor/` (źródła i snapshoty nvim) – tylko przyspieszenie / tryb offline.
- **`make-zip.sh`** robi zip samego rdzenia (`git archive` z wykluczeniem `vendor/` przez `export-ignore` w `.gitattributes`). Zip rdzenia musi się mieścić w **limicie Discorda dla darmowego konta (20 MB)** – przy samych plikach tekstowych to w praktyce kilkaset KB.
- Całego repo z `vendor/` (do 3 GB) **nie da się wysłać przez Discord** – kolega dostaje zip rdzenia, a `auto.sh` bez `vendor/` po prostu pobiera wszystko z internetu.
- `auto.sh` musi działać w obu przypadkach: **z `vendor/`** (offline / szybko) i **bez `vendor/`** (z internetu).
---
 
## 10. `BROKEN.md` – lista rzeczy, które wywaliły build
 
- Plik w repo, w którym zapisujemy każdy pakiet / opcję / override, które **wywaliły build, budowały się absurdalnie długo albo zepsuły system**.
- Każdy wpis: **co** (pakiet/opcja), **kiedy** (data, wersja nixpkgs), **profil** (minimal/full), **objaw** (błąd, czas buildu), **przyczyna** (jeśli znana), **status** (zablokowane / obejście / rozwiązane) i **obejście**.
- **Przed dodaniem pakietu agent sprawdza `BROKEN.md`.** Pakiet ze statusem „zablokowane” nie wraca do konfiguracji, dopóki nie ma potwierdzonego rozwiązania – a w minimal nie wraca nigdy bez zgody użytkownika.
- Po każdym rollbacku (system albo nvim) agent dopisuje wpis do `BROKEN.md` – żeby ten sam błąd nie kosztował czasu drugi raz.
---
 
## 11. Wydajność – X250 jako sprzęt referencyjny
 
- **ThinkPad X250 to minimum, na którym full ma działać płynnie** – nie tylko się uruchamiać. Każda rozbudowa systemu jest oceniana pod kątem tego, jak działa na X250.
- Na mocniejszych maszynach może być ładniej, ale **nic nie może wymagać więcej, niż daje X250**, żeby w ogóle było używalne.
### Efekty graficzne – zawsze z wyłącznikiem
- Zaawansowane efekty (animacje, blur, cienie, przezroczystości, ciężkie motywy, animowane tapety itp.) są **dozwolone tylko z przełącznikiem**, który je wyłącza.
- Przełącznik najlepiej **w locie** – skrót klawiszowy / mały skrypt, który wyłącza efekty bez przebudowy systemu (przydatne np. w trakcie budowania full w tle).
- Domyślne ustawienie dla danej maszyny (efekty włączone / wyłączone) w lokalnym pliku obok `hardware-configuration.nix` (np. `/etc/nixos/local.nix`, poza repo) – bez flag i bez osobnych konfiguracji per maszyna (złota reguła 7).
- Wszystkie przełączniki opisane w jednym miejscu (komentarz w module + lista w `README`), żeby było wiadomo, co można wyłączyć.
### Jak pilnujemy wydajności
- **Punkt odniesienia:** po postawieniu full na X250 agent zapisuje w `PERF.md` podstawowe pomiary: zużycie RAM po zalogowaniu, obciążenie CPU w spoczynku, czas startu systemu (`systemd-analyze`), liczba usług działających w tle.
- **Przy każdej większej zmianie** (nowe środowisko graficzne, nowa usługa w tle, nowe efekty) agent porównuje z `PERF.md`. Jeśli jest wyraźnie gorzej → mówi o tym użytkownikowi i proponuje: przełącznik, lżejszy zamiennik albo rezygnację.
- Usługi w tle (indeksowanie plików, ciężkie demony, rzeczy startujące „na wszelki wypadek”) – tylko jeśli są faktycznie używane.
- Preferujemy lżejsze odpowiedniki, jeśli robią to samo (np. lekki terminal / menedżer plików zamiast ciężkich z całym środowiskiem).
- Responsywność wspierają już: kernel zen, zram i budowanie w tle z niskim priorytetem (pkt 3 i 5); temperaturę przy długich buildach – turbo off na X250 i starszych (pkt 5).
---
 
## 12. Quickshell – domyślne narzędzie do interfejsu
 
**Stan obecny:** Quickshell generuje pasek (w miejsce Waybara). Działa to dobrze: animacja zmiany tapety nie wymaga ponownego uruchamiania paska, a całość mniej obciąża system.
 
### Zasada
- **Nowe elementy interfejsu robimy w Quickshell, jeśli się da i ma to sens**: pasek, widgety, zmiana tapety i jej animacje, OSD (głośność, jasność), powiadomienia, launcher, ekran blokady/wylogowania, menu zasilania itp.
- Cel: **jeden lekki proces zamiast wielu osobnych demonów** – mniej RAM-u i CPU na X250, zmiany bez restartów (QML przeładowuje się w locie).
- „Ma sens” = Quickshell robi to co najmniej tak samo dobrze i nie jest cięższy. Jeśli dedykowany program jest wyraźnie lżejszy albo pewniejszy dla danej funkcji, zostaje dedykowany program – agent wtedy krótko uzasadnia wybór.
- Efekty i animacje w Quickshell podlegają zasadzie wydajności: **każdy cięższy efekt z wyłącznikiem** (pkt 11), najlepiej przełączanym w locie z poziomu samego Quickshell.
### Instalacja i stabilność – minimal bez kompilacji, full z kompilacją
- **Full:** Quickshell **kompilowany** – tak jak obecnie w repo (to jedna z głównych przyczyn, dla których full buduje się tak długo, i to jest akceptowane). Budowany bez flake'ów (złota reguła 7) i zawsze z działającego systemu, w tle (pkt 5).
- **Minimal:** Quickshell **bez kompilacji** – gotowy pakiet `quickshell` z nixpkgs (wydanie release, z cache), bez override'ów (override = kompilacja lokalna, pkt 4).
- **Zgodność konfiguracji:** wersja z nixpkgs w minimal może być starsza niż kompilowana w full. Pliki QML muszą działać na obu – albo konfiguracja minimal korzysta tylko z funkcji dostępnych w wersji z nixpkgs (np. osobny, prostszy plik wejściowy paska dla minimal). Agent sprawdza pasek w obu profilach.
- Jeśli wersji z nixpkgs w minimal nie da się sensownie użyć (brak w cache, za stara, nie mieści się w budżecie ~3 GB – ciągnie Qt 6, sprawdzić dry-buildem) → minimal dostaje najprostszy lekki pasek, a pełny Quickshell zostaje w full.
- Pliki QML (konfiguracja Quickshell) są w repo, w osobnym katalogu (np. `quickshell/`), z komentarzami, co który plik robi – jak moduły `.nix`.
- Quickshell jest jeszcze przed wersją 1.0 i miewa zmiany łamiące zgodność. Dlatego aktualizację Quickshell sprawdzamy jak nvim: punkt powrotu przed aktualizacją, pasek musi wstać bez błędów w logach, inaczej rollback i wpis w `BROKEN.md`.
---
 
## 13. Full – zawsze najnowsze wersje (poza nvim)
 
**Stan obecny:** w full są obejścia, które kompilują programy z **najnowszych źródeł z GitHuba**, bo ciągłe komunikaty „wersja nieaktualna” są irytujące. Włączone są funkcje eksperymentalne Nixa i tryb **impure** (pobieranie bez przypiętego hasha/commita).
 
### Zasada
- **Budowanie z git/GitHuba (najnowsze) tylko z uzasadnieniem.** Każdy taki pakiet musi mieć jeden z powodów:
  1. **wersja z nixpkgs realnie przeszkadza** – program wyłącza się / odmawia działania / ciągle krzyczy o aktualizację na nieaktualnej wersji (np. **Discord**, który aktualizuje się bardzo często),
  2. **pakietu nie ma w nixpkgs** w ogóle.
- **Bez takiego powodu – pakiet z nixpkgs (z cache).** Programy, którym starsza wersja nie przeszkadza (np. **pakiet biurowy / office**), nie są budowane z git.
- **Sprawdzenie przed dodaniem pakietu z git:** agent najpierw sprawdza, czy pakiet jest w nixpkgs i czy jego wersja wystarcza. Jeśli jest i działa – używamy nixpkgs. Nie chcemy sytuacji, że pakiet jest dostępny gotowy, a my kompilujemy go niepotrzebnie.
- **Kolejność wyboru źródła pakietu** (bierzemy pierwszą działającą opcję):
  1. **gotowy pakiet z nixpkgs** (z cache) – zawsze pierwszy wybór,
  2. **oficjalna binarka z GitHub Releases** (lub strony projektu) zapakowana w Nixa: pobranie gotowego pliku z przypiętym hashem + dopasowanie ścieżek bibliotek (`autoPatchelfHook`) – **zero kompilacji**,
  3. **kompilacja ze źródeł** – dopiero gdy 1 i 2 odpadają (brak binarki na Linuksa, binarka nie działa na NixOS, potrzebna funkcja tylko w kodzie z git), z uzasadnieniem.
- **Wydajność programu ≠ kompilacja lokalna.** Programy w Rust (np. **PhotoCraft**) wybieramy, bo działają wydajnie – ale gotowa binarka działa tak samo szybko jak skompilowana u nas (o ile nie kompilujemy pod konkretny procesor). Lokalna kompilacja Rusta to setki bibliotek (crate'ów) i dziesiątki minut na X250 na jeden program, bez zysku w działaniu.
- **Jeśli już kompilujemy – to z optymalizacją pod procesor danej maszyny.** Skoro i tak płacimy czasem kompilacji, niech program działa jak najszybciej (szczególnie programy liczące dużo, np. edycja obrazu w PhotoCraft).
  - Optymalizacja **tylko per pakiet**, tylko dla pakietów, które i tak kompilujemy ze źródeł (krok 3 powyżej):
    - Rust: `RUSTFLAGS = "-C target-cpu=<cpu>"`,
    - C/C++: `NIX_CFLAGS_COMPILE = "-march=<cpu> -mtune=<cpu>"`,
    - dodawane przez `overrideAttrs` w module full, z komentarzem.
  - **Zakaz globalnej optymalizacji** (`nixpkgs.hostPlatform.gcc.arch`, `-march` dla wszystkich pakietów, `nixpkgs.config` zmieniające kompilator): zmienia hash każdej paczki → cache przestaje pasować → **przebudowa całego systemu** od glibc w górę. Pakiety z nixpkgs i binarki z Releases zostają bez zmian (z cache).
  - **`<cpu>` ustawiany per maszyna w `/etc/nixos/local.nix`** (poza repo), np. `cpuTarget = "broadwell";` dla X250. Konkretna nazwa zamiast `native` – wiadomo, pod co zbudowano, a build nie zależy od tego, na czym akurat działa. Brak wpisu = brak optymalizacji (wersja ogólna).
  - **Nie przenosimy zoptymalizowanych binarek między maszynami** – zbudowane pod nowszy procesor mogą nie uruchomić się na starszym („illegal instruction”). Dlatego **wszystko w `vendor/` (nvim, snapshoty) jest budowane bez optymalizacji pod CPU**, żeby działało na każdej maszynie.
  - Minimal nie kompiluje, więc go to nie dotyczy (wyjątek: awaryjna kompilacja nvim z `vendor/` – też bez optymalizacji pod CPU).
- Binarki z Releases: tylko z oficjalnego źródła projektu, z przypiętym hashem (sha256), wersja zapisana w komentarzu; przy aktualizacji – nowa wersja, nowy hash, test uruchomienia.
- **Uzasadnienie w kodzie** – przy każdym pakiecie z git komentarz w stałym formacie:
  ```nix
  # GIT: discord – powód: nieaktualna wersja się wyłącza – dodano: RRRR-MM-DD
  ```
- **Przegląd przy aktualizacjach:** jeśli wersja w nixpkgs dogoniła potrzeby albo pakiet pojawił się w nixpkgs → wracamy do nixpkgs i usuwamy obejście (mniej kompilacji w full).
- **Jedyny wyjątek: nvim** – wersja przypięta na sztywno, z plikami w `vendor/nvim` (pkt 7). Obejścia „najnowsze z GitHuba” **nie mogą** dotykać nvim ani jego zależności.
- **Minimal nigdy nie używa tych obejść:** żadnego impure, żadnego pobierania najnowszych źródeł – tylko gotowe pakiety z cache (lub `vendor/`). Inaczej minimal przestałby działać offline i mógłby nagle zacząć kompilować (złote reguły 5 i 6).
- Obejścia „najnowsze z GitHuba” trzymamy **tylko w modułach full** (np. `program.nix` albo osobny `latest.nix`), z komentarzem przy każdym: co, skąd i dlaczego najnowsze.
- Ustawienia eksperymentalne/impure są **włączone świadomie** – nie wyłączamy ich bez zgody użytkownika.
### Co z tego wynika dla bezpieczeństwa systemu
- **Ten sam commit w repo może dać inny system** (bo „najnowsze” zmienia się z dnia na dzień). Dlatego:
  - powrót do działającego full robimy przede wszystkim **przez poprzednią generację w menu GRUB-a**, nie przez `git revert` (stare generacje zostają – złota reguła 3),
  - po udanym buildzie full `rebuild.sh` zapisuje do pliku (np. `LATEST-BUILT.md`) **commity/wersje, z których faktycznie zbudowano** pobierane na najnowsze programy – żeby w razie problemu dało się tymczasowo przypiąć ostatnią działającą wersję danego programu.
- Gdy najnowsza wersja programu nie buduje się albo psuje działanie → tymczasowe przypięcie ostatniej działającej wersji (z `LATEST-BUILT.md`) + wpis w `BROKEN.md`; przy następnej aktualizacji próbujemy znowu najnowszej.
- Najnowszy kod prosto z GitHuba to także ryzyko (błędy, w skrajnym przypadku złośliwa zmiana). Przy większych aktualizacjach agent rzuca okiem na zmiany w programach, które mają dostęp do sieci lub danych (jak przy pluginach nvim, pkt 7).
---
 
## 14. ROS – zmiany bardzo delikatne
 
**Stan:** ROS jest planowany. To duży skok, a działać ma na **jednym PC** – dlatego obowiązują tu najostrzejsze zasady w całym projekcie.
 
### Izolacja – ROS nie może ruszyć reszty systemu
- ROS **tylko w full**, nigdy w minimal.
- ROS **tylko na maszynie, która go potrzebuje**: włączany przełącznikiem w lokalnym pliku `/etc/nixos/local.nix` (poza repo, domyślnie wyłączony). Na pozostałych maszynach ten sam config po prostu go nie buduje – bez flag i bez osobnych konfiguracji (złota reguła 7).
- Wszystko, co dotyczy ROS, w osobnym miejscu: moduł `modules/ros.nix` (rzeczy systemowe: reguły udev, grupy, wyjątki w firewallu) + katalog `ros/` (środowisko pracy, np. `shell.nix` z paczkami ROS).
- **Preferowane: ROS w osobnym środowisku (`nix-shell` w `ros/`), a nie w pakietach całego systemu.** Wtedy problem z ROS psuje tylko środowisko ROS, a nie system i nie bootowanie.
- Paczki ROS z projektu **nix-ros-overlay** i jego **binary cache (ros.cachix.org)** – inaczej ROS kompiluje się godzinami. Uwaga: overlay wymaga zgodnej wersji nixpkgs (tej, której używa), inaczej cache nie trafia i wszystko się kompiluje. Dlatego nixpkgs dla ROS jest **przypięty do wersji z overlaya i trzymany tylko w środowisku ROS** – nie miesza się z nixpkgs systemu ani z obejściami „najnowsze z GitHuba” (pkt 13).
- Bez flake'ów: overlay da się użyć bez flake'ów (import / `fetchTarball` z przypiętym commitem i hashem).
- ROS (DDS) używa sieci (multicast, porty UDP) – potrzebne wyjątki w firewallu ustalamy **z użytkownikiem**, najwęższe możliwe, najlepiej tylko w sieci lokalnej (pkt 8).
### Osobne commity
- **Zmiany ROS zawsze w osobnych commitach** – commit z ROS nie zawiera nic poza ROS, a commit z innymi zmianami nie zawiera nic z ROS.
- Wiadomość commita zaczyna się od `ros:` (np. `ros: dodanie rviz2`) – łatwo znaleźć i cofnąć jednym `git revert`.
- Jedna zmiana ROS = jeden commit (żadnego „przy okazji”).
### Dodatkowa weryfikacja (ponad zwykły workflow z pkt 6)
Przed commitem zmiany ROS agent wykonuje i pokazuje użytkownikowi wyniki:
1. **dry-build** – co zostanie pobrane, a co **kompilowane** (lista „will be built”); jeśli kompiluje się coś dużego, bo cache nie trafia → stop i wyjaśnienie,
2. **sprawdzenie, że reszta systemu się nie zmieniła** – porównanie nowego systemu z obecnym (`nix store diff-closures`): poza ROS nic nie powinno się zmienić (zwłaszcza kernel, GRUB, nvim, Quickshell),
3. build w trybie `boot` (jak zawsze),
4. **test ROS po restarcie** – podstawowy test (np. demo talker/listener) + sprawdzenie, że reszta systemu działa jak przed zmianą (nvim, pasek, sieć, Tailscale),
5. **commit dopiero po potwierdzeniu użytkownika.**
- Przy problemach z ROS: rollback (poprzednia generacja w GRUB / `git revert` commita `ros:`) + wpis w `BROKEN.md`.
- Użytkownik w każdej chwili może powiedzieć **„stop”** → agent przerywa i cofa zmiany ROS do ostatniej działającej wersji.
---
 
## 15. Wspierana wersja NixOS
 
**Stan na 2026-11-10:** system jest na **NixOS 25.11**, która **od 2026-06-30 nie dostaje aktualizacji bezpieczeństwa**. Migracja jest **do zrobienia**: na 26.05 (wsparcie do 2026-12-31) albo od razu na 26.11 (spodziewana pod koniec listopada 2026) – decyzja użytkownika.
 
### Zasada
- System (kanał nixpkgs) jest **zawsze na wersji stabilnej, która jeszcze dostaje łatki bezpieczeństwa**.
- Cykl NixOS: nowe wersje w **maju** i **listopadzie**; każda jest wspierana ok. **7 miesięcy**, a po wyjściu nowej stara ma jeszcze **ok. miesiąca** wsparcia. To jest okno na migrację.
- **Pilnowanie:** przy regularnym sprawdzaniu aktualizacji (pkt 7 – raz na 7 dni, jako powiadomienie, bez przerywania pracy) agent sprawdza też, czy obecna wersja NixOS jest wspierana i kiedy kończy się jej wsparcie. Gdy wyszła nowa wersja albo do końca wsparcia zostało mniej niż miesiąc → zgłasza to użytkownikowi.
- `rebuild.sh` wypisuje ostrzeżenie (bez blokowania buildu), jeśli wersja systemu jest po końcu wsparcia.
- **Bez `system.autoUpgrade`** – migracja zawsze świadomie, wg procedury poniżej.
### Procedura migracji na nową wersję
1. Przeczytać **release notes** nowej wersji (zmiany łamiące zgodność, usunięte opcje) – agent streszcza, co dotyczy tego configu.
2. Punkt powrotu: tag w git (np. `przed-26.05`); stare generacje zostają w GRUB-ie.
3. Zmiana kanału: `sudo nix-channel --add https://nixos.org/channels/nixos-<wersja> nixos` + `sudo nix-channel --update`.
4. **`system.stateVersion` NIE zmieniamy** – ono oznacza wersję, na której system był pierwotnie instalowany, a nie aktualną wersję. Zmiana może zepsuć dane usług.
5. Najpierw **minimal**: dry-build (lista „will be built” – po migracji wszystko powinno iść z cache), build w trybie `boot`, restart, test.
6. Potem **full**, tym samym trybem.
7. **Przegląd obejść „najnowsze z GitHuba”** (pkt 13): na nowej wersji część może być zbędna – wracamy do nixpkgs, gdzie się da (mniej kompilacji).
8. Sprawdzenie nvim (przypięty – musi działać bez zmian, pkt 7), Quickshell w obu profilach (pkt 12), wydajność względem `PERF.md` (pkt 11).
9. Migracja w **osobnym commicie** z wiadomością `release: <stara> -> <nowa>`; problemy → rollback + wpis w `BROKEN.md`.
---
 
## 16. Claude Code i czaty AI – zawsze dostępne (zasada najważniejsza)
 
Gdy system się sypie, pomoc AI (Claude Code w terminalu, czaty w przeglądarce) często ratuje sytuację. Dlatego **dostęp do AI ma pierwszeństwo przed wszystkim innym w minimal**.
 
### W minimal
- **Claude Code** zainstalowany w minimal, z nixpkgs: pakiet `claude-code-bin` (gotowa binarka) albo `claude-code`. To pakiet **unfree** – zezwalamy tylko na niego (nie na wszystko):
  ```nix
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [ "claude-code" "claude-code-bin" ];  # + inne świadomie dopuszczone
  ```
- To tylko pobranie gotowego programu – **bez kompilacji**, mieści się w zasadach minimal (pkt 4).
- **Zapas:** przeglądarka (już w minimal) z czatami AI – działa nawet wtedy, gdy Claude Code z jakiegoś powodu nie wstanie.
- Wymaga internetu i zalogowania – offline AI nie pomoże, więc sieć (NetworkManager, Wi-Fi) też jest w minimal priorytetem.
- Po postawieniu minimal sprawdzamy: `claude` uruchamia się i odpowiada, przeglądarka otwiera czat.
### W full
- Claude Code może być w najnowszej wersji (aktualizuje się bardzo często, a wersja z nixpkgs bywa w tyle) – wg kolejności z pkt 13: nixpkgs → oficjalna binarka → nic więcej. Uzasadnienie w komentarzu jak przy Discordzie.
### Gdy system nie wstaje (chroot / live USB)
- Claude Code da się odpalić tymczasowo, bez instalowania w systemie:
  ```
  NIXPKGS_ALLOW_UNFREE=1 nix-shell -p claude-code-bin
  claude
  ```
- **Uwaga (2026-11-10):** jeśli `NIX_PATH` wskazuje `nixpkgs=flake:nixpkgs`, a flake'i są wyłączone, `nix-shell -p` kończy się błędem „experimental Nix feature 'flakes' is disabled”. Doraźnie: `NIXPKGS_ALLOW_UNFREE=1 nix-shell --extra-experimental-features flakes -p claude-code-bin`. Na stałe: klasyczny kanał `nixos` + `nix.nixPath` wskazujący kanał (bez flake'ów, złota reguła 7), a Claude Code zainstalowany w minimal – wtedy `nix-shell` niepotrzebny.
- Uruchomiony **w folderze repo** od razu widzi zasady projektu (patrz niżej).
### `CLAUDE.md` w repo
- W głównym folderze repo leży `CLAUDE.md` – Claude Code czyta go automatycznie przy starcie w tym folderze.
- Zawartość: krótko – „przeczytaj i stosuj `MASTER.md`; najważniejsze: tryb `boot`, nie wyłączać Claude Code z minimal, nie ruszać partycji Windowsa, nvim przypięty, ROS osobne commity”. Szczegóły zawsze w `MASTER.md` (jedno źródło prawdy).
- `MASTER.md` i `BROKEN.md` leżą **w repo** (kopie z projektu claude.ai, aktualizowane razem) – Claude Code w terminalu nie widzi dokumentów ani pamięci projektu z claude.ai, widzi tylko pliki na dysku. W `CLAUDE.md` można je dołączyć importem `@MASTER.md` i `@BROKEN.md`, żeby były wczytywane automatycznie.
- Dzięki temu każdy agent pracujący na repo – także w awaryjnej sytuacji z chroot – działa wg tych samych zasad.
---
 
## 17. TODO – jak wprowadzamy zadania
 
Wszystkie zadania są w `TODO.md`. Nic nie jest wprowadzane prosto z listy – każde zadanie przechodzi tę ścieżkę:
 
1. **Przepisanie.** Zadanie zostaje rozpisane na konkretne podpunkty, z których każdy da się sprawdzić (co dokładnie się zmienia, w którym pliku, jak sprawdzić, że działa).
2. **Sprawdzenie zgodności z `MASTER.md`.** Każdy podpunkt jest porównany z zasadami (minimal bez ciężkiej kompilacji, tryb `boot`, nvim przypięty, Claude Code w minimal, partycje Windowsa nietykalne, ROS osobno, firewall itd.). Konflikt z zasadą → podpunkt jest zmieniany albo pytamy użytkownika; nigdy nie wprowadzamy niczego sprzecznego z MASTER po cichu.
3. **Priorytet.** Każdy podpunkt dostaje priorytet:
   - **P0** – bezpieczeństwo, system nie wstaje, AI niedostępne w minimal,
   - **P1** – rzeczy, które blokują inne zadania albo kosztują dużo czasu (np. niepotrzebna rekompilacja),
   - **P2** – usprawnienia,
   - **P3** – na kiedyś.
   Kolejność **zatwierdza użytkownik** przed rozpoczęciem wprowadzania.
4. **Wprowadzanie po kolei.** Jeden podpunkt naraz, w kolejności priorytetów. Każdy podpunkt przechodzi zwykły workflow (pkt 6: sprawdzenia, build `boot`, test) i kończy się **osobnym commitem** z identyfikatorem zadania w wiadomości (np. `T3.2: firewall – wyjątek dla Tailscale`). Żadnego łączenia kilku podpunktów w jeden commit (zmiany ROS – dodatkowo wg pkt 14).
5. **Zapis postępu po każdym podpunkcie** w `TODO.md`: status (`do przepisania` / `gotowe do zrobienia` / `w trakcie` / `zrobione` / `wstrzymane`), commit, krótka notatka. Przy przerwaniu pracy – w sekcji „Gdzie skończyliśmy” jedno-dwa zdania: co ostatnio zrobione, co dalej, czy coś jest w połowie.
6. Na start każdej sesji agent czyta `MASTER.md`, potem `TODO.md` (sekcja „Gdzie skończyliśmy”) i `BROKEN.md` – i dopiero wtedy pracuje dalej.

