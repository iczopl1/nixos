# NixOS Configuration

This repository contains my personal NixOS configuration.

## Keybindings (Hyprland)

The main modifier key (`$mainMod`) is set to the **SUPER (Windows) key**.

| Keybinding          | Action                                   | Notes                                         |
| :------------------ | :--------------------------------------- | :-------------------------------------------- |
| `$mainMod + Q`      | Kill active window                       |                                               |
| `$mainMod + M`      | Lock screen                              | Executes `$lock` (hyprlock)                   |
| `$mainMod + E`      | File manager                             | Executes `$fileManager` (thunar .)            |
| `$mainMod + W`      | Terminal                                 | Executes `$terminal` (alacritty)              |
| `$mainMod + X`      | Web Browser                              | Executes `$web` (brave)                       |
| `SUPER_L`           | Application Menu                         | Executes `$menu` (rofi)                       |
| `$mainMod + SHIFT + S` | Screenshot (selection)                   | Executes `$ss` (grim -g "$(slurp)" - | wl-copy) |
| `$mainMod + V`      | Clipboard history                        | Executes `$clip` (cliphist)                   |
| `$mainMod + F3`     | Toggle Wayscriber                        | Executes `$scriber`                           |
| `$mainMod + F10`    | Switch random wallpaper                  |                                               |
| `$mainMod + F11`    | Toggle Waybar                            |                                               |
| `$mainMod + F12`    | Toggle BGM Power Monitor                 |                                               |
| `$mainMod + O`      | Toggle Wvkbd (virtual keyboard)          |                                               |
| `$mainMod + INSERT` | Skip BGM Power Monitor                   |                                               |
| `$mainMod + T`      | Toggle floating mode for active window   |                                               |
| `$mainMod + P`      | Toggle pseudo mode (dwindle layout)      |                                               |
| `$mainMod + U`      | Toggle split (dwindle layout)            |                                               |
| `$mainMod + F`      | Toggle fullscreen for active window      |                                               |
| `$mainMod + J/L/I/K`| Move focus (left/right/up/down)          |                                               |
| `$mainMod + CTRL + L/J/I/K`| Resize active window (right/left/up/down) |                                               |
| `$mainMod + SHIFT + L/J/K/I`| Move window (right/left/down/up)       | **Already configured**                        |
| `$mainMod + 1-10`   | Switch to workspace 1-10                 |                                               |
| `$mainMod + A`      | Switch to previous workspace             | Equivalent to `e-1`                           |
| `$mainMod + S`      | Switch to next workspace                 | Equivalent to `e+1`                           |
| `$mainMod + SHIFT + 1-10`| Move active window to workspace 1-10     |                                               |
| `$mainMod + mouse:272`| Move window (drag with left mouse button) |                                               |
| `$mainMod + mouse:273`| Resize window (drag with right mouse button) |                                               |
| `XF86AudioRaiseVolume`| Increase volume                          |                                               |
| `XF86AudioLowerVolume`| Decrease volume                          |                                               |
| `XF86AudioMute`     | Mute/unmute volume                       |                                               |
| `XF86AudioMicMute`  | Mute/unmute microphone                   |                                               |
| `XF86MonBrightnessUp`| Increase bri

## Key Configuration Details

### Global Packages and Libraries (`hosts/laptop/configuration.nix`)
The following global packages and runtime libraries have been configured:
-   **`python311`**: Python 3.11 for general use.
-   **`gcc`**: The GNU Compiler Collection.
-   **`runtimeLibs`**: A collection of essential runtime libraries including `stdenv.cc.cc.lib`, `zlib`, `glib`, `dbus`, `fontconfig`, `freetype`, `libGL`, various `xorg` components (e.g., `libX11`, `libXext`, `libXrender`, `libxcb` utilities), `libxkbcommon`, and `wayland`. These are included in `environment.systemPackages`.

### Environment Variables
-   **`LD_LIBRARY_PATH`**: Configured via `environment.extraInit` to ensure necessary libraries are found at runtime.
-   **`QT_QPA_PLATFORM`**: Set to `"offscreen"` via `environment.sessionVariables`.

## Important Note for AI Tools / Automated Agents

**Under no circumstances are AI tools or automated agents permitted to execute the following commands:**

-   `git commit`
-   `git push`
-   `nixos-rebuild switch`

These commands modify the system's state or version control history and must only be run by a human user to prevent accidental system disruption or unintended changes.
