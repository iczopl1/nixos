//! Suggestion sources: bash history, command names, directory entries,
//! subcommands learned from history. Nothing here runs other programs.

use std::collections::HashMap;
use std::fs::File;
use std::io::{Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};
use std::time::SystemTime;

/// Max history entries kept in memory (newest win).
const MAX_HISTORY: usize = 100_000;

pub struct Entry {
    pub text: Box<str>,
    /// Bitmask of characters present (see `char_mask`), for cheap prefiltering.
    pub mask: u64,
    pub count: u32,
    /// Sequence number of the newest occurrence (higher = more recent).
    pub last: u32,
}

pub struct History {
    path: PathBuf,
    offset: u64,
    mtime: Option<SystemTime>,
    seq: u32,
    pub entries: Vec<Entry>,
    index: HashMap<Box<str>, usize>,
}

/// Bit per a-z, 0-9; one shared bit for everything else.
pub fn char_mask(s: &str) -> u64 {
    let mut m = 0u64;
    for b in s.bytes() {
        let b = b.to_ascii_lowercase();
        m |= match b {
            b'a'..=b'z' => 1 << (b - b'a'),
            b'0'..=b'9' => 1 << (26 + b - b'0'),
            b' ' => 0,
            _ => 1 << 63,
        };
    }
    m
}

impl History {
    pub fn load(path: &Path) -> Self {
        let mut h = History {
            path: path.to_path_buf(),
            offset: 0,
            mtime: None,
            seq: 0,
            entries: Vec::new(),
            index: HashMap::new(),
        };
        h.reload_full();
        h
    }

    /// Re-read only appended bytes if the file changed; full reload if it shrank.
    pub fn refresh_if_changed(&mut self) {
        let Ok(meta) = std::fs::metadata(&self.path) else {
            return;
        };
        let mtime = meta.modified().ok();
        if mtime == self.mtime && meta.len() == self.offset {
            return;
        }
        if meta.len() < self.offset {
            self.reload_full();
        } else {
            self.read_tail(false);
        }
    }

    fn reload_full(&mut self) {
        self.offset = 0;
        self.seq = 0;
        self.entries.clear();
        self.index.clear();
        self.read_tail(true);
    }

    /// Read complete lines after `offset`. `cap` keeps only the newest MAX_HISTORY lines.
    fn read_tail(&mut self, cap: bool) {
        let Ok(mut f) = File::open(&self.path) else {
            return;
        };
        self.mtime = f.metadata().and_then(|m| m.modified()).ok();
        let mut buf = Vec::new();
        if f.seek(SeekFrom::Start(self.offset)).is_err() || f.read_to_end(&mut buf).is_err() {
            return;
        }
        // Only consume complete lines; a partial last line is read next time.
        let Some(last_nl) = buf.iter().rposition(|&b| b == b'\n') else {
            return;
        };
        self.offset += last_nl as u64 + 1;
        let text = String::from_utf8_lossy(&buf[..last_nl]);
        let lines: Vec<&str> = text.split('\n').filter(|l| is_command(l)).collect();
        let skip = if cap { lines.len().saturating_sub(MAX_HISTORY) } else { 0 };
        for l in &lines[skip..] {
            self.add(l);
        }
    }

    fn add(&mut self, line: &str) {
        self.seq += 1;
        if let Some(&i) = self.index.get(line) {
            let e = &mut self.entries[i];
            e.count += 1;
            e.last = self.seq;
            return;
        }
        let text: Box<str> = line.into();
        self.index.insert(text.clone(), self.entries.len());
        self.entries.push(Entry {
            mask: char_mask(line),
            text,
            count: 1,
            last: self.seq,
        });
    }

    /// Highest sequence number assigned so far.
    pub fn newest(&self) -> u32 {
        self.seq
    }
}

