//! Picture-based boxes for what AT-SPI cannot see: windows with no accessible app (terminals)
//! and empty lists such as Ferdium's service rail. Same idea as wl-kbptr's "detect" mode:
//! edges, thickened until letters merge into words, bounding boxes of what is left.
use crate::atspi::Rect;
use crate::shot::Capturer;
use std::process::Stdio;
use tokio::io::AsyncReadExt;
use tokio::process::Command;

/// detect_* knobs, read from the user's wl-kbptr config like the old daemon did.
pub struct Params {
    min_w: i32,
    min_h: i32,
    max_w: i32,
    max_h: i32,
    merge_x: f64,
    merge_y: f64,
    edge_low: i32,
    edge_high: i32,
    /// In-process screen capture; None = use the grim program.
    cap: Option<Capturer>,
}

impl Params {
    pub fn load() -> Params {
        let cap = if std::env::var_os("HINTD_GRIM").is_some() {
            None
        } else {
            Capturer::connect().map_err(|e| eprintln!("hintd: in-process capture off, using grim: {e}")).ok()
        };
        let mut p = Params { min_w: 8, min_h: 4, max_w: 499, max_h: 49, merge_x: 3.5, merge_y: 2.5, edge_low: 70, edge_high: 220, cap };
        let cfg = std::env::var_os("XDG_CONFIG_HOME")
            .map(std::path::PathBuf::from)
            .or_else(|| std::env::var_os("HOME").map(|h| std::path::PathBuf::from(h).join(".config")))
            .map(|d| d.join("wl-kbptr/config"));
        let Some(text) = cfg.and_then(|f| std::fs::read_to_string(f).ok()) else { return p };
        let mut section = String::new();
        for line in text.lines() {
            let line = line.trim();
            if let Some(s) = line.strip_prefix('[').and_then(|l| l.strip_suffix(']')) {
                section = s.to_string();
            } else if section == "mode_floating" {
                if let Some((k, v)) = line.split_once('=') {
                    let v = v.trim().parse::<f64>().ok();
                    match (k.trim(), v) {
                        ("detect_min_width", Some(v)) => p.min_w = v as i32,
                        ("detect_min_height", Some(v)) => p.min_h = v as i32,
                        ("detect_max_width", Some(v)) => p.max_w = v as i32,
                        ("detect_max_height", Some(v)) => p.max_h = v as i32,
                        ("detect_merge_x", Some(v)) => p.merge_x = v,
                        ("detect_merge_y", Some(v)) => p.merge_y = v,
                        ("detect_edge_low", Some(v)) => p.edge_low = v as i32,
                        ("detect_edge_high", Some(v)) => p.edge_high = v as i32,
                        _ => {}
                    }
                }
            }
        }
        p
    }
}

fn debug() -> bool {
    std::env::var_os("HINTD_DEBUG").is_some()
}

/// A gray picture: width, height, one byte per pixel.
type Gray = (usize, usize, Vec<u8>);

/// The grim program: slower than the in-process capture, kept for compositors without wlr-screencopy.
async fn gray_by_grim((x, y, w, h): Rect) -> Option<Gray> {
    let mut child = Command::new("grim")
        .args(["-t", "ppm", "-s", "1", "-g", &format!("{x},{y} {w}x{h}"), "-"])
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .kill_on_drop(true)
        .spawn()
        .ok()?;
    let mut ppm = Vec::with_capacity((w * h * 3 + 32) as usize);
    child.stdout.take()?.read_to_end(&mut ppm).await.ok()?;
    child.wait().await.ok()?;
    gray_from_ppm(&ppm)
}

/// Set while a live-mode refresh runs: picture boxes are skipped (the overlay would be photographed, and 50 ms leaves no room).
pub static PAUSED: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

