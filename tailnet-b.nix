# Tailnet B, reachable system-wide (ssh, ping, Moonlight) next to tailnet A.
#
# How it works:
#   - A second tailscaled (kernel mode) runs inside its own network namespace "tsb",
#     so it never touches tailnet A's routes, ip rules, firewall chains or DNS.
#   - A veth pair links host (vtsb0, 10.250.0.1) and namespace (vtsb1, 10.250.0.2).
#   - Tailnet B addresses (100.<bOctet>.x.x) are shown on the host as 10.<bOctet>.x.x
#     (100.77.0.1 in B  ->  10.77.0.1 here; see bOctet below). The namespace translates 1:1 (NETMAP).
#     This avoids clashes with tailnet A's 100.x addresses and A's anti-spoof firewall rule.
#   - The host does NAT for the namespace's own internet traffic (control server, DERP, WireGuard).
#
# Install: copy to /etc/nixos/, add ./tailnet-b.nix to imports, and DELETE the old
# systemd.services.tailscaled-b block from networking.nix (this file replaces it).

{ config, pkgs, lib, ... }:

let
  ns = "tsb";
  hostIf = "vtsb0";
  nsIf = "vtsb1";
  tunIf = "tailscale1";

  # Tailnet B range: 100.<bOctet>.0.0/16 in B, shown here as 10.<bOctet>.0.0/16.
  # Renumber B to 100.78.x.x?  Change this to "78" and rebuild. Nothing else to edit
  # (as long as each machine keeps its last two numbers; else fix bHosts below).
  bOctet = "77";
  bHere = "10.${bOctet}.0.0/16";
  bReal = "100.${bOctet}.0.0/16";

  # Tailnet B machines: name = last two numbers of its address.
  # Add a line when a new machine joins tailnet B, then rebuild.
  bHosts = {
    host1 = "0.1";
    host2 = "0.2";
    host3 = "0.3";
    host4 = "0.4";
    host5 = "0.5";
    host6 = "0.6";
  };
  bSuffix = "tailnet-b.example.ts.net";
  ip = "${pkgs.iproute2}/bin/ip";
  ipt = "${pkgs.iptables}/bin/iptables";
