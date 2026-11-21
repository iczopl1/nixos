//! hintd: reads clickable AT-SPI fields on request and clicks at a picked spot.
//! Idle = blocked on its socket. Socket protocol (one request per connection):
//!   "boxes\n"                -> "<monitor>\n" then one "x y w h" per line, monitor-local
//!   "boxes live\n"           -> same, but no picture boxes (live mode refreshes every ~50 ms)
//!   "click <mon> x y l|m|r|x|n|h|d\n" -> "ok\n"  (see click.rs)
mod atspi;
mod boxes;
mod click;
mod mango;
mod shot;
mod vision;

use atspi::{Atspi, Node, Rect, Window, MAX_PER_SOURCE};
use boxes::{clip, dedupe, merge_rows, MAX_RECTS};
use futures_util::future::join_all;
use mango::{Client, Mango};
use std::collections::HashMap;
use std::os::unix::fs::PermissionsExt;
use std::time::Duration;
use tokio::io::{AsyncBufReadExt, AsyncReadExt, AsyncWriteExt, BufReader};
use tokio::net::{UnixListener, UnixStream};

fn deadline() -> Duration {
    Duration::from_millis(std::env::var("HINTD_DEADLINE_MS").ok().and_then(|v| v.parse().ok()).unwrap_or(300))
}

/// The accessible window matching this Mango window, or None if unsure.
async fn pick_win<'a>(at: &Atspi, wins: &'a [Window], title: &str, size: (i32, i32)) -> Option<&'a Window> {
    let same: Vec<&Window> = wins
        .iter()
        .filter(|w| {
            let fits = |(_, _, ww, wh): Rect| (ww == 0 && wh == 0) || ((ww - size.0).abs() <= 2 && (wh - size.1).abs() <= 2);
            fits(w.extents) || fits(w.screen)
        })
        .collect();
    if wins.len() == 1 || title.is_empty() {
        return (same.len() == 1).then(|| same[0]);
    }
    let names = join_all(same.iter().map(|w| at.window_name(w))).await;
    let ok: Vec<&Window> = same.into_iter().zip(names).filter(|(_, n)| n.as_deref() == Some(title)).map(|(w, _)| w).collect();
    (ok.len() == 1).then(|| ok[0])
}

/// Boxes of one window, global coordinates. None = could not tell which window it is.
async fn read_client(at: &Atspi, vp: &vision::Params, roots: &[Node], c: &Client, bw: i32) -> Option<Vec<Rect>> {
    let b = if c.is_fullscreen { 0 } else { bw };
    let (x, y, w, h) = (c.x + b, c.y + b, c.width - 2 * b, c.height - 2 * b);
    let wins = at.windows(roots).await;
    let win = match pick_win(at, &wins, &c.title, (w, h)).await {
        Some(w) => w,
        None => {
            eprintln!("hintd: no unique accessible window for {:?} {:?}, using picture", c.appid, c.title);
            return vision::boxes(vp, (x, y, w, h)).await.map(|mut v| { v.truncate(MAX_PER_SOURCE); v });
        }
    };
    // Window coordinates are right unless the window reports a stale size there (VLC): then the screen ones are.
    let fits = |(_, _, ww, wh): Rect| (ww == 0 && wh == 0) || ((ww - w).abs() <= 2 && (wh - h).abs() <= 2);
    let use_screen = !fits(win.extents) && fits(win.screen);
    let (coords, origin) = if use_screen { (atspi::SCREEN_COORDS, win.screen) } else { (atspi::WINDOW_COORDS, win.extents) };
    if debug() { eprintln!("hintd: {} window extents {:?} screen {:?}, client {:?}", c.appid, win.extents, win.screen, (x, y, w, h)); }
    let t0 = std::time::Instant::now();
    let tree = async {
        match at.collect(&win.node, coords).await {
            Some(f) => f,
            None => {
                if debug() { eprintln!("hintd: {} has no Collection", c.appid); }
                at.walk(&win.node, coords).await
            }
        }
    };
    // Empty lists get picture boxes; the grim screenshot runs while the tree is still being read.
    let pictures = async {
        let spots: Vec<Rect> = at
            .holes(&win.node, coords)
            .await
            .into_iter()
            .filter_map(|(hx, hy, hw, hh)| clip((hx.saturating_sub(origin.0).saturating_add(x), hy.saturating_sub(origin.1).saturating_add(y), hw, hh), (x, y, w, h)))
            .collect();
        join_all(spots.iter().map(|s| vision::boxes(vp, *s))).await.into_iter().flatten().flatten().collect::<Vec<Rect>>()
    };
    let (found, pics) = futures_util::future::join(tree, pictures).await;
    if debug() { eprintln!("hintd: {} {} raw boxes in {:?}", c.appid, found.len(), t0.elapsed()); }
    let mut out = pics;
    let mut cells = vec![];
    for (kind, (ex, ey, ew, eh)) in found {
        if let Some(r) = clip((ex.saturating_sub(origin.0).saturating_add(x), ey.saturating_sub(origin.1).saturating_add(y), ew, eh), (x, y, w, h)) {
            if kind == 3 { cells.push(r) } else { out.push(r) }
        }
    }
    out.extend(merge_rows(cells));
    if out.is_empty() {
        // The app is on the bus but exposes nothing (video streams such as Moonlight): the picture is all there is.
        if debug() { eprintln!("hintd: {} exposes no fields, using picture", c.appid); }
        out = vision::boxes(vp, (x, y, w, h)).await.unwrap_or_default();
    }
    out.truncate(MAX_PER_SOURCE);
    Some(out)
}