/// Boxes inside one screen rectangle (global coordinates), top to bottom. None = the screenshot failed.
pub async fn boxes(p: &Params, rect @ (x, y, w, h): Rect) -> Option<Vec<Rect>> {
    if w < 8 || h < 8 || PAUSED.load(std::sync::atomic::Ordering::Relaxed) || std::env::var_os("HINTD_NO_VISION").is_some() {
        return Some(vec![]);
    }
    let t0 = std::time::Instant::now();
    let mut shot = None;
    if let Some(c) = p.cap.clone() {
        shot = tokio::task::spawn_blocking(move || c.gray(rect)).await.ok().flatten();
    }
    let (iw, ih, gray) = match shot {
        Some(g) => g,
        None => gray_by_grim(rect).await?,
    };
    if (iw as i32 - w).abs() > 2 || (ih as i32 - h).abs() > 2 {
        return None;
    }
    let t_shot = t0.elapsed();
    let (lo, hi) = (p.edge_low, p.edge_high);
    let (kw, kh) = ((p.merge_x * 2.0) as usize + 1, (p.merge_y * 2.0) as usize + 1);
    let found = tokio::task::spawn_blocking(move || analyse(&gray, iw, ih, lo, hi, kw, kh)).await.ok()?;
    if debug() {
        eprintln!("hintd: vision {w}x{h}: screenshot {t_shot:?}, analysis {:?}", t0.elapsed() - t_shot);
    }
    let mut out: Vec<Rect> = found
        .into_iter()
        .filter(|&(_, _, bw, bh)| p.min_w <= bw && bw <= p.max_w && p.min_h <= bh && bh <= p.max_h)
        .map(|(bx, by, bw, bh)| (x + bx, y + by, bw.min(w - bx), bh.min(h - by)))
        .collect();
    out.sort_by_key(|r| (r.1, r.0));
    Some(out)
}

pub(crate) fn gray_from_ppm(d: &[u8]) -> Option<Gray> {
    // "P6\n<w> <h>\n255\n" then rgb bytes
    let mut pos = 0;
    let mut tok = || {
        while d.get(pos).is_some_and(|c| c.is_ascii_whitespace()) {
            pos += 1;
        }
        let s = pos;
        while d.get(pos).is_some_and(|c| !c.is_ascii_whitespace()) {
            pos += 1;
        }
        std::str::from_utf8(&d[s..pos]).ok().map(str::to_string)
    };
    if tok()? != "P6" {
        return None;
    }
    let (w, h): (usize, usize) = (tok()?.parse().ok()?, tok()?.parse().ok()?);
    let _max = tok()?;
    pos += 1;
    let px = d.get(pos..pos + w * h * 3)?;
    let gray = px.chunks_exact(3).map(|c| ((c[0] as u32 * 299 + c[1] as u32 * 587 + c[2] as u32 * 114) / 1000) as u8).collect();
    Some((w, h, gray))
}

/// Edges, thickening, blobs: the three steps of the picture analysis.
pub fn analyse(gray: &[u8], w: usize, h: usize, lo: i32, hi: i32, kw: usize, kh: usize) -> Vec<Rect> {
    let edges = canny(gray, w, h, lo, hi);
    let edges = dilate(&edges, w, h, kw, kh);
    components(&edges, w, h)
}

/// Workers for the row-parallel steps: a few, since the work is short and the user's cores are shared.
fn workers() -> usize {
    std::thread::available_parallelism().map(|n| n.get()).unwrap_or(1).clamp(1, 4)
}

/// Run `f(first_row, rows_of_the_buffer)` over bands of whole rows, one thread per band.
fn par_rows<F: Fn(usize, &mut [u8]) + Sync>(buf: &mut [u8], w: usize, h: usize, f: F) {
    let band = h.div_ceil(workers()).max(1);
    if w == 0 || h == 0 {
        return;
    }
    std::thread::scope(|s| {
        for (i, chunk) in buf.chunks_mut(band * w).enumerate() {
            let f = &f;
            s.spawn(move || f(i * band, chunk));
        }
    });
}

