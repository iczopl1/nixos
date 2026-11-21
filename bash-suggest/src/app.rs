//! Glue between bash output, user input and drawing. All decisions live here;
//! main.rs only moves bytes and waits on file descriptors.

use crate::keys::{edit_bytes, Action, Keys, View};
use crate::markers::{Mark, Scanner};
use crate::render::{self, Drawn};
use crate::screen::Screen;
use crate::sources::{path_commands, read_names, History};
use crate::suggest::{suggest, Ctx, Suggestion};
use std::path::PathBuf;
use std::time::{Duration, Instant, SystemTime};

/// List height when the prompt is near the bottom (the screen scrolls to make room).
/// Otherwise the list fills every row below the prompt.
const MIN_ITEMS: usize = 8;
/// Quiet time after bash output before drawing (one recompute per burst of typing).
const SETTLE: Duration = Duration::from_millis(5);
/// How long a lone ESC / incomplete sequence is held back.
const ESC_HOLD: Duration = Duration::from_millis(25);
/// Give up on the cursor-position reply after this long.
const QUERY_TIMEOUT: Duration = Duration::from_millis(50);

/// Files and lists that feed suggestions; refreshed only at a new prompt.
struct Sources {
    names_file: PathBuf,
    env_file: PathBuf,
    names_mtime: Option<SystemTime>,
    env_mtime: Option<SystemTime>,
    path_var: String,
    path_mtimes: Vec<Option<SystemTime>>,
    path_cmds: Vec<String>,
    names: Vec<String>,
    /// path_cmds + names, sorted and deduped.
    commands: Vec<String>,
    history: History,
    hist_path: PathBuf,
}

fn mtime(p: &std::path::Path) -> Option<SystemTime> {
    std::fs::metadata(p).and_then(|m| m.modified()).ok()
}

impl Sources {
    fn new(bash_pid: u32) -> Self {
        let dir = std::env::var_os("XDG_RUNTIME_DIR").map_or_else(|| PathBuf::from("/tmp"), PathBuf::from);
        let home = std::env::var_os("HOME").map(PathBuf::from).unwrap_or_default();
        let hist_path = home.join(".bash_history");
        Sources {
            names_file: dir.join(format!("bash-suggest.{bash_pid}.names")),
            env_file: dir.join(format!("bash-suggest.{bash_pid}.env")),
            names_mtime: None,
            env_mtime: None,
            path_var: std::env::var("PATH").unwrap_or_default(),
            path_mtimes: Vec::new(),
            path_cmds: Vec::new(),
            names: Vec::new(),
            commands: Vec::new(),
            history: History::load(&hist_path),
            hist_path,
        }
    }

    /// A few stats; real work only when something changed.
    fn refresh(&mut self) {
        let mut cmds_dirty = false;
        let em = mtime(&self.env_file);
        if em.is_some() && em != self.env_mtime {
            self.env_mtime = em;
            let text = std::fs::read_to_string(&self.env_file).unwrap_or_default();
            let mut lines = text.lines();
            let hist = lines.next().unwrap_or("");
            let path = lines.next().unwrap_or("");
            if !hist.is_empty() && PathBuf::from(hist) != self.hist_path {
                self.hist_path = PathBuf::from(hist);
                self.history = History::load(&self.hist_path);
            }
            if !path.is_empty() && path != self.path_var {
                self.path_var = path.to_owned();
                self.path_mtimes.clear();
            }
        }
        let pm: Vec<Option<SystemTime>> = self.path_var.split(':').map(|d| mtime(d.as_ref())).collect();
        if pm != self.path_mtimes {
            self.path_mtimes = pm;
            self.path_cmds = path_commands(&self.path_var);
            cmds_dirty = true;
        }
        let nm = mtime(&self.names_file);
        if nm != self.names_mtime {
            self.names_mtime = nm;
            self.names = read_names(&self.names_file);
            cmds_dirty = true;
        }
        if cmds_dirty {
            self.commands = self.path_cmds.iter().chain(&self.names).cloned().collect();
            self.commands.sort_unstable();
            self.commands.dedup();
        }
        self.history.refresh_if_changed();
    }

