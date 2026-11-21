mod app;
mod fuzzy;
mod keys;
mod markers;
mod pty;
mod render;
mod screen;
mod sources;
mod suggest;
mod term;

use rustix::event::{poll, PollFd, PollFlags};
use rustix::fd::AsFd;
use rustix::io::Errno;
use std::os::unix::process::{CommandExt, ExitStatusExt};
use std::time::Instant;

const BUF: usize = 64 * 1024;

fn main() {
    let size = term::winsize();
    let modes = term::current_termios();
    let mut child = match pty::spawn_bash(size, modes.as_ref()) {
        Ok(c) => c,
        Err(e) => {
            // Never lock the user out: fall back to a plain interactive bash.
            eprintln!("bash-suggest: {e}; starting plain bash");
            let err = pty::bash_command().exec();
            eprintln!("bash-suggest: exec bash failed: {err}");
            std::process::exit(127);
        }
    };
    let pid = rustix::process::Pid::from_child(&child.proc);

    let guard = term::RawGuard::new().ok();
    let prev_hook = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        term::restore();
        let _ = rustix::process::kill_process_group(pid, rustix::process::Signal::HUP);
        prev_hook(info);
    }));

    let sigs = term::signal_pipe().ok();
    let mut app = app::App::new(child.proc.id(), (size.ws_row, size.ws_col));
    run_loop(&child, sigs.as_ref(), pid, &mut app);
    app.shutdown();
    write_all(rustix::stdio::stdout(), &app.out);

    drop(guard);
    let status = child.proc.wait().ok();
    let code = status.map_or(1, |s| s.code().unwrap_or_else(|| 128 + s.signal().unwrap_or(0)));
    std::process::exit(code);
}

fn run_loop(child: &pty::Child, sigs: Option<&rustix::fd::OwnedFd>, pid: rustix::process::Pid, app: &mut app::App) {
    let stdin = rustix::stdio::stdin();
    let stdout = rustix::stdio::stdout();
    let master = child.master.as_fd();
    rustix::io::ioctl_fionbio(master, true).ok();
    let mut buf = vec![0u8; BUF];
    let mut stdin_open = true;
    let fg_is_bash = || rustix::termios::tcgetpgrp(master).is_ok_and(|p| p == pid);

    loop {
        let want_in = stdin_open && app.to_child.len() < BUF;
        let timeout = app.next_deadline().map(|d| {
            let left = d.saturating_duration_since(Instant::now());
            rustix::time::Timespec { tv_sec: left.as_secs() as i64, tv_nsec: left.subsec_nanos() as i64 }
        });
        let mut fds = Vec::with_capacity(3);
        let mflags = if app.to_child.is_empty() { PollFlags::IN } else { PollFlags::IN | PollFlags::OUT };
        fds.push(PollFd::new(&master, mflags));
        if want_in {
            fds.push(PollFd::new(&stdin, PollFlags::IN));
        }
        if let Some(s) = sigs {
            fds.push(PollFd::new(s, PollFlags::IN));
        }
        match poll(&mut fds, timeout.as_ref()) {
            Ok(_) => {}
            Err(Errno::INTR) => continue,
            Err(_) => return,
        }
        let m_ev = fds[0].revents();
        let in_ev = if want_in { fds[1].revents() } else { PollFlags::empty() };
        let sig_ev = if sigs.is_some() { fds[fds.len() - 1].revents() } else { PollFlags::empty() };
        drop(fds);

        if sig_ev.contains(PollFlags::IN) {
            if let Some(s) = sigs {
                let mut b = [0u8; 16];
                if let Ok(n) = rustix::io::read(s, &mut b) {
                    for &sig in &b[..n] {
                        match sig as i32 {
                            libc::SIGWINCH => {
                                let ws = term::winsize();
                                app.on_resize((ws.ws_row, ws.ws_col));
                                let _ = rustix::termios::tcsetwinsize(master, ws);
                            }
                            libc::SIGHUP => {
                                let _ = rustix::process::kill_process_group(pid, rustix::process::Signal::HUP);
                            }
                            libc::SIGTERM => {
                                let _ = rustix::process::kill_process_group(pid, rustix::process::Signal::TERM);
                            }
                            _ => {}
                        }
                    }
                }
            }
        }

        if !m_ev.is_empty() {
            // Read (and so drain) before reacting to HUP/ERR.
            match rustix::io::read(master, &mut buf) {
                Ok(0) => return,
                Ok(n) => app.on_output(&buf[..n], fg_is_bash),
                Err(Errno::AGAIN) | Err(Errno::INTR) => {}
                Err(_) => return, // EIO: bash and all its children closed the pty
            }
        }
        if !in_ev.is_empty() {
            match rustix::io::read(stdin, &mut buf[..BUF]) {
                Ok(0) => stdin_open = false,
                Ok(n) => app.on_input(&buf[..n]),
                Err(Errno::AGAIN) | Err(Errno::INTR) => {}
                Err(_) => stdin_open = false,
            }
        }
        app.on_tick(Instant::now());

        if !app.out.is_empty() {
            write_all(stdout, &app.out);
            app.out.clear();
        }
        if !app.to_child.is_empty() {
            match rustix::io::write(master, &app.to_child) {
                Ok(n) => {
                    app.to_child.drain(..n);
                }
                Err(Errno::AGAIN) | Err(Errno::INTR) => {}
                Err(_) => return,
            }
        }
    }
}

fn write_all(fd: impl AsFd, mut data: &[u8]) {
    while !data.is_empty() {
        match rustix::io::write(&fd, data) {
            Ok(n) => data = &data[n..],
            Err(Errno::INTR) | Err(Errno::AGAIN) => {}
            Err(_) => return,
        }
    }
}
