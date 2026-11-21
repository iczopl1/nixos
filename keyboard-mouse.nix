# Keyboard-only pointer control for Mango.
# Add to your NixOS config (e.g. import it from configuration.nix), then rebuild.
# Keep the imported wl-kbptr patch and hintd sources in dotfiles/syshelp/hint-atspi.
# Remove the two withA11y lines below if you do not want the Signal/Ferdium flag.
{ pkgs, unstable, ... }: # `unstable` comes from /etc/nixos/unstable.nix
let
  # wl-kbptr for the G / SHIFT+G binds. Patched: Vimium-style tags (flat yellow, bold
  # uppercase), 1/2/3/4 button prefixes, tunable detection (detect_* in ~/.config/wl-kbptr/config).
  wl-kbptr = pkgs.wl-kbptr.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./dotfiles/syshelp/hint-atspi/wl-kbptr-vimium.patch ];
    # Upstream .desktop (SUPER+X w config.conf) nie ma Icon= wcale – w SUPER-tap
    # gridzie wychodziła goła/domyślna ikonka. input-mouse jest w adwaita-icon-theme.
    postInstall = (old.postInstall or "") + ''
      sed -i '/^Exec=/a Icon=input-mouse' $out/share/applications/wl-kbptr.desktop
    '';
  });

  # SUPER+D: reads the accessibility tree of the visible windows on request and clicks
  # at the picked spot (wlr virtual pointer). The labels are drawn by the bar's quickshell
  # (Hints.qml), so no helper process starts on a key press. Never clicks on its own.
  hintd = pkgs.callPackage ./dotfiles/syshelp/hint-atspi/hintd { };

  # Signal and Ferdium start with Chromium's accessibility tree on, so SUPER+D
  # sees their real buttons/links. Costs some CPU/RAM in those apps; restart them
  # after a rebuild (the flag is read at startup).
  withA11y = pkg: bin: pkgs.symlinkJoin {
    name = "${pkg.name}-a11y";
    paths = [ pkg ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/${bin} --add-flags "--force-renderer-accessibility"
    '';
  };
in
{
  environment.systemPackages = [
    wl-kbptr
    hintd
    (pkgs.lib.hiPrio (withA11y unstable.signal-desktop "signal-desktop"))
    (pkgs.lib.hiPrio (withA11y pkgs.ferdium "ferdium"))
  ];

  # Narrow font for the hint labels (Hints.qml and wl-kbptr.config: label_font_family).
  fonts.packages = [ pkgs.barlow ];

  # Already enabled on this machine (ydotoold running, you're in the ydotool group).
  # Used for the cursor submap (move/drag/scroll).
  programs.ydotool.enable = true;
}
