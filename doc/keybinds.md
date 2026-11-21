# Skróty klawiszowe Mango

Aktywna konfiguracja jest w [`dotfiles/mango/config.conf`](../dotfiles/mango/config.conf)
i jest dowiązana do `~/.config/mango/config.conf`. `SUPER` oznacza klawisz
Windows. Tabela podsumowuje skróty; konfiguracja Mango pozostaje źródłem prawdy.

## Aplikacje i pulpit

| Skrót | Działanie |
|---|---|
| `SUPER+Return` | Alacritty |
| `SUPER+W` | Alacritty |
| `SUPER+E` | Thunar |
| `SUPER+X` | Brave |
| `ALT+Space` | menu aplikacji rofi |
| `SUPER+Q` / `ALT+F4` | zamknij okno |
| `SUPER+T` | przełącz okno pływające |
| `SUPER+F` | pełny ekran |
| `SUPER+Escape` | wlogout: blokada, wylogowanie lub zasilanie |
| `SUPER+M` | zablokuj ekran przez hyprlock |
| `SUPER+Tab` | przełącznik okien rofi ze wszystkich tagów |
| `SUPER+R` | przeładuj konfigurację Mango |

## Okna i tagi

| Skrót | Działanie |
|---|---|
| `SUPER+J/L/I/K` | fokus: lewo/prawo/góra/dół |
| `SUPER+SHIFT+J/L/I/K` | przenieś okno w kierunku |
| `SUPER+CTRL+J/L/I/K` | zmień rozmiar okna |
| `SUPER+1…9`, `SUPER+0` | przejdź do tagu 1–10 |
| `SUPER+SHIFT+1…9`, `SUPER+SHIFT+0` | przenieś okno do tagu 1–10 |
| `SUPER+A` / `SUPER+S` | poprzedni / następny tag |
| `SUPER+LPM` / `SUPER+PPM` | przeciągnij / zmień rozmiar okna |
| gest trzema palcami lewo/prawo | fokus sąsiedniego okna |
| gest trzema palcami góra/dół | overview włącz/wyłącz |

## Narzędzia

| Skrót | Działanie |
|---|---|
| `SUPER+D` | podpowiedzi klikalnych elementów AT-SPI i paska |
| `SUPER+CTRL+D` | podpowiedzi live, które odświeżają się na bieżąco |
| `SUPER+ALT+D` | licznik czasu i liczby pól podpowiedzi |
| litery/cyfry w trybie podpowiedzi | wybór etykiety i akcji myszy |
| `Escape` w trybie podpowiedzi | zakończ tryb i puść przycisk myszy |
| `SUPER+V` | historia schowka |
| `SUPER+SHIFT+S` | zrzut zaznaczenia do schowka |
| `SUPER+SHIFT+A` | zrzut zaznaczenia z adnotacjami w satty |
| `SUPER+F5` | start/stop nagrywania ekranu |
| `SUPER+F6` | zmień motyw efektów cząsteczkowych |
| `SUPER+F7` | przełącz zestaw słuchawkowy BT PC/telefon |
| `SUPER+F8` | szybki toggle efektów |
| `SUPER+F9` | wyłącz ekran; ruch myszy/klawisz go włączy |
| `SUPER+F10` | zmień tapetę |
| `SUPER+F11` | pokaż/ukryj pasek Quickshell |
| `SUPER+F12` | włącz/wyłącz muzykę w tle |
| `SUPER+Insert` | następny utwór |
| `SUPER+H` | nakładka skrótów |
| `XF86Audio*` | głośność i wyciszenie przez `wpctl` |
| `XF86MonBrightnessUp/Down` | jasność przez `brightnessctl` |

## Podpowiedzi klawiaturowe

Gdy widoczne są podpowiedzi, wpisz etykietę złożoną z liter. Cyfra przed
etykietą zmienia akcję myszy: `1` przesuń kursor, `2` prawy przycisk, `3`
środkowy, `4` podwójne kliknięcie, `5` naciśnij i trzymaj, `6` puść.
Backspace cofa znak. `SUPER+C` puszcza trzymany przycisk i wraca do domyślnego
trybu klawiszy.

`G` / `Shift+G` w trybie kursora obsługuje etykiety wl-kbptr. Konfigurację i
zachowanie trybu wskazują `keyboard-mouse.nix` oraz `dotfiles/mango/config.conf`.
