#!/usr/bin/env bash
# fzf control menu for a robot, run inside a terminal by the custom/unitree on-click.
# Usage: robot-menu.sh <tailnet-name> <ssh-host>   e.g. robot-menu.sh unitree-g1 robot1-ssh
set -u

name="$1" host="$2"
UNIT=voice-agent-client.service
PORT=8844

# Full MagicDNS name (unitree-g1.tailXXXX.ts.net) from tailscaled; bare name if it can't say.
dns_name() {
  tailscale status --json 2>/dev/null | python3 -c '
import json, sys
d = json.load(sys.stdin)
for p in (d.get("Peer") or {}).values():
    dns = (p.get("DNSName") or "").rstrip(".")
    if dns.split(".")[0] == sys.argv[1]:
        print(dns); sys.exit()
sfx = d.get("MagicDNSSuffix")
print(f"{sys.argv[1]}.{sfx}" if sfx else sys.argv[1])
' "$name" 2>/dev/null || echo "$name"
}

pause() { read -rsn1 -p $'\npress any key to return to the menu'; }

while :; do
  choice=$(printf '%s\n' \
    "shell        ssh $host" \
    "web          open https://$name:$PORT" \
    "agent-tui    ssh $host, run agent-tui" \
    "start agent  systemctl --user start $UNIT" \
    "files        ~ over sftp in thunar" |
    fzf --prompt="$name ($host) > " --height=100% --layout=reverse --no-multi --cycle) || exit 0

  case "$choice" in
    shell*) exec ssh -t "$host" 'bash --rcfile ~/.msbashrc -i' ;;
    web*)
      url="https://$(dns_name):$PORT"
      setsid -f xdg-open "$url" >/dev/null 2>&1
      exit 0 ;;
    # --rcfile: read ~/.msbashrc on the robot instead of ~/.bashrc (defines agent-tui)
    agent-tui*) exec ssh -t "$host" 'bash --rcfile ~/.msbashrc -ic agent-tui' ;;
    start*)
      echo "starting $UNIT on $host..."
      ssh "$host" "
        if ! systemctl --user cat $UNIT >/dev/null 2>&1; then
          echo '$UNIT is not installed: open agent-tui once and use Client -> Start'; exit 1
        fi
        systemctl --user start $UNIT && sleep 2
        systemctl --user --no-pager --lines=5 status $UNIT"
      pause ;;
    # gvfs runs plain ssh, so the ~/.ssh/config alias (user, key) applies
    files*)
      user=$(ssh -G "$host" | awk '/^user /{print $2}')
      setsid -f thunar "sftp://$host/home/$user" >/dev/null 2>&1
      exit 0 ;;
  esac
done
