# NixOS Configuration

This repository contains my personal NixOS configuration.

## Keybindings

### Hyprland

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
| `$mainMod + SHIFT + 0`  | Move active window to workspace 10       |
| `$mainMod + SHIFT + CTRL + R` | Move active window to next empty workspace |
| `$mainMod + ALT + L`  | Toggle dynamic 80/20 window layout       |
| `$mainMod + mouse:272`| Move window (drag with left mouse button) |                                               |
| `$mainMod + mouse:273`| Resize window (drag with right mouse button) |                                               |
| `XF86AudioRaiseVolume`| Increase volume                          |                                               |
| `XF86AudioLowerVolume`| Decrease volume                          |                                               |
| `XF86AudioMute`     | Mute/unmute volume                       |                                               |
| `XF86AudioMicMute`  | Mute/unmute microphone                   |                                               |
| `XF86MonBrightnessUp`| Increase brightness
| `XF86MonBrightnessDown`| Decrease brightness

### Neovim

These are custom keybindings defined in `dotfiles/nvim/lua/mappings.lua`:

| Keybinding          | Action                                   | Notes                                         |
| :------------------ | :--------------------------------------- | :-------------------------------------------- |
| `<mouse>`           | No operation                             | Disabled mouse in certain modes               |
| `;` (Normal mode)   | Enter command mode (`:`)                 |                                               |
| `jk` (Insert mode)  | Escape                                   |                                               |
| `<PageUp>`          | No operation                             | Disabled in certain modes                     |
| `<PageDown>`        | No operation                             | Disabled in certain modes                     |
| `<C-s>`             | Save (commented out)                     |                                               |

## Aliases

These aliases and functions are defined in `home.nix` under `programs.bash.shellAliases` and `initExtra`.

### Aliases

| Alias             | Command                                                                                                      | Description                                     |
| :---------------- | :----------------------------------------------------------------------------------------------------------- | :---------------------------------------------- |
| `update`          | `sudo nixos-rebuild switch --flake /home/iczo/git/nixos#ThinkPadNIX`                                         | Update NixOS system                             |
| `update-test`     | `sudo nixos-rebuild test --flake /home/iczo/git/nixos#ThinkPadNIX`                                           | Test NixOS configuration                        |
| `update-build`    | `nix --extra-experimental-features nix-command --extra-experimental-features flakes build /home/iczo/git/nixos#nixosConfigurations.ThinkPadNIX.config.system.build.toplevel` | Build NixOS system                              |
| `ls`              | `ls --color=auto`                                                                                            | List directory contents with color              |
| `ll`              | `ls -alF --color=auto`                                                                                       | List directory contents in long format          |
| `la`              | `ls -A --color=auto`                                                                                         | List all files including hidden                 |
| `l`               | `ls -CF --color=auto`                                                                                        | List directory contents in column format        |
| `..`              | `cd ..`                                                                                                      | Change to parent directory                      |
| `...`             | `cd ../..`                                                                                                   | Change to grand-parent directory                |
| `home`            | `cd ~`                                                                                                       | Change to home directory                        |
| `s`               | `git status --short`                                                                                         | Git status (short format)                       |
| `gs`              | `git status --short`                                                                                         | Git status (short format)                       |
| `ga`              | `git add`                                                                                                    | Git add                                         |
| `gaa`             | `git add --all`                                                                                              | Git add all                                     |
| `gc`              | `git commit`                                                                                                 | Git commit                                      |
| `gcm`             | `git commit -m`                                                                                              | Git commit with message                         |
| `gd`              | `git diff`                                                                                                   | Git diff                                        |
| `gl`              | `git log --oneline --graph --decorate -20`                                                                   | Git log (pretty format, last 20 commits)        |
| `gp`              | `git push`                                                                                                   | Git push                                        |
| `gpl`             | `git pull --ff-only`                                                                                         | Git pull (fast-forward only)                    |
| `gsw`             | `git switch`                                                                                                 | Git switch branch                               |
| `gb`              | `git branch`                                                                                                 | Git branch                                      |
| `n`               | `nvim`                                                                                                       | Alias for Neovim                                |
| `py`              | `python3`                                                                                                    | Alias for python3                               |
| `venv`            | `python3 -m venv .venv`                                                                                      | Create a Python virtual environment             |
| `va`              | `source .venv/bin/activate`                                                                                  | Activate Python virtual environment             |
| `pipup`           | `python3 -m pip install --upgrade pip`                                                                       | Upgrade pip                                     |
| `p7`              | `7z`                                                                                                         | Alias for 7-zip                                 |
| `7zl`             | `7z l`                                                                                                       | List contents of 7-zip archive                  |
| `7zx`             | `7z x`                                                                                                       | Extract 7-zip archive                           |
| `7za`             | `7z a`                                                                                                       | Add files to 7-zip archive                      |
| `th`              | `thunar . >/dev/null 2>&1 &`                                                                                 | Open Thunar file manager in current directory   |
| `h`               | `_histpick`                                                                                                  | Run `_histpick` function (interactive history)  |
| `hist`            | `history`                                                                                                    | Show command history                            |

