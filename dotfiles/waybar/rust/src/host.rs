//! Tailnet host dots + tailnet status table tooltip.
//!
//! Shows only the state tailscaled reports; nothing is kept between checks except
//! the ssh probe cache. Dot: green online, red offline, gray tailscale down / not on
//! tailnet. Online hosts in PROBES show a number instead of the dot (robots: battery
//! SoC, gpu-server: VRAM %), read over ssh at most once per PROBE_INTERVAL and cached in
//! PROBE_CACHE (shared by all instances, survives waybar restarts).

use crate::common::*;
use serde_json::{json, Value};
use std::collections::{HashMap, HashSet};
use std::io::{Read, Write};
use std::os::unix::net::UnixStream;
use std::process::{Command, Stdio};
use std::sync::{mpsc, Arc, Mutex};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

const INTERVAL: u64 = 5;
const TS_SOCK: &str = "/var/run/tailscale/tailscaled.sock";
const PROBE_INTERVAL: f64 = 30.0;
const BATTERY_CMD: &str = "cat ~/.cache/g1_state.json";
const BATTERY_MAX_AGE: f64 = 120.0;
const GPU_CMD: &str = "nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu,temperature.gpu,power.draw --format=csv,noheader,nounits 2>&1 | head -8; echo @; nvidia-smi --query-compute-apps=pid,used_memory --format=csv,noheader,nounits 2>/dev/null | head -12 | while IFS=', ' read -r p m; do echo \"$m $(ps -o user=,comm= -p $p)\"; done; echo @; nproc; cat /proc/loadavg /proc/uptime; echo \"cpu $(head -1 /proc/stat)\"; sleep 0.5; echo \"cpu $(head -1 /proc/stat)\"; grep -E '^(MemTotal|MemAvailable|SwapTotal|SwapFree):' /proc/meminfo; df -P / | tail -1";

fn color(state: &str) -> &'static str {
    match state {
        "up" => "#50fa7b",
        "down" => "#ff5555",
        _ => "#808080",
    }
}

#[derive(Clone, Copy, PartialEq)]
enum Kind {
    Battery,
    Gpu,
    /// same probe as Gpu, but the dot shows CPU % instead of VRAM %
    GpuCpu,
}

/// tailnet host -> (ssh alias, remote command, kind)
fn probe_for(host: &str) -> Option<(&'static str, &'static str, Kind)> {
    match host {
        "unitree-g1" => Some(("robot1-ssh", BATTERY_CMD, Kind::Battery)),
        "unitree-r1" => Some(("robot2-ssh", BATTERY_CMD, Kind::Battery)),
        "gpu-server" => Some(("gpu-server-ssh", GPU_CMD, Kind::Gpu)),
        "my-pc" => Some(("my-pc-ssh", GPU_CMD, Kind::GpuCpu)),
        _ => None,
    }
}

#[derive(Default)]
struct Shared {
    online: HashSet<String>,
    probed: HashMap<String, Value>,
    probe_t: HashMap<String, f64>,
}

fn now() -> f64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs_f64()).unwrap_or(0.0)
}

fn cache_path() -> String {
    format!("{}/waybar-host-battery.json", runtime_dir())
}

fn ts_status() -> Option<Value> {
    let mut s = UnixStream::connect(TS_SOCK).ok()?;
    let t = Some(Duration::from_secs(2));
    s.set_read_timeout(t).ok()?;
    s.set_write_timeout(t).ok()?;
    // HTTP/1.0: the reply is never chunked, so the body is whatever follows the headers
    s.write_all(b"GET /localapi/v0/status HTTP/1.0\r\nHost: local-tailscaled.sock\r\n\r\n").ok()?;
    let mut buf = Vec::new();
    s.read_to_end(&mut buf).ok()?;
    let at = buf.windows(4).position(|w| w == b"\r\n\r\n")?;
    serde_json::from_slice(&buf[at + 4..]).ok()
}

fn short(p: &Value) -> String {
    let n = p["DNSName"].as_str().filter(|s| !s.is_empty())
        .or(p["HostName"].as_str().filter(|s| !s.is_empty())).unwrap_or("?");
    n.split('.').next().unwrap_or("?").to_string()
}

