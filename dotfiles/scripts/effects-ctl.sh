#!/usr/bin/env bash
# effects-ctl.sh – JEDEN program do włączania/wyłączania WSZYSTKICH przełączników
# efektów w tym projekcie (Mango, Quickshell bar, power-fx), zamiast grzebania
# w kilku różnych plikach/skryptach.
#
# Trzy grupy przełączników, każda w swoim pliku, każda w formacie
# "linia z samą nazwą = WŁĄCZONE, # na początku = WYŁĄCZONE":
#
#   1) "specjalne" (EFFECT_NAMES + particles-*) – ~/.config/mango-effects.conf, w sekcjach:
#      Mango (blur/shadows/animations/layer_animations), Particles (5 niezależnych
#      przełączników, jeden per motyw – patrz niżej), WPM (wpm-color/wpm-move/wpm-count),
#      Muzyka (cava). WYŁĄCZANE AUTOMATYCZNIE NA BATERII (plik pamięta co ma się włączyć
#      z powrotem po podłączeniu zasilacza – battery-effects-monitor.sh + `effects reapply`).
#
#      Particles: KAŻDY motyw (leaves/rain/snow/sparks/cursor) jest osobnym, w pełni
#      niezależnym przełącznikiem w pliku. Od 2026-11-19 silnik (Particles.qml +
#      ParticleCanvas.qml) renderuje WSZYSTKIE aktywne motywy NARAZ (prawdziwe nakładanie
#      warstw, nie tylko "ostatni wygrywa") – budżet cząsteczek (80) jest wspólny dla
#      wszystkich naraz, nie 80 na każdy (MASTER §11). `effects particles <motyw>` robi
#      wyłączny wybór (gasi resztę, ustawia tylko ten jeden) – do ręcznego włączania więcej
#      niż jednego naraz służy `effects particles-<motyw> on` dla każdego z osobna.
#      SUPER+F6 nie przełącza już particles – otwiera terminal z `effects` (edycja pliku
#      w $EDITOR), bo to najwygodniejszy sposób włączyć kilka motywów naraz ręcznie.
#
#   2) power-fx (PFX_CURSOR/PFX_TILES/PFX_PET/PFX_SYSTEM/PFX_BARFX/PFX_MENUFX, razem
#      PFX_NAMES) – ~/syshelp/power-fx/effects.conf, w tych samych kategoriach co tamten
#      plik: reakcje na mysz/kursor (clicks/sparkles/afterimage/touchtrail/wobble/stretch/
#      scroll/drag/pop/edgeglow/kbtrail), animacje okien (focus/open/close/swap/fullscreen/
#      floating/urgent/resize – "open" = animacja wejścia okna), pet (desktop pet – goni/
#      umyka przed kursorem, to jest "efekt podrążający za myszką"; + swarm/flocks/annoying),
#      system (notify/plug/keymode/phonefile), bar (barripple/volripple/musicbob/lyrics/
#      lockwobble/weatherfx/claudespin), menu (mousedance).
#      Osobny, już istniejący plik (power-fx go sam obserwuje, zmiana działa
#      w ciągu sekundy, bez restartu). effects-ctl.sh tylko go edytuje –
#      każdy z tych przełączników jest też wywołalny bezpośrednio pod własną
#      nazwą, np. `effects pet on`. Grupy mysz/okna też naraz: `effects mousefx on`,
#      `effects windowfx off`. Same się gaszą na baterii (kod w Fx.qml).
#
#   3) pojedyncze, nie "specjalne" – nie gasi ich bateria, bo to nie dodatki
#      a sposób rysowania/działania pulpitu:
#      opacity (przezroczystość okien), bar (widoczność paska),
#      nightlight (filtr niebieskiego światła, wlsunset).
#
#      cpu-throttle (T2.40) jest też w tej grupie (plik LEGACY_STATE, nie gasi go
#      bateria), ale NIE jest kosmetyczny – to bezpiecznik termiczny sprzętu (85°C ->
#      max_perf_pct 50%, histereza do 70°C). Logika mieszka w Quickshell
#      (bar/ThermalThrottle.qml, Timer co 5 s) – effects-ctl.sh tu tylko przełącza
#      flagę "czy aktywny", tak jak nightlight przełącza swoją.
#
# Użycie:
#   effects                          interaktywne menu (bez argumentów)
#   effects status                   stan WSZYSTKICH przełączników, w sekcjach
#   effects reapply                  zastosuj plik stanu teraz (na AC: wg pliku; na baterii: specjalne off)
#   effects edit                     otwórz ~/.config/mango-effects.conf w $EDITOR, potem reapply
#   effects all         [on|off]     blur+shadows+animations+layer_animations na raz (był SUPER+F8)
#   effects blur        [on|off]
#   effects shadows     [on|off]
#   effects animations  [on|off]     animacje Mango (okna)
#   effects layer       [on|off]     layer_animations (animacje warstw Quickshell/bar)
#   effects particles   off|leaves|rain|snow|sparks|cursor
#                                    wyłączny wybór: włącza tylko ten jeden motyw, gasi resztę
#   effects particles-leaves  [on|off]   pojedyncza linia, NIE gasi innych – można mieć kilka naraz
#   effects particles-rain    [on|off]   (silnik renderuje je WSZYSTKIE naraz, patrz wyżej)
#   effects particles-snow   [on|off]
#   effects particles-sparks [on|off]
#   effects particles-cursor [on|off]
#   effects wpm-count                przełącz liczenie WPM (zatrzymuje evtest - oszczędza CPU)
#   effects wpm-color                przełącz kolor obramówki wg prędkości pisania (T3.13)
#   effects wpm-move                 przełącz "ruszanie się" okna (border_px/gap + puls) przy pisaniu
#   effects cava        [on|off]     wizualizator muzyki na pulpicie (cava-bg, na środku)
#   effects bar                      przełącz widoczność baru (SUPER+F11)
#   effects opacity     [on|off]     przezroczystość okien (Brave, terminal...) – off = pełna
#                                    nieprzezroczystość (np. do filmów)
#   effects nightlight  [on|off]     filtr niebieskiego światła wieczorem (wlsunset) – nie gasi go bateria
#   effects cpu-throttle [on|off]    BEZPIECZNIK TERMICZNY CPU (T2.40, nie kosmetyczny!) – domyślnie
#                                    ON; wyłącz tylko jeśli wiesz co robisz. Nie gasi go bateria.
#   effects pfx                      lista WSZYSTKICH przełączników power-fx + stan
#   effects pfx <nazwa> [on|off]     przełącz jeden efekt power-fx (to samo co `effects <nazwa>`)
#   effects pfx-edit                 otwórz ~/syshelp/power-fx/effects.conf w $EDITOR (bez reapply – power-fx sam go obserwuje)
#   effects <nazwa-pfx> [on|off]     każdy przełącznik power-fx jest też dostępny pod własną nazwą,
#                                    np. `effects pet on`, `effects mousedance off` (patrz `effects pfx`)
#
# Bez argumentu on/off: przełącza (toggle).

