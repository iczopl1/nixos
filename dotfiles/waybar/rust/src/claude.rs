//! Claude Code activity: what every running claude session is doing.
//!
//! Reads the per-session files the `waybar-status` Claude Code mod writes to
//! $XDG_RUNTIME_DIR/claude-status/<session>.json and drops files whose claude
//! process is gone. Only the spinner moves between data reads: frames re-render
//! the cached sessions; files, /proc and the tooltip are touched at most once
//! per DATA_S / PROC_S.

use crate::common::*;
use serde_json::{json, Value};
use std::collections::{HashMap, HashSet};
use std::process::Command;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

const STALE_S: f64 = 45.0;
const FAST: Duration = Duration::from_millis(200);
const SLOW: Duration = Duration::from_millis(1000);
const DATA_S: f64 = 1.0;
const PROC_S: f64 = 3.0;
const SPINNER: [&str; 10] = ["·", "✢", "✳", "✶", "✻", "✽", "✻", "✶", "✳", "✢"];
const ICON_FONT: &str = "DejaVu Sans Mono";
const FALLBACK: &[(&str, &str)] = &[
    ("flow-1", "#4fb3ff"), ("flow-3", "#6faef7"), ("flow-7", "#afa5e7"), ("flow-10", "#df9fdb"),
    ("flow-12", "#ff9ad3"), ("text", "#ffd7e3"), ("overlay2", "#8c96b8"), ("green", "#8faaef"),
];

type Colors = HashMap<String, String>;

fn dir() -> String {
    format!("{}/claude-status", runtime_dir())
}

fn rank(s: &str) -> u8 {
    match s {
        "waiting" => 0,
        "working" => 1,
        "done" => 2,
        "idle" => 3,
        "unknown" => 4,
        _ => 9,
    }
}

fn is_comm(c: &str) -> bool {
    c == "claude" || c == ".claude-wrapped" // the nix wrapper renames the process
}

fn parent_of(pid: i32) -> Option<(String, i32)> {
    let s = std::fs::read_to_string(format!("/proc/{pid}/stat")).ok()?;
    let (l, r) = (s.find('(')?, s.rfind(')')?);
    let ppid = s[r + 1..].split_whitespace().nth(1)?.parse().ok()?;
    Some((s[l + 1..r].to_string(), ppid))
}

/// (pid, cwd) of every top-level claude process: one per session.
fn claude_procs() -> Vec<(i32, String)> {
    let mut procs: HashMap<i32, (String, i32)> = HashMap::new();
    for e in std::fs::read_dir("/proc").into_iter().flatten().flatten() {
        if let Some(pid) = e.file_name().to_str().and_then(|n| n.parse::<i32>().ok()) {
            if let Some(p) = parent_of(pid) {
                procs.insert(pid, p);
            }
        }
    }
    let claude = |pid: i32| procs.get(&pid).is_some_and(|p| is_comm(&p.0));
    let mut pids: Vec<i32> = procs.iter().filter(|(_, (comm, ppid))| is_comm(comm) && !claude(*ppid)).map(|(pid, _)| *pid).collect();
    pids.sort_unstable(); // stable order: the pill must not reshuffle between rescans
    pids.into_iter().map(|pid| {
        let cwd = std::fs::read_link(format!("/proc/{pid}/cwd")).map(|p| p.to_string_lossy().into_owned()).unwrap_or_default();
        (pid, cwd)
    }).collect()
}

fn now_s() -> f64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs_f64()).unwrap_or(0.0)
}

fn sessions(procs: &[(i32, String)]) -> Vec<Value> {
    let mut out: Vec<Value> = vec![];
    let now = now_s();
    for e in std::fs::read_dir(dir()).into_iter().flatten().flatten() {
        let path = e.path();
        if path.extension().and_then(|x| x.to_str()) != Some("json") {
            continue;
        }
        let Ok(s) = std::fs::read_to_string(&path).map_err(|_| ()).and_then(|t| serde_json::from_str::<Value>(&t).map_err(|_| ())) else {
            continue; // mid-write; next frame reads it
        };
        let gone = s["state"] == "ended" || match s["pid"].as_i64() {
            Some(pid) => !pid_alive(pid as i32),
            None => now - s["updated"].as_f64().unwrap_or(0.0) / 1000.0 > STALE_S,
        };
        if gone {
            let _ = std::fs::remove_file(&path);
            continue;
        }
        out.push(s);
    }
    // claude processes the mod is not running in (started before it was set up)
    let reported: HashSet<i64> = out.iter().filter_map(|s| s["pid"].as_i64()).collect();
    for (pid, cwd) in procs {
        if !reported.contains(&(*pid as i64)) {
            out.push(json!({"session": format!("pid-{pid}"), "pid": pid, "cwd": cwd, "state": "unknown", "since": 0}));
        }
    }
    out.sort_by_key(|s| (rank(s["state"].as_str().unwrap_or("")), std::cmp::Reverse(s["since"].as_i64().unwrap_or(0))));
    out
}

