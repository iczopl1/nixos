//! Start `bash -i` on a new pseudo-terminal.

use rustix::fd::OwnedFd;
use rustix::fs::{open, Mode, OFlags};
use rustix::pty::{grantpt, openpt, ptsname, unlockpt, OpenptFlags};
use rustix::termios::{tcsetattr, tcsetwinsize, OptionalActions, Termios, Winsize};
use std::fs::File;
use std::os::unix::process::CommandExt;
use std::process::{Child as Proc, Command};

pub struct Child {
    pub master: OwnedFd,
    pub proc: Proc,
}

/// Command for the inner shell; also used by the no-pty fallback.
pub fn bash_command() -> Command {
    let mut c = Command::new("bash");
    c.arg("-i").env("BASH_SUGGEST", "1");
    c
}

pub fn spawn_bash(size: Winsize, modes: Option<&Termios>) -> std::io::Result<Child> {
    if std::env::var_os("BASH_SUGGEST_FAIL").is_some() {
        return Err(std::io::Error::other("BASH_SUGGEST_FAIL set"));
    }
    let master = openpt(OpenptFlags::RDWR | OpenptFlags::NOCTTY | OpenptFlags::CLOEXEC)?;
    grantpt(&master)?;
    unlockpt(&master)?;
    let name = ptsname(&master, Vec::new())?;
    tcsetwinsize(&master, size)?;
    let slave: OwnedFd = open(name.as_c_str(), OFlags::RDWR | OFlags::NOCTTY | OFlags::CLOEXEC, Mode::empty())?;
    if let Some(t) = modes {
        tcsetattr(&slave, OptionalActions::Now, t)?; // same line settings as the real tty
    }
    let slave = File::from(slave);
    let mut cmd = bash_command();
    cmd.stdin(slave.try_clone()?).stdout(slave.try_clone()?).stderr(slave);
    // SAFETY: only async-signal-safe syscalls between fork and exec.
    unsafe {
        cmd.pre_exec(|| {
            rustix::process::setsid()?;
            rustix::process::ioctl_tiocsctty(rustix::stdio::stdin())?;
            Ok(())
        });
    }
    let proc = cmd.spawn()?;
    Ok(Child { master, proc })
}