set -euo pipefail

LEGACY_STATE="$HOME/.config/mango-effects"          # opacity + nightlight + cpu-throttle (nie są "specjalne")
CONF="$HOME/.config/mango-effects.conf"             # efekty specjalne, format comment-to-disable, w sekcjach
WPM_STATE="$HOME/.config/wpm-effects"               # pisany przez WpmBorder.qml (color/move/count)
PFX_CONF="$HOME/syshelp/power-fx/effects.conf"      # przełączniki power-fx (cursor/tile/pet/bar fx)
MAX_PERF_PCT="/sys/devices/system/cpu/intel_pstate/max_perf_pct"  # T2.40, czytany tylko do `status`
SOCK_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
WL="${WAYLAND_DISPLAY:-wayland-1}"

# Efekty "specjalne" bez parametru (sekcje Mango/WPM/Muzyka) – off na baterii, pamiętane w $CONF.
EFFECT_NAMES=(blur shadows animations layer_animations wpm-color wpm-move wpm-count cava)

# Motywy particles – każdy osobna linia "particles-<motyw>" w $CONF (sekcja Particles).
PARTICLE_THEMES=(leaves rain snow sparks cursor)

# Wszystkie przełączniki z ~/syshelp/power-fx/effects.conf (patrz CLAUDE.md tamtego projektu),
# podzielone na te same kategorie co w tamtym pliku. "pokeinterval" nie jest tu wpisany – to
# parametr liczbowy (annoying: MIN MAX sekund), nie on/off; edytować ręcznie przez `effects pfx-edit`.
PFX_CURSOR=(clicks sparkles afterimage touchtrail wobble stretch scroll drag pop edgeglow kbtrail)   # reakcje na mysz/kursor – grupa: `effects mousefx`
PFX_TILES=(focus open close swap fullscreen floating urgent resize)                                  # animacje okien (otwarcie/zamknięcie/fokus/...) – grupa: `effects windowfx`
PFX_PET=(pet swarm flocks annoying)                                                                   # desktop pet – goni/umyka przed kursorem (`effects pet on`)
PFX_SYSTEM=(notify plug keymode phonefile)
PFX_BARFX=(barripple volripple musicbob lyrics lockwobble weatherfx claudespin)
PFX_MENUFX=(mousedance)

PFX_NAMES=(
  "${PFX_CURSOR[@]}"
  "${PFX_TILES[@]}"
  "${PFX_PET[@]}"
  "${PFX_SYSTEM[@]}"
  "${PFX_BARFX[@]}"
  "${PFX_MENUFX[@]}"
)

is_pfx_name() {
  local n
  for n in "${PFX_NAMES[@]}"; do [ "$n" = "$1" ] && return 0; done
  return 1
}