/// Sobel (|gx| + |gy|) then hysteresis: weak edges count only when they touch a strong one.
fn canny(g: &[u8], w: usize, h: usize, lo: i32, hi: i32) -> Vec<u8> {
    if lo < 0 || hi < 0 || w < 3 || h < 3 {
        // Thresholds below zero would let the empty border count as edge: the plain version keeps those semantics.
        return hysteresis_plain(&sobel(g, w, h), w, h, lo, hi);
    }
    let p = w + 2; // classes live in a picture with a 1-pixel empty frame, so no neighbour needs a bounds check
    let mut st = vec![0u8; p * (h + 2)];
    let band = (h - 2).div_ceil(workers()).max(1);
    std::thread::scope(|s| {
        for (i, chunk) in st[2 * p..(h * p)].chunks_mut(band * p).enumerate() {
            s.spawn(move || classify_rows(g, w, 1 + i * band, lo, hi, chunk));
        }
    });
    // Weak pixels touching a strong one are the starting points; strong pixels never need to be walked themselves.
    let around = [-(p as isize) - 1, -(p as isize), -(p as isize) + 1, -1, 1, p as isize - 1, p as isize, p as isize + 1];
    let mut stack: Vec<usize> = vec![];
    for i in p..st.len() - p {
        if st[i] == WEAK && around.iter().any(|d| st[(i as isize + d) as usize] == EDGE) {
            st[i] = EDGE;
            stack.push(i);
        }
    }
    while let Some(i) = stack.pop() {
        for d in around {
            let j = (i as isize + d) as usize;
            if st[j] == WEAK {
                st[j] = EDGE;
                stack.push(j);
            }
        }
    }
    let mut out = vec![0u8; w * h];
    for (y, row) in out.chunks_mut(w).enumerate() {
        for (o, s) in row.iter_mut().zip(&st[(y + 1) * p + 1..]) {
            *o = if *s == EDGE { 255 } else { 0 };
        }
    }
    out
}

const WEAK: u8 = 1;
const EDGE: u8 = 2;

/// Class of every pixel of the rows starting at `y0`: EDGE (above `hi`), WEAK (above `lo`) or 0.
/// `out` holds those rows with a 1-pixel frame on each side (stride w + 2).
fn classify_rows(g: &[u8], w: usize, y0: usize, lo: i32, hi: i32, out: &mut [u8]) {
    let mut mag = vec![0i16; w];
    for (r, row) in out.chunks_mut(w + 2).enumerate() {
        let y = y0 + r;
        if y + 1 >= g.len() / w {
            break;
        }
        sobel_rows(g, w, y, &mut mag);
        for x in 1..w - 1 {
            let m = mag[x] as i32;
            row[x + 1] = if m > hi { EDGE } else if m > lo { WEAK } else { 0 };
        }
    }
}

fn sobel(g: &[u8], w: usize, h: usize) -> Vec<i16> {
    let mut mag = vec![0i16; w * h];
    if w >= 3 && h >= 3 {
        let band = (h - 2).div_ceil(workers()).max(1);
        std::thread::scope(|s| {
            for (i, chunk) in mag[w..(h - 1) * w].chunks_mut(band * w).enumerate() {
                s.spawn(move || sobel_rows(g, w, 1 + i * band, chunk));
            }
        });
    }
    mag
}

fn hysteresis_plain(mag: &[i16], w: usize, h: usize, lo: i32, hi: i32) -> Vec<u8> {
    let mut out = vec![0u8; w * h];
    let mut stack: Vec<usize> = (0..w * h).filter(|&i| mag[i] as i32 > hi).collect();
    for &i in &stack {
        out[i] = 255;
    }
    while let Some(i) = stack.pop() {
        let (x, y) = (i % w, i / w);
        for ny in y.saturating_sub(1)..=(y + 1).min(h - 1) {
            for nx in x.saturating_sub(1)..=(x + 1).min(w - 1) {
                let j = ny * w + nx;
                if out[j] == 0 && mag[j] as i32 > lo {
                    out[j] = 255;
                    stack.push(j);
                }
            }
        }
    }
    out
}

/// Sobel magnitude of the rows starting at `y0`; `out` holds those rows (borders stay 0).
fn sobel_rows(g: &[u8], w: usize, y0: usize, out: &mut [i16]) {
    for (r, row) in out.chunks_mut(w).enumerate() {
        let y = y0 + r;
        let (a, b, c) = (&g[(y - 1) * w..y * w], &g[y * w..(y + 1) * w], &g[(y + 1) * w..(y + 2) * w]);
        for x in 1..w - 1 {
            let (a0, a1, a2) = (a[x - 1] as i32, a[x] as i32, a[x + 1] as i32);
            let (b0, b2) = (b[x - 1] as i32, b[x + 1] as i32);
            let (c0, c1, c2) = (c[x - 1] as i32, c[x] as i32, c[x + 1] as i32);
            let gx = (a2 + 2 * b2 + c2) - (a0 + 2 * b0 + c0);
            let gy = (c0 + 2 * c1 + c2) - (a0 + 2 * a1 + a2);
            row[x] = (gx.abs() + gy.abs()).min(i16::MAX as i32) as i16;
        }
    }
}

