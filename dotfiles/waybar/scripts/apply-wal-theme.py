#!/usr/bin/env python3

from __future__ import annotations

import colorsys
import pathlib
import re
import sys
import tomllib


ROOT = pathlib.Path(__file__).resolve().parent.parent
TEMPLATE = ROOT / "colors-template.css"
OUTPUT = ROOT / "colors.css"
CONFIG = ROOT / "theme.toml"
WAL_COLORS = pathlib.Path.home() / ".cache" / "wal" / "colors.sh"

TEMPLATE_RE = re.compile(r"@define-color\s+([\w-]+)\s+(#[0-9A-Fa-f]{6});")
WAL_RE = re.compile(r"^(background|foreground|color(?:[0-9]|1[0-5]))='(#[0-9A-Fa-f]{6})'$")

BACKGROUND_GROUP = {
    "base",
    "mantle",
    "crust",
    "surface0",
    "surface1",
    "surface2",
    "overlay0",
    "overlay1",
    "overlay2",
}
FOREGROUND_GROUP = {
    "text",
    "subtext0",
    "subtext1",
    "lavender",
    "sapphire",
    "teal",
    "yellow",
    "peach",
    "red",
    "mauve",
    "pink",
    "rosewater",
}
ACCENT_GROUP = {
    "blue",
    "sky",
    "green",
    "maroon",
    "flamingo",
}
GRADIENT_NAMES = [
    "grad-red",
    "grad-orange",
    "grad-yellow",
    "grad-green",
    "grad-cyan",
    "grad-blue",
    "grad-indigo",
    "grad-purple",
]
FLOW_NAMES = [f"flow-{index}" for index in range(1, 13)]
DEFAULT_CONFIG = {
    "background": 0.32,
    "text": 0.96,
    "gradient": 0.78,
}
DEFAULT_GRADIENT_CONFIG = {
    "min_complement_distance": 0.22,
}


def hex_to_rgb(value: str) -> tuple[float, float, float]:
    value = value.lstrip("#")
    return (
        int(value[0:2], 16) / 255.0,
        int(value[2:4], 16) / 255.0,
        int(value[4:6], 16) / 255.0,
    )


def rgb_to_hex(rgb: tuple[float, float, float]) -> str:
    r, g, b = rgb
    return "#{:02x}{:02x}{:02x}".format(round(r * 255), round(g * 255), round(b * 255))


def hex_to_hsv(value: str) -> tuple[float, float, float]:
    return colorsys.rgb_to_hsv(*hex_to_rgb(value))


def hsv_to_hex(hue: float, sat: float, val: float) -> str:
    rgb = colorsys.hsv_to_rgb(hue % 1.0, min(max(sat, 0.0), 1.0), min(max(val, 0.0), 1.0))
    return rgb_to_hex(rgb)


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def mix_rgb(left: tuple[float, float, float], right: tuple[float, float, float], t: float) -> tuple[float, float, float]:
    return (
        lerp(left[0], right[0], t),
        lerp(left[1], right[1], t),
        lerp(left[2], right[2], t),
    )


def lighten(hex_value: str, amount: float) -> str:
    h, s, v = hex_to_hsv(hex_value)
    return hsv_to_hex(h, s, lerp(v, 1.0, amount))


def darken(hex_value: str, amount: float) -> str:
    h, s, v = hex_to_hsv(hex_value)
    return hsv_to_hex(h, s, v * (1.0 - amount))


def set_value(hex_value: str, target_value: float) -> str:
    h, s, _v = hex_to_hsv(hex_value)
    return hsv_to_hex(h, s, target_value)


def raise_value_floor(hex_value: str, floor_value: float) -> str:
    h, s, v = hex_to_hsv(hex_value)
    return hsv_to_hex(h, s, max(v, floor_value))


def clamp01(value: float) -> float:
    return min(max(value, 0.0), 1.0)


def tint_toward(hex_value: str, target_hex: str, amount: float) -> str:
    rgb = mix_rgb(hex_to_rgb(hex_value), hex_to_rgb(target_hex), amount)
    return rgb_to_hex(rgb)


def rotate_group(
    target: dict[str, str],
    template_hsv: dict[str, tuple[float, float, float]],
    names: set[str],
    anchor_name: str,
    new_anchor_hue: float,
) -> None:
    template_anchor_hue = template_hsv[anchor_name][0]
    rotation = new_anchor_hue - template_anchor_hue
    for name in names:
        hue, sat, val = template_hsv[name]
        target[name] = hsv_to_hex(hue + rotation, sat, val)


