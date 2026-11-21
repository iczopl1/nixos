//! Runs the real binary on a private pty (no real terminal involved).

use rustix::event::{poll, PollFd, PollFlags};
use rustix::fs::{open, Mode, OFlags};
use rustix::pty::{grantpt, openpt, ptsname, unlockpt, OpenptFlags};
use rustix::termios::{tcsetwinsize, Winsize};
use std::fs::File;
use std::io::{Read, Write};
use std::os::fd::OwnedFd;
use std::os::unix::process::CommandExt;
use std::process::Command;
use std::time::{Duration, Instant};

fn home() -> std::path::PathBuf {
    use std::sync::atomic::{AtomicU32, Ordering};
    static N: AtomicU32 = AtomicU32::new(0);
    let d = std::env::temp_dir().join(format!(
        "bash-suggest-relay-{}-{}",
        std::process::id(),
        N.fetch_add(1, Ordering::Relaxed)
    ));
    let _ = std::fs::remove_dir_all(&d);
    std::fs::create_dir_all(&d).unwrap();
    std::fs::write(d.join(".bashrc"), "PS1='$ '\n").unwrap();
    d
}

/// Start the wrapper on a fresh pty, type `input`, collect all output until it exits.
pub fn run(input: &str, envs: &[(&str, &str)]) -> (String, Option<i32>) {
    let master: OwnedFd = openpt(OpenptFlags::RDWR | OpenptFlags::NOCTTY).unwrap();
    grantpt(&master).unwrap();
    unlockpt(&master).unwrap();
    let name = ptsname(&master, Vec::new()).unwrap();
    tcsetwinsize(&master, Winsize { ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0 }).unwrap();
    let slave: OwnedFd = open(name.as_c_str(), OFlags::RDWR | OFlags::NOCTTY, Mode::empty()).unwrap();
    let slave = File::from(slave);

    let h = home();
    let mut cmd = Command::new(env!("CARGO_BIN_EXE_bash-suggest"));
    cmd.env_clear()
        .env("HOME", &h)
        .env("PATH", std::env::var_os("PATH").unwrap())
        .env("TERM", "xterm-256color")
        .env("XDG_RUNTIME_DIR", &h)
        .envs(envs.iter().copied())
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
    let mut child = cmd.spawn().unwrap();
    drop(cmd); // closes our copies of the slave

    let mut m = File::from(master);
    m.write_all(input.as_bytes()).unwrap();

    let mut out = Vec::new();
    let deadline = Instant::now() + Duration::from_secs(10);
    let mut buf = [0u8; 4096];
    loop {
        assert!(Instant::now() < deadline, "timeout; output so far: {}", String::from_utf8_lossy(&out));
        let mut fds = [PollFd::new(&m, PollFlags::IN)];
        let ts = rustix::time::Timespec { tv_sec: 0, tv_nsec: 100_000_000 };
        if poll(&mut fds, Some(&ts)).unwrap() == 0 {
            if child.try_wait().unwrap().is_some() {
                break;
            }
            continue;
        }
        match m.read(&mut buf) {
            Ok(0) | Err(_) => break, // EIO: all slave ends closed
            Ok(n) => out.extend_from_slice(&buf[..n]),
        }
    }
    let status = child.wait().unwrap();
    use std::os::unix::process::ExitStatusExt;
    let code = status.code().or(status.signal().map(|s| 128 + s));
    (String::from_utf8_lossy(&out).into_owned(), code)
}

#[test]
fn relays_and_returns_exit_code() {
    let (out, code) = run("echo h''i\nexit 3\n", &[]);
    assert!(out.contains("hi\r\n"), "output: {out:?}");
    assert_eq!(code, Some(3));
}

#[test]
fn bash_killed_by_signal() {
    let (_, code) = run("kill -9 $$\n", &[]);
    assert_eq!(code, Some(137));
}

#[test]
fn exec_true_exits_zero() {
    let (_, code) = run("exec true\n", &[]);
    assert_eq!(code, Some(0));
}

#[test]
fn spawn_failure_falls_back_to_plain_bash() {
    let (out, code) = run("echo o''k\nexit\n", &[("BASH_SUGGEST_FAIL", "1")]);
    assert!(out.contains("ok\r\n"), "output: {out:?}");
    assert_eq!(code, Some(0));
}

#[test]
fn inner_bash_has_env_flag() {
    let (out, _) = run("echo flag=$BASH_SUGGEST\nexit\n", &[]);
    assert!(out.contains("flag=1\r\n"), "output: {out:?}");
}
