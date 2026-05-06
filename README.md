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
| `$mainMod + SHIFT + S` | Screenshot (selection)                   | Executes `$ss` (grim -g "$(slurp)" - \| wl-copy) |
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
| `XF86MonBrightnessUp`| Increase brightness                      |                                               |
| `XF86MonBrightnessDown`| Decrease brightness                      |                                               |
| `$mainMod + DELETE` | Submap for cleaning up (resets with `$mainMod + DELETE`) |                                               |
| `$mainMod + F2`     | Zoom in                                  |                                               |
| `$mainMod + F1`     | Zoom out                                 |                                               |
| `Lid Switch`        | Lock screen when lid closes              | Executes `hyprlock`                           |

## Shell Aliases and Functions (Bash)

These are configured in `home.nix` under `programs.bash`.

### Aliases
- `ll`: `ls -alF` (long listing, show all, add file type indicator)
- `la`: `ls -A` (list all but omit . and ..)
- `l`: `ls -CF` (columnar listing, add file type indicator)
- `s`: `git status` (show git status)
- `g`: `gemini` (run gemini command)
- `n`: `nvim` (launch nvim editor)
- `h`: `cd ~` (navigate to home directory)

### Functions
- `z`: Integrated with `zoxide` for fast directory jumping.
- `uu`: Navigate up multiple directories. Usage: `uu` (up 1), `uu 2` (up 2), etc.

## Waybar Configuration

- **Nerd Fonts:** Waybar now uses "JetBrainsMono Nerd Font" as its primary font, with fallbacks to "Fira Sans Semibold", "Font Awesome 4 Free", FontAwesome, Roboto, Helvetica, Arial, sans-serif.