in
{
  # Tailnet B names -> 10.<bOctet>.x.x. Tailscale IPs are stable.
  # "laptop" in B gets its full name only: the short name would clash with this laptop.
  networking.hosts = lib.mapAttrs' (name: tail:
      lib.nameValuePair "10.${bOctet}.${tail}" [ name "${name}.${bSuffix}" ]) bHosts
    // { "10.${bOctet}.0.10" = [ "laptop.${bSuffix}" ]; };

  # Host must forward the namespace's internet traffic. FORWARD is locked down below.
  boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

  networking.firewall.extraCommands = ''
    # Anti-spoof: the namespace address may only arrive on its own cable.
    iptables -w -t raw -N tsb-raw 2>/dev/null || iptables -w -t raw -F tsb-raw
    iptables -w -t raw -A tsb-raw -s 10.250.0.2/32 ! -i ${hostIf} -j DROP
    iptables -w -t raw -D PREROUTING -j tsb-raw 2>/dev/null || true
    iptables -w -t raw -I PREROUTING 1 -j tsb-raw

    # Nothing may be forwarded into or out of tailnet A (tailscale0). Host's own A traffic
    # is not forwarded, so it is unaffected. mangle runs before tailscaled's ts-forward.
    # Rules are only added if missing (never flushed), so this block is never empty.
    for t in iptables ip6tables; do
      $t -w -t mangle -N tsb-mfwd 2>/dev/null || true
      $t -w -t mangle -C tsb-mfwd -o tailscale0 -j DROP 2>/dev/null || $t -w -t mangle -A tsb-mfwd -o tailscale0 -j DROP
      $t -w -t mangle -C tsb-mfwd -i tailscale0 -j DROP 2>/dev/null || $t -w -t mangle -A tsb-mfwd -i tailscale0 -j DROP
      $t -w -t mangle -C FORWARD -j tsb-mfwd 2>/dev/null || $t -w -t mangle -I FORWARD 1 -j tsb-mfwd
    done
    # IPv6 forwarding is off today; this keeps it safe if that changes.
    ip6tables -w -P FORWARD DROP

    # Forwarding: only the namespace may go out to the internet, plus its replies.
    iptables -w -P FORWARD DROP
    iptables -w -N tsb-fwd 2>/dev/null || iptables -w -F tsb-fwd
    # No tailnet-A space, no link-local. Private LAN: UDP only (Tailscale direct
    # connections to B peers on the same LAN, e.g. host1 at home); no TCP/other to LAN.
    iptables -w -A tsb-fwd -i ${hostIf} -d 100.64.0.0/10,169.254.0.0/16 -j DROP
    iptables -w -A tsb-fwd -i ${hostIf} -d 10.0.0.0/8,172.16.0.0/12,192.168.0.0/16 ! -p udp -j DROP
    # UDP to LAN: high ports only (Tailscale uses 41641+); keeps probes off router/LAN services.
    iptables -w -A tsb-fwd -i ${hostIf} -d 10.0.0.0/8,172.16.0.0/12,192.168.0.0/16 -p udp -m multiport --dports 1:1023,1900,5353 -j DROP
    iptables -w -A tsb-fwd -i ${hostIf} -s 10.250.0.2/32 ! -o tailscale0 -j ACCEPT
    iptables -w -A tsb-fwd -o ${hostIf} -d 10.250.0.2/32 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    iptables -w -D FORWARD -j tsb-fwd 2>/dev/null || true
    iptables -w -A FORWARD -j tsb-fwd

    iptables -w -t nat -N tsb-post 2>/dev/null || iptables -w -t nat -F tsb-post
    iptables -w -t nat -A tsb-post -s 10.250.0.2/32 ! -o ${hostIf} -j MASQUERADE
    iptables -w -t nat -D POSTROUTING -j tsb-post 2>/dev/null || true
    iptables -w -t nat -A POSTROUTING -j tsb-post
  '';
  networking.firewall.extraStopCommands = ''
    iptables -w -t raw -D PREROUTING -j tsb-raw 2>/dev/null || true
    iptables -w -t raw -F tsb-raw 2>/dev/null || true
    iptables -w -t raw -X tsb-raw 2>/dev/null || true
    # tsb-mfwd (tailnet A forward block) is left in place on purpose: it must never be off
    # while ip_forward=1. Its rules are added only if missing (never flushed), so it is never empty.
    iptables -w -D FORWARD -j tsb-fwd 2>/dev/null || true
    iptables -w -F tsb-fwd 2>/dev/null || true
    iptables -w -X tsb-fwd 2>/dev/null || true
    iptables -w -t nat -D POSTROUTING -j tsb-post 2>/dev/null || true
    iptables -w -t nat -F tsb-post 2>/dev/null || true
    iptables -w -t nat -X tsb-post 2>/dev/null || true
  '';

  # Public DNS for tailscaled-b's own lookups (controlplane.tailscale.com etc.).
  # The host resolver (100.100.100.100) belongs to tailnet A and is not reachable from the namespace.
  environment.etc."tsb/resolv.conf".text = ''
    nameserver 9.9.9.9
    nameserver 1.1.1.1
  '';

  systemd.services.tsb-netns = {
    description = "Network namespace for tailnet B";
    before = [ "tailscaled-b.service" ];
    after = [ "firewall.service" ];
    wants = [ "firewall.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.iproute2 pkgs.iptables pkgs.procps ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -eu
      # First, so tailnet B addresses can never leak to the Wi-Fi router even if a later step fails.
      # Own table + rule: beats any LAN route that overlaps 10.<bOctet>.x.x (e.g. a 10.77.x.0/24 hotspot).
      ${ip} route replace blackhole ${bHere} table 190 metric 4000
      ${ip} rule del to ${bHere} lookup 190 pref 190 2>/dev/null || true
      ${ip} rule add to ${bHere} lookup 190 pref 190
      # Same as boot.kernel.sysctl above, but applied now, not only after the next sysctl reload.
      sysctl -qw net.ipv4.ip_forward=1
      ${ip} netns del ${ns} 2>/dev/null || true
      ${ip} link del ${hostIf} 2>/dev/null || true
      ${ip} netns add ${ns}

      ${ip} link add ${hostIf} type veth peer name ${nsIf} netns ${ns}
      ${ip} addr add 10.250.0.1/30 dev ${hostIf}
      ${ip} link set ${hostIf} up
      ${ip} -n ${ns} link set lo up
      ${ip} -n ${ns} addr add 10.250.0.2/30 dev ${nsIf}
      ${ip} -n ${ns} link set ${nsIf} up
      ${ip} -n ${ns} route add default via 10.250.0.1
      # Tailnet B addresses with no live peer must die here, never go out the default route.
      # Real peers still win: tailscaled-b puts them in table 52, looked up first.
      ${ip} -n ${ns} route add blackhole 100.64.0.0/10

      ${ip} netns exec ${ns} sysctl -qw net.ipv4.ip_forward=1
      # Host 10.<bOctet>.x.x <-> tailnet B 100.<bOctet>.x.x, 1:1.
      ${ip} netns exec ${ns} ${ipt} -w -t nat -A PREROUTING -i ${nsIf} -d ${bHere} -j NETMAP --to ${bReal}
      ${ip} netns exec ${ns} ${ipt} -w -t nat -A POSTROUTING -o ${tunIf} -j MASQUERADE

      # (fallback blackhole + rule are set at the top in table 190; not removed on stop, on purpose)
      # mtu 1280 = tailscale tunnel size, so big packets are cut down on the host already.
      ${ip} route add ${bHere} via 10.250.0.2 dev ${hostIf} mtu 1280 table 190
    '';
    preStop = ''
      ${ip} netns del ${ns} 2>/dev/null || true
      ${ip} link del ${hostIf} 2>/dev/null || true
    '';
  };

  systemd.services.tailscaled-b = {
    description = "Second Tailscale daemon (tailnet B, own network namespace)";
    wantedBy = [ "multi-user.target" ];
    requires = [ "tsb-netns.service" ];
    after = [ "tsb-netns.service" ];
    bindsTo = [ "tsb-netns.service" ];
    path = [ pkgs.iproute2 pkgs.iptables pkgs.procps ];
    serviceConfig = {
      ExecStart = "${config.services.tailscale.package}/bin/tailscaled --tun=${tunIf} --state=/var/lib/tailscale-b/tailscaled.state --socket=/run/tailscale-b/tailscaled.sock --port=41642";
      NetworkNamespacePath = "/run/netns/${ns}";
      # tailscaled-b must never rewrite the host's /etc/resolv.conf (tailnet A's DNS).
      BindReadOnlyPaths = [ "/etc/tsb/resolv.conf:/etc/resolv.conf" ];
      StateDirectory = "tailscale-b";
      RuntimeDirectory = "tailscale-b";
      Restart = "on-failure";
    };
  };
}