# Stary format (przed podziałem na sekcje) zapisywał motyw particles jako JEDNĄ linię
# "particles <motyw>" / "#particles <motyw>" z parametrem. Jeśli taka linia jeszcze
# istnieje w $CONF (plik z poprzedniej wersji effects-ctl.sh), przepisz ją na nowe,
# niezależne linie "particles-<motyw>" (ten sam stan: włączony motyw zostaje włączony,
# reszta wyłączona) i usuń starą linię. Bezpieczne do wołania wielokrotnie (no-op gdy
# starej linii nie ma).
migrate_conf() {
  [ -f "$CONF" ] || return 0
  local old_line enabled theme t
  old_line=$(grep -m1 -E '^[[:space:]]*#?[[:space:]]*particles[[:space:]]+(leaves|rain|snow|sparks|cursor)[[:space:]]*$' "$CONF" 2>/dev/null || true)
  [ -z "$old_line" ] && return 0
  if [[ "$old_line" =~ ^[[:space:]]*# ]]; then enabled=0; else enabled=1; fi
  theme=$(echo "$old_line" | awk '{print $NF}')
  sed -i -E '/^[[:space:]]*#?[[:space:]]*particles[[:space:]]+(leaves|rain|snow|sparks|cursor)[[:space:]]*$/d' "$CONF"
  for t in "${PARTICLE_THEMES[@]}"; do
    grep -q -E "^[[:space:]]*#?[[:space:]]*particles-$t([[:space:]]|\$)" "$CONF" 2>/dev/null && continue
    if [ "$enabled" = 1 ] && [ "$t" = "$theme" ]; then
      echo "particles-$t" >> "$CONF"
    else
      echo "#particles-$t" >> "$CONF"
    fi
  done
  echo "(migracja mango-effects.conf: stary 'particles $theme' -> nowe particles-$theme)" >&2
}

ensure_conf() {
  if [ -f "$CONF" ]; then
    migrate_conf
    return 0
  fi
  cat > "$CONF" <<'EOF'
# mango-effects.conf — linia z samą nazwą efektu jest WŁĄCZONA. Dodaj `#` na początku
# linii, żeby ją WYŁĄCZYĆ. Zapisywane/czytane przez `effects` (effects-ctl.sh). Plik jest
# podzielony na sekcje.
#
# Na baterii (brak zasilacza) WSZYSTKIE te efekty są wyłączane automatycznie, niezależnie
# od tego pliku – plik tylko pamięta co ma się włączyć z powrotem po podłączeniu zasilacza
# (battery-effects-monitor.sh woła `effects reapply` przy każdej zmianie zasilania).
#
# NIE zaczynaj żadnej innej linii komentarza od samej nazwy efektu (np. "blur" na początku
# linii) – ten plik parsuje się prostym grepem po nazwie na początku linii.

# --- Mango (okna) ---
blur
shadows
animations
layer_animations

# --- Particles (tło) ---
# Każdy motyw jest osobnym, w pełni niezależnym przełącznikiem – włącz więcej niż jeden
# naraz i silnik (Particles.qml) narysuje je WSZYSTKIE naraz (prawdziwe nakładanie warstw
# cząsteczek, nie tylko jedna na raz). `effects particles <motyw>` robi wyłączny wybór
# (gasi resztę, ustawia tylko ten jeden) – do włączenia kilku naraz odkomentuj kilka linii
# poniżej albo użyj `effects particles-<motyw> on` dla każdego z osobna.
#particles-leaves
#particles-rain
#particles-snow
#particles-sparks
#particles-cursor

# --- WPM (szybkość pisania) ---
wpm-color
wpm-move
wpm-count

# --- Muzyka (pulpit) ---
#cava
EOF
}

# --- Odczyt/zapis stanu w $CONF (comment = off) ---

conf_line() {
  # Pierwsza linia zaczynająca się (opcjonalnym #, spacjami) nazwą efektu $1.
  grep -m1 -E "^[[:space:]]*#?[[:space:]]*$1([[:space:]]|\$)" "$CONF" 2>/dev/null || true
}

conf_enabled() {
  local line; line=$(conf_line "$1")
  [ -n "$line" ] || return 1
  [[ "$line" =~ ^[[:space:]]*# ]] && return 1
  return 0
}

conf_set() {
  # conf_set NAME on|off
  local name="$1" state="$2"
  ensure_conf
  if conf_line "$name" >/dev/null && [ -n "$(conf_line "$name")" ]; then
    if [ "$state" = on ]; then
      sed -i -E "s/^[[:space:]]*#?[[:space:]]*$name([[:space:]].*)?\$/$name/" "$CONF"
    else
      sed -i -E "s/^[[:space:]]*#?[[:space:]]*$name([[:space:]].*)?\$/#$name/" "$CONF"
    fi
  else
    if [ "$state" = on ]; then echo "$name" >> "$CONF"; else echo "#$name" >> "$CONF"; fi
  fi
}

# --- Odczyt/zapis stanu w $PFX_CONF (comment = off) – jak $CONF, ale KAŻDA linia ma
# własny trwały komentarz "# opis" na końcu, który trzeba zachować (nie nadpisywać
# całej linii jak w conf_set, tylko doklejać/zdejmować wiodący #). ---

pfx_line() {
  grep -m1 -E "^[[:space:]]*#?[[:space:]]*$1([[:space:]]|\$)" "$PFX_CONF" 2>/dev/null || true
}

pfx_enabled() {
  local line; line=$(pfx_line "$1")
  [ -n "$line" ] || return 1
  [[ "$line" =~ ^[[:space:]]*# ]] && return 1
  return 0
}

pfx_set() {
  # pfx_set NAME on|off – zdejmuje/dokleja tylko wiodący #, zostawia opis po nazwie bez zmian.
  local name="$1" state="$2"
  if [ ! -f "$PFX_CONF" ]; then
    echo "brak $PFX_CONF (power-fx nie jest skonfigurowany na tej maszynie?)" >&2
    return 1
  fi
  if [ "$state" = on ]; then
    sed -i -E "s/^([[:space:]]*)#[[:space:]]*($name([[:space:]].*)?)\$/\1\2/" "$PFX_CONF"
  else
    sed -i -E "s/^([[:space:]]*)($name([[:space:]].*)?)\$/\1#\2/" "$PFX_CONF"
  fi
}

pfx_onoff() {
  local name="$1" mode="${2:-toggle}"
  if ! is_pfx_name "$name"; then
    echo "Nieznany efekt power-fx: $name (patrz 'effects pfx' po listę)" >&2
    return 1
  fi
  local cur=off; pfx_enabled "$name" && cur=on
  local target
  case "$mode" in
    on)  target=on ;;
    off) target=off ;;
    *)   target=$([ "$cur" = on ] && echo off || echo on) ;;
  esac
  pfx_set "$name" "$target"
  echo "$name: $target"
}

# Przełącz CAŁĄ grupę power-fx naraz (np. wszystkie reakcje myszy albo wszystkie animacje
# okien jednym poleceniem) – toggle liczony wg stanu pierwszego efektu w grupie, reszta
# dociąga się do tego samego stanu. Używane przez `effects mousefx`/`effects windowfx`.
pfx_group_onoff() {
  local mode="$1"; shift
  if [ "$mode" = toggle ]; then
    local cur=off; pfx_enabled "$1" && cur=on
    mode=$([ "$cur" = on ] && echo off || echo on)
  fi
  local n
  for n in "$@"; do pfx_onoff "$n" "$mode"; done
}

# Wypisuje jedną kategorię efektów power-fx (nazwa grupy + stan każdego przełącznika).
print_pfx_group() {
  local label="$1"; shift
  echo "  · $label"
  local n
  for n in "$@"; do
    local enabled=off; pfx_enabled "$n" && enabled=on
    printf "    %-14s %s\n" "$n:" "$enabled"
  done
}

pfx_status() {
  echo "--- power-fx ($PFX_CONF) ---"
  if [ ! -f "$PFX_CONF" ]; then
    echo "  (brak pliku – power-fx nieskonfigurowany na tej maszynie)"
    return
  fi
  print_pfx_group "mysz / kursor – reakcje na mysz (grupa: 'effects mousefx [on|off]')" "${PFX_CURSOR[@]}"
  print_pfx_group "okna – animacje wejścia/wyjścia/fokusu (grupa: 'effects windowfx [on|off]')" "${PFX_TILES[@]}"
  print_pfx_group "pet – goni/umyka przed kursorem ('effects pet [on|off]')" "${PFX_PET[@]}"
  print_pfx_group "system" "${PFX_SYSTEM[@]}"
  print_pfx_group "bar" "${PFX_BARFX[@]}"
  print_pfx_group "menu" "${PFX_MENUFX[@]}"
}

# --- Zasilanie ---

ac_online() {
  local ps
  for ps in /sys/class/power_supply/*; do
    [ -d "$ps" ] || continue
    case "$(cat "$ps/type" 2>/dev/null || true)" in
      Mains|USB|USB_C)
        [ "$(cat "$ps/online" 2>/dev/null || echo 0)" = "1" ] && return 0
        ;;
    esac
  done
  return 1
}

# Czekaj aż mango odpowiada przez mmsg (na starcie bywa chwilę głuche) – maks ~5 s.
wait_for_mango() {
  local i
  for i in $(seq 1 25); do
    mmsg get cursorpos >/dev/null 2>&1 && return 0
    sleep 0.2
  done
  return 1
}

# --- Mango (mmsg setoption) – blur/shadows/animations/layer_animations + opacja (legacy) ---

legacy_state_get() { grep -m1 "^$1=" "$LEGACY_STATE" 2>/dev/null | cut -d= -f2 || true; }
legacy_state_set() {
  local key="$1" val="$2"
  touch "$LEGACY_STATE"
  if grep -q "^$key=" "$LEGACY_STATE" 2>/dev/null; then
    sed -i "s/^$key=.*/$key=$val/" "$LEGACY_STATE"
  else
    echo "$key=$val" >> "$LEGACY_STATE"
  fi
}

mango_apply() { mmsg dispatch "setoption,$1,$2" >/dev/null 2>&1 || true; }

socket_ping() {
  socat -u /dev/null "UNIX-CONNECT:$SOCK_DIR/$1-$WL.sock" 2>/dev/null || true
}

socket_send() {
  printf '%s\n' "$2" | socat -u - "UNIX-CONNECT:$SOCK_DIR/$1-$WL.sock" 2>/dev/null || true
}

cava_running() {
  pgrep -f 'kitty.*kitten panel .*cava-bg' >/dev/null 2>&1
}

cava_apply() {
  case "$1" in
    on)
      cava_running && return 0
      local launcher="$HOME/.config/scripts/launch-cava-bg.sh"
      [ -x "$launcher" ] && { nohup "$launcher" >/dev/null 2>&1 & disown 2>/dev/null || true; }
      true
      ;;
    off)
      pkill -f 'kitty.*kitten panel .*cava-bg' >/dev/null 2>&1 || true
      pkill -f 'cava -p .*/config-bg' >/dev/null 2>&1 || true
      ;;
  esac
}

# wpm-color/wpm-move/wpm-count: WpmBorder.qml ma tylko sockety TOGGLE (nie set), ale
# zapisuje swój własny stan do $WPM_STATE po każdej zmianie – odczytaj go i przełącz
# TYLKO jeśli aktualny stan różni się od docelowego (idempotentne "ustaw na X").
wpm_state_get() { grep -m1 "^$1=" "$WPM_STATE" 2>/dev/null | cut -d= -f2 || true; }

wpm_apply() {
  # wpm_apply color|move|count on|off
  local key="$1" want="$2" cur
  cur=$(wpm_state_get "$key")
  [ -z "$cur" ] && cur=1   # brak wpisu = domyślnie włączone (zgodnie z WpmBorder.qml)
  local want_bit=1; [ "$want" = off ] && want_bit=0
  [ "$cur" != "$want_bit" ] && socket_ping "qs-wpm-$key"
  true
}

particles_apply() {
  # particles_apply LISTA_PO_PRZECINKU_LUB_PUSTE – silnik (Particles.qml) renderuje
  # WSZYSTKIE przekazane motywy naraz (prawdziwe nakładanie warstw cząsteczek).
  socket_send qs-particles-set "$1"
}

# Lista WSZYSTKICH aktualnie włączonych motywów particles (kolejność = PARTICLE_THEMES),
# po przecinku – "" (puste), gdy żadna linia particles-<motyw> nie jest włączona.
particles_active_list() {
  local out="" t
  for t in "${PARTICLE_THEMES[@]}"; do
    if conf_enabled "particles-$t"; then
      [ -n "$out" ] && out="$out,"
      out="$out$t"
    fi
  done
  echo "$out"
}

particles_apply_active() {
  if ac_online; then particles_apply "$(particles_active_list)"; else particles_apply ""; fi
}

# --- Night light (wlsunset) – nie jest "specjalny": nie gasi go bateria. ---

nightlight_running() { pgrep -x wlsunset >/dev/null 2>&1; }

nightlight_apply() {
  case "$1" in
    on)
      nightlight_running && return 0
      command -v wlsunset >/dev/null 2>&1 || { echo "wlsunset nie jest zainstalowany (wymaga rebuild)" >&2; return 1; }
      setsid wlsunset -t 4000 -T 6500 >/dev/null 2>&1 &
      disown 2>/dev/null || true
      ;;
    off)
      pkill -x wlsunset >/dev/null 2>&1 || true
      ;;
  esac
}