    fn remove_files(&self) {
        let _ = std::fs::remove_file(&self.names_file);
        let _ = std::fs::remove_file(&self.env_file);
    }
}

enum Query {
    None,
    /// `ESC[6n` sent; bash output meanwhile is kept for the mirror.
    Waiting { deadline: Instant, backlog: Vec<u8>, inbuf: Vec<u8> },
}

pub struct App {
    bash_pid: u32,
    scanner: Scanner,
    screen: Screen,
    keys: Keys,
    sources: Sources,
    query: Query,
    items: Vec<Suggestion>,
    sel: Option<usize>,
    /// Line the items were computed for.
    items_line: Option<String>,
    drawn: Drawn,
    drawn_cursor: (u16, u16),
    settle_at: Option<Instant>,
    esc_at: Option<Instant>,
    /// Bytes for the real terminal.
    pub out: Vec<u8>,
    /// Bytes for bash.
    pub to_child: Vec<u8>,
}

impl App {
    pub fn new(bash_pid: u32, size: (u16, u16)) -> Self {
        App {
            bash_pid,
            scanner: Scanner::default(),
            screen: Screen::new(size),
            keys: Keys::default(),
            sources: Sources::new(bash_pid),
            query: Query::None,
            items: Vec::new(),
            sel: None,
            items_line: None,
            drawn: Drawn::default(),
            drawn_cursor: (0, 0),
            settle_at: None,
            esc_at: None,
            out: Vec::new(),
            to_child: Vec::new(),
        }
    }

    /// When the main loop must wake up next (None = only on I/O).
    pub fn next_deadline(&self) -> Option<Instant> {
        let q = match &self.query {
            Query::Waiting { deadline, .. } => Some(*deadline),
            Query::None => None,
        };
        [self.settle_at, self.esc_at, q].into_iter().flatten().min()
    }

    /// Output from bash. `fg_is_bash` tells whether our bash is the foreground job.
    pub fn on_output(&mut self, data: &[u8], fg_is_bash: impl Fn() -> bool) {
        self.erase();
        let mut marks: Vec<(usize, Mark)> = Vec::new();
        self.scanner.scan(data, |end, m| marks.push((end, m)));
        let mut pos = 0;
        for (end, m) in marks {
            self.pass_output(&data[pos..end]);
            pos = end;
            match m {
                Mark::InputStart if fg_is_bash() => {
                    self.hide();
                    self.screen.stop();
                    self.out.extend_from_slice(b"\x1b[6n");
                    self.query = Query::Waiting {
                        deadline: Instant::now() + QUERY_TIMEOUT,
                        backlog: Vec::new(),
                        inbuf: Vec::new(),
                    };
                }
                Mark::InputStart => {}
                Mark::PromptStart | Mark::CmdStart => {
                    self.hide();
                    self.screen.stop();
                    self.query = Query::None;
                    if m == Mark::PromptStart {
                        self.sources.refresh();
                    }
                }
                Mark::PasteOn | Mark::PasteOff => {}
            }
        }
        self.pass_output(&data[pos..]);
        if self.screen.active() {
            self.settle_at = Some(Instant::now() + SETTLE);
        }
    }

    fn pass_output(&mut self, bytes: &[u8]) {
        self.out.extend_from_slice(bytes);
        match &mut self.query {
            Query::Waiting { backlog, .. } => backlog.extend_from_slice(bytes),
            Query::None => self.screen.feed(bytes),
        }
    }

    /// Input from the user.
    pub fn on_input(&mut self, data: &[u8]) {
        let mut data = data.to_vec();
        if let Query::Waiting { inbuf, backlog, .. } = &mut self.query {
            inbuf.extend_from_slice(&data);
            match take_cpr(inbuf) {
                Cpr::Found(pos, rest) => {
                    let backlog = std::mem::take(backlog);
                    self.query = Query::None;
                    self.screen.start(pos);
                    self.screen.feed(&backlog);
                    self.settle_at = Some(Instant::now());
                    data = rest;
                }
                Cpr::Partial => return,
                Cpr::NotThere => data = std::mem::take(inbuf),
            }
        }
        if data.is_empty() {
            return;
        }
        let acts = self.keys.handle(&data, self.view());
        self.apply(acts);
        self.esc_at = self.keys.pending().then(|| Instant::now() + ESC_HOLD);
    }

