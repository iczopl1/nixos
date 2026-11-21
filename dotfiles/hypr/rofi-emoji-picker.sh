#!/usr/bin/env bash
set -euo pipefail

theme="${ROFI_EMOJI_THEME:-$HOME/.config/hypr/rofi-emoji.rosi}"
emoji_file="${ROFI_EMOJI_FILE:-/usr/share/unicode/emoji/emoji-test.txt}"
emoji_files=(
  "$emoji_file"
  "/usr/share/unicode/emoji/emoji-test.txt"
  "/usr/share/unicode/emoji-test.txt"
  "/usr/share/emoji/emoji-test.txt"
  "/run/current-system/sw/share/unicode/emoji/emoji-test.txt"
  "/run/current-system/sw/share/unicode/emoji-test.txt"
)

if [[ "${1:-}" != "--print" ]] && ! command -v rofi >/dev/null 2>&1; then
  echo "error: rofi is required" >&2
  exit 1
fi

if ! command -v wl-copy >/dev/null 2>&1; then
  echo "error: wl-copy is required" >&2
  exit 1
fi

emoji_entries() {
  local file

  for file in "${emoji_files[@]}"; do
    [[ -r "$file" ]] || continue
    awk -F '# ' '
      /^[0-9A-F ]+; fully-qualified/ {
        emoji = $2
        name = $2
        sub(/[[:space:]]+E[0-9.]+.*/, "", emoji)
        sub(/^.*[[:space:]]E[0-9.]+[[:space:]]+/, "", name)
        if (emoji != "" && name != "") {
          print emoji "\0meta\x1f" name
        }
      }
    ' "$file"
    return
  done

  if command -v python3 >/dev/null 2>&1; then
    python3 - <<'PY'
import unicodedata

variation_ranges = (
    range(0x2194, 0x21AA + 1),
    range(0x231A, 0x231B + 1),
    range(0x2328, 0x2328 + 1),
    range(0x23CF, 0x23CF + 1),
    range(0x23E9, 0x23F3 + 1),
    range(0x23F8, 0x23FA + 1),
    range(0x24C2, 0x24C2 + 1),
    range(0x25AA, 0x25AB + 1),
    range(0x25B6, 0x25B6 + 1),
    range(0x25C0, 0x25C0 + 1),
    range(0x25FB, 0x25FE + 1),
    range(0x2600, 0x27BF + 1),
    range(0x2934, 0x2935 + 1),
    range(0x2B05, 0x2B55 + 1),
    range(0x3030, 0x3030 + 1),
    range(0x303D, 0x303D + 1),
    range(0x3297, 0x3299 + 1),
)

emoji_ranges = (
    range(0x1F004, 0x1F004 + 1),
    range(0x1F0CF, 0x1F0CF + 1),
    range(0x1F170, 0x1F251 + 1),
    range(0x1F300, 0x1FAFF + 1),
)

common_flags = (
    "AC", "AD", "AE", "AF", "AG", "AI", "AL", "AM", "AO", "AQ", "AR", "AS",
    "AT", "AU", "AW", "AX", "AZ", "BA", "BB", "BD", "BE", "BF", "BG", "BH",
    "BI", "BJ", "BL", "BM", "BN", "BO", "BQ", "BR", "BS", "BT", "BV", "BW",
    "BY", "BZ", "CA", "CC", "CD", "CF", "CG", "CH", "CI", "CK", "CL", "CM",
    "CN", "CO", "CR", "CU", "CV", "CW", "CX", "CY", "CZ", "DE", "DJ", "DK",
    "DM", "DO", "DZ", "EC", "EE", "EG", "EH", "ER", "ES", "ET", "EU", "FI",
    "FJ", "FK", "FM", "FO", "FR", "GA", "GB", "GD", "GE", "GF", "GG", "GH",
    "GI", "GL", "GM", "GN", "GP", "GQ", "GR", "GS", "GT", "GU", "GW", "GY",
    "HK", "HM", "HN", "HR", "HT", "HU", "IC", "ID", "IE", "IL", "IM", "IN",
    "IO", "IQ", "IR", "IS", "IT", "JE", "JM", "JO", "JP", "KE", "KG", "KH",
    "KI", "KM", "KN", "KP", "KR", "KW", "KY", "KZ", "LA", "LB", "LC", "LI",
    "LK", "LR", "LS", "LT", "LU", "LV", "LY", "MA", "MC", "MD", "ME", "MF",
    "MG", "MH", "MK", "ML", "MM", "MN", "MO", "MP", "MQ", "MR", "MS", "MT",
    "MU", "MV", "MW", "MX", "MY", "MZ", "NA", "NC", "NE", "NF", "NG", "NI",
    "NL", "NO", "NP", "NR", "NU", "NZ", "OM", "PA", "PE", "PF", "PG", "PH",
    "PK", "PL", "PM", "PN", "PR", "PS", "PT", "PW", "PY", "QA", "RE", "RO",
    "RS", "RU", "RW", "SA", "SB", "SC", "SD", "SE", "SG", "SH", "SI", "SJ",
    "SK", "SL", "SM", "SN", "SO", "SR", "SS", "ST", "SV", "SX", "SY", "SZ",
    "TA", "TC", "TD", "TF", "TG", "TH", "TJ", "TK", "TL", "TM", "TN", "TO",
    "TR", "TT", "TV", "TW", "TZ", "UA", "UG", "UM", "UN", "US", "UY", "UZ",
    "VA", "VC", "VE", "VG", "VI", "VN", "VU", "WF", "WS", "XK", "YE", "YT",
    "ZA", "ZM", "ZW",
)

manual = {
    "😀": "grinning face smile happy",
    "😃": "grinning face big eyes smile happy",
    "😄": "grinning face smiling eyes smile happy",
    "😁": "beaming face smiling eyes grin happy",
    "😆": "laughing face laugh smile happy",
    "😅": "sweat smile relief nervous",
    "😂": "tears of joy laugh crying funny",
    "🤣": "rolling on floor laughing rofl lol funny",
    "🙂": "slight smile happy",
    "🙃": "upside down face silly",
    "😉": "wink winking face",
    "😊": "smiling eyes blush happy",
    "😇": "halo angel innocent",
    "😍": "heart eyes love crush",
    "😘": "kiss blowing kiss love",
    "😋": "yum tasty savoring food",
    "😛": "tongue silly",
    "😜": "wink tongue silly",
    "🤪": "zany crazy silly",
    "🤔": "thinking hmm",
    "🤨": "raised eyebrow skeptical",
    "😐": "neutral face meh",
    "😑": "expressionless meh",
    "🙄": "rolling eyes annoyed",
    "😴": "sleep sleeping tired",
    "🤤": "drool drooling",
    "😷": "mask sick medical",
    "🤒": "thermometer sick",
    "🤕": "head bandage hurt",
    "🤢": "nauseated sick",
    "🤮": "vomit sick",
    "😭": "cry sob sad tears",
    "😢": "cry sad tear",
    "🥺": "pleading puppy eyes sad",
    "😡": "angry mad rage",
    "🤬": "swearing angry",
    "😱": "scream scared fear",
    "🤯": "mind blown exploding head",
    "🥳": "party celebration birthday",
    "😎": "cool sunglasses",
    "🤓": "nerd geek glasses",
    "🤖": "robot bot",
    "👻": "ghost spooky",
    "💀": "skull dead",
    "☠️": "skull crossbones pirate poison",
    "💩": "poop pile poo",
    "👋": "wave waving hello bye",
    "👍": "thumbs up like yes approve",
    "👎": "thumbs down dislike no",
    "👌": "ok hand perfect",
    "✌️": "victory peace",
    "🤞": "crossed fingers luck",
    "🤘": "rock horns",
    "🙏": "pray please thanks folded hands",
    "👏": "clap applause",
    "🙌": "raise hands celebrate",
    "🤝": "handshake deal",
    "💪": "muscle strong flex",
    "👀": "eyes look watch",
    "🧠": "brain mind smart",
    "👨‍💻": "developer programmer coder man laptop work",
    "👩‍💻": "developer programmer coder woman laptop work",
    "🧑‍💻": "developer programmer coder laptop work",
    "🐶": "dog pet puppy",
    "🐱": "cat pet kitten",
    "🐭": "mouse animal",
    "🐹": "hamster pet",
    "🐰": "rabbit bunny",
    "🦊": "fox animal",
    "🐻": "bear animal",
    "🐼": "panda animal",
    "🐨": "koala animal",
    "🐯": "tiger animal",
    "🦁": "lion animal",
    "🐮": "cow animal",
    "🐷": "pig animal",
    "🐸": "frog animal",
    "🐵": "monkey animal",
    "🐔": "chicken bird",
    "🐧": "penguin bird",
    "🐦": "bird animal",
    "🐤": "chick bird",
    "🦆": "duck bird",
    "🦅": "eagle bird",
    "🦉": "owl bird",
    "🐺": "wolf animal",
    "🐴": "horse animal",
    "🦄": "unicorn animal",
    "🐝": "bee insect",
    "🐛": "bug insect",
    "🦋": "butterfly insect",
    "🐌": "snail animal",
    "🐞": "lady beetle bug insect",
    "🐜": "ant insect",
    "🕷️": "spider insect",
    "🐢": "turtle animal",
    "🐍": "snake animal",
    "🦎": "lizard animal",
    "🦖": "dinosaur trex animal",
    "🐙": "octopus sea",
    "🦑": "squid sea",
    "🦀": "crab sea",
    "🐡": "blowfish fish sea",
    "🐠": "tropical fish sea",
    "🐟": "fish sea",
    "🐬": "dolphin sea",
    "🐳": "whale sea",
    "🦈": "shark sea",
    "❤️": "heart love red",
    "🧡": "heart love orange",
    "💛": "heart love yellow",
    "💚": "heart love green",
    "💙": "heart love blue",
    "💜": "heart love purple",
    "🖤": "heart love black",
    "🤍": "heart love white",
    "🤎": "heart love brown",
    "💔": "broken heart sad love",
    "❣️": "heart exclamation love",
    "💕": "two hearts love",
    "💞": "revolving hearts love",
    "💖": "sparkling heart love",
    "💘": "heart arrow cupid love",
    "⭐": "star favorite",
    "🌟": "glowing star favorite",
    "🌠": "shooting star wish",
    "✨": "sparkles stars magic",
    "✳️": "eight-spoked asterisk star",
    "✴️": "eight-pointed star",
    "❇️": "sparkle star",
    "*️⃣": "keycap asterisk star",
    "🔥": "fire hot lit",
    "💯": "hundred perfect score",
    "✅": "check mark done yes complete",
    "☑️": "checkbox check done yes",
    "✔️": "check mark done yes",
    "❌": "cross mark no wrong cancel x",
    "⚠️": "warning alert",
    "🚫": "prohibited forbidden no",
    "💬": "speech bubble chat message",
    "💭": "thought bubble thinking",
    "☕": "coffee drink cafe",
    "🍵": "tea drink",
    "🍺": "beer drink",
    "🍷": "wine drink",
    "🍕": "pizza food",
    "🍔": "burger hamburger food",
    "🍟": "fries food",
    "🌭": "hot dog food",
    "🌮": "taco food",
    "🌯": "burrito food",
    "🍿": "popcorn food movie",
    "🍰": "cake dessert food",
    "🎂": "birthday cake dessert party",
    "🍪": "cookie dessert food",
    "🍩": "donut doughnut dessert food",
    "🍎": "apple fruit food",
    "🍌": "banana fruit food",
    "🍓": "strawberry fruit food",
    "🍒": "cherries fruit food",
    "🌍": "earth globe world Europe Africa",
    "🌎": "earth globe world Americas",
    "🌏": "earth globe world Asia Australia",
    "🏠": "home house",
    "🏢": "office building work",
    "🏥": "hospital medical",
    "🏫": "school education",
    "🚗": "car automobile vehicle",
    "🚕": "taxi car vehicle",
    "🚌": "bus vehicle",
    "🚓": "police car vehicle",
    "🚑": "ambulance medical vehicle",
    "🚒": "fire engine truck vehicle",
    "🚚": "truck delivery vehicle",
    "🚲": "bike bicycle",
    "✈️": "plane airplane flight travel",
    "🚀": "rocket launch space",
    "🚁": "helicopter vehicle",
    "🚂": "train locomotive",
    "🚇": "metro subway train",
    "⌚": "watch time clock",
    "📱": "phone mobile smartphone",
    "💻": "laptop computer work",
    "🖥️": "desktop computer monitor work",
    "⌨️": "keyboard computer",
    "🖱️": "mouse computer",
    "📷": "camera photo",
    "🎥": "movie camera video",
    "🎧": "headphones music audio",
    "🎤": "microphone mic music audio",
    "🎵": "music note song",
    "🎶": "music notes song",
    "📚": "books reading study",
    "📖": "book reading",
    "📝": "memo note write",
    "📌": "pin pushpin",
    "📎": "paperclip attach",
    "🔒": "lock locked security",
    "🔓": "unlock unlocked security",
    "🔑": "key password",
    "🔨": "hammer tool",
    "🪛": "screwdriver tool",
    "🔧": "wrench tool",
    "🧰": "toolbox tools",
    "💡": "light bulb idea",
    "📈": "chart up graph increase",
    "📉": "chart down graph decrease",
    "📊": "bar chart graph",
    "📅": "calendar date",
    "⏰": "alarm clock time",
    "⚙️": "gear settings config",
    "🎁": "gift present",
    "🎉": "party popper celebration",
    "🎊": "confetti celebration",
    "🏆": "trophy award winner",
    "⚽": "soccer ball football sport",
    "🏀": "basketball sport",
    "🏈": "football sport",
    "⚾": "baseball sport",
    "🎾": "tennis sport",
    "🎮": "game controller gaming",
    "🎲": "dice game",
    "♟️": "chess pawn game",
    "🧩": "puzzle piece game",
    "🎯": "target bullseye goal",
    "🎨": "palette art paint",
    "➡️": "right arrow",
    "⬅️": "left arrow",
    "⬆️": "up arrow",
    "⬇️": "down arrow",
    "©️": "copyright",
    "®️": "registered",
    "™️": "trade mark",
}

seen = set()

def emit(emoji, name):
    if emoji in seen:
        return
    seen.add(emoji)
    print(f"{emoji}\0meta\x1f{name.lower()}", flush=False)

for emoji, name in manual.items():
    emit(emoji, name)

for block in emoji_ranges:
    for cp in block:
        if 0x1F1E6 <= cp <= 0x1F1FF:
            continue
        char = chr(cp)
        try:
            name = unicodedata.name(char)
        except ValueError:
            continue
        emit(char, name)

for block in variation_ranges:
    for cp in block:
        try:
            name = unicodedata.name(chr(cp))
        except ValueError:
            continue
        emit(chr(cp) + "\ufe0f", name)

for code in common_flags:
    flag = "".join(chr(0x1F1E6 + ord(letter) - ord("A")) for letter in code)
    emit(flag, f"flag {code.lower()}")
PY
    return
  fi

  awk -F '\t' '{ print $1 "\0meta\x1f" $2 }' <<'EOF'
😀	grinning face smile happy
😃	grinning face with big eyes happy
😄	grinning face with smiling eyes happy
😁	beaming face with smiling eyes happy
😆	grinning squinting face laugh
😅	grinning face with sweat relief
😂	face with tears of joy laugh
🤣	rolling on the floor laughing
🙂	slightly smiling face
🙃	upside-down face
😉	winking face
😊	smiling face with smiling eyes
😍	smiling face with heart-eyes love
😘	face blowing a kiss
😎	smiling face with sunglasses cool
🥳	partying face celebration
🤔	thinking face
😭	loudly crying face
😡	pouting face
🤯	exploding head
😴	sleeping face
🤖	robot
👋	waving hand
👍	thumbs up
👎	thumbs down
👏	clapping hands
🙏	folded hands please thanks
💪	flexed biceps strong
👀	eyes
👨‍💻	man technologist coding
👩‍💻	woman technologist coding
🧑‍💻	technologist coding
❤️	red heart love
💔	broken heart
💕	two hearts
💯	hundred points
🔥	fire
✨	sparkles
⭐	star
✅	check mark
❌	cross mark
⚠️	warning
💬	speech balloon
☕	hot beverage coffee
🍕	pizza
🍔	hamburger
🍟	french fries
🍰	shortcake
🎂	birthday cake
🍎	red apple
🌍	globe showing Europe-Africa
🏠	house
🚗	automobile car
✈️	airplane
🚀	rocket
💻	laptop
⌨️	keyboard
🎧	headphone
📚	books
📝	memo
📌	pushpin
🔒	locked
🔑	key
🔨	hammer
🪛	screwdriver
🔧	wrench
💡	light bulb
📈	chart increasing
📉	chart decreasing
📅	calendar
⏰	alarm clock
⚙️	gear settings
🎁	wrapped gift
🎉	party popper
🏆	trophy
⚽	soccer ball
🎮	video game
🎲	game die
🎯	direct hit
🎨	artist palette
🇵🇱	flag Poland
🇺🇸	flag United States
🇬🇧	flag United Kingdom
🇪🇺	flag European Union
EOF
}

# for the Quickshell emoji menu (~/.config/quickshell/bar/menus/Emoji.qml): one "<emoji>\t<name>" per line
if [[ "${1:-}" == "--print" ]]; then
  emoji_entries | sed 's/\x00meta\x1f/\t/'
  exit 0
fi

selection="$(
  emoji_entries |
    rofi -dmenu -i -matching normal -p emoji -window-title emoji-rofi -theme "$theme"
)"

[[ -n "$selection" ]] || exit 0

emoji="$selection"
printf '%s' "$emoji" | wl-copy --type text/plain

if command -v ydotool >/dev/null 2>&1; then
  sleep 0.08
  if [[ -S /run/ydotoold/socket ]]; then
    YDOTOOL_SOCKET="${YDOTOOL_SOCKET:-/run/ydotoold/socket}" ydotool key 29:1 47:1 47:0 29:0 || true
  else
    ydotool key 29:1 47:1 47:0 29:0 || true
  fi
elif command -v wtype >/dev/null 2>&1; then
  sleep 0.05
  wtype "$emoji" || true
fi

if command -v notify-send >/dev/null 2>&1; then
  notify-send -a rofi "Emoji" "Copied and pasted $emoji"
fi