nightlight_set() {
  local mode="${1:-toggle}"
  case "$mode" in
    on)
      legacy_state_set nightlight on
      nightlight_apply on
      echo "nightlight: on"
      ;;
    off)
      legacy_state_set nightlight off
      nightlight_apply off
      echo "nightlight: off"
      ;;
    *)
      if nightlight_running; then nightlight_set off; else nightlight_set on; fi
      return
      ;;
  esac
}

# --- CPU thermal throttle (T2.40) – bezpiecznik termiczny, NIE efekt kosmetyczny. ---
# Ten skrypt tylko przełącza flagę w LEGACY_STATE ("cpu-throttle=on|off"); cała logika
# odczytu temperatury i zapisu do max_perf_pct żyje w Quickshell
# (dotfiles/quickshell/bar/ThermalThrottle.qml, Timer co 5 s, odpytuje tę flagę). Domyślnie
# (klucz nieobecny w pliku) bezpiecznik jest WŁĄCZONY – nigdy nie wyłączamy go "domyślnie
# przez brak wpisu", tylko przez jawne "off".
cpu_throttle_enabled() {
  local v; v=$(legacy_state_get cpu-throttle)
  [ "$v" = "off" ] && return 1
  return 0
}

cpu_throttle_set() {
  local mode="${1:-toggle}"
  case "$mode" in
    on)
      legacy_state_set cpu-throttle on
      echo "cpu-throttle: on (bezpiecznik termiczny CPU aktywny – 85°C -> max_perf_pct 50%, do 70°C)"
      ;;
    off)
      legacy_state_set cpu-throttle off
      echo "cpu-throttle: off (UWAGA: bezpiecznik termiczny WYŁĄCZONY – throttled/TLP same w sobie"
      echo "  nie chronią przed przegrzaniem przy długim 100% obciążeniu, np. kompilacji full)"
      ;;
    *)
      if cpu_throttle_enabled; then cpu_throttle_set off; else cpu_throttle_set on; fi
      return
      ;;
  esac
}