/// Apps whose AT-SPI side did not answer in time, and when: they go straight to the picture for a while
/// instead of making every keypress wait out the deadline (video streams such as Moonlight never answer).
static SILENT: std::sync::Mutex<Option<HashMap<i64, std::time::Instant>>> = std::sync::Mutex::new(None);
const SILENT_FOR: Duration = Duration::from_secs(60);

fn is_silent(pid: i64) -> bool {
    SILENT.lock().unwrap().as_ref().and_then(|m| m.get(&pid)).is_some_and(|t| t.elapsed() < SILENT_FOR)
}

async fn press(at: &mut Atspi, mango: &Mango, vp: &vision::Params, bw: i32) -> Option<(String, Vec<Rect>)> {
    let snap = mango.snapshot()?;
    let target = snap
        .focus_monitor
        .clone()
        .or_else(|| snap.monitors.iter().find(|m| m.active).map(|m| m.name.clone()))?;
    let mon = snap.monitors.iter().find(|m| m.name == target)?.clone();
    let mut clients: Vec<Client> = snap
        .clients
        .into_iter()
        .filter(|c| c.monitor == target && c.is_visible && !c.is_minimized)
        .collect();
    let focused = |c: &Client| Some(c.id) == snap.focus_id;
    if clients.iter().any(|c| focused(c) && c.is_fullscreen) {
        clients.retain(|c| focused(c));
    }
    clients.sort_by_key(|c| !focused(c));

    let t_apps = std::time::Instant::now();
    let mut by_pid: HashMap<i64, Vec<Node>> = HashMap::new();
    let app_list = at.apps().await;
    if debug() { eprintln!("hintd: apps() {:?}", t_apps.elapsed()); }
    for (root, pid) in app_list {
        by_pid.entry(pid).or_default().push(root);
    }
    let at = &*at;
    let t_read = std::time::Instant::now();
    let dl = deadline();
    let results = join_all(clients.iter().map(|c| {
        let roots = by_pid.get(&c.pid).cloned();
        async move {
            // Alacritty: one hint on the whole window, no picture scan.
            if c.appid.eq_ignore_ascii_case("alacritty") {
                let b = if c.is_fullscreen { 0 } else { bw };
                return Some(vec![(c.x + b, c.y + b, c.width - 2 * b, c.height - 2 * b)]);
            }
            // No accessible app (terminals): the window's picture is all there is.
            let roots = roots.filter(|_| !is_silent(c.pid));
            let Some(roots) = roots else {
                let b = if c.is_fullscreen { 0 } else { bw };
                let rect = (c.x + b, c.y + b, c.width - 2 * b, c.height - 2 * b);
                return tokio::time::timeout(dl, vision::boxes(vp, rect)).await.ok().flatten().map(|mut v| { v.truncate(MAX_PER_SOURCE); v });
            };
            match tokio::time::timeout(dl, read_client(at, vp, &roots, c, bw)).await {
                Ok(r) => r,
                Err(_) => {
                    // On the bus but silent (video streams such as Moonlight): the picture is all there is.
                    eprintln!("hintd: {:?} did not answer in {dl:?}, using picture", c.appid);
                    // Live polling is harder on slow apps than one press: it must not send them to the picture for a minute.
                    if !vision::PAUSED.load(std::sync::atomic::Ordering::Relaxed) {
                        SILENT.lock().unwrap().get_or_insert_with(HashMap::new).insert(c.pid, std::time::Instant::now());
                    }
                    let b = if c.is_fullscreen { 0 } else { bw };
                    let rect = (c.x + b, c.y + b, c.width - 2 * b, c.height - 2 * b);
                    tokio::time::timeout(dl, vision::boxes(vp, rect)).await.ok().flatten().map(|mut v| { v.truncate(MAX_PER_SOURCE); v })
                }
            }
        }
    }))
    .await;

    if debug() { eprintln!("hintd: read all clients {:?}", t_read.elapsed()); }
    // Drop boxes hidden under a window drawn above them (floating sits above tiled).
    let fh = |c: &Client| if focused(c) { 0 } else { 1_000_000 };
    let mut items: Vec<Rect> = vec![];
    for (c, r) in clients.iter().zip(results) {
        let above: Vec<Rect> = clients
            .iter()
            .filter(|o| o.id != c.id && o.is_floating && (!c.is_floating || fh(o) < fh(c)))
            .map(|o| (o.x, o.y, o.width, o.height))
            .collect();
        for b in r.unwrap_or_default() {
            let (cx, cy) = (b.0 as f64 + b.2 as f64 / 2.0, b.1 as f64 + b.3 as f64 / 2.0);
            let hidden = above.iter().any(|a| {
                a.0 as f64 <= cx && cx < (a.0 + a.2) as f64 && a.1 as f64 <= cy && cy < (a.1 + a.3) as f64
            });
            if !hidden {
                items.push(b);
            }
        }
    }
    items.truncate(800);
    let rank: HashMap<Rect, usize> = items.iter().enumerate().fold(HashMap::new(), |mut m, (i, b)| {
        m.entry(*b).or_insert(i);
        m
    });
    let mut boxes = dedupe(items);
    boxes.sort_by_key(|b| rank[b]);
    boxes.truncate(MAX_RECTS);

    let (mw, mh) = (mon.width, mon.height);
    let res = boxes
        .into_iter()
        .filter_map(|(x, y, w, h)| clip((x - mon.x, y - mon.y, w, h), (0, 0, mw, mh)))
        .collect();
    Some((target, res))
}