fn ipv4(p: &Value) -> String {
    p["TailscaleIPs"].as_array().into_iter().flatten().filter_map(Value::as_str)
        .find(|a| a.contains('.')).unwrap_or("").to_string()
}

/// Seconds since the Unix epoch of an RFC 3339 timestamp, None if it won't parse.
fn parse_ts(ts: &str) -> Option<f64> {
    let b = ts.as_bytes();
    if b.len() < 20 || b[4] != b'-' || b[7] != b'-' || b[10] != b'T' {
        return None;
    }
    let n = |r: std::ops::Range<usize>| ts.get(r)?.parse::<i64>().ok();
    let (y, mo, d, h, mi, s) = (n(0..4)?, n(5..7)?, n(8..10)?, n(11..13)?, n(14..16)?, n(17..19)?);
    let mut i = 19;
    let mut frac = 0.0;
    if b.get(i) == Some(&b'.') {
        let st = i;
        i += 1;
        while b.get(i).is_some_and(u8::is_ascii_digit) {
            i += 1;
        }
        frac = ts[st..i].parse().unwrap_or(0.0);
    }
    let off = match b.get(i)? {
        b'Z' => 0,
        sign @ (b'+' | b'-') => {
            let v = n(i + 1..i + 3)? * 3600 + n(i + 4..i + 6)? * 60;
            if *sign == b'+' { v } else { -v }
        }
        _ => return None,
    };
    // days from civil (Howard Hinnant)
    let y2 = if mo <= 2 { y - 1 } else { y };
    let era = y2.div_euclid(400);
    let yoe = y2 - era * 400;
    let doy = (153 * (mo + if mo > 2 { -3 } else { 9 }) + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    let days = era * 146097 + doe - 719468;
    Some((days * 86400 + h * 3600 + mi * 60 + s - off) as f64 + frac)
}

fn ago(ts: Option<&str>) -> String {
    let Some(t) = ts.and_then(parse_ts) else { return String::new() };
    if t < 946684800.0 {
        return String::new(); // year < 2000: tailscale's "never"
    }
    let s = (now() - t) as i64;
    for (unit, n) in [("d", 86400), ("h", 3600), ("m", 60)] {
        if s >= n {
            return format!("{}{unit} ago", s / n);
        }
    }
    format!("{s}s ago")
}

fn table(d: &Value, highlight: &[String]) -> String {
    let mut peers: Vec<&Value> = vec![&d["Self"]];
    if let Some(m) = d["Peer"].as_object() {
        peers.extend(m.values());
    }
    let mut rows: Vec<(bool, String, String, String, String)> = peers.iter().enumerate().map(|(i, p)| {
        let online = p["Online"].as_bool().unwrap_or(false);
        let mut status = if online { "online".to_string() } else { format!("offline {}", ago(p["LastSeen"].as_str())).trim().to_string() };
        if i == 0 {
            status += " (this)";
        }
        (online, short(p), ipv4(p), p["OS"].as_str().unwrap_or("").to_string(), status)
    }).collect();
    rows.sort_by(|a, b| (!a.0, &a.1).cmp(&(!b.0, &b.1)));
    let w = |f: fn(&(bool, String, String, String, String)) -> usize| rows.iter().map(f).max().unwrap_or(0);
    let (wn, wi, wo) = (w(|r| r.1.chars().count()), w(|r| r.2.chars().count()), w(|r| r.3.chars().count()));
    let lines: Vec<String> = rows.iter().map(|(online, name, ip, os, status)| {
        let mut line = escape(&format!("{name:<wn$}  {ip:<wi$}  {os:<wo$}  {status}"));
        if highlight.contains(name) {
            line = format!("<b>{line}</b>");
        }
        format!("<span color='{}'>●</span> {line}", color(if *online { "up" } else { "down" }))
    }).collect();
    format!("<tt>{}</tt>", lines.join("\n"))
}

fn cache_load() -> serde_json::Map<String, Value> {
    std::fs::read_to_string(cache_path()).ok().and_then(|s| serde_json::from_str::<Value>(&s).ok())
        .and_then(|v| if let Value::Object(m) = v { Some(m) } else { None }).unwrap_or_default()
}

fn cache_store(host: &str, value: Value, t: f64) {
    let mut d = cache_load();
    d.insert(host.to_string(), json!({"v": value, "t": t}));
    let tmp = format!("{}.{}.{}", cache_path(), std::process::id(), host);
    if std::fs::write(&tmp, Value::Object(d).to_string()).is_ok() {
        let _ = std::fs::rename(&tmp, cache_path());
    }
}

fn cache_apply(sh: &mut Shared, host: &str, entry: &Value) {
    let v = entry.get("v").or_else(|| entry.get("soc")).filter(|v| !v.is_null()); // "soc": pre-PROBES cache
    match v {
        Some(v) => {
            sh.probed.insert(host.into(), v.clone());
            match entry["t"].as_f64() {
                Some(t) => sh.probe_t.insert(host.into(), t),
                None => sh.probe_t.remove(host),
            };
        }
        None => {
            sh.probed.remove(host);
        }
    }
}

fn parse_battery(out: &str) -> Option<Value> {
    let st: Value = serde_json::from_str(out).ok()?;
    if (now() - st["written_at"].as_f64()?).abs() > BATTERY_MAX_AGE {
        return None;
    }
    Some(json!(st["bms"]["soc"].as_f64()? as i64))
}

fn num(x: &str) -> Value {
    x.trim().parse::<f64>().map(Value::from).unwrap_or(Value::Null)
}

fn parse_gpu(out: &str) -> Option<Value> {
    let mut parts = out.splitn(3, "@\n");
    let (gpu, procs, sys) = (parts.next()?, parts.next().unwrap_or(""), parts.next().unwrap_or(""));
    if sys.trim().is_empty() {
        return None;
    }
    let (mut gpus, mut gpu_err, mut pr) = (vec![], String::new(), vec![]);
    for line in gpu.lines() {
        let f: Vec<&str> = line.split(',').map(str::trim).collect();
        if f.len() == 6 && !num(f[1]).is_null() {
            let mut g = vec![json!(f[0])];
            g.extend(f[1..].iter().map(|x| num(x)));
            gpus.push(Value::Array(g));
        } else if !line.trim().is_empty() && gpu_err.is_empty() {
            gpu_err = line.trim().to_string();
        }
    }
    for line in procs.lines() {
        let f: Vec<&str> = line.split_whitespace().collect();
        if !f.is_empty() && !num(f[0]).is_null() {
            let cmd = f[2.min(f.len())..].join(" ");
            pr.push(json!([num(f[0]), f.get(1).unwrap_or(&"?"), if cmd.is_empty() { "?" } else { &cmd }]));
        }
    }
    let mut r = json!({"gpus": gpus, "gpu_err": gpu_err, "procs": pr});
    let mut mem: HashMap<&str, i64> = HashMap::new();
    let mut stat = vec![];
    for line in sys.lines() {
        let f: Vec<&str> = line.split_whitespace().collect();
        if f.len() > 9 && f[0] == "cpu" && f[1] == "cpu" {
            stat.push(f[2..10].iter().map(|x| x.parse::<i64>().unwrap_or(0)).collect::<Vec<_>>());
        } else if f.len() == 1 && f[0].bytes().all(|b| b.is_ascii_digit()) {
            r["cores"] = json!(f[0].parse::<i64>().unwrap_or(0));
        } else if f.len() == 5 && f[3].contains('/') {
            r["load"] = json!(&f[..3]);
        } else if f.len() == 2 && !num(f[0]).is_null() {
            r["uptime"] = num(f[0]);
        } else if f.len() == 3 && f[0].ends_with(':') {
            mem.insert(&f[0][..f[0].len() - 1], f[1].parse::<i64>().unwrap_or(0) * 1024);
        } else if f.len() == 6 && f[4].ends_with('%') {
            let (u, a) = (f[2].parse::<i64>().unwrap_or(0), f[3].parse::<i64>().unwrap_or(0));
            r["disk"] = json!([u * 1024, (u + a) * 1024]);
        }
    }
    if !stat.is_empty() {
        r["stat"] = json!(stat);
    }
    if let Some(&mt) = mem.get("MemTotal") {
        let g = |k| mem.get(k).copied().unwrap_or(0);
        r["mem"] = json!([mt - g("MemAvailable"), mt]);
        r["swap"] = json!([g("SwapTotal") - g("SwapFree"), g("SwapTotal")]);
    }
    Some(r)
}

/// CPU busy % over the 0.5 s between two /proc/stat reads.
fn cpu_fill(v: &Value) -> Option<i64> {
    let s = v["stat"].as_array().filter(|a| a.len() >= 2)?;
    let get = |i: usize| -> Vec<i64> { s[i].as_array().map(|a| a.iter().filter_map(Value::as_i64).collect()).unwrap_or_default() };
    let (a, b) = (get(0), get(1));
    if a.len() < 5 || b.len() < 5 {
        return None;
    }
    let total = b.iter().sum::<i64>() - a.iter().sum::<i64>();
    let idle = (b[3] + b[4]) - (a[3] + a[4]); // idle + iowait
    (total > 0).then(|| (100.0 * (total - idle) as f64 / total as f64).round_ties_even() as i64)
}

/// VRAM used % summed over all GPUs.
fn vram_fill(v: &Value) -> Option<i64> {
    let g = v["gpus"].as_array()?;
    let sum = |i: usize| g.iter().filter_map(|x| x[i].as_f64()).sum::<f64>();
    let total = sum(2);
    (total > 0.0).then(|| (100.0 * sum(1) / total).round_ties_even() as i64)
}

fn gib(b: f64) -> String {
    format!("{:.1}", b / (1u64 << 30) as f64)
}

fn gpu_table(v: &Value) -> String {
    let mut rows: Vec<String> = vec![];
    let gpus = v["gpus"].as_array().cloned().unwrap_or_default();
    if !gpus.is_empty() {
        rows.push("GPU  memory (GiB)       util  temp  power".into());
        for (i, g) in gpus.iter().enumerate() {
            let f = |k: usize| g[k].as_f64();
            let (used, total) = (f(1).unwrap_or(0.0), f(2).unwrap_or(0.0));
            let pct = if total > 0.0 { format!("{:.0}%", 100.0 * used / total) } else { "?".into() };
            let m = format!("{:.1}/{:.1} {pct}", used / 1024.0, total / 1024.0);
            let opt = |k: usize, suf: &str| f(k).map(|x| format!("{x:.0}{suf}")).unwrap_or("-".into());
            rows.push(format!("{i:<3}  {m:<17}  {:>4}  {:>4}  {:>5}  {}", opt(3, "%"), opt(4, "°C"), opt(5, "W"),
                g[0].as_str().unwrap_or("")));
        }
        let mut procs: Vec<(f64, String, String)> = v["procs"].as_array().into_iter().flatten()
            .map(|p| (p[0].as_f64().unwrap_or(0.0), p[1].as_str().unwrap_or("?").into(), p[2].as_str().unwrap_or("?").into())).collect();
        procs.sort_by(|a, b| b.partial_cmp(a).unwrap_or(std::cmp::Ordering::Equal));
        for (mib, user, cmd) in procs {
            rows.push(format!("     {:5.1} GiB  {user:<10} {cmd}", mib / 1024.0));
        }
    } else {
        let e = v["gpu_err"].as_str().filter(|s| !s.is_empty()).unwrap_or("no GPUs reported");
        rows.push(format!("GPU  {e}"));
    }
    rows.push(String::new());
    if let Some(cpu) = cpu_fill(v) {
        rows.push(format!("CPU now {cpu}%"));
    }
    if let Some(load) = v["load"].as_array() {
        let ls: Vec<&str> = load.iter().filter_map(Value::as_str).collect();
        match v["cores"].as_i64().filter(|&c| c > 0) {
            Some(cores) => {
                let pct: Vec<String> = ls.iter().map(|x| {
                    let p = 100.0 * x.parse::<f64>().unwrap_or(0.0) / cores as f64;
                    if p < 10.0 { format!("{p:.1}%") } else { format!("{p:.0}%") }
                }).collect();
                rows.push(format!("CPU     {}  (1/5/15m load, {cores} cores)", pct.join(" ")));
            }
            None => rows.push(format!("load    {}", ls.join(" "))),
        }
    }
    for (key, label) in [("mem", "RAM"), ("swap", "swap"), ("disk", "disk /")] {
        if let (Some(u), Some(t)) = (v[key][0].as_f64(), v[key][1].as_f64().filter(|&t| t > 0.0)) {
            rows.push(format!("{label:<7} {}/{} GiB  {:.0}%", gib(u), gib(t), 100.0 * u / t));
        }
    }
    if let Some(up) = v["uptime"].as_f64() {
        let s = up as i64;
        rows.push(format!("uptime  {}d {}h {}m", s / 86400, s % 86400 / 3600, s % 3600 / 60));
    }
    format!("<tt>{}</tt>", escape(&rows.join("\n")))
}

fn ssh_probe(alias: &str, cmd: &str) -> Option<String> {
    let mut child = Command::new("ssh")
        .args(["-o", "BatchMode=yes", "-o", "ConnectTimeout=5", alias, cmd])
        .stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::null()).spawn().ok()?;
    let mut out = child.stdout.take()?;
    let (tx, rx) = mpsc::channel();
    std::thread::spawn(move || {
        let mut s = Vec::new();
        let _ = out.read_to_end(&mut s);
        let _ = tx.send(String::from_utf8_lossy(&s).into_owned());
    });
    match rx.recv_timeout(Duration::from_secs(10)) {
        Ok(s) => {
            let _ = child.wait();
            Some(s)
        }
        Err(_) => {
            let _ = child.kill();
            let _ = child.wait();
            None
        }
    }
}