# --- Zastosuj jeden efekt "specjalny" (sekcje Mango/WPM/Muzyka – bez particles, ma własną
# ścieżkę przez particles_apply_active) do systemu, wg desired on/off. ---
apply_special() {
  local name="$1" desired="$2"
  case "$name" in
    blur|shadows|animations)
      mango_apply "$name" "$([ "$desired" = on ] && echo 1 || echo 0)" ;;
    layer_animations)
      mango_apply layer_animations "$([ "$desired" = on ] && echo 1 || echo 0)" ;;
    wpm-color) wpm_apply color "$desired" ;;
    wpm-move)  wpm_apply move  "$desired" ;;
    wpm-count) wpm_apply count "$desired" ;;
    cava) cava_apply "$desired" ;;
  esac
}

# Zastosuj CAŁY plik stanu wg aktualnego zasilania: na AC -> jak w pliku, na baterii -> wszystko off.
reapply() {
  ensure_conf
  wait_for_mango || true
  local on_ac=1; ac_online || on_ac=0
  local name
  for name in "${EFFECT_NAMES[@]}"; do
    local enabled=0; conf_enabled "$name" && enabled=1
    local desired=off
    if [ "$enabled" = 1 ] && [ "$on_ac" = 1 ]; then desired=on; fi
    apply_special "$name" "$desired"
  done
  particles_apply_active
  # opacja + nightlight: legacy, niezależne od baterii
  local op; op=$(legacy_state_get focused_opacity)
  if [ -n "$op" ]; then
    mango_apply focused_opacity "$op"
    mango_apply unfocused_opacity "$(legacy_state_get unfocused_opacity)"
  fi
  [ "$(legacy_state_get nightlight)" = on ] && nightlight_apply on
  if [ "$on_ac" = 0 ]; then
    echo "reapply: bateria – wszystkie efekty specjalne wyłączone (plik stanu bez zmian)"
  else
    echo "reapply: AC – efekty specjalne wg $CONF"
  fi
}