async fn serve_one(s: UnixStream, at: &mut Atspi, mango: &Mango, vp: &vision::Params, clicker: &mut Option<click::Clicker>, bw: i32) -> std::io::Result<()> {
    let (rd, mut wr) = s.into_split();
    let mut line = String::new();
    // A client that connects and says nothing must not freeze the one-thread loop.
    let io_limit = Duration::from_secs(2);
    match tokio::time::timeout(io_limit, BufReader::new(rd.take(300)).read_line(&mut line)).await {
        Ok(r) => { r?; }
        Err(_) => return Ok(()),
    }
    if !line.ends_with('\n') {
        return Ok(());
    }
    let parts: Vec<&str> = line.split_whitespace().collect();
    match parts.as_slice() {
        ["boxes"] | ["boxes", "live"] => {
            vision::PAUSED.store(parts.len() == 2, std::sync::atomic::Ordering::Relaxed);
            let out = match tokio::time::timeout(Duration::from_secs(3), press(at, mango, vp, bw)).await.ok().flatten() {
                Some((mon, rs)) => {
                    let mut o = format!("{mon}\n");
                    for (x, y, w, h) in rs {
                        o.push_str(&format!("{x} {y} {w} {h}\n"));
                    }
                    o
                }
                None => "\n".to_string(),
            };
            vision::PAUSED.store(false, std::sync::atomic::Ordering::Relaxed);
            wr.write_all(out.as_bytes()).await?;
        }
        ["click", mon, x, y, kind] => {
            let reply = do_click(mango, clicker, mon, x, y, kind);
            wr.write_all(reply.as_bytes()).await?;
        }
        ["release"] => {
            let r = clicker.as_mut().map(|c| c.release()).unwrap_or(Err("no pointer".into()));
            wr.write_all(if r.is_ok() { b"ok\n" } else { b"err\n" }).await?;
        }
        ["state"] => {
            let hold = clicker.as_ref().is_some_and(|c| c.holding());
            wr.write_all(if hold { b"hold\n" } else { b"idle\n" }).await?;
        }
        _ => {}
    }
    Ok(())
}

