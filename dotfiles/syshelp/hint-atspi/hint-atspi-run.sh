#!/usr/bin/env bash
# Dev wrapper: same env the Nix package sets. Usage: hint-atspi-run.sh
. "$(dirname "$(readlink -f "$0")")/env.sh"
exec "$PY" -I "$(dirname "$(readlink -f "$0")")/hint-atspi.py" "$@"