# --- Komendy generyczne on/off/toggle dla efektów "specjalnych" bez parametru ---
special_onoff() {
  local name="$1" mode="${2:-toggle}"
  ensure_conf
  local cur=off; conf_enabled "$name" && cur=on
  local target
  case "$mode" in
    on)  target=on ;;
    off) target=off ;;
    *)   target=$([ "$cur" = on ] && echo off || echo on) ;;
  esac
  conf_set "$name" "$target"
  if ac_online; then
    apply_special "$name" "$target"
  else
    echo "(bateria – zapamiętane, włączy się po podłączeniu zasilacza)"
  fi
  echo "$name: $target"
}

all_onoff() {
  local mode="${1:-toggle}"
  if [ "$mode" = toggle ]; then
    local cur=off; conf_enabled blur && cur=on
    mode=$([ "$cur" = on ] && echo off || echo on)
  fi
  local n
  for n in blur shadows animations layer_animations; do special_onoff "$n" "$mode"; done
}

# Wyłączny wybór motywu particles: włącza TEN jeden, gasi resztę. Do ręcznego włączania
# więcej niż jednego naraz – patrz particle_theme_onoff (`effects particles-<motyw> [on|off]`).
particles_set() {
  local theme="$1" t
  case "$theme" in
    off)
      for t in "${PARTICLE_THEMES[@]}"; do conf_set "particles-$t" off; done
      ;;
    leaves|rain|snow|sparks|cursor)
      for t in "${PARTICLE_THEMES[@]}"; do
        conf_set "particles-$t" "$([ "$t" = "$theme" ] && echo on || echo off)"
      done
      ;;
    *) echo "Nieznany motyw: $theme (off|leaves|rain|snow|sparks|cursor)" >&2; return 1 ;;
  esac
  if ac_online; then particles_apply_active; else echo "(bateria – zapamiętane, włączy się po podłączeniu zasilacza)"; fi
  echo "particles: $theme"
}

# Przełącznik JEDNEJ linii particles-<motyw>, bez gaszenia innych – można mieć kilka naraz.
# Silnik (Particles.qml) renderuje WSZYSTKIE włączone motywy naraz (particles_apply_active).
particle_theme_onoff() {
  local theme="$1" mode="${2:-toggle}" name
  name="particles-$theme"
  local cur=off; conf_enabled "$name" && cur=on
  local target
  case "$mode" in
    on)  target=on ;;
    off) target=off ;;
    *)   target=$([ "$cur" = on ] && echo off || echo on) ;;
  esac
  conf_set "$name" "$target"
  if ac_online; then
    particles_apply_active
    local active; active="$(particles_active_list)"
    echo "$name: $target (aktywne teraz: ${active:-żadne})"
  else
    echo "$name: $target"
    echo "(bateria – zapamiętane, włączy się po podłączeniu zasilacza)"
  fi
}

wpm_cmd() {
  local key="$1" mode="${2:-toggle}"   # key: color|move|count
  ensure_conf
  local name="wpm-$key"
  local cur=off; conf_enabled "$name" && cur=on
  local target
  case "$mode" in
    on)  target=on ;;
    off) target=off ;;
    *)   target=$([ "$cur" = on ] && echo off || echo on) ;;
  esac
  conf_set "$name" "$target"
  if ac_online; then
    wpm_apply "$key" "$target"
  else
    echo "(bateria – zapamiętane, włączy się po podłączeniu zasilacza)"
  fi
  echo "$name: $target"
}

cava_cmd() {
  local mode="${1:-toggle}"
  ensure_conf
  local cur=off; conf_enabled cava && cur=on
  local target
  case "$mode" in
    on)  target=on ;;
    off) target=off ;;
    *)   target=$([ "$cur" = on ] && echo off || echo on) ;;
  esac
  conf_set cava "$target"
  if ac_online; then cava_apply "$target"; else echo "(bateria – zapamiętane, włączy się po podłączeniu zasilacza)"; fi
  echo "cava: $target"
}

# Domyślne wartości przezroczystości z config.conf (dotfiles/mango/config.conf) – "on" wraca
# do nich, "off" wymusza 1 (pełna nieprzezroczystość) na oknach aktywnych i nieaktywnych.
OPACITY_FOCUSED_NORMAL=0.97
OPACITY_UNFOCUSED_NORMAL=0.87

opacity_set() {
  local mode="${1:-toggle}"
  case "$mode" in
    off)
      legacy_state_set focused_opacity 1
      legacy_state_set unfocused_opacity 1
      mango_apply focused_opacity 1
      mango_apply unfocused_opacity 1
      echo "opacity: off (pełna nieprzezroczystość – tapeta nie przebija)"
      ;;
    on)
      legacy_state_set focused_opacity "$OPACITY_FOCUSED_NORMAL"
      legacy_state_set unfocused_opacity "$OPACITY_UNFOCUSED_NORMAL"
      mango_apply focused_opacity "$OPACITY_FOCUSED_NORMAL"
      mango_apply unfocused_opacity "$OPACITY_UNFOCUSED_NORMAL"
      echo "opacity: on (normalna przezroczystość)"
      ;;
    *)
      if [[ "$(legacy_state_get focused_opacity)" == "1" ]]; then opacity_set on; else opacity_set off; fi
      return
      ;;
  esac
  reapply_opacity_to_open_windows
}