    /// Timers.
    pub fn on_tick(&mut self, now: Instant) {
        if let Query::Waiting { deadline, inbuf, .. } = &mut self.query {
            if now >= *deadline {
                // Terminal never answered: no suggestions at this prompt.
                let held = std::mem::take(inbuf);
                self.query = Query::None;
                if !held.is_empty() {
                    let acts = self.keys.handle(&held, self.view());
                    self.apply(acts);
                }
            }
        }
        if self.esc_at.is_some_and(|t| now >= t) {
            self.esc_at = None;
            let acts = self.keys.flush(self.view());
            self.apply(acts);
        }
        if self.settle_at.is_some_and(|t| now >= t) {
            self.settle_at = None;
            self.refresh_suggestions();
            self.draw();
        }
    }

    pub fn on_resize(&mut self, size: (u16, u16)) {
        self.erase();
        self.hide();
        self.screen.resize(size);
        self.query = Query::None;
    }

    pub fn shutdown(&mut self) {
        self.erase();
        self.sources.remove_files();
    }

    fn view(&self) -> View {
        View {
            n_items: self.items.len(),
            has_ghost: self.items.first().is_some_and(|s| s.ghost.is_some()),
        }
    }

    fn apply(&mut self, acts: Vec<Action>) {
        for a in acts {
            match a {
                Action::Forward(b) => {
                    self.erase();
                    self.to_child.extend_from_slice(&b);
                }
                Action::Select(s) => {
                    self.sel = s;
                    self.erase();
                    self.draw();
                }
                Action::AcceptItem(i) => self.accept(i, false),
                Action::AcceptGhost => self.accept(0, true),
            }
        }
    }

    fn accept(&mut self, i: usize, ghost_only: bool) {
        self.erase();
        let (Some(line), Some(item)) = (self.items_line.clone(), self.items.get(i)) else {
            return;
        };
        let new = if ghost_only {
            // Right arrow takes one word of the ghost text at a time.
            let Some(g) = &item.ghost else { return };
            format!("{line}{}", next_word(g))
        } else {
            item.text.clone()
        };
        if let Some(b) = edit_bytes(&line, &new) {
            self.to_child.extend_from_slice(&b);
        }
        self.hide();
    }

    /// Forget suggestions (nothing is drawn after the next erase).
    fn hide(&mut self) {
        self.items.clear();
        self.items_line = None;
        self.sel = None;
        self.keys.reset();
    }

    fn refresh_suggestions(&mut self) {
        let line = match self.screen.current_line() {
            Some((l, idx)) if idx == l.len() && !l.trim().is_empty() => l,
            _ => {
                self.hide();
                return;
            }
        };
        if self.items_line.as_deref() == Some(line.as_str()) {
            return; // unchanged: keep items and selection
        }
        let cwd = cwd_of(self.bash_pid);
        let ctx = Ctx { history: &self.sources.history, commands: &self.sources.commands, cwd: &cwd };
        let (rows, _) = self.screen.size();
        let below = self.screen.cursor().map_or(0, |(r, _)| rows.saturating_sub(r + 1) as usize);
        let max = below.max(MIN_ITEMS);
        let mut items = suggest(&line, &ctx, max * 2);
        items.retain(|s| !s.text.bytes().any(|b| b < 0x20 || b == 0x7f));
        items.truncate(max);
        self.items = items;
        self.items_line = Some(line);
        self.sel = None;
        self.keys.reset();
    }

    fn draw(&mut self) {
        if self.items.is_empty() || !self.drawn.is_empty() {
            return;
        }
        let Some(_) = self.screen.cursor() else { return };
        let reserve = render::reserve(self.items.len() as u16);
        self.screen.feed(&reserve);
        let cursor = self.screen.cursor().unwrap_or((0, 0));
        self.out.extend_from_slice(&reserve);
        let texts: Vec<String> = self.items.iter().map(|s| s.text.clone()).collect();
        let ghost = if self.sel.is_none() { self.items[0].ghost.as_deref() } else { None };
        self.drawn = render::draw(&mut self.out, ghost, &texts, self.sel, cursor, self.screen.size().1);
        self.drawn_cursor = cursor;
    }