/// Rectangular dilation, anchor in the middle like OpenCV; horizontal then vertical pass.
fn dilate(e: &[u8], w: usize, h: usize, kw: usize, kh: usize) -> Vec<u8> {
    let (ax, ay) = (kw / 2, kh / 2);
    let mut tmp = vec![0u8; w * h];
    par_rows(&mut tmp, w, h, |y0, rows| {
        for (r, dst) in rows.chunks_mut(w).enumerate() {
            let y = y0 + r;
            dilate_row(&e[y * w..(y + 1) * w], dst, kw, ax);
        }
    });
    let mut out = vec![0u8; w * h];
    par_rows(&mut out, w, h, |y0, rows| {
        for (r, dst) in rows.chunks_mut(w).enumerate() {
            let y = y0 + r;
            let (a, b) = (y.saturating_sub(kh - 1 - ay), (y + ay).min(h - 1));
            dst.copy_from_slice(&tmp[a * w..(a + 1) * w]);
            for k in a + 1..=b {
                for (o, t) in dst.iter_mut().zip(&tmp[k * w..(k + 1) * w]) {
                    *o |= *t;
                }
            }
        }
    });
    out
}

/// One row: a pixel is set when any source pixel in [x - (kw-1-ax), x + ax] is set.
fn dilate_row(src: &[u8], dst: &mut [u8], kw: usize, ax: usize) {
    let (w, back) = (src.len(), kw - 1 - ax);
    let (mut last, mut next) = (None::<usize>, 0usize);
    for x in 0..w {
        let hi = (x + ax).min(w - 1);
        while next <= hi {
            if src[next] != 0 {
                last = Some(next);
            }
            next += 1;
        }
        dst[x] = if last.is_some_and(|q| q + back >= x) { 255 } else { 0 };
    }
}

/// Bounding box of every 8-connected blob, in the order a left-to-right, top-to-bottom scan first meets them.
/// Works on runs of set pixels (a few thousand) instead of single pixels (millions).
fn components(e: &[u8], w: usize, h: usize) -> Vec<Rect> {
    let mut runs: Vec<(u32, u32, u32)> = vec![]; // (row, first x, last x)
    let mut parent: Vec<u32> = vec![];
    fn find(parent: &mut [u32], mut a: u32) -> u32 {
        while parent[a as usize] != a {
            parent[a as usize] = parent[parent[a as usize] as usize];
            a = parent[a as usize];
        }
        a
    }
    let mut prev = 0usize;
    for y in 0..h {
        let row = &e[y * w..(y + 1) * w];
        let cur = runs.len();
        let mut x = 0;
        while let Some(p) = row[x..].iter().position(|&v| v != 0) {
            let s = x + p;
            let last = s + row[s..].iter().position(|&v| v == 0).unwrap_or(w - s) - 1;
            parent.push(runs.len() as u32);
            runs.push((y as u32, s as u32, last as u32));
            x = last + 1;
        }
        // Runs of the row above that touch this run (diagonals count) join it; the lower index stays the root.
        let mut up = prev;
        for c in cur..runs.len() {
            let (_, c0, c1) = runs[c];
            while up < cur && runs[up].2 + 1 < c0 {
                up += 1;
            }
            let mut k = up;
            while k < cur && runs[k].1 <= c1 + 1 {
                let (a, b) = (find(&mut parent, k as u32), find(&mut parent, c as u32));
                if a != b {
                    parent[a.max(b) as usize] = a.min(b);
                }
                k += 1;
            }
        }
        prev = cur;
    }
    let mut boxes: Vec<(u32, u32, u32, u32)> = vec![(u32::MAX, u32::MAX, 0, 0); runs.len()]; // x0, y0, x1, y1 at the root
    for (i, &(y, x0, x1)) in runs.iter().enumerate() {
        let r = find(&mut parent, i as u32) as usize;
        let b = &mut boxes[r];
        *b = (b.0.min(x0), b.1.min(y), b.2.max(x1), b.3.max(y));
    }
    (0..runs.len())
        .filter(|&i| parent[i] == i as u32)
        .map(|i| {
            let (x0, y0, x1, y1) = boxes[i];
            (x0 as i32, y0 as i32, (x1 - x0 + 1) as i32, (y1 - y0 + 1) as i32)
        })
        .collect()
}

#[cfg(test)]
mod tests;
