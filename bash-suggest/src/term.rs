//! Real-terminal helpers: raw mode with guaranteed restore, size, signal self-pipe.

use rustix::fd::{AsFd, OwnedFd};
use rustix::termios::{tcgetattr, tcgetwinsize, tcsetattr, OptionalActions, Termios, Winsize};
use std::sync::atomic::{AtomicI32, Ordering};
use std::sync::OnceLock;

static SAVED: OnceLock<Termios> = OnceLock::new();

/// Puts stdin in raw mode; restores the saved mode on drop and on panic.
pub struct RawGuard;

impl RawGuard {
    pub fn new() -> std::io::Result<Self> {
        let stdin = rustix::stdio::stdin();
        let orig = tcgetattr(stdin)?;
        let _ = SAVED.set(orig.clone());
        let mut raw = orig;
        raw.make_raw();
        tcsetattr(stdin, OptionalActions::Now, &raw)?;
        Ok(RawGuard)
    }
}

/// Restore the terminal mode saved by `RawGuard::new` (no-op if none).
pub fn restore() {
    if let Some(t) = SAVED.get() {
        let _ = tcsetattr(rustix::stdio::stdin(), OptionalActions::Now, t);
    }
}

impl Drop for RawGuard {
    fn drop(&mut self) {
        restore();
    }
}

pub fn winsize() -> Winsize {
    tcgetwinsize(rustix::stdio::stdout())
        .or_else(|_| tcgetwinsize(rustix::stdio::stdin()))
        .unwrap_or(Winsize { ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0 })
}

/// Original termios of our terminal (for the inner pty), if stdin is a tty.
pub fn current_termios() -> Option<Termios> {
    tcgetattr(rustix::stdio::stdin()).ok()
}

static SIG_FD: AtomicI32 = AtomicI32::new(-1);

extern "C" fn on_signal(sig: libc::c_int) {
    let fd = SIG_FD.load(Ordering::Relaxed);
    if fd >= 0 {
        let b = sig as u8;
        // SAFETY: write(2) is async-signal-safe; a full pipe just drops the byte.
        unsafe { libc::write(fd, &b as *const u8 as *const libc::c_void, 1) };
    }
}

/// Route SIGWINCH, SIGHUP, SIGTERM, SIGINT-free set to a non-blocking pipe.
/// Returns the read end; each byte is a signal number.
pub fn signal_pipe() -> std::io::Result<OwnedFd> {
    use rustix::pipe::{pipe_with, PipeFlags};
    let (r, w) = pipe_with(PipeFlags::CLOEXEC | PipeFlags::NONBLOCK)?;
    SIG_FD.store(rustix::fd::AsRawFd::as_raw_fd(&w.as_fd()), Ordering::Relaxed);
    std::mem::forget(w); // lives for the whole process
    for sig in [libc::SIGWINCH, libc::SIGHUP, libc::SIGTERM] {
        // SAFETY: plain sigaction with an async-signal-safe handler.
        unsafe {
            let mut sa: libc::sigaction = std::mem::zeroed();
            sa.sa_sigaction = on_signal as usize;
            sa.sa_flags = libc::SA_RESTART;
            libc::sigemptyset(&mut sa.sa_mask);
            libc::sigaction(sig, &sa, std::ptr::null_mut());
        }
    }
    Ok(r)
}