    fn erase(&mut self) {
        if !self.drawn.is_empty() {
            render::erase(&mut self.out, &self.drawn, self.drawn_cursor);
            self.drawn = Drawn::default();
        }
    }
}

/// First word of `ghost`: leading spaces, then up to the next space (excluded)
/// or `/` / `.` (included, so paths and names fill one part at a time).
fn next_word(ghost: &str) -> &str {
    let start = ghost.len() - ghost.trim_start_matches(' ').len();
    let rest = &ghost[start..];
    let end = match rest.find([' ', '/', '.']) {
        Some(i) if rest.as_bytes()[i] != b' ' => i + 1,
        Some(i) => i,
        None => rest.len(),
    };
    &ghost[..start + end]
}

/// bash's current directory (it may differ from ours after `cd`).
fn cwd_of(pid: u32) -> PathBuf {
    std::fs::read_link(format!("/proc/{pid}/cwd")).unwrap_or_else(|_| PathBuf::from("."))
}

enum Cpr {
    /// Reply found: 0-based (row, col) and the input with the reply removed.
    Found((u16, u16), Vec<u8>),
    /// Input ends with what may be the start of a reply: wait for more.
    Partial,
    NotThere,
}

/// Find and remove a cursor position report `ESC [ row ; col R`.
fn take_cpr(buf: &[u8]) -> Cpr {
    let mut i = 0;
    while let Some(k) = memchr::memchr(0x1b, &buf[i..]) {
        let s = i + k;
        let rest = &buf[s..];
        let mut j = 1;
        let mut nums = [0u32; 2];
        let mut which = 0;
        let mut digits = 0;
        let ok = loop {
            match rest.get(j) {
                None => return Cpr::Partial,
                Some(b'[') if j == 1 => {}
                Some(d @ b'0'..=b'9') if j > 1 => {
                    nums[which] = nums[which].saturating_mul(10).saturating_add((d - b'0') as u32);
                    digits += 1;
                }
                Some(b';') if which == 0 && digits > 0 => {
                    which = 1;
                    digits = 0;
                }
                Some(b'R') if which == 1 && digits > 0 => break true,
                _ => break false,
            }
            j += 1;
        };
        if ok {
            let mut restv = buf[..s].to_vec();
            restv.extend_from_slice(&rest[j + 1..]);
            let pos = (nums[0].saturating_sub(1) as u16, nums[1].saturating_sub(1) as u16);
            return Cpr::Found(pos, restv);
        }
        i = s + 1;
    }
    Cpr::NotThere
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cpr_found_and_removed() {
        match take_cpr(b"a\x1b[12;5Rb") {
            Cpr::Found(p, rest) => {
                assert_eq!(p, (11, 4));
                assert_eq!(rest, b"ab");
            }
            _ => panic!(),
        }
    }

    #[test]
    fn cpr_partial_waits() {
        assert!(matches!(take_cpr(b"\x1b[12"), Cpr::Partial));
        assert!(matches!(take_cpr(b"\x1b"), Cpr::Partial));
    }

    #[test]
    fn other_keys_not_cpr() {
        assert!(matches!(take_cpr(b"\x1b[A"), Cpr::NotThere));
        assert!(matches!(take_cpr(b"x"), Cpr::NotThere));
    }
}

#[cfg(test)]
mod word_tests {
    use super::next_word;

    #[test]
    fn takes_first_word() {
        assert_eq!(next_word("tatus --short"), "tatus");
    }

    #[test]
    fn leading_spaces_belong_to_the_word() {
        assert_eq!(next_word(" --short x"), " --short");
    }

    #[test]
    fn last_word_is_whole_rest() {
        assert_eq!(next_word("lpha"), "lpha");
    }

    #[test]
    fn path_parts_count_as_words() {
        assert_eq!(next_word("rc/main.rs"), "rc/");
    }
}

#[cfg(test)]
mod dot_tests {
    use super::next_word;

    #[test]
    fn dot_ends_a_word_and_is_included() {
        assert_eq!(next_word("ain.rs --x"), "ain.");
        assert_eq!(next_word("rs --x"), "rs");
    }
}