# Mango przelicza focused_opacity/unfocused_opacity per-okno tylko w momencie zmiany
# fokusu (client_set_focus_opacity w binarce) – setoption sam nie odświeża już otwartych
# okien. Przełącz fokus przez każde z nich i wróć do tego, co było, żeby zmiana była
# widoczna od razu, bez ręcznego klikania po oknach.
reapply_opacity_to_open_windows() {
  command -v jq >/dev/null 2>&1 || return 0
  local focused ids id
  focused=$(mmsg get focusing-client 2>/dev/null | jq -r '.id // empty')
  ids=$(mmsg get all-clients 2>/dev/null | jq -r '.clients[].id')
  for id in $ids; do
    mmsg dispatch "focusid,$id" >/dev/null 2>&1 || true
  done
  [ -n "$focused" ] && mmsg dispatch "focusid,$focused" >/dev/null 2>&1
  true
}

# Wypisuje jedną linię stanu dla efektu "specjalnego" (sekcje Mango/WPM/Muzyka).
print_special() {
  local name="$1" on_ac="$2"
  local enabled=off; conf_enabled "$name" && enabled=on
  local suffix=""
  [ "$enabled" = on ] && [ "$on_ac" = 0 ] && suffix="  (teraz: off – bateria)"
  printf "  %-18s %s%s\n" "$name:" "$enabled" "$suffix"
}

status() {
  ensure_conf
  local on_ac=1; ac_online || on_ac=0
  echo "--- Zasilanie: $([ "$on_ac" = 1 ] && echo "AC" || echo "BATERIA – efekty specjalne wyłączone")"

  echo "--- Mango (okna) [$CONF] ---"
  local name
  for name in blur shadows animations layer_animations; do print_special "$name" "$on_ac"; done

  local active_particles; active_particles="$(particles_active_list)"
  echo "--- Particles (aktywne naraz: ${active_particles:-żadne}) ---"
  local t
  for t in "${PARTICLE_THEMES[@]}"; do print_special "particles-$t" "$on_ac"; done

  echo "--- WPM (szybkość pisania) ---"
  for name in wpm-color wpm-move wpm-count; do print_special "$name" "$on_ac"; done

  echo "--- Muzyka ---"
  print_special cava "$on_ac"

  echo "--- Pulpit / inne (nie \"specjalne\" – nie gasi ich bateria) ---"
  printf "  %-18s %s\n" "opacity:" "$([ "$(legacy_state_get focused_opacity)" = "1" ] && echo off || echo on)"
  printf "  %-18s %s\n" "nightlight:" "$(nightlight_running && echo on || echo off)"
  echo "  bar:               (socket toggle – SUPER+F11)"
  local tstate; cpu_throttle_enabled && tstate=on || tstate=off
  local curperf=""
  [ -r "$MAX_PERF_PCT" ] && curperf="$(cat "$MAX_PERF_PCT" 2>/dev/null || true)"
  if [ -n "$curperf" ]; then
    printf "  %-18s %s (bezpiecznik termiczny; teraz max_perf_pct=%s%%)\n" "cpu-throttle:" "$tstate" "$curperf"
  else
    printf "  %-18s %s (bezpiecznik termiczny; brak intel_pstate na tej maszynie)\n" "cpu-throttle:" "$tstate"
  fi
  echo
  pfx_status
}

usage() {
  cat <<'EOF'
Użycie:
  effects                          interaktywne menu (bez argumentów)
  effects status                   stan WSZYSTKICH przełączników, w sekcjach
  effects reapply                  zastosuj plik stanu teraz (na AC: wg pliku; na baterii: specjalne off)
  effects edit                     otwórz ~/.config/mango-effects.conf w $EDITOR, potem reapply
  effects all         [on|off]     blur+shadows+animations+layer_animations na raz (był SUPER+F8)
  effects blur        [on|off]
  effects shadows     [on|off]
  effects animations  [on|off]     animacje Mango (okna)
  effects layer       [on|off]     layer_animations (animacje warstw Quickshell/bar)
  effects particles   off|leaves|rain|snow|sparks|cursor
                                   wyłączny wybór: włącza tylko ten jeden, gasi resztę
  effects particles-<motyw> [on|off]   pojedyncza linia, NIE gasi innych – kilka naraz,
                                   silnik renderuje je WSZYSTKIE naraz (leaves|rain|snow|sparks|cursor)
  effects wpm-count                przełącz liczenie WPM (zatrzymuje evtest - oszczędza CPU)
  effects wpm-color                przełącz kolor obramówki wg prędkości pisania
  effects wpm-move                 przełącz "ruszanie się" okna przy pisaniu
  effects cava        [on|off]     wizualizator muzyki na pulpicie (cava-bg)
  effects bar                      przełącz widoczność baru (SUPER+F11)
  effects opacity     [on|off]     przezroczystość okien
  effects nightlight  [on|off]     filtr niebieskiego światła (wlsunset) – nie gasi go bateria
  effects cpu-throttle [on|off]    bezpiecznik termiczny CPU (85°C -> max_perf_pct 50%, do 70°C,
                                   w Quickshell ThermalThrottle.qml) – domyślnie ON, nie gasi go bateria
  effects pfx                      lista WSZYSTKICH przełączników power-fx + stan, w grupach
  effects pfx <nazwa> [on|off]     przełącz jeden efekt power-fx
  effects pfx-edit                 otwórz ~/syshelp/power-fx/effects.conf w $EDITOR
  effects mousefx     [on|off]     WSZYSTKIE reakcje na mysz naraz (clicks/sparkles/afterimage/
                                   touchtrail/wobble/stretch/scroll/drag/pop/edgeglow/kbtrail)
  effects windowfx    [on|off]     WSZYSTKIE animacje okien naraz (focus/open/close/swap/
                                   fullscreen/floating/urgent/resize – "open" = wejście okna)
  effects pet         [on|off]     desktop pet, który goni/umyka przed kursorem (efekt "za myszką")
  effects <nazwa-pfx> [on|off]     każdy przełącznik power-fx też pod własną nazwą (patrz 'effects pfx')
EOF
}