fn probe_loop(host: String, sh: Arc<Mutex<Shared>>) {
    let (alias, cmd, kind) = probe_for(&host).unwrap();
    loop {
        std::thread::sleep(Duration::from_secs(1));
        if !sh.lock().unwrap().online.contains(&host) {
            continue;
        }
        let entry = cache_load().get(&host).cloned().filter(Value::is_object).unwrap_or(json!({}));
        cache_apply(&mut sh.lock().unwrap(), &host, &entry);
        if let Some(t) = entry["t"].as_f64() {
            let age = now() - t;
            if (0.0..PROBE_INTERVAL).contains(&age) {
                continue;
            }
        }
        let value = ssh_probe(alias, cmd)
            .and_then(|o| if kind == Kind::Battery { parse_battery(&o) } else { parse_gpu(&o) })
            .unwrap_or(Value::Null);
        let t = now();
        cache_store(&host, value.clone(), t);
        cache_apply(&mut sh.lock().unwrap(), &host, &json!({"v": value, "t": t}));
    }
}

fn tick(hosts: &[String], sh: &Mutex<Shared>) -> Value {
    let d = ts_status();
    let running = d.as_ref().is_some_and(|d| d["BackendState"] == "Running");
    let mut peers: HashMap<String, &Value> = HashMap::new();
    if let (true, Some(d)) = (running, &d) {
        if let Some(m) = d["Peer"].as_object() {
            peers.extend(m.values().map(|p| (short(p), p)));
        }
    }
    let mut sh = sh.lock().unwrap();
    let (mut dots, mut header, mut extra) = (vec![], vec![], vec![]);
    for h in hosts {
        let (state, mut desc) = match peers.get(h) {
            None => ("noroute", if running { "not on tailnet" } else { "tailscale down" }.to_string()),
            Some(p) if p["Online"].as_bool().unwrap_or(false) => ("up", format!("online ({})", ipv4(p))),
            Some(p) => ("down", format!("offline {} ({})", ago(p["LastSeen"].as_str()), ipv4(p))),
        };
        if state == "up" {
            sh.online.insert(h.clone());
        } else {
            sh.online.remove(h);
            sh.probed.remove(h);
        }
        let mut mark = "●".to_string();
        if let (Some(v), Some((_, _, kind))) = (sh.probed.get(h), probe_for(h)) {
            if kind == Kind::Battery {
                mark = v.as_i64().map(|n| n.to_string()).unwrap_or_else(|| v.to_string());
                desc += &format!(", battery {mark}%");
            } else {
                if kind == Kind::GpuCpu {
                    if let Some(p) = cpu_fill(v) {
                        mark = p.to_string();
                        desc += &format!(", CPU {mark}%");
                    }
                } else if let Some(p) = vram_fill(v) {
                    mark = p.to_string();
                    desc += &format!(", VRAM {mark}%");
                }
                if let Some(t) = sh.probe_t.get(h) {
                    desc += &format!(", read {}s ago", (now() - t) as i64);
                }
                extra.push(gpu_table(v));
            }
        }
        dots.push(format!("<span color='{}'>{mark}</span>", color(state)));
        header.push(format!("<span color='{}'>●</span> <b>{}</b>: {}", color(state), escape(h), escape(&desc)));
    }
    let body = match (&d, running) {
        (Some(d), true) => table(d, hosts),
        (None, _) => "tailscale unavailable".to_string(),
        (Some(d), false) => format!("tailscale: {}", escape(d["BackendState"].as_str().unwrap_or("None"))),
    };
    let mut parts = vec![header.join("\n")];
    parts.extend(extra);
    parts.push(body);
    json!({"text": dots.join("  "), "tooltip": parts.join("\n\n")})
}

