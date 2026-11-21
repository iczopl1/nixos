# PROPOSAL for you to review and copy into /etc/nixos (e.g. into io.nix). Not applied.
#
# Why: the `input` group lets every program running as `me` read ALL input devices,
# including your keyboard (passwords). power-fx only needs the mouse and
# touchpad. This gives a small dedicated group access to pointer devices only.
#
# After adding it: rebuild, remove "input" from your extraGroups, log out and in,
# then check `id -nG` (no `input`, but `clickwatch`) and `ls -l /dev/input/event*`.
# Do not chmod the keyboard nodes yourself: the compositor gets them via logind.
{ ... }:
{
  users.groups.clickwatch = { };
  users.users."<you>".extraGroups = [ "clickwatch" ];   # and remove "input" from this list

  services.udev.extraRules = ''
    SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_INPUT_MOUSE}=="1",    ENV{ID_INPUT_KEY}!="1", GROUP="clickwatch", MODE="0660"
    SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_INPUT_TOUCHPAD}=="1", ENV{ID_INPUT_KEY}!="1", GROUP="clickwatch", MODE="0660"
  '';
}