def read_template() -> tuple[list[str], dict[str, str]]:
    text = TEMPLATE.read_text()
    entries = TEMPLATE_RE.findall(text)
    if not entries:
        raise RuntimeError(f"no colors found in {TEMPLATE}")
    order = [name for name, _ in entries]
    return order, dict(entries)


def read_wal() -> dict[str, str]:
    colors: dict[str, str] = {}
    for line in WAL_COLORS.read_text().splitlines():
        match = WAL_RE.match(line.strip())
        if match:
            colors[match.group(1)] = match.group(2)
    required = {"background", "foreground", "color1", "color2", "color3", "color4", "color5", "color6"}
    missing = required.difference(colors)
    if missing:
        raise RuntimeError(f"missing wal colors: {', '.join(sorted(missing))}")
    return colors


def read_config() -> dict[str, float]:
    config = dict(DEFAULT_CONFIG)
    gradient_config = dict(DEFAULT_GRADIENT_CONFIG)
    if not CONFIG.exists():
        return {**config, **gradient_config}

    data = tomllib.loads(CONFIG.read_text())
    brightness = data.get("brightness", {})
    for key in DEFAULT_CONFIG:
        value = brightness.get(key)
        if isinstance(value, (int, float)):
            config[key] = clamp01(float(value))
    gradient = data.get("gradient", {})
    for key in DEFAULT_GRADIENT_CONFIG:
        value = gradient.get(key)
        if isinstance(value, (int, float)):
            gradient_config[key] = clamp01(float(value))
    return {**config, **gradient_config}


def score_color(hex_value: str) -> float:
    hue, sat, val = hex_to_hsv(hex_value)
    return sat * 1.5 + val * 0.5 + hue * 0.05


def hue_distance(a: str, b: str) -> float:
    ah = hex_to_hsv(a)[0]
    bh = hex_to_hsv(b)[0]
    distance = abs(ah - bh)
    return min(distance, 1.0 - distance)


def complementary_hex(hex_value: str) -> str:
    hue, sat, val = hex_to_hsv(hex_value)
    return hsv_to_hex(hue + 0.5, sat, val)


def select_primary_accent(accents: list[str]) -> str:
    return max(accents, key=score_color)


def select_gradient_anchors(wal_colors: dict[str, str], min_complement_distance: float) -> tuple[str, str]:
    accents = [wal_colors[f"color{i}"] for i in range(1, 7)]
    primary = select_primary_accent(accents)
    best_match = None
    best_distance_error = float("inf")
    best_match_score = -1.0

    for accent in accents:
        if accent == primary:
            continue
        distance = hue_distance(primary, accent)
        distance_error = abs(0.5 - distance)
        accent_score = score_color(accent)
        if distance_error < best_distance_error or (
            distance_error == best_distance_error and accent_score > best_match_score
        ):
            best_match = accent
            best_distance_error = distance_error
            best_match_score = accent_score

    if best_match is not None and hue_distance(primary, best_match) >= min_complement_distance:
        return primary, best_match
    return primary, complementary_hex(primary)


def generate_flow(start_hex: str, end_hex: str, count: int) -> list[str]:
    start_rgb = hex_to_rgb(start_hex)
    end_rgb = hex_to_rgb(end_hex)
    return [rgb_to_hex(mix_rgb(start_rgb, end_rgb, index / (count - 1))) for index in range(count)]


