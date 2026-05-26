{ config, lib, pkgs, ... }:

let
  cfg = config.services.ttsMako;

  ttsmakoToggle = pkgs.writeShellApplication {
    name = "ttsmako-toggle";
    runtimeInputs = with pkgs; [ coreutils libnotify ];
    text = ''
      set -euo pipefail

      state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/ttsmako"
      enabled_file="$state_dir/enabled"
      mkdir -p "$state_dir"

      if [ -e "$enabled_file" ] && [ "$(cat "$enabled_file")" = "0" ]; then
        printf '1' > "$enabled_file"
        notify-send 'TTS notifications' 'Enabled'
      else
        printf '0' > "$enabled_file"
        notify-send 'TTS notifications' 'Disabled'
      fi
    '';
  };

  ttsmakoSkip = pkgs.writeShellApplication {
    name = "ttsmako-skip";
    runtimeInputs = with pkgs; [ coreutils findutils gawk procps systemd ];
    text = ''
      set -euo pipefail

      runtime_dir="''${XDG_RUNTIME_DIR:-/tmp}/ttsmako"
      skip_file="$runtime_dir/skip"
      player_pid_file="$runtime_dir/player.pid"
      mkdir -p "$runtime_dir"
      : > "$skip_file"

      if [ -s "$player_pid_file" ]; then
        player_pid="$(cat "$player_pid_file")"
        if [ -n "$player_pid" ] && kill -0 "$player_pid" 2>/dev/null; then
          kill -TERM "$player_pid" 2>/dev/null || true
        fi
      fi

      export DBUS_SESSION_BUS_ADDRESS="''${DBUS_SESSION_BUS_ADDRESS:-unix:path=''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/bus}"
      systemctl --user kill --kill-whom=main --signal=USR1 ttsmako-listen.service 2>/dev/null || true
    '';
  };

  ttsmakoAvrcpWatch = pkgs.writers.writePython3Bin "ttsmako-avrcp-watch" { } ''
    import os
    import pathlib
    import re
    import select
    import struct
    import subprocess
    import time

    device_list = pathlib.Path("/proc/bus/input/devices")
    event_dir = pathlib.Path("/dev/input")
    skip_command = "${lib.getExe ttsmakoSkip}"
    event_format = "llHHI"
    event_size = struct.calcsize(event_format)
    ev_key = 1
    key_press = 1
    media_keys = {
        119, 128, 163, 164, 165, 166, 168, 200, 201, 207, 208,
    }

    def avrcp_event_paths():
        try:
            content = device_list.read_text(encoding="utf-8", errors="replace")
        except OSError:
            return []

        paths = []
        for block in content.strip().split("\n\n"):
            if "(AVRCP)" not in block:
                continue
            match = re.search(r"\b(event\d+)\b", block)
            if match is not None:
                paths.append(event_dir / match.group(1))
        return paths

    def open_devices():
        devices = {}
        for path in avrcp_event_paths():
            try:
                handle = path.open("rb", buffering=0)
            except OSError:
                continue
            devices[handle.fileno()] = (path, handle)
            print(f"watching {path}", flush=True)
        return devices

    def skip():
        env = os.environ.copy()
        env["XDG_RUNTIME_DIR"] = f"/run/user/{os.getuid()}"
        subprocess.run([skip_command], env=env, check=False)

    while True:
        devices = open_devices()
        if not devices:
            time.sleep(2)
            continue

        while devices:
            readable, _, _ = select.select(list(devices), [], [], 2)
            if not readable:
                current_paths = set(avrcp_event_paths())
                watched_paths = {path for path, _handle in devices.values()}
                if current_paths != watched_paths:
                    break
                continue

            for fd in readable:
                path, handle = devices[fd]
                try:
                    data = handle.read(event_size)
                except OSError:
                    data = b""
                if len(data) != event_size:
                    print(f"lost {path}", flush=True)
                    handle.close()
                    devices.pop(fd, None)
                    continue

                _sec, _usec, event_type, code, value = struct.unpack(
                    event_format,
                    data,
                )
                if event_type == ev_key and value == key_press and code in media_keys:
                    print(f"media key code={code}", flush=True)
                    skip()

        for _path, handle in devices.values():
            handle.close()
  '';

  ttsmakoListen = pkgs.writers.writePython3Bin "ttsmako-listen" {
    libraries = pkgs.piper-tts.propagatedBuildInputs;
  } ''
    import codecs
    import datetime
    import fcntl
    import html
    import os
    import pathlib
    import re
    import shutil
    import signal
    import subprocess

    from piper import PiperVoice, SynthesisConfig

    dbus_monitor = "${pkgs.dbus}/bin/dbus-monitor"
    aplay = "${pkgs.alsa-utils}/bin/aplay"
    pwcat = "${pkgs.pipewire}/bin/pw-cat"
    wpctl = "${pkgs.wireplumber}/bin/wpctl"
    notify_member = "interface=org.freedesktop.Notifications; member=Notify"

    polish_words = {
        "a", "aby", "ale", "albo", "bardzo", "bedzie", "bez", "bo", "byc",
        "byla", "bylo", "byly", "chce", "chcesz", "ci", "cie", "co", "cos",
        "czy", "dla", "dlaczego", "do", "dobrze", "gdzie", "go", "ich",
        "jak", "ja", "jego", "jej", "jest", "jesli", "juz", "kiedy", "ktory",
        "ktora", "ktore", "lub", "ma", "mam", "masz", "mial", "miala",
        "mialo", "mi", "mnie", "moj", "moja", "moje", "moze", "na", "nad",
        "nam", "nas", "nie", "nim", "nia", "oraz", "po", "pod", "prosze",
        "przez", "przy", "sa", "sie", "tak", "tam", "tego", "tej", "ten",
        "teraz", "tez", "to", "twoj", "twoja", "twoje", "ty", "w", "we",
        "witam", "z", "za", "ze", "zeby",
    }
    polish_chars = set("ąćęłńóśźżĄĆĘŁŃÓŚŹŻ")
    voice_names = (
        "en_US-kathleen-low.onnx",
        "pl_PL-gosia-medium.onnx",
    )
    staged_models = {}
    voices = {}
    current_player = None
    skip_requested = False
    speaking = False
    synthesis_config = SynthesisConfig(length_scale=0.75, volume=0.3)

    monitor = subprocess.Popen(
        [
            dbus_monitor,
            "--session",
            "interface='org.freedesktop.Notifications',member='Notify'",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        bufsize=1,
    )

    in_notify = False
    strings = []
    state_home = pathlib.Path(
        os.environ.get("XDG_STATE_HOME", pathlib.Path.home() / ".local/state")
    )
    data_home = pathlib.Path(
        os.environ.get("XDG_DATA_HOME", pathlib.Path.home() / ".local/share")
    )
    runtime_home = pathlib.Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp"))
    state_dir = state_home / "ttsmako"
    data_dir = data_home / "ttsmako"
    runtime_dir = runtime_home / "ttsmako"
    enabled_file = state_dir / "enabled"
    log_path = state_dir / "listener.log"
    lock_path = runtime_dir / "queue.lock"
    skip_path = runtime_dir / "skip"
    player_pid_path = runtime_dir / "player.pid"
    runtime_voice_dir = runtime_dir / "voices"
    state_dir.mkdir(parents=True, exist_ok=True)
    runtime_dir.mkdir(parents=True, exist_ok=True)
    runtime_voice_dir.mkdir(parents=True, exist_ok=True)

    def log(message):
        timestamp = datetime.datetime.now().isoformat(timespec="seconds")
        with log_path.open("a", encoding="utf-8") as handle:
            handle.write(f"{timestamp} {message}\n")

    def request_skip(_signum, _frame):
        global skip_requested
        if not speaking:
            return
        skip_requested = True
        if current_player is not None and current_player.poll() is None:
            current_player.terminate()

    signal.signal(signal.SIGUSR1, request_skip)

    def enabled():
        try:
            return enabled_file.read_text(encoding="utf-8") != "0"
        except FileNotFoundError:
            return True

    def skip_pending():
        return skip_requested or skip_path.exists()

    def clear_skip():
        global skip_requested
        skip_requested = False
        try:
            skip_path.unlink()
        except FileNotFoundError:
            pass

    def write_player_pid(player):
        player_pid_path.write_text(str(player.pid), encoding="utf-8")

    def clear_player_pid(player):
        try:
            current_pid = player_pid_path.read_text(encoding="utf-8").strip()
        except FileNotFoundError:
            return
        if current_pid == str(player.pid):
            player_pid_path.unlink()

    def unquote_dbus_string(line):
        line = line.strip()
        if not line.startswith('string "'):
            return None
        value = line[len('string "'):]
        if value.endswith('"'):
            value = value[:-1]
        unescaped = codecs.decode(value, "unicode_escape")
        try:
            return unescaped.encode("latin1").decode("utf-8")
        except (UnicodeEncodeError, UnicodeDecodeError):
            return unescaped

    def strip_text(value):
        value = re.sub(r"<[^>]*>", " ", value)
        value = html.unescape(value)
        value = re.sub(r"https?://\S+", "", value)
        return re.sub(r"\s+", " ", value).strip()

    def prepare_text(summary, body):
        parts = []
        for value in (summary, body):
            cleaned = strip_text(value)
            if cleaned:
                if cleaned[-1] not in ".!?":
                    cleaned = f"{cleaned}."
                parts.append(cleaned)
        return strip_text(" ".join(parts[:2]))

    def detect_lang(text):
        if any(char in polish_chars for char in text):
            return "pl"
        words = re.findall(r"[^\W\d_]+", text.lower(), flags=re.UNICODE)
        pl_hits = sum(1 for word in words if word in polish_words)
        return "pl" if pl_hits >= 2 else "en"

    def piper_model_for(lang):
        if lang == "pl":
            return data_dir / "voices/pl_PL-gosia-medium.onnx"
        return data_dir / "voices/en_US-kathleen-low.onnx"

    def stage_voice(source_model):
        if source_model.name in staged_models:
            return staged_models[source_model.name]
        source_config = pathlib.Path(f"{source_model}.json")
        if not source_model.is_file() or not source_config.is_file():
            return None
        staged_model = runtime_voice_dir / source_model.name
        staged_config = pathlib.Path(f"{staged_model}.json")
        for source, staged in (
            (source_model, staged_model),
            (source_config, staged_config),
        ):
            needs_copy = True
            if staged.exists():
                source_stat = source.stat()
                staged_stat = staged.stat()
                needs_copy = (
                    source_stat.st_size != staged_stat.st_size
                    or source_stat.st_mtime_ns != staged_stat.st_mtime_ns
                )
            if needs_copy:
                shutil.copy2(source, staged)
        staged_models[source_model.name] = staged_model
        return staged_model

    def preload_voices():
        source_dir = data_dir / "voices"
        for voice_name in voice_names:
            staged_model = stage_voice(source_dir / voice_name)
            if staged_model is not None:
                voices[voice_name] = PiperVoice.load(staged_model)

    def sink_ids():
        try:
            status = subprocess.run(
                [wpctl, "status"],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                check=False,
            ).stdout
        except OSError:
            return []
        in_sinks = False
        ids = []
        for line in status.splitlines():
            if "Sinks:" in line:
                in_sinks = True
                continue
            if in_sinks and any(
                section in line
                for section in ("Sources:", "Filters:", "Streams:", "Video")
            ):
                break
            if in_sinks:
                match = re.search(r"(\d+)\.", line)
                if match is not None:
                    ids.append(match.group(1))
        return ids

    def headset_target():
        for sink_id in sink_ids():
            try:
                inspect = subprocess.run(
                    [wpctl, "inspect", sink_id],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.DEVNULL,
                    text=True,
                    check=False,
                ).stdout
            except OSError:
                continue
            if "headset" in inspect.lower():
                return sink_id
        return None

    def playback_command(sample_rate, target=None):
        command = [
            pwcat, "--playback", "--raw", "--format", "s16",
            "--rate", str(sample_rate), "--channels", "1",
        ]
        if target is not None:
            command.extend(["--target", target])
        return command

    def run_player(command, audio_chunks):
        global current_player
        player = subprocess.Popen(
            command,
            stdin=subprocess.PIPE,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        current_player = player
        write_player_pid(player)
        try:
            if player.stdin is not None:
                for chunk in audio_chunks:
                    if skip_pending():
                        player.terminate()
                        break
                    player.stdin.write(chunk)
                player.stdin.close()
        except BrokenPipeError:
            pass
        try:
            return player.wait() == 0 and not skip_pending()
        finally:
            if current_player is player:
                current_player = None
            clear_player_pid(player)

    def play_pipewire(audio_chunks, sample_rate, target=None):
        return run_player(playback_command(sample_rate, target), audio_chunks)

    def play_alsa(audio_chunks, sample_rate):
        return run_player(
            [aplay, "-q", "-t", "raw", "-f", "S16_LE", "-r", str(sample_rate), "-c", "1"],
            audio_chunks,
        )

    def play_audio(audio_chunks, sample_rate):
        target = headset_target()
        if target is not None and play_pipewire(audio_chunks, sample_rate, target):
            return True
        if skip_pending():
            return False
        if play_pipewire(audio_chunks, sample_rate):
            return True
        if skip_pending():
            return False
        return play_alsa(audio_chunks, sample_rate)

    def speak_piper(text, model):
        global speaking
        model = stage_voice(model)
        if model is None:
            return False
        voice = voices.get(model.name)
        if voice is None:
            voice = PiperVoice.load(model)
            voices[model.name] = voice
        clear_skip()
        speaking = True
        try:
            audio_chunks = [
                chunk.audio_int16_bytes
                for chunk in voice.synthesize(text, syn_config=synthesis_config)
                if not skip_pending()
            ]
            if skip_pending():
                return True
            sample_rate = voice.config.sample_rate
            played = play_audio(audio_chunks, sample_rate)
            return True if skip_pending() else played
        finally:
            speaking = False
            clear_skip()

    def speak(text):
        lang = detect_lang(text)
        if speak_piper(text, piper_model_for(lang)):
            return
        log(f"missing voice for lang={lang}")

    preload_voices()

    try:
        for line in monitor.stdout:
            if notify_member in line:
                in_notify = True
                strings = []
                continue
            if not in_notify:
                continue
            value = unquote_dbus_string(line)
            if value is None:
                continue
            strings.append(value)
            if len(strings) >= 4:
                summary = strings[2]
                body = strings[3]
                text = prepare_text(summary, body)
                if text and enabled():
                    with lock_path.open("w") as lock_file:
                        fcntl.flock(lock_file, fcntl.LOCK_EX)
                        speak(text)
                in_notify = False
                strings = []
    finally:
        monitor.terminate()
  '';

  ttsmakoInstallVoices = pkgs.writeShellApplication {
    name = "ttsmako-install-voices";
    runtimeInputs = with pkgs; [ coreutils curl ];
    text = ''
      set -euo pipefail

      voice_dir="''${XDG_DATA_HOME:-$HOME/.local/share}/ttsmako/voices"
      mkdir -p "$voice_dir"

      fetch_voice() {
        base_url="$1"
        name="$2"
        curl -L --fail --output "$voice_dir/$name.onnx" "$base_url/$name.onnx"
        curl -L --fail --output "$voice_dir/$name.onnx.json" "$base_url/$name.onnx.json"
      }

      fetch_voice \
        "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/kathleen/low" \
        "en_US-kathleen-low"

      fetch_voice \
        "https://huggingface.co/rhasspy/piper-voices/resolve/main/pl/pl_PL/gosia/medium" \
        "pl_PL-gosia-medium"

      printf 'Installed Piper voices in %s\n' "$voice_dir"
    '';
  };
in
{
  options.services.ttsMako = {
    enable = lib.mkEnableOption "TTS reader for mako notifications";
    avrcpUser = lib.mkOption {
      type = lib.types.str;
      default = "iczo";
      description = "User that runs the AVRCP headset key watcher.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.libnotify
      pkgs.piper-tts
      ttsmakoAvrcpWatch
      ttsmakoInstallVoices
      ttsmakoListen
      ttsmakoSkip
      ttsmakoToggle
    ];

    systemd.user.services.ttsmako-listen = {
      description = "TTS reader for mako notifications";
      wantedBy = [ "default.target" ];
      after = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = "${lib.getExe ttsmakoListen}";
        Restart = "on-failure";
        RestartSec = 2;
      };
    };

    systemd.services.ttsmako-avrcp-watch = {
      description = "AVRCP headset media key bridge for TTS notifications";
      wantedBy = [ "multi-user.target" ];
      after = [ "bluetooth.service" "systemd-logind.service" ];
      serviceConfig = {
        ExecStart = "${lib.getExe ttsmakoAvrcpWatch}";
        User = cfg.avrcpUser;
        SupplementaryGroups = [ "input" ];
        Restart = "always";
        RestartSec = 2;
      };
    };
  };
}
