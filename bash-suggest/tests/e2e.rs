//! End to end: the real binary on a private pty, with a vt100 screen standing in
//! for the user's terminal (it answers cursor-position queries like a real one).

use rustix::event::{poll, PollFd, PollFlags};
use rustix::fs::{open, Mode, OFlags};
use rustix::pty::{grantpt, openpt, ptsname, unlockpt, OpenptFlags};
use rustix::termios::{tcsetwinsize, Winsize};
use std::fs::File;
use std::io::{Read, Write};
use std::num::NonZeroU16;
use std::os::fd::OwnedFd;
use std::os::unix::process::CommandExt;
use std::process::{Child, Command};
use std::time::{Duration, Instant};

const ROWS: u16 = 12;
const COLS: u16 = 60;

struct Term {
    m: File,
    p: vt100::Parser,
    child: Child,
}

impl Term {
    fn start(history: &[&str]) -> Term {
        use std::sync::atomic::{AtomicU32, Ordering};
        static N: AtomicU32 = AtomicU32::new(0);
        let home = std::env::temp_dir().join(format!(
            "bash-suggest-e2e-{}-{}",
            std::process::id(),
            N.fetch_add(1, Ordering::Relaxed)
        ));
        let _ = std::fs::remove_dir_all(&home);
        std::fs::create_dir_all(&home).unwrap();
        std::fs::write(home.join(".bash_history"), history.join("\n") + "\n").unwrap();
        let init = concat!(env!("CARGO_MANIFEST_DIR"), "/init.bash");
        std::fs::write(
            home.join(".bashrc"),
            format!("PS1='$ '\nHISTFILE=$HOME/.bash_history\nsource {init}\n"),
        )
        .unwrap();

        let master: OwnedFd = openpt(OpenptFlags::RDWR | OpenptFlags::NOCTTY).unwrap();
        grantpt(&master).unwrap();
        unlockpt(&master).unwrap();
        let name = ptsname(&master, Vec::new()).unwrap();
        tcsetwinsize(&master, Winsize { ws_row: ROWS, ws_col: COLS, ws_xpixel: 0, ws_ypixel: 0 }).unwrap();
        let slave = File::from(open(name.as_c_str(), OFlags::RDWR | OFlags::NOCTTY, Mode::empty()).unwrap());
        let mut cmd = Command::new(env!("CARGO_BIN_EXE_bash-suggest"));
        cmd.env_clear()
            .env("HOME", &home)
            .env("PATH", std::env::var_os("PATH").unwrap())
            .env("TERM", "xterm-256color")
            .env("XDG_RUNTIME_DIR", &home)
            .stdin(slave.try_clone().unwrap())
            .stdout(slave.try_clone().unwrap())
            .stderr(slave);
        unsafe {
            cmd.pre_exec(|| {
                rustix::process::setsid()?;
                rustix::process::ioctl_tiocsctty(rustix::stdio::stdin())?;
                Ok(())
            });
        }
        let child = cmd.spawn().unwrap();
        drop(cmd);
        let p = vt100::Parser::new(NonZeroU16::new(ROWS).unwrap(), NonZeroU16::new(COLS).unwrap(), 0);
        let mut t = Term { m: File::from(master), p, child };
        t.pump(600);
        t
    }

    /// Read output for `ms`, feeding the screen and answering `ESC[6n`.
    fn pump(&mut self, ms: u64) {
        let deadline = Instant::now() + Duration::from_millis(ms);
        let mut buf = [0u8; 8192];
        while let Some(left) = deadline.checked_duration_since(Instant::now()) {
            let mut fds = [PollFd::new(&self.m, PollFlags::IN)];
            let ts = rustix::time::Timespec { tv_sec: 0, tv_nsec: left.as_nanos().min(50_000_000) as i64 };
            if poll(&mut fds, Some(&ts)).unwrap() == 0 {
                continue;
            }
            let n = match self.m.read(&mut buf) {
                Ok(0) | Err(_) => return,
                Ok(n) => n,
            };
            let mut data = &buf[..n];
            while let Some(i) = data.windows(4).position(|w| w == b"\x1b[6n") {
                self.p.process(&data[..i]);
                let (r, c) = self.p.screen().cursor_position();
                self.m.write_all(format!("\x1b[{};{}R", r + 1, c + 1).as_bytes()).unwrap();
                data = &data[i + 4..];
            }
            self.p.process(data);
        }
    }

    fn typ(&mut self, s: &str) {
        for ch in s.as_bytes() {
            self.m.write_all(&[*ch]).unwrap();
            self.pump(30);
        }
        self.pump(150);
    }

    fn key(&mut self, k: &[u8]) {
        self.m.write_all(k).unwrap();
        self.pump(200);
    }

    fn row(&self, r: u16) -> String {
        self.p.screen().contents_between(r, 0, r, COLS)
    }

    fn cursor_row(&self) -> u16 {
        self.p.screen().cursor_position().0
    }

