PRZYSTOSOWAĆ REPO DO ZASAD MASTER


Dodać skrót do helpa np super + h i tam jest cała dokumentacja klawiszologi dodatkowo coś podobnego dodać do nvim 


skrypt ustawiń skrypt do szybkiej zmiany ustawień w terminalu polecenie setn które uruchamia program który pozwala na szybką zmiane wizualnych ustawień typu wielkość cionki kolorki w terminalu
do tego ten skrypt ma mieć liste programów w fajnej kolejności które trzeba postinstall ustawiać czyli ustaw syntching, połącz tailscale,dodaj klusz ssh git, i inne programy które wymagają wiecej konfiguracji w tej konfiguracji najlepiej jakby miało link do programu i strony która mówi jak to ustawić

dysk sda5 jest ntfs i jest wspólnym magazynem na dane dla windows i linux na dual boot oraz dlatego że dość często wywalam system i mam na nim dane by ich nie utracić 
sprawdz czy istnieje lepszy sposób na montowanie go i by w terminalu foldere z tego dysku nie miały zielonej obramówki która utrudnia odczytanie i sugeruje że dane są tylko do odczytu
Dodać auto montowanie dysków po wykryciu dyski które są włożone automatycznie montują się w /mnt/{nazwa partycji} jest komunikat po montowaniu sukces bądz faill

przeniesienie konfiguracji do /etc/nixos/ 

ustawienia nvim ma pokazywać do 5 lini od kórsoraz zależnie od pozycji czyli 5 ,4 ,3 ,2 ,1 ,{numer lini} ,1 ,2 ,3 ,4 ,5 oraz główny nr lini w innych pozycjach 

nvim upewnić się że wszystko działa w konfiguracji oraz jeżeli programuje z venv w głównym folderze otwartym to wspomagacze do pisania kodu mają bibloteki z venv załadowane (pisze venv ale nie musi być to w taki folderze np dla python może to być .v .venv venv v dla innych jezyków mogą być to inne foldery które przyjeły się jako standardowe)

dodać do nvim samouczek skrótów dostępnych 

dodać skróty na otwarcie/zamknięcie buffora na tab na wychodzenie z terminala lepsze tak by jedną kombinacją wychodzić albo by terminal nie blokował skrótów przejścia do innego bufora taba 


synchronizacja schowka tak by y i p działało z linuxem bez specialnej kombinacji oraz by działało w nvim super + v które wkleja z histori 

dodać skrót na zwiekszenie / zminiejszenie cionki w terminalu i w nvim to samo !!

w nvim po zapisaniu ma auto formatować kod

obsługa prawie wszystkich popularnych formatów plików i programów kodów w nvim

obsługa pełna texlive i skróty typu tex który kompiluje znaleziony plik .tex do pdf bez śmiecenia 
usuwa pliki pomocnicze do generowania korzystam z minted wiec odpowiednie flagi mają być do kompilacji 

dodać wiekszość narzędzi do sprawdzania sieci do benchmark wszystkiego co się da dns dhcp nmap skanowania sieci podatności analizy ruchu tak bym mógł stwierdzić dlaczego pobiera mi z prędkością 150kb/s i wiedział czego to wina 


program do łatwego ograniczania prędkości internetu absolutnej i relatywnej np 150 KB dla discord i 0.8 / 80% dla brave całego dostępnego do tego coś typu piorytet dostępu 


programy do sprawdzania stunu dysku /dysków ssd hdd sd 

środowiska do programowania stm esp nrf arduino i innych kontrolerów 


w nvim odpowiedni skrót klawiszowy do odpalania make build/ make debug i wywołanie debaggera wraz z przykładem 
dodaj do tego pythona  jave rust go lua 

w nvim dodaj na auto start tab 0 w którym mam pliki projektu otwarte dane pracuje tab 1 w którym jest terminal oraz termianl z claude oraz w tab 3 obsługa git nie wiem jakiś program plugin do łatwego zarządzania github 

dodaj animacje pisania np podczas pisania okienko aktualnie wybrane reaguje zmienia delikatnie kolorek do odwrotnego kolorku z motywu do tego im szybciej piszesz tym bardziej zmienia kolor pełna zmiana przy około 90 wpm efekty delikatny od 1 wpm 

spróbuj dodać jakieś wsparcie do programów z win interesuje mnie cpdev twincad 3 codesys 3 jak nie opłaca się działać pomiń bo jesteś na x250 i wirtualizacja zawasowane sterowniki z tych programów to zabujczy element 

skruty klawiszowy na wyłączenie ekranu , i zablokowanie klawiatury dopuki go nie odklikne często czyszcze środkiem i nie chce by coś zostało wciśnięte przełączone 


status z syntching w barze dodaj mi stan syntching np przez 1 min ilość połączeń przez następne 1 min stan synchronizacji 

w brave zmniejsz krok przewijania w pgup pgdown bo nie mam scrrol i z tego korzystam ale za dużo scroluje na raz na razie ustaw 0.5 tego co jest bez żadnych ustawień 