fn dur(ms: f64) -> String {
    let s = (ms / 1000.0).floor().max(0.0) as i64;
    if s < 60 {
        format!("{s}s")
    } else if s < 3600 {
        format!("{}m{:02}s", s / 60, s % 60)
    } else {
        format!("{}h{:02}m", s / 3600, s % 3600 / 60)
    }
}

fn name(s: &Value) -> String {
    if let Some(t) = s["title"].as_str().filter(|t| !t.is_empty()) {
        return t.into();
    }
    let cwd = s["cwd"].as_str().unwrap_or("").trim_end_matches('/');
    let base = cwd.rsplit('/').next().unwrap_or("");
    if base.is_empty() { "~".into() } else { base.into() }
}

fn st(s: &Value) -> &str {
    s["state"].as_str().unwrap_or("idle")
}

fn tooltip(ss: &[Value], c: &Colors, now_ms: f64) -> String {
    if ss.is_empty() {
        return "No Claude sessions running".into();
    }
    let ov = &c["overlay2"];
    let mut rows = vec![];
    for s in ss {
        let state = st(s);
        let (col, dot) = match state {
            "waiting" => (&c["flow-12"], "◆"),
            "working" => (&c["flow-1"], "●"),
            "done" => (&c["green"], "✓"),
            "idle" => (ov, "○"),
            "unknown" => (ov, "◌"),
            _ => (&c["text"], "?"),
        };
        let mut head = format!("<span color='{col}'>{dot}</span> <b>{}</b>  <span color='{ov}'>{}", escape(&name(s)), escape(state));
        let reason = s["lastReason"].as_str();
        if matches!(state, "working" | "waiting") && s["turnStart"].as_f64().is_some_and(|t| t != 0.0) {
            head += &format!(" · {}", dur(now_ms - s["turnStart"].as_f64().unwrap()));
        } else if matches!(state, "done" | "idle") && s["lastDurationMs"].as_f64().is_some() {
            head += &format!(" · last turn {}", dur(s["lastDurationMs"].as_f64().unwrap()));
            if let Some(r) = reason.filter(|r| *r != "answer") {
                head += &format!(" ({})", escape(r));
            }
        } else if state == "unknown" {
            head += " · not reporting, restart it to load the mod";
        }
        head += "</span>";
        let mut lines = vec![head];
        if matches!(state, "working" | "waiting") {
            let what: Vec<&str> = ["tool", "detail"].iter().filter_map(|k| s[*k].as_str().filter(|x| !x.is_empty())).collect();
            if !what.is_empty() {
                lines.push(format!("    ⤷ {}", escape(&what.join(" "))));
            }
            let mut extra = vec![format!("{} tool calls", s["tools"].as_i64().unwrap_or(0))];
            if let Some(a) = s["agents"].as_i64().filter(|&a| a != 0) {
                extra.push(format!("{a} subagent{}", if a > 1 { "s" } else { "" }));
            }
            lines.push(format!("    <span color='{ov}'>{}</span>", extra.join(" · ")));
        }
        if let Some(p) = s["prompt"].as_str().filter(|p| !p.is_empty()) {
            lines.push(format!("    <i><span color='{ov}'>“{}”</span></i>", escape(p)));
        }
        let home = home();
        let raw = s["cwd"].as_str().unwrap_or("");
        let cwd = if home.is_empty() { raw.to_string() } else { raw.replacen(&home, "~", 1) };
        lines.push(format!("    <span size='small' color='{ov}'>{}  {}</span>", escape(&cwd), escape(s["model"].as_str().unwrap_or(""))));
        rows.push(lines.join("\n"));
    }
    format!("{}\n\n<span size='small' color='{ov}'>click: jump to the session that needs you</span>", rows.join("\n\n"))
}

/// One icon per session, all in ICON_FONT so every glyph has the same advance.
fn glyph(s: &Value, i: usize, frame: usize, animate: bool, c: &Colors) -> String {
    let inner = match st(s) {
        "working" => {
            let f = if animate { frame + i * 3 } else { 0 }; // on battery: one fixed frame, no redraws
            let breath = (1.0 + (f as f64 / 4.0).sin()) / 2.0;
            format!("<span color='{}'>{}</span>", mix(&c["flow-10"], &c["text"], breath), SPINNER[f % SPINNER.len()])
        }
        "waiting" => format!("<span color='{}'><b>◆</b></span>", c["flow-12"]),
        "done" => {
            let failed = s["lastReason"].as_str().is_some_and(|r| r != "answer");
            format!("<span color='{}'>{}</span>", if failed { &c["flow-12"] } else { &c["green"] }, if failed { "✗" } else { "✓" })
        }
        "unknown" => format!("<span color='{}'>◌</span>", c["overlay2"]),
        _ => format!("<span color='{}'>✻</span>", c["overlay2"]),
    };
    format!("<span font_family='{ICON_FONT}'>{inner}</span>")
}