def main() -> int:
    if not TEMPLATE.exists():
        print(f"missing template: {TEMPLATE}", file=sys.stderr)
        return 1
    if not WAL_COLORS.exists():
        print(f"missing wal cache: {WAL_COLORS}", file=sys.stderr)
        return 1

    order, template_colors = read_template()
    wal_colors = read_wal()
    config = read_config()
    template_hsv = {name: hex_to_hsv(value) for name, value in template_colors.items()}

    generated = dict(template_colors)

    background_hue = hex_to_hsv(wal_colors["background"])[0]
    foreground_hue = hex_to_hsv(wal_colors["foreground"])[0]
    accent_hue = hex_to_hsv(wal_colors["color4"])[0]

    rotate_group(generated, template_hsv, BACKGROUND_GROUP, "base", background_hue)
    rotate_group(generated, template_hsv, FOREGROUND_GROUP, "text", foreground_hue)
    rotate_group(generated, template_hsv, ACCENT_GROUP, "overlay2", accent_hue)

    flow_start, flow_end = select_gradient_anchors(wal_colors, config["min_complement_distance"])
    flow_start = set_value(flow_start, config["gradient"])
    flow_end = set_value(flow_end, config["gradient"])
    flow_palette = generate_flow(flow_start, flow_end, len(FLOW_NAMES))
    grad_palette = generate_flow(flow_start, flow_end, len(GRADIENT_NAMES))

    for name, value in zip(GRADIENT_NAMES, grad_palette):
        generated[name] = value
    for name, value in zip(FLOW_NAMES, flow_palette):
        generated[name] = value

    base_background = set_value(raise_value_floor(wal_colors["background"], config["background"]), config["background"])
    bright_foreground = set_value(raise_value_floor(wal_colors["foreground"], config["text"]), config["text"])

    generated["base"] = base_background
    generated["text"] = bright_foreground
    generated["subtext0"] = bright_foreground
    generated["subtext1"] = bright_foreground
    generated["lavender"] = bright_foreground
    generated["sapphire"] = bright_foreground
    generated["teal"] = bright_foreground
    generated["yellow"] = bright_foreground
    generated["peach"] = bright_foreground
    generated["red"] = bright_foreground
    generated["mauve"] = bright_foreground
    generated["pink"] = bright_foreground
    generated["rosewater"] = bright_foreground

    generated["surface0"] = tint_toward(base_background, flow_start, 0.46)
    generated["surface1"] = tint_toward(base_background, flow_end, 0.54)
    generated["surface2"] = tint_toward(base_background, flow_palette[len(flow_palette) // 2], 0.5)
    generated["overlay0"] = tint_toward(generated["surface2"], wal_colors["foreground"], 0.18)
    generated["overlay1"] = tint_toward(generated["surface1"], bright_foreground, 0.28)
    generated["overlay2"] = tint_toward(generated["surface0"], bright_foreground, 0.4)
    generated["blue"] = flow_palette[7]
    generated["sky"] = flow_palette[6]
    generated["green"] = flow_palette[4]
    generated["maroon"] = flow_palette[2]
    generated["flamingo"] = flow_palette[9]
    generated["mantle"] = tint_toward(base_background, bright_foreground, 0.52)
    generated["crust"] = tint_toward(base_background, flow_palette[8], 0.45)

    # Light mode (autobright-theme): the state file says "light", so write the light
    # palette in this one pass. Writing dark first would flash on the bar.
    state = pathlib.Path.home() / ".local" / "state" / "autobright" / "theme"
    if state.exists() and state.read_text().strip() == "light":
        light = {
            "base": "#f6f1e7", "mantle": "#ebe4d4", "crust": "#ded6c4",
            "text": "#2a2a2e", "subtext0": "#4a4a50", "subtext1": "#3a3a40",
            "surface0": "#e4ddcf", "surface1": "#d8d0bf", "surface2": "#cdc4b1",
            "overlay0": "#9a937f", "overlay1": "#7d7766", "overlay2": "#5f5a4c",
            "blue": "#1a5fb4", "sky": "#1a8d9c", "green": "#2e7d32",
            "maroon": "#8a3b2e", "flamingo": "#8e3ba8",
        }
        for name in ("lavender", "sapphire", "teal", "yellow", "peach", "red", "mauve", "pink", "rosewater"):
            light[name] = "#2a2a2e"
        generated.update(light)
        for name in GRADIENT_NAMES + FLOW_NAMES:
            r, g, b = hex_to_rgb(generated[name])
            generated[name] = rgb_to_hex((r * 0.6, g * 0.6, b * 0.6))

    lines = [
        "/* Auto-generated by scripts/apply-wal-theme.py. */",
        "/* Edit colors-template.css to change preserved background/text value structure. */",
        "",
    ]
    for name in order:
        lines.append(f"@define-color {name} {generated[name]};")
    lines.append("")
    for name in FLOW_NAMES:
        lines.append(f"@define-color {name} {generated[name]};")
    lines.append("")
    tmp = OUTPUT.with_suffix(".css.tmp")
    tmp.write_text("\n".join(lines))
    tmp.replace(OUTPUT)   # one atomic swap, so the bar never sees a half file
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