pub fn run(args: &[String]) {
    let notify = args.iter().any(|a| a == "--notify");
    let hosts: Vec<String> = args.iter().filter(|a| *a != "--notify").cloned().collect();
    let sh = Arc::new(Mutex::new(Shared::default()));
    // start from the cached readings so the first output already shows them
    for (h, e) in cache_load() {
        if e.is_object() {
            cache_apply(&mut sh.lock().unwrap(), &h, &e);
        }
    }
    if notify {
        let t = tick(&hosts, &sh)["tooltip"].as_str().unwrap_or("").to_string();
        let _ = Command::new("notify-send").args(["-r", "47120", "-a", "tailnet", "Tailnet", &t]).status();
        return;
    }
    for h in hosts.iter().filter(|h| probe_for(h).is_some()) {
        let (h, sh) = (h.clone(), sh.clone());
        std::thread::spawn(move || probe_loop(h, sh));
    }
    loop {
        emit(&tick(&hosts, &sh));
        std::thread::sleep(Duration::from_secs(INTERVAL));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rfc3339() {
        assert_eq!(parse_ts("1970-01-02T00:00:00Z"), Some(86400.0));
        assert_eq!(parse_ts("2026-10-27T12:00:00.5+02:00"), Some(1793095200.5));
        assert_eq!(parse_ts("0001-01-01T00:00:00Z").map(|t| t < 946684800.0), Some(true));
        assert_eq!(ago(Some("0001-01-01T00:00:00Z")), "");
        assert_eq!(parse_ts("garbage"), None);
    }

    #[test]
    fn gpu_parse_and_table() {
        let out = "NVIDIA H200, 14, 143771, 5, 34, 71.9\n@\n2048 root python train.py\n@\n32\n0.10 0.20 0.30 1/200 999\n100.5 200.5\n\
cpu cpu  100 0 100 800 0 0 0 0\ncpu cpu  200 0 200 1000 0 0 0 0\nMemTotal: 1000 kB\nMemAvailable: 400 kB\nSwapTotal: 0 kB\nSwapFree: 0 kB\n\
/dev/x 1000 600 400 60% /\n";
        let v = parse_gpu(out).unwrap();
        assert_eq!(vram_fill(&v), Some(0));
        assert_eq!(cpu_fill(&v), Some(50));
        assert_eq!(v["procs"][0][2], "python train.py");
        let t = gpu_table(&v);
        assert!(t.contains("2.0 GiB  root       python train.py"), "{t}");
        assert!(t.contains("CPU now 50%") && t.contains("32 cores") && t.contains("uptime  0d 0h 1m"), "{t}");
        assert!(parse_gpu("only gpu\n").is_none());
    }
}