/// Names of entries in each `:`-separated PATH directory, deduped and sorted.
pub fn path_commands(path_var: &str) -> Vec<String> {
    let mut v: Vec<String> = path_var
        .split(':')
        .filter(|d| !d.is_empty())
        .filter_map(|d| std::fs::read_dir(d).ok())
        .flatten()
        .filter_map(|e| e.ok()?.file_name().into_string().ok())
        .collect();
    v.sort_unstable();
    v.dedup();
    v
}

/// One name per line (aliases/functions dump written by init.bash).
pub fn read_names(file: &Path) -> Vec<String> {
    std::fs::read_to_string(file)
        .unwrap_or_default()
        .lines()
        .filter(|l| !l.is_empty())
        .map(str::to_owned)
        .collect()
}

/// Entries of the directory part of `typed`, returned as `typed_dir + name`
/// (dirs end with `/`). Hidden entries only when the typed basename starts with `.`.
pub fn list_dir(cwd: &Path, typed: &str, max: usize) -> Vec<String> {
    let (dir_part, base) = match typed.rfind('/') {
        Some(i) => typed.split_at(i + 1),
        None => ("", typed),
    };
    let dir: PathBuf = if dir_part.is_empty() {
        cwd.to_path_buf()
    } else if let Some(rest) = dir_part.strip_prefix("~/") {
        match std::env::var_os("HOME") {
            Some(h) => PathBuf::from(h).join(rest),
            None => return Vec::new(),
        }
    } else {
        cwd.join(dir_part) // absolute dir_part replaces cwd
    };
    let Ok(rd) = std::fs::read_dir(&dir) else {
        return Vec::new();
    };
    let show_hidden = base.starts_with('.');
    rd.take(max)
        .filter_map(|e| {
            let e = e.ok()?;
            let name = e.file_name().into_string().ok()?;
            if name.starts_with('.') && !show_hidden {
                return None;
            }
            let is_dir = match e.file_type() {
                Ok(t) if t.is_symlink() => std::fs::metadata(e.path()).map(|m| m.is_dir()).unwrap_or(false),
                Ok(t) => t.is_dir(),
                Err(_) => false,
            };
            Some(format!("{dir_part}{name}{}", if is_dir { "/" } else { "" }))
        })
        .collect()
}

/// Second words of history lines whose first word is `cmd`, most used first.
/// Flags (starting with `-`) are skipped.
pub fn subcommands(h: &History, cmd: &str) -> Vec<String> {
    let mut counts: HashMap<&str, u32> = HashMap::new();
    for e in &h.entries {
        let mut w = e.text.split_whitespace();
        if w.next() != Some(cmd) {
            continue;
        }
        if let Some(sub) = w.next().filter(|s| !s.starts_with('-')) {
            *counts.entry(sub).or_default() += e.count;
        }
    }
    let mut v: Vec<(&str, u32)> = counts.into_iter().collect();
    v.sort_unstable_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(b.0)));
    v.into_iter().map(|(s, _)| s.to_owned()).collect()
}

/// History file lines that are commands (not blank, not `#<epoch>` timestamps).
fn is_command(l: &str) -> bool {
    if l.trim().is_empty() {
        return false;
    }
    !(l.len() > 1 && l.starts_with('#') && l[1..].bytes().all(|b| b.is_ascii_digit()))
}

#[cfg(test)]
pub mod testutil {
    use std::path::PathBuf;
    use std::sync::atomic::{AtomicU32, Ordering};

    static N: AtomicU32 = AtomicU32::new(0);

    /// Fresh empty temp dir for one test.
    pub fn tempdir() -> PathBuf {
        let d = std::env::temp_dir().join(format!(
            "bash-suggest-test-{}-{}",
            std::process::id(),
            N.fetch_add(1, Ordering::Relaxed)
        ));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        d
    }
}

#[cfg(test)]
mod tests {
    use super::testutil::tempdir;
    use super::*;
    use std::io::Write;

