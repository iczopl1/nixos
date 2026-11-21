//! Goal pill for clev / hintdrive: opens the goal prompt and shows what a run is doing.
//!
//! No polling: blocks on inotify over $XDG_RUNTIME_DIR/<name> and on a pidfd of
//! the running <name>-goal. Frames tick only while a run is active.

use crate::common::*;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::os::unix::process::CommandExt;
use std::process::{Command, Stdio};

const FALLBACK: &[(&str, &str)] = &[
    ("flow-1", "#4fb3ff"), ("flow-2", "#5ab0fb"), ("flow-3", "#6faef7"), ("flow-4", "#80aaf3"),
    ("flow-5", "#8fa8ef"), ("flow-6", "#9fa6eb"), ("flow-7", "#afa5e7"), ("flow-8", "#bfa3e3"),
    ("flow-9", "#cfa1df"), ("flow-10", "#df9fdb"), ("flow-11", "#ef9cd7"), ("flow-12", "#ff9ad3"),
    ("text", "#ffd7e3"), ("overlay2", "#8c96b8"),
];
const ICON_FONT: &str = "DejaVu Sans Mono";
const SPIN: [&str; 4] = ["◐", "◓", "◑", "◒"];
const FRAME_MS: i32 = 150;
const PROMPT_W: i64 = 440;
const PROMPT_GAP: i64 = 6;
const DEFAULT_PILL_X: i64 = 244;
const ICON_X: i64 = 18;

pub struct Flow {
    name: &'static str,
    title: &'static str, // "Clev AI" / "hintdrive"
    run: String,
}

#[derive(PartialEq, Clone, Copy)]
enum St {
    Idle,
    Running,
    Confirm,
}

impl St {
    fn s(self) -> &'static str {
        match self {
            St::Idle => "idle",
            St::Running => "running",
            St::Confirm => "confirm",
        }
    }
}

impl Flow {
    pub fn new(name: &'static str) -> Self {
        let title = if name == "clev" { "Clev AI" } else { name };
        Flow { name, title, run: format!("{}/{}", runtime_dir(), name) }
    }

    fn driver_pid(&self) -> Option<i32> {
        let pid: i32 = std::fs::read_to_string(format!("{}/driver.pid", self.run)).ok()?.trim().parse().ok()?;
        let cmd = std::fs::read(format!("/proc/{pid}/cmdline")).ok()?;
        let needle = format!("{}-goal", self.name);
        cmd.windows(needle.len()).any(|w| w == needle.as_bytes()).then_some(pid)
    }

    fn state(&self) -> (St, Option<i32>) {
        let pid = self.driver_pid();
        if std::path::Path::new(&format!("{}/answer", self.run)).exists() {
            return (St::Confirm, pid);
        }
        (if pid.is_some() { St::Running } else { St::Idle }, pid)
    }

    fn goal_text(&self) -> String {
        std::fs::read_to_string(format!("{}/goal", self.run))
            .map(|s| s.split_whitespace().collect::<Vec<_>>().join(" "))
            .unwrap_or_default()
    }

    fn icon(glyph: &str, color: &str) -> String {
        format!("<span weight='bold' font_family='{ICON_FONT}' size='large' color='{color}'>{glyph}</span>")
    }

    fn render(&self, st: St, c: &HashMap<String, String>, frame: usize) -> Value {
        let (text, tip) = match st {
            St::Confirm => (
                Self::icon("?", &c["flow-12"]),
                format!("{} is waiting on you\nleft click / SUPER+Y  allow\nright click / SUPER+N  deny\n60 s without an answer = deny", self.title),
            ),
            St::Running => {
                let goal = self.goal_text();
                let step = frame % 22;
                let idx = 1 + if step < 12 { step } else { 22 - step };
                let text = Self::icon(SPIN[frame % 4], &c[&format!("flow-{idx}")]);
                let head = if goal.is_empty() {
                    format!("{} is working\n", self.title)
                } else {
                    format!("{}: {}\n", self.title, escape(&goal))
                };
                (text, head + "right click / SUPER+SHIFT+Esc  stop")
            }
            St::Idle => (
                Self::icon("✦", &c["flow-12"]),
                format!("{}: what should I help with?\nleft click / SUPER+SHIFT+D  type a goal", self.title),
            ),
        };
        json!({"text": text, "class": st.s(), "alt": st.s(), "tooltip": tip})
    }

