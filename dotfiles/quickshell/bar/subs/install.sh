#!/usr/bin/env bash
# Builds bar-subs.xpi (the add-on) next to this script and copies it to
# ~/Downloads, where the browser's file picker can reach it.
set -euo pipefail

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
rm -f "$here/bar-subs.xpi"
(cd "$here/extension" && zip -q -r "$here/bar-subs.xpi" manifest.json background.js content.js)
mkdir -p "$HOME/Downloads"
command cp -f "$here/bar-subs.xpi" "$HOME/Downloads/bar-subs.xpi"
echo "add-on: $HOME/Downloads/bar-subs.xpi"