fn socket_path() -> std::path::PathBuf {
    let run = std::fs::canonicalize(std::env::var_os("XDG_RUNTIME_DIR").expect("XDG_RUNTIME_DIR not set")).expect("XDG_RUNTIME_DIR");
    let path = std::env::var_os("HINTD_SOCK").map(std::path::PathBuf::from).unwrap_or_else(|| run.join("hintd.sock"));
    // The socket can click anywhere: it must live in the private runtime directory, nowhere else.
    let dir = path.parent().and_then(|p| std::fs::canonicalize(p).ok());
    if dir.as_deref() != Some(run.as_path()) {
        eprintln!("hintd: socket must live directly in $XDG_RUNTIME_DIR");
        std::process::exit(2);
    }
    path
}

#[tokio::main(flavor = "current_thread")]
async fn main() {
    let path = socket_path();
    if std::os::unix::net::UnixStream::connect(&path).is_ok() {
        eprintln!("hintd: already running");
        std::process::exit(1);
    }
    // Only a stale socket may be removed, never some other file of the same name.
    if let Ok(md) = std::fs::symlink_metadata(&path) {
        use std::os::unix::fs::FileTypeExt;
        if !md.file_type().is_socket() {
            eprintln!("hintd: {} exists and is not a socket", path.display());
            std::process::exit(2);
        }
        let _ = std::fs::remove_file(&path);
    }
    let listener = UnixListener::bind(&path).expect("bind socket");
    std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o600)).expect("chmod socket");
    let mut at = Atspi::connect().await.expect("accessibility bus");
    let mut clicker = click::Clicker::connect().map_err(|e| eprintln!("hintd: clicks off: {e}")).ok();
    let mango = Mango::start();
    let bw = mango::border();
    let vp = vision::Params::load();
    loop {
        match listener.accept().await {
            Ok((s, _)) => {
                if let Err(e) = serve_one(s, &mut at, &mango, &vp, &mut clicker, bw).await {
                    eprintln!("hintd: {e}");
                }
            }
            Err(e) => eprintln!("hintd: accept: {e}"),
        }
    }
}

fn debug() -> bool {
    std::env::var_os("HINTD_DEBUG").is_some()
}

/// "click <monitor> <x> <y> <l|m|r|x|n|h|d>": numbers are strictly parsed, nothing else is trusted.
fn do_click(mango: &Mango, clicker: &mut Option<click::Clicker>, mon: &str, x: &str, y: &str, kind: &str) -> String {
    let num = |s: &str| s.parse::<i32>().ok().filter(|v| (-100_000..=100_000).contains(v));
    let (Some(x), Some(y)) = (num(x), num(y)) else { return "err bad number\n".into() };
    let kind = match kind {
        "l" => 'l', "m" => 'm', "r" => 'r', "h" => 'h', "d" => 'd', "n" => 'n', "x" => 'x',
        _ => return "err bad button\n".into(),
    };
    if debug() { eprintln!("hintd: click {mon} {x} {y} {kind}"); }
    let Some(snap) = mango.snapshot() else { return "err no mango state\n".into() };
    let Some(m) = snap.monitors.iter().find(|m| m.name == mon) else { return "err unknown monitor\n".into() };
    if x < 0 || x >= m.width || y < 0 || y >= m.height {
        return "err outside monitor\n".into();
    }
    let Some(c) = clicker.as_mut() else { return "err clicks unavailable\n".into() };
    match c.click(mon, x, y, m.width, m.height, kind) {
        Ok(()) => if c.holding() { "ok hold\n".into() } else { "ok\n".into() },
        Err(e) => format!("err {e}\n"),
    }
}