    pub fn watch(&self) {
        let _ = std::fs::create_dir_all(&self.run);
        let _ = std::fs::set_permissions(&self.run, std::os::unix::fs::PermissionsExt::from_mode(0o700));
        let ino = unsafe { libc::inotify_init1(libc::IN_CLOEXEC) };
        let mask = libc::IN_CREATE | libc::IN_DELETE | libc::IN_CLOSE_WRITE | libc::IN_MOVED_FROM
            | libc::IN_MOVED_TO | libc::IN_DELETE_SELF;
        let dir = std::ffi::CString::new(self.run.clone()).unwrap();
        if ino < 0 || unsafe { libc::inotify_add_watch(ino, dir.as_ptr(), mask) } < 0 {
            eprintln!("{}-status: inotify: {}", self.name, std::io::Error::last_os_error());
            std::process::exit(1);
        }
        let (mut c, mut last, mut pidfd, mut watched, mut frame) =
            (palette(FALLBACK), String::new(), -1i32, None::<i32>, 0usize);
        loop {
            let (st, pid) = self.state();
            if pid != watched {
                // follow the run's process: its exit wakes us even without a file event
                if pidfd >= 0 {
                    unsafe { libc::close(pidfd) };
                    pidfd = -1;
                }
                watched = pid;
                if let Some(p) = pid {
                    pidfd = unsafe { libc::syscall(libc::SYS_pidfd_open, p, 0) } as i32;
                }
            }
            let v = self.render(st, &c, frame);
            let line = v.to_string();
            if line != last {
                emit(&v);
                last = line;
            }
            let mut fds = vec![ino];
            if pidfd >= 0 {
                fds.push(pidfd);
            }
            let ready = poll(&fds, if st == St::Running { FRAME_MS } else { -1 });
            frame = if st == St::Running { frame + 1 } else { 0 };
            if ready[0] {
                let mut buf = [0u8; 4096];
                let n = unsafe { libc::read(ino, buf.as_mut_ptr().cast(), buf.len()) };
                let mut off = 0usize;
                while n > 0 && off + 16 <= n as usize {
                    let m = u32::from_ne_bytes(buf[off + 4..off + 8].try_into().unwrap());
                    let len = u32::from_ne_bytes(buf[off + 12..off + 16].try_into().unwrap()) as usize;
                    if m & libc::IN_DELETE_SELF != 0 {
                        // run dir removed: start over
                        let exe = std::env::current_exe().unwrap_or_else(|_| "wbw".into());
                        let err = Command::new(exe).args(std::env::args().skip(1)).exec();
                        eprintln!("{}-status: exec: {err}", self.name);
                        std::process::exit(1);
                    }
                    off += 16 + len;
                }
                c = palette(FALLBACK); // cheap; picks up a wal re-theme on the next event
            }
        }
    }

    fn prompt_theme(c: &HashMap<String, String>, x: i64, y: i64) -> String {
        let base = c.get("base").map(String::as_str).unwrap_or("#293c47");
        let (hi, text, ov) = (&c["flow-12"], &c["text"], &c["overlay2"]);
        format!(
            "\n* {{ background-color: transparent; text-color: {text}; font: \"DejaVu Sans 11\"; }}\n\
window {{ location: north west; anchor: north west; x-offset: {x}px; y-offset: {y}px;\n  \
width: {PROMPT_W}px; border: 2px solid; border-radius: 12px;\n  border-color: {hi};\n  \
background-color: {base}f2; padding: 4px 10px; }}\n\
mainbox {{ children: [ inputbar ]; padding: 0; spacing: 0; }}\n\
inputbar {{ children: [ prompt, entry ]; spacing: 10px; padding: 6px 2px; }}\n\
prompt {{ text-color: {hi}; }}\n\
entry {{ placeholder: \"What should I help with?\"; placeholder-color: {ov};\n  cursor: text; }}\n"
        )
    }