cmd="${1:-menu}"

# Każdy przełącznik power-fx jest wywołalny bezpośrednio pod swoją nazwą,
# np. `effects pet on`, `effects mousedance toggle`.
if is_pfx_name "$cmd"; then
  pfx_onoff "$cmd" "${2:-toggle}"
  exit 0
fi

case "$cmd" in
  status)      status ;;
  reapply)     reapply ;;
  edit)
    ensure_conf
    "${EDITOR:-nvim}" "$CONF"
    reapply
    ;;
  pfx-edit)
    "${EDITOR:-nvim}" "$PFX_CONF"
    ;;
  pfx)
    if [ -z "${2:-}" ]; then pfx_status; else pfx_onoff "$2" "${3:-toggle}"; fi
    ;;
  mousefx)     pfx_group_onoff "${2:-toggle}" "${PFX_CURSOR[@]}" ;;
  windowfx)    pfx_group_onoff "${2:-toggle}" "${PFX_TILES[@]}" ;;
  all)         all_onoff "${2:-toggle}" ;;
  blur)        special_onoff blur "${2:-}" ;;
  shadows)     special_onoff shadows "${2:-}" ;;
  animations)  special_onoff animations "${2:-}" ;;
  layer)       special_onoff layer_animations "${2:-}" ;;
  particles)   particles_set "${2:?podaj motyw: off|leaves|rain|snow|sparks|cursor}" ;;
  particles-leaves|particles-rain|particles-snow|particles-sparks|particles-cursor)
    particle_theme_onoff "${cmd#particles-}" "${2:-toggle}"
    ;;
  wpm-count)   wpm_cmd count "${2:-toggle}" ;;
  wpm-color)   wpm_cmd color "${2:-toggle}" ;;
  wpm-move)    wpm_cmd move "${2:-toggle}" ;;
  cava)        cava_cmd "${2:-toggle}" ;;
  bar)         timeout 2 qs -c bar ipc call bar toggle 2>/dev/null || true ;;
  opacity)     opacity_set "${2:-toggle}" ;;
  nightlight)  nightlight_set "${2:-toggle}" ;;
  cpu-throttle) cpu_throttle_set "${2:-toggle}" ;;
  help|-h|--help) usage ;;
  menu)
    while true; do
      clear
      echo "=== Efekty graficzne (Mango / Quickshell / power-fx) ==="
      status
      echo
      echo " 1) blur toggle        2) shadows toggle      3) animations toggle"
      echo " 4) layer_animations   5) wszystko (all) toggle"
      echo " n) wpm liczenie toggle (CPU)  k) wpm kolor toggle   r) wpm ruch toggle"
      echo " m) cava (muzyka) toggle       b) bar toggle          o) opacity toggle"
      echo " l) night light (wlsunset) toggle"
      echo " h) bezpiecznik termiczny CPU toggle (T2.40 – NIE kosmetyczny, domyślnie ON)"
      echo " c) MYSZ – wszystkie reakcje na kursor naraz toggle (clicks/trail/wobble/...)"
      echo " t) OKNA – wszystkie animacje okien naraz toggle (open/close/focus/swap/...)"
      echo " p) PET – desktop pet, goni/umyka przed kursorem, toggle"
      echo " x) power-fx: przełącz jeden efekt po nazwie (lista: 'effects pfx')"
      echo " e) edytuj plik efektów (particles-<motyw> też tu; $CONF)"
      echo " q) wyjście"
      read -rp "> " choice
      case "$choice" in
        1) special_onoff blur ;;
        2) special_onoff shadows ;;
        3) special_onoff animations ;;
        4) special_onoff layer_animations ;;
        5) all_onoff toggle ;;
        n) wpm_cmd count toggle ;;
        k) wpm_cmd color toggle ;;
        r) wpm_cmd move toggle ;;
        m) cava_cmd toggle ;;
        b) timeout 2 qs -c bar ipc call bar toggle 2>/dev/null || true ;;
        o) opacity_set toggle ;;
        l) nightlight_set toggle ;;
        h) cpu_throttle_set toggle ;;
        c) pfx_group_onoff toggle "${PFX_CURSOR[@]}" ;;
        t) pfx_group_onoff toggle "${PFX_TILES[@]}" ;;
        p) pfx_onoff pet toggle ;;
        x) read -rp "nazwa efektu power-fx: " pfxname; pfx_onoff "$pfxname" toggle ;;
        e) ensure_conf; "${EDITOR:-nvim}" "$CONF"; reapply ;;
        q) exit 0 ;;
        *) ;;
      esac
      sleep 1
    done
    ;;
  *)
    usage
    exit 1
    ;;
esac