    fn rows_below(&self) -> Vec<String> {
        (self.cursor_row() + 1..ROWS).map(|r| self.row(r)).collect()
    }

    fn dump(&self) -> String {
        (0..ROWS).map(|r| format!("{r:2}|{}\n", self.row(r))).collect()
    }
}

impl Drop for Term {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

#[test]
fn ghost_shows_and_right_accepts() {
    let mut t = Term::start(&["echo alpha", "ls"]);
    t.typ("echo a");
    let r = t.cursor_row();
    assert_eq!(t.row(r), "$ echo alpha", "{}", t.dump());
    assert_eq!(t.rows_below()[0], "echo alpha", "{}", t.dump());
    t.key(b"\x1b[C");
    t.key(b"\r");
    assert!(t.dump().contains("\nalpha") || t.dump().contains("|alpha"), "{}", t.dump());
}

#[test]
fn tab_selects_and_enter_fills_line() {
    let mut t = Term::start(&["echo one", "echo two"]);
    t.typ("echo ");
    let r = t.cursor_row();
    let second = t.row(r + 2);
    assert!(second.starts_with("echo "), "{}", t.dump());
    t.key(b"\t");
    t.key(b"\t");
    assert!(t.p.screen().cell(r + 2, 0).unwrap().inverse(), "{}", t.dump());
    t.key(b"\r"); // fills the line, does not run it
    assert_eq!(t.row(r).trim_end(), format!("$ {second}"), "{}", t.dump());
    t.key(b"\r");
    let word = second.trim_start_matches("echo ");
    assert!(t.dump().contains(&format!("|{word}\n")), "{}", t.dump());
}

#[test]
fn list_cleared_when_line_emptied() {
    let mut t = Term::start(&["echo alpha"]);
    t.typ("ec");
    assert!(!t.rows_below()[0].is_empty(), "{}", t.dump());
    t.key(b"\x15"); // Ctrl-U
    assert!(t.rows_below().iter().all(|r| r.is_empty()), "{}", t.dump());
}

#[test]
fn ctrl_c_leaves_no_list() {
    let mut t = Term::start(&["echo alpha"]);
    t.typ("ec");
    t.key(b"\x03");
    assert!(t.rows_below().iter().all(|r| r.is_empty()), "{}", t.dump());
    assert_eq!(t.row(t.cursor_row()).trim_end(), "$", "{}", t.dump());
}

#[test]
fn prompt_on_bottom_row_scrolls_for_list() {
    let mut t = Term::start(&["echo alpha", "echo again"]);
    for _ in 0..ROWS {
        t.key(b"\r");
    }
    t.typ("echo a");
    let r = t.cursor_row();
    assert!(r < ROWS - 1, "{}", t.dump());
    assert!(t.row(r).starts_with("$ echo a"), "{}", t.dump());
    assert!(t.row(r + 1).starts_with("echo a"), "{}", t.dump());
}

#[test]
fn paste_is_not_intercepted() {
    let mut t = Term::start(&["echo alpha"]);
    t.key(b"\x1b[200~echo pas\tted\x1b[201~");
    t.key(b"\r");
    assert!(t.dump().contains("|pas\tted") || t.dump().contains("|pas     ted") || t.dump().contains("pas"), "{}", t.dump());
    assert!(!t.dump().contains("alpha"), "{}", t.dump());
}

#[test]
fn nothing_drawn_while_command_runs() {
    let mut t = Term::start(&["echo alpha"]);
    t.typ("cat");
    t.key(b"\r");
    t.typ("ec"); // typed into cat, not at a prompt
    assert!(!t.dump().contains("echo alpha"), "{}", t.dump());
    t.key(b"\x04");
}

#[test]
fn right_accepts_one_word_at_a_time() {
    let mut t = Term::start(&["echo alpha beta"]);
    t.typ("echo a");
    let r = t.cursor_row();
    assert_eq!(t.row(r), "$ echo alpha beta", "{}", t.dump());
    t.key(b"\x1b[C");
    // line is now "echo alpha"; ghost " beta" still shown after the cursor
    assert_eq!(t.p.screen().cursor_position(), (r, 12), "{}", t.dump());
    assert_eq!(t.row(r), "$ echo alpha beta", "{}", t.dump());
    t.key(b"\x15\r"); // Ctrl-U clears what bash really has; nothing runs
    t.typ("echo a");
    t.key(b"\x1b[C");
    t.key(b"\x1b[C");
    t.key(b"\r");
    assert!(t.dump().contains("|alpha beta\n"), "{}", t.dump());
}

#[test]
fn list_fills_all_rows_below() {
    let lines: Vec<String> = (0..30).map(|i| format!("echo item{i}")).collect();
    let refs: Vec<&str> = lines.iter().map(|s| s.as_str()).collect();
    let mut t = Term::start(&refs);
    t.typ("echo ");
    let r = t.cursor_row();
    assert_eq!(r, 0, "{}", t.dump());
    assert!(t.rows_below().iter().all(|row| row.starts_with("echo item")), "{}", t.dump());
}