    fn hist(lines: &[&str]) -> (PathBuf, History) {
        let d = tempdir();
        let p = d.join("hist");
        std::fs::write(&p, lines.join("\n") + "\n").unwrap();
        let h = History::load(&p);
        (p, h)
    }

    fn find<'a>(h: &'a History, t: &str) -> &'a Entry {
        h.entries.iter().find(|e| &*e.text == t).unwrap()
    }

    #[test]
    fn history_dedups_and_counts() {
        let (_, h) = hist(&["ls", "git status", "git push", "git status"]);
        assert_eq!(h.entries.len(), 3);
        assert_eq!(find(&h, "git status").count, 2);
        assert!(find(&h, "git status").last > find(&h, "git push").last);
    }

    #[test]
    fn history_skips_timestamps() {
        let (_, h) = hist(&["#1700000000", "ls"]);
        assert_eq!(h.entries.len(), 1);
    }

    #[test]
    fn history_missing_file_is_empty() {
        let h = History::load(Path::new("/nonexistent/bash-suggest-hist"));
        assert!(h.entries.is_empty());
    }

    #[test]
    fn history_reads_appended_lines_only() {
        let (p, mut h) = hist(&["ls", "pwd"]);
        // mtime granularity: make sure the change is visible
        std::thread::sleep(std::time::Duration::from_millis(20));
        let mut f = std::fs::OpenOptions::new().append(true).open(&p).unwrap();
        f.write_all(b"make\nls\n").unwrap();
        drop(f);
        h.refresh_if_changed();
        assert_eq!(h.entries.len(), 3);
        assert_eq!(find(&h, "ls").count, 2);
        assert_eq!(find(&h, "pwd").count, 1);
    }

    #[test]
    fn history_full_reload_when_truncated() {
        let (p, mut h) = hist(&["ls", "pwd", "make"]);
        std::thread::sleep(std::time::Duration::from_millis(20));
        std::fs::write(&p, "echo\n").unwrap();
        h.refresh_if_changed();
        assert_eq!(h.entries.len(), 1);
        assert_eq!(&*h.entries[0].text, "echo");
    }

    #[test]
    fn subcommands_by_count() {
        let (_, h) = hist(&["git status", "git push", "git status", "git -C x log", "ls -l"]);
        assert_eq!(subcommands(&h, "git"), vec!["status", "push"]);
    }

    #[test]
    fn list_dir_marks_dirs_and_hides_dotfiles() {
        let d = tempdir();
        std::fs::create_dir(d.join("src")).unwrap();
        std::fs::write(d.join("a.txt"), "").unwrap();
        std::fs::write(d.join(".hidden"), "").unwrap();
        let mut v = list_dir(&d, "s", 500);
        v.sort();
        assert_eq!(v, vec!["a.txt", "src/"]);
        assert!(list_dir(&d, ".h", 500).contains(&".hidden".to_string()));
        std::fs::write(d.join("src/main.rs"), "").unwrap();
        assert_eq!(list_dir(&d, "src/m", 500), vec!["src/main.rs"]);
    }

    #[test]
    fn path_commands_dedup_sorted() {
        let a = tempdir();
        let b = tempdir();
        std::fs::write(a.join("zz"), "").unwrap();
        std::fs::write(a.join("cargo"), "").unwrap();
        std::fs::write(b.join("cargo"), "").unwrap();
        let pv = format!("{}:{}:/nonexistent", a.display(), b.display());
        assert_eq!(path_commands(&pv), vec!["cargo", "zz"]);
    }

    #[test]
    fn read_names_lines() {
        let d = tempdir();
        std::fs::write(d.join("n"), "ll\nmyfn\n\n").unwrap();
        assert_eq!(read_names(&d.join("n")), vec!["ll", "myfn"]);
        assert!(read_names(&d.join("missing")).is_empty());
    }

    #[test]
    fn mask_prefilter() {
        assert_eq!(char_mask("ab") & !char_mask("cab"), 0);
        assert_ne!(char_mask("z") & !char_mask("cab"), 0);
    }
}
