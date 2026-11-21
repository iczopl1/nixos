//! Mango state: the newest line of each `mmsg watch` stream, parsed only when a press needs it.
use serde::Deserialize;
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Command;

#[derive(Deserialize, Clone, Debug)]
pub struct Client {
    pub id: i64,
    pub pid: i64,
    pub title: String,
    pub appid: String,
    pub monitor: String,
    pub is_visible: bool,
    pub is_fullscreen: bool,
    pub is_floating: bool,
    pub is_minimized: bool,
    pub x: i32,
    pub y: i32,
    pub width: i32,
    pub height: i32,
}

#[derive(Deserialize, Clone, Debug)]
pub struct Monitor {
    pub name: String,
    pub active: bool,
    pub x: i32,
    pub y: i32,
    pub width: i32,
    pub height: i32,
}

#[derive(Deserialize)]
struct Clients {
    clients: Vec<Client>,
}
#[derive(Deserialize)]
struct Monitors {
    monitors: Vec<Monitor>,
}
#[derive(Deserialize)]
struct Focus {
    id: Option<i64>,
    monitor: Option<String>,
}

pub struct Snapshot {
    pub clients: Vec<Client>,
    pub monitors: Vec<Monitor>,
    pub focus_id: Option<i64>,
    pub focus_monitor: Option<String>,
}

type Slot = Arc<Mutex<String>>;

#[derive(Clone, Default)]
pub struct Mango {
    clients: Slot,
    monitors: Slot,
    focus: Slot,
}

impl Mango {
    pub fn start() -> Mango {
        let m = Mango::default();
        for (what, slot) in [("all-clients", &m.clients), ("all-monitors", &m.monitors), ("focusing-client", &m.focus)] {
            tokio::spawn(watch(what, slot.clone()));
        }
        m
    }

    pub fn snapshot(&self) -> Option<Snapshot> {
        let take = |s: &Slot| s.lock().unwrap().clone();
        let clients: Clients = serde_json::from_str(&take(&self.clients)).ok()?;
        let monitors: Monitors = serde_json::from_str(&take(&self.monitors)).ok()?;
        let focus: Option<Focus> = serde_json::from_str(&take(&self.focus)).ok();
        Some(Snapshot {
            clients: clients.clients,
            monitors: monitors.monitors,
            focus_id: focus.as_ref().and_then(|f| f.id),
            focus_monitor: focus.and_then(|f| f.monitor),
        })
    }
}

/// Keeps only the newest line; restarts the stream with a growing pause if it dies.
async fn watch(what: &'static str, slot: Slot) {
    let mut pause = Duration::from_millis(250);
    loop {
        let child = Command::new("mmsg")
            .args(["watch", what])
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::null())
            .kill_on_drop(true)
            .spawn();
        if let Ok(mut child) = child {
            if let Some(out) = child.stdout.take() {
                let mut lines = BufReader::new(out).lines();
                while let Ok(Some(line)) = lines.next_line().await {
                    pause = Duration::from_millis(250);
                    *slot.lock().unwrap() = line;
                }
            }
            let _ = child.wait().await;
        }
        tokio::time::sleep(pause).await;
        pause = (pause * 2).min(Duration::from_secs(8));
    }
}

/// borderpx from the mango config (last one wins, like mango); 2 = what this setup draws without one.
pub fn border() -> i32 {
    let mut bw = 2;
    let base = std::env::var("XDG_CONFIG_HOME")
        .unwrap_or_else(|_| format!("{}/.config", std::env::var("HOME").unwrap_or_default()));
    for name in ["config.conf", "mango-wal.conf"] {
        if let Ok(text) = std::fs::read_to_string(format!("{base}/mango/{name}")) {
            for line in text.lines() {
                if let Some((k, v)) = line.split_once('=') {
                    if k.trim() == "borderpx" {
                        if let Ok(n) = v.trim().parse() {
                            bw = n;
                        }
                    }
                }
            }
        }
    }
    bw
}