fn render(ss: &[Value], frame: usize, animate: bool, c: &Colors, tip: &str) -> (Value, bool) {
    if ss.is_empty() {
        return (json!({"text": "", "class": "none", "tooltip": tip}), false);
    }
    let state = st(&ss[0]); // the most urgent session sets the pill's mood
    let text = ss.iter().enumerate().map(|(i, s)| glyph(s, i, frame, animate, c)).collect::<Vec<_>>().join(" ");
    let moving = animate && ss.iter().any(|s| st(s) == "working");
    (json!({"text": text, "class": state, "tooltip": tip, "alt": state}), moving)
}

fn hypr(args: &[&str]) -> Option<Value> {
    let o = Command::new("hyprctl").args(args).output().ok()?;
    serde_json::from_slice(&o.stdout).ok()
}

pub fn focus() {
    let ss = sessions(&claude_procs());
    let Some(target) = ss.first() else { return };
    let Some(mut pid) = target["pid"].as_i64().map(|p| p as i32) else { return };
    let mango = std::env::var_os("MANGO_INSTANCE_SIGNATURE").is_some();
    let clients = if mango {
        let o = Command::new("mmsg").args(["get", "all-clients"]).output().ok();
        o.and_then(|o| serde_json::from_slice::<Value>(&o.stdout).ok()).map(|v| v["clients"].clone())
    } else {
        hypr(&["clients", "-j"])
    };
    let Some(clients) = clients else { return };
    let clients = clients.as_array().cloned().unwrap_or_default();
    let owned = |p: i32| clients.iter().any(|c| c["pid"].as_i64() == Some(p as i64));
    while pid > 1 && !owned(pid) {
        // walk up to the terminal that owns it
        match parent_of(pid) {
            Some((_, pp)) => pid = pp,
            None => return,
        }
    }
    let wins: Vec<&Value> = clients.iter().filter(|c| c["pid"].as_i64() == Some(pid as i64)).collect();
    if wins.is_empty() {
        return;
    }
    // one terminal process may own many windows: prefer the one titled after the session
    let want = name(target).to_lowercase();
    let win = wins.iter().find(|w| !want.is_empty() && w["title"].as_str().unwrap_or("").to_lowercase().contains(&want)).unwrap_or(&wins[0]);
    if mango {
        if let Some(id) = win["id"].as_i64() {
            let _ = Command::new("mmsg").args(["dispatch", "focusid", &format!("client,{id}")]).output();
        }
    } else if let Some(a) = win["address"].as_str() {
        let _ = Command::new("hyprctl").args(["dispatch", "focuswindow", &format!("address:{a}")]).output();
    }
}

// the Claude spinner moves only on AC and while power-fx's effects.conf has the `claudespin` line on
// (a moving spinner redraws the whole bar 5x a second). Unreadable AC or file = on.
fn on_ac() -> bool {
    std::fs::read_to_string("/sys/class/power_supply/AC/online").map(|t| t.trim() != "0").unwrap_or(true)
}

fn spin_on() -> bool {
    let home = std::env::var("HOME").unwrap_or_default();
    std::fs::read_to_string(format!("{home}/syshelp/power-fx/effects.conf"))
        .map(|t| t.lines().any(|l| l.split_whitespace().next() == Some("claudespin")))
        .unwrap_or(true)
}

pub fn run() {
    let parent = getppid(); // waybar; reparented means it is gone
    let (mut frame, mut colors, mut last) = (0usize, palette(FALLBACK), String::new());
    let start = Instant::now();
    let t = || start.elapsed().as_secs_f64();
    let (mut data_at, mut procs_at, mut colors_at) = (f64::NEG_INFINITY, f64::NEG_INFINITY, f64::NEG_INFINITY);
    let (mut procs, mut ss, mut tip) = (vec![], vec![], String::new());
    loop {
        let now = t();
        if now - colors_at > 5.0 {
            colors = palette(FALLBACK);
            colors_at = now;
        }
        if now - procs_at >= PROC_S {
            if getppid() != parent {
                return;
            }
            procs = claude_procs();
            procs_at = now;
        }
        if now - data_at >= DATA_S {
            ss = sessions(&procs);
            data_at = now;
            tip = tooltip(&ss, &colors, now_s() * 1000.0);
        }
        let animate = on_ac() && spin_on();
        let (v, moving) = render(&ss, frame, animate, &colors, &tip);
        let line = v.to_string();
        if line != last {
            emit(&v);
            last = line;
        }
        frame += 1;
        std::thread::sleep(if moving { FAST } else { SLOW });
    }
}