## Configuration Details

### Python

Python is configured in `modules/programs/python.nix`.

The default interpreter is `python311` with a broad engineering stack installed globally:
`numpy`, `scipy`, `sympy`, `pandas`, `matplotlib`, `seaborn`, `plotly`, `pygame`,
`ortools`, `casadi`, `control`, `pinocchio`, `pyqt5`, `tkinter`, `pillow`, `opencv4`,
`scikit-image`, `pyserial`, `pyusb`, `jupyterlab`, `ipython`, `black`, `ruff`, `mypy`,
`pyright`, `debugpy` and `pytest`.

`pyenv` is also installed for projects that need a Python version different from the
system default. Typical workflow:

```bash
pyenv install 3.12.4
pyenv local 3.12.4
python -m venv .venv
source .venv/bin/activate
python -m pip install -U pip
```

Neovim detects `.venv` or `venv` in the project root, and also respects an already
active `VIRTUAL_ENV`. Pyright uses that interpreter, so imports installed in the
project virtual environment are visible to completions and diagnostics.

### Hyprland Autostart Programs

The following programs are configured to autostart on specific workspaces upon Hyprland login:

*   **Terminal** (Alacritty): Workspace 1
*   **Brave** (Web Browser): Workspace 2
*   **Discord**: Workspace 3
*   **KeePassXC**: Workspace 9

### Waybar Weather Module

The Waybar configuration includes a custom weather module that displays the temperature. It cycles through the following predefined locations:

*   **Rzeszów**
*   **Wiśniowa**
*   **Stalowa Wola**

### Functions

| Function          | Description                                                                                                                                                                                                                                                                                                                                 |
| :---------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `uu [count]`      | Navigates up `count` directories. If `count` is not provided, it goes up one directory.                                                                                                                                                                                                                                                     |
| `u [query]`       | Interactive directory changer. If `query` is a number, it behaves like `uu`. Otherwise, it uses `fzf` to let you select a parent directory to jump to. If `fzf` is not available, it lists parent directories.                                                                                                                                |
| `z [query]`       | Smart directory changer. If `query` is empty, it opens an interactive `fzf` menu to quickly navigate to subdirectories. If `query` matches a directory prefix, it changes to that directory. Otherwise, it uses `zoxide` to query and change to a frequently visited directory.                                                          |
| `_histpick`       | Interactive history picker. Uses `fzf` to let you select and execute a command from your bash history. If `fzf` is not available, it just prints the history.                                                                                                                                                                              |

### Shell Enhancements

| Keybinding          | Description                                                                                             |
| :------------------ | :------------------------------------------------------------------------------------------------------ |
| `Ctrl+R`            | Interactive history search (FZF-based). Allows fuzzy searching and selection of previous commands.      |
