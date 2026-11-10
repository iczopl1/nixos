#!/usr/bin/env bash
set -euo pipefail

choice="$(
  cat <<'EMOJI' | rofi -dmenu -i -p emoji -theme ~/.config/rofi/rofi2.rosi
😀 grinning face
😂 face with tears of joy
🤣 rolling on the floor laughing
🙂 slight smile
😉 wink
😍 heart eyes
😘 kiss
😎 sunglasses
🤔 thinking
😐 neutral
🙃 upside down
😭 loudly crying
😤 triumph
😴 sleeping
🤯 mind blown
🥳 party
👍 thumbs up
👎 thumbs down
👏 clapping
🙏 folded hands
💪 flexed biceps
👌 ok hand
🤝 handshake
❤️ red heart
💜 purple heart
🔥 fire
✨ sparkles
⭐ star
✅ check
❌ cross
⚠️ warning
💡 light bulb
📌 pin
📎 paperclip
📅 calendar
⏰ alarm clock
💻 laptop
⌨️ keyboard
🖱️ mouse
🎧 headphones
🎵 music
🚀 rocket
🐧 linux
☕ coffee
🍕 pizza
EMOJI
)"

[ -n "$choice" ] || exit 0
emoji="$(printf '%s' "$choice" | awk '{print $1}')"
printf '%s' "$emoji" | wl-copy
notify-send "Emoji copied" "$emoji"