    fn sh(cmd: &str, args: &[&str]) -> String {
        Command::new(cmd).args(args).stdin(Stdio::null()).stderr(Stdio::null()).output()
            .map(|o| String::from_utf8_lossy(&o.stdout).into_owned()).unwrap_or_default()
    }

    /// Top-left for the prompt: its ✦ under the pill's ✦, kept on the monitor.
    fn prompt_at(&self, clicked: bool) -> (i64, i64) {
        let fallback = (8, PROMPT_GAP);
        let pill_x = format!("{}/.cache/{}/pill-x", home(), self.name);
        // mango reports logical monitor sizes; hyprland physical ones plus a scale
        let mango = std::env::var_os("MANGO_INSTANCE_SIGNATURE").is_some();
        let mons: Value = match serde_json::from_str(&if mango {
            Self::sh("mmsg", &["get", "all-monitors"])
        } else {
            Self::sh("hyprctl", &["monitors", "-j"])
        }) {
            Ok(v) => v,
            Err(_) => return fallback,
        };
        let (list, key) = if mango { (&mons["monitors"], "active") } else { (&mons, "focused") };
        let Some(mon) = list.as_array().and_then(|a| a.iter().find(|m| m[key] == true)) else {
            return fallback;
        };
        let mx = mon["x"].as_i64().unwrap_or(0);
        let px = if clicked {
            let cx = if mango {
                serde_json::from_str::<Value>(&Self::sh("mmsg", &["get", "cursorpos"])).ok().and_then(|v| v["x"].as_f64()).map(|x| x as i64)
            } else {
                Self::sh("hyprctl", &["cursorpos"]).split(',').next().unwrap_or("").trim().parse::<i64>().ok()
            };
            let Some(cx) = cx else {
                return fallback;
            };
            let px = cx - mx;
            let _ = std::fs::create_dir_all(format!("{}/.cache/{}", home(), self.name));
            let _ = std::fs::write(&pill_x, px.to_string());
            px
        } else {
            std::fs::read_to_string(&pill_x).ok().and_then(|s| s.trim().parse().ok()).unwrap_or(DEFAULT_PILL_X)
        };
        let (w, s) = (mon["width"].as_f64().unwrap_or(0.0), if mango { 1.0 } else { mon["scale"].as_f64().unwrap_or(1.0) });
        let w = (w / s).round() as i64;
        ((px - ICON_X).max(8).min(w - PROMPT_W - 8), PROMPT_GAP)
    }

    fn ask_goal(&self, clicked: bool) -> String {
        let (x, y) = self.prompt_at(clicked);
        let theme = format!("{}/prompt.rasi", self.run); // a whole theme: nothing leaks in from config.rasi
        let _ = std::fs::create_dir_all(&self.run);
        if std::fs::write(&theme, Self::prompt_theme(&palette(FALLBACK), x, y)).is_err() {
            return String::new();
        }
        let out = Command::new("rofi").args(["-dmenu", "-p", "✦", "-theme", &theme])
            .stdin(Stdio::null()).stderr(Stdio::null()).output();
        match out {
            Ok(o) if o.status.success() => String::from_utf8_lossy(&o.stdout).trim().to_string(),
            _ => String::new(),
        }
    }

    fn start(&self, clicked: bool) {
        let goal = self.ask_goal(clicked);
        if goal.is_empty() {
            return;
        }
        let mut cmd = Command::new(format!("{}-goal", self.name));
        cmd.arg(goal).stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null());
        unsafe {
            cmd.pre_exec(|| {
                libc::setsid();
                Ok(())
            });
        }
        let _ = cmd.spawn();
    }

    pub fn click(&self, button: &str) {
        let st = self.state().0;
        if button == "L" && st == St::Idle {
            self.start(true);
        } else if st == St::Confirm {
            let _ = Command::new(self.name).args(["answer", if button == "L" { "y" } else { "n" }]).status();
        } else if button == "R" && st == St::Running {
            let _ = Command::new(self.name).arg("stop").status();
        }
    }

    pub fn hotkey(&self) {
        if self.state().0 == St::Idle {
            self.start(false);
        } else {
            let _ = Command::new("notify-send")
                .args(["-a", self.name, &format!("{} busy", self.name),
                        "A goal is already running (SUPER+SHIFT+Escape stops it)"])
                .status();
        }
    }
}
