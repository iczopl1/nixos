# NixOS Configuration

This repository contains the NixOS configuration for this system, managed using flakes.

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