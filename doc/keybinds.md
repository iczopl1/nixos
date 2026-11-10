# Skróty klawiszowe

Skróty pulpitu definiuje Mango w `~/.config/mango/config.conf`. Ten plik **nie jest** generowany przez NixOS –
repo dostarcza tylko fragmenty do wklejenia:

- `mango-hintd.conf` – podpowiedzi SUPER+D (z nixos-selected),
- `mango-autostart.conf` – tapety, muzyka, historia schowka, blokada ekranu (przeniesione z Hyprlanda).

Sprawdzenie składni po edycji: `mango -c ~/.config/mango/config.conf -p`.
`SUPER` = klawisz Windows.

## Aktywne skróty (z fragmentów w repo)

### Podpowiedzi / klikanie z klawiatury (`mango-hintd.conf`)

| Skrót | Działanie |
|---|---|
| `SUPER+D` | pokaż podpowiedzi (etykiety na klikalnych elementach okien i paska) |
| `SUPER+CTRL+D` | tryb „live”: podpowiedzi odświeżają się na bieżąco, mysz działa normalnie |
| `SUPER+ALT+D` | pokaż/ukryj licznik czasu („N ms · M boxes”) w rogu nakładki |

Gdy podpowiedzi są widoczne (tryb klawiszy `hintkeys`):

| Klawisz | Działanie |
|---|---|
| `a c d e f g q r s t v w x z` | litery etykiet – wpisz etykietę, żeby kliknąć |
| cyfra **przed** etykietą | wybór akcji: `1` tylko przesuń kursor, `2` prawy przycisk, `3` środkowy, `4` podwójne kliknięcie, `5` naciśnij i trzymaj (przeciąganie), `6` upuść |
| bez cyfry | zwykłe lewe kliknięcie |
| `BackSpace` | cofnij ostatnią literę |
| `Escape` | zamknij podpowiedzi |
| `F1` | (tylko live) pauza – wszystkie klawisze idą do aplikacji; `F1` lub `Escape` wznawia |

W trybie kursora (cursor key_mode) `Escape` lub `SUPER+C` puszcza trzymany przycisk i wraca do trybu domyślnego.

### Tapety, muzyka, schowek, blokada (`mango-autostart.conf`)

| Skrót | Działanie |
|---|---|
| `SUPER+V` | historia schowka (cliphist + rofi) – wybrane trafia do schowka; w nvim wklejasz `p` |
| `SUPER+F10` | losowa nowa tapeta (z `dotfiles/wallpapers/`) |
| `SUPER+F12` | włącz / wyłącz muzykę w tle (ręczne nadpisanie trybu zasilania) |
| `SUPER+Insert` | następny utwór |
| `SUPER+M` | blokada ekranu (hyprlock) – na każdy wpisany znak pojawia się kropka |

## Skróty zależne od twojego `config.conf` (nie ma ich w repo)

`keyboard-mouse.nix` zakłada też skróty, których definicji nie ma w repo:

| Skrót | Program | Uwagi |
|---|---|---|
| `G` / `SHIFT+G` (w trybie kursora) | `wl-kbptr` | etykiety w stylu Vimium; cyfra 1/2/3/4 przed etykietą wybiera przycisk; ustawienia `detect_*` i `label_font_family` w `~/.config/wl-kbptr/config` |
| tryb kursora (submapa) | `ydotool` | przesuwanie / przeciąganie / przewijanie kursorem z klawiatury |

## Klawisze multimedialne

W Hyprlandzie działały przez `wpctl`/`brightnessctl`. W Mango trzeba je dodać ręcznie, np.:

```
bind=NONE,XF86AudioRaiseVolume,spawn,wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+
bind=NONE,XF86AudioLowerVolume,spawn,wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
bind=NONE,XF86AudioMute,spawn,wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
bind=NONE,XF86AudioMicMute,spawn,wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle
bind=NONE,XF86MonBrightnessUp,spawn,brightnessctl -e3 -n0 set 10%+
bind=NONE,XF86MonBrightnessDown,spawn,brightnessctl -e3 -n0 set 10%-
```

## Stare skróty z Hyprlanda (NIEAKTYWNE – do przeniesienia)

Dla wygody: lista z `nixos/dotfiles/hypr/keybinds.conf`. W Mango jeszcze ich nie ma.

### Aplikacje

| Skrót | Działanie | Komenda |
|---|---|---|
| `SUPER+Q` | zamknij okno | – |
| `SUPER+W` | terminal | `alacritty` |
| `SUPER+E` | menedżer plików | `thunar .` |
| `SUPER+X` | przeglądarka | `brave` |
| `SUPER` (puszczony sam) | menu aplikacji | `rofi -show drun -theme ~/.config/rofi/rofi.rosi` |
| `SUPER+SHIFT+S` | zrzut zaznaczenia do schowka | `grim -g "$(slurp)" - \| wl-copy` |
| `SUPER+.` | emoji | `~/.config/scripts/emoji-menu.sh` |
| `SUPER+F11` | pokaż/ukryj waybar | `~/.config/scripts/waybar-toggle.sh` |
| `SUPER+O` | klawiatura ekranowa | `~/.config/scripts/toggle-wvkbd.sh` |
| `SUPER+F3` | wayscriber | `pkill -SIGUSR1 wayscriber` (wayscriber nie jest instalowany) |

### Okna i obszary robocze

| Skrót | Działanie |
|---|---|
| `SUPER+T` | okno pływające |
| `SUPER+F` | pełny ekran |
| `SUPER+P` / `SUPER+U` | pseudo / zmiana podziału (układ dwindle) |
| `SUPER+J/L/I/K` | fokus lewo / prawo / góra / dół |
| `SUPER+SHIFT+J/L/I/K` | przesuń okno |
| `SUPER+CTRL+J/L/I/K` | zmień rozmiar o 5% |
| `SUPER+1…0` | obszar roboczy 1–10 (w Mango: tagi) |
| `SUPER+SHIFT+1…0` | przenieś okno na obszar 1–10 |
| `SUPER+A` / `SUPER+S` | poprzedni / następny obszar |
| `SUPER+SHIFT+CTRL+R` | przenieś okno na pierwszy pusty obszar |
| `SUPER+ALT+L` | układ 80/20 (skrypt hyprctl – nie przeniesiony) |
| `SUPER+LPM` / `SUPER+PPM` | przeciąganie / zmiana rozmiaru myszą |
| `SUPER+Delete` | wyłącz wszystkie skróty (submapa „clean”), ponownie – włącz |
| `SUPER+F1` / `SUPER+F2` | zoom kursora −/+ (hyprctl) |
| zamknięcie klapy | było: blokada ekranu; teraz nic się nie dzieje (`power.nix`), laptop liczy dalej |

Uwaga: `SUPER+D` jest teraz zajęty przez podpowiedzi, a `SUPER+F1` w starym układzie był zoomem.