spróbuj dać drugi klawisz super np altGR+Ctrl też ma działać jak super wykorzystał bym to w niektórych skrutach by szybciej pisać dwoma rekami

Dodanie statusu telefonu mam grafeneOS i chce mieć status telefonu planuje połączenie poprzez tailscale i na stałym adresie ip byłby telefon i teraz na telefonie jakieś wysyłanie danych aplikacja gotowa do połączenia 
chce móc szybko przełączyć słuchawki bt z telefonu na pc i w drugą stronę oba urządzenia mają bt włączone i skonfigurowane połączenie i w trakcie przełączenia urządzenie dostaje komunikat by się rozłączyło a wtedy słuchawiki z automatu połączyły by się  z drugim urządzeniem robiąc przełączenie 


jdownloader dodaj na auto start oraz dodaj możliwość szybkiego przełączenia zbierania linków w tym progranie dodaj tagże obsługę torentów 
auto instalowanie dodatków do brave na pewno od  keepass najlepiej w osobnym pliku

aplikacja kalendarza i auto uzupełnianie co godzine do tego synchronizacja z telefonem 
mam na stronie  https://pei.prz.edu.pl/as/Zima2026_groups_days_horizontal.html moja grupa to A3S i A3S-L3  na ten rok w skrypcie konfiguracji dodaj szybką opcje wyłączenia zmiany grupy 

wsparcie z sterownikami hp laserjet M175n drukarka przewodowa 

w brave wyłącz proponowanie zapisania chasła 

dodaj zakładki do brave automatycznie w folderze local w którym są wszystkie strony lokalne z tej konfiguracji 
w brave domyślna strona główna powinła proponować ostatnio odwiedzane strony poniżej pasek wyszukiwania i statyczna grafika niezmieniająca się na samym dole mogą być staty 
tak jak jest teraz ujdzie 
Wyłącz AI w brave ile się da wyszukiwanie w google też wyłącz ale za to dodaj bookmarki w folderze AI do stron z chatami z gpt, gemini,lechat claude i innymi które mają darmowy dostęp 
dodaj też folder google gdzie mam skruty do doogle drive do poczty oraz mam link do mega.nz.
W brave wyłącz autouzupełnianie bez tab bo jak piszę i proponije mi link to po pisaniu i wciśnięciu enter zamiast szukać otwiera link a że mam podobne linki do żeczy które szukam albo chce wejść na strone domyślną np olx.pl ale przekierowóje mnie od razu do jakiegoś uzupełnienia get i wyszukiwania chce bym musiał wcisnąć tab by uzupełniało linki
Włącz tryb jak najmniejszej telemetri w przeglondarce tak by mnie tyle nie śledzili nie wysyłaj danych opcionalnych i tak dalej w brave  ale nie wpływaj na sesie by mnie nie wylogowywało po uruchomieniu ponownie 


Dodaj mega nz menager do nixos

keepassXC ma zawsze być odpalony na 9 workspace nawet jak go zamkne to ma zostać automatycznie uruchomiony i przeniesiony na workspace 9

chce mieć możliwość super + tab i zmiane okienka np jestem na workspace 3 klikam super tab odpala się menu takie jak w windows gdzie mam programy z wszystkich workspace i mogę wybierać klawiszami h j k l oraz potwierdzić wybór enter wtedy przechodzi mi na workspace na którym jest aplikacja oraz pełen ekran na nią 

dodaj polecenie w teminalu agent.md który zwraca ustawienia dostępne programy i przydatne informacje dla agenta AI który pracuje nad projektem np w python i ma za zadanie wygenerować sprawozdanie z wykonanego programu i by ten agent po poproszeniu o wykonanie tej komendy dostał informacje o tym jak ustawione jest textlive oraz python jakie narzędzia w terminalu ma dostępne


dodać ./autoinstall.sh skrypt który autogeneruje ustawienia hardware-configuration a potem instaluje wszystkie te ustawienia  za pierwszym razem  tak by nowa maszyna szybciej była wdrożona !! uwaga musiałem włączyć wiele ustawień typu experymentalne żródła impure za dużo plików i zwiększyłem limit i spędziłem pół dnia na ustawieniach 

python usunąć komplentnie bibloteki które się długo kompilują i mają czesto problemy z kompilacją globalną typu opencv tak by uniknąć błędów kompilacji zależności od pythona do tego upewnić się że inne pakiety nie robią takich problemów że po 30 min kompilacji error na x% i instalacja systemu zablokowana a ja nadal tkwie na niepełnym systemie bez grub i tak dalej najwyżej dodaj w tym skrypcie wybór czy ładować całą konfiguracje czy mniejszą tak by system był urzywalny po pierwszej instalacji a potem jak sytem wstanie można było dokończyć pełną instalacje 


przygotuj kilka dotowych ustawień do wyboru typu minimal , medum ,full gdzie włączasz/ wyłączasz efekty wizualne animacje tak że jak mam dwa urządzenia thinkpax x250 który nie jest silny i mam pc serwerowy z rtx to mógł szybko przełączać efekty najlepiej w programie od ustawień


