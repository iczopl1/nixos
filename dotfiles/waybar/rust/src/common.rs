//! Shared helpers: palette from colors.css, html escaping, colour mixing, output.

use std::collections::HashMap;
use std::io::Write;

pub fn runtime_dir() -> String {
    std::env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "/tmp".into())
}

pub fn home() -> String {
    std::env::var("HOME").unwrap_or_default()
}

pub fn colors_css() -> String {
    format!("{}/.config/waybar/colors.css", home())
}

/// Same as Python's html.escape(quote=True).
pub fn escape(s: &str) -> String {
    let mut o = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '&' => o.push_str("&amp;"),
            '<' => o.push_str("&lt;"),
            '>' => o.push_str("&gt;"),
            '"' => o.push_str("&quot;"),
            '\'' => o.push_str("&#x27;"),
            _ => o.push(c),
        }
    }
    o
}

/// `@define-color name #rrggbb` lines of colors.css laid over `fallback`.
pub fn palette(fallback: &[(&str, &str)]) -> HashMap<String, String> {
    let mut c: HashMap<String, String> =
        fallback.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect();
    if let Ok(text) = std::fs::read_to_string(colors_css()) {
        let mut it = text.split_whitespace();
        while let Some(tok) = it.next() {
            if tok != "@define-color" {
                continue;
            }
            if let (Some(name), Some(val)) = (it.next(), it.next()) {
                let v = val.trim_end_matches(';');
                let b = v.as_bytes();
                if b.len() >= 7 && b[0] == b'#' && b[1..7].iter().all(u8::is_ascii_hexdigit) {
                    c.insert(name.to_string(), v[..7].to_string());
                }
            }
        }
    }
    c
}

fn rgb(h: &str) -> [f64; 3] {
    let p = |i: usize| u8::from_str_radix(&h[i..i + 2], 16).unwrap_or(0) as f64;
    [p(1), p(3), p(5)]
}

pub fn mix(a: &str, b: &str, t: f64) -> String {
    let (pa, pb) = (rgb(a), rgb(b));
    let mut o = String::from("#");
    for i in 0..3 {
        o.push_str(&format!("{:02x}", (pa[i] + (pb[i] - pa[i]) * t).round_ties_even() as i64));
    }
    o
}

/// One JSON line to waybar; a closed pipe means waybar is gone.
pub fn emit(v: &serde_json::Value) {
    let mut out = std::io::stdout().lock();
    if writeln!(out, "{v}").and_then(|_| out.flush()).is_err() {
        std::process::exit(0);
    }
}

pub fn getppid() -> i32 {
    unsafe { libc::getppid() }
}

pub fn pid_alive(pid: i32) -> bool {
    unsafe {
        libc::kill(pid, 0) == 0 || *libc::__errno_location() != libc::ESRCH
    }
}

/// Wait for any of `fds` to become readable. Returns the ready flags; timeout_ms < 0 blocks.
pub fn poll(fds: &[i32], timeout_ms: i32) -> Vec<bool> {
    let mut p: Vec<libc::pollfd> =
        fds.iter().map(|&fd| libc::pollfd { fd, events: libc::POLLIN, revents: 0 }).collect();
    unsafe { libc::poll(p.as_mut_ptr(), p.len() as libc::nfds_t, timeout_ms) };
    p.iter().map(|x| x.revents != 0).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn helpers() {
        assert_eq!(escape("<a href='x'>&\"</a>"), "&lt;a href=&#x27;x&#x27;&gt;&amp;&quot;&lt;/a&gt;");
        assert_eq!(mix("#000000", "#ffffff", 0.5), "#808080");
        assert_eq!(mix("#102030", "#102030", 0.9), "#102030");
    }
}
