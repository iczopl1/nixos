//! Turns raw terminal input into actions. Pure state machine: no I/O.
//! Only a few keys are ever taken; everything else goes to bash unchanged.

#[derive(Debug, Clone, PartialEq)]
pub enum Action {
    /// Send these bytes to bash.
    Forward(Vec<u8>),
    /// Highlight this list row (None = leave list mode); redraw needed.
    Select(Option<usize>),
    /// Put list row N on the command line.
    AcceptItem(usize),
    /// Append the ghost text to the command line.
    AcceptGhost,
}

/// What is on screen right now, as seen by the main loop.
#[derive(Debug, Clone, Copy, Default)]
pub struct View {
    pub n_items: usize,
    pub has_ghost: bool,
}

const PASTE_START: &[u8] = b"\x1b[200~";
const PASTE_END: &[u8] = b"\x1b[201~";

#[derive(Default)]
pub struct Keys {
    list_mode: bool,
    sel: usize,
    in_paste: bool,
    /// Incomplete escape sequence (or paste-end prefix) from the previous read.
    carry: Vec<u8>,
}

impl Keys {
    #[cfg(test)]
    pub fn in_list(&self) -> bool {
        self.list_mode
    }

    /// Leave list mode without an action (e.g. suggestions changed or hidden).
    pub fn reset(&mut self) {
        self.list_mode = false;
        self.sel = 0;
    }

    /// Bytes are held back (incomplete sequence). Caller should call `flush`
    /// after ~25 ms without more input.
    pub fn pending(&self) -> bool {
        !self.carry.is_empty()
    }

    pub fn handle(&mut self, input: &[u8], view: View) -> Vec<Action> {
        let mut buf = std::mem::take(&mut self.carry);
        buf.extend_from_slice(input);
        let mut acts = Vec::new();
        // Once bash got new input, the view is stale: the rest goes to bash as is.
        let mut stale = false;
        let mut i = 0;
        while i < buf.len() {
            let rest = &buf[i..];
            if self.in_paste {
                if let Some(p) = find(rest, PASTE_END) {
                    let n = p + PASTE_END.len();
                    push_fwd(&mut acts, &rest[..n]);
                    self.in_paste = false;
                    i += n;
                    continue;
                }
                let keep = partial_suffix(rest, PASTE_END);
                push_fwd(&mut acts, &rest[..rest.len() - keep]);
                self.carry = rest[rest.len() - keep..].to_vec();
                return acts;
            }
            let Some(n) = key_len(rest) else {
                self.carry = rest.to_vec();
                return acts;
            };
            let key = &rest[..n];
            if key == PASTE_START {
                self.leave_list(&mut acts);
                self.in_paste = true;
                push_fwd(&mut acts, key);
                stale = true;
            } else if stale {
                push_fwd(&mut acts, key);
            } else {
                stale = self.key(key, view, &mut acts);
            }
            i += n;
        }
        acts
    }

    /// Timeout after `pending()`: treat held bytes as complete keys.
    pub fn flush(&mut self, view: View) -> Vec<Action> {
        let held = std::mem::take(&mut self.carry);
        let mut acts = Vec::new();
        if held == b"\x1b" && !self.in_paste {
            self.key(&held, view, &mut acts);
        } else if !held.is_empty() {
            push_fwd(&mut acts, &held);
        }
        acts
    }

    /// Handle one complete key. Returns true when bash's line may have changed.
    fn key(&mut self, key: &[u8], view: View, acts: &mut Vec<Action>) -> bool {
        let n = view.n_items;
        if n == 0 {
            self.list_mode = false;
        }
        self.sel %= n.max(1);
        match key {
            b"\x1b[C" | b"\x1bOC" if !self.list_mode && view.has_ghost => {
                acts.push(Action::AcceptGhost);
                return true;
            }
            b"\t" if n > 0 => {
                self.sel = if self.list_mode { (self.sel + 1) % n } else { 0 };
                self.list_mode = true;
                acts.push(Action::Select(Some(self.sel)));
                return false;
            }
            b"\x1b[Z" if n > 0 => {
                self.sel = if self.list_mode { (self.sel + n - 1) % n } else { n - 1 };
                self.list_mode = true;
                acts.push(Action::Select(Some(self.sel)));
                return false;
            }
            b"\x1b[A" | b"\x1bOA" if self.list_mode => {
                self.sel = (self.sel + n - 1) % n;
                acts.push(Action::Select(Some(self.sel)));
                return false;
            }
            b"\x1b[B" | b"\x1bOB" if self.list_mode => {
                self.sel = (self.sel + 1) % n;
                acts.push(Action::Select(Some(self.sel)));
                return false;
            }
            b"\r" if self.list_mode => {
                acts.push(Action::AcceptItem(self.sel));
                self.reset();
                return true;
            }
            b"\x1b" if self.list_mode => {
                self.leave_list(acts);
                return false;
            }
            _ => {}
        }
        self.leave_list(acts);
        push_fwd(acts, key);
        true
    }

    fn leave_list(&mut self, acts: &mut Vec<Action>) {
        if self.list_mode {
            self.reset();
            acts.push(Action::Select(None));
        }
    }
}

/// Length of the first complete key in `b`, or None if it is an incomplete
/// escape sequence (more bytes may follow).
fn key_len(b: &[u8]) -> Option<usize> {
    if b[0] != 0x1b {
        return Some(1);
    }
    match b.get(1) {
        None => None,
        Some(b'[') => match b[2..].iter().position(|c| (0x40..=0x7e).contains(c)) {
            Some(p) => Some(p + 3),
            None if b.len() > 32 => Some(b.len()), // garbage: pass through
            None => None,
        },
        Some(b'O') => (b.len() >= 3).then_some(3),
        Some(0x1b) => Some(1),
        Some(_) => Some(2),
    }
}

fn push_fwd(acts: &mut Vec<Action>, bytes: &[u8]) {
    if bytes.is_empty() {
        return;
    }
    if let Some(Action::Forward(v)) = acts.last_mut() {
        v.extend_from_slice(bytes);
    } else {
        acts.push(Action::Forward(bytes.to_vec()));
    }
}

fn find(hay: &[u8], needle: &[u8]) -> Option<usize> {
    memchr::memmem::find(hay, needle)
}

/// Length of the longest suffix of `b` that is a proper prefix of `pat`.
fn partial_suffix(b: &[u8], pat: &[u8]) -> usize {
    (1..pat.len().min(b.len() + 1)).rev().find(|&k| b.ends_with(&pat[..k])).unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::Action::*;
    use super::*;

    const ITEMS: View = View { n_items: 3, has_ghost: true };
    const NONE: View = View { n_items: 0, has_ghost: false };

    fn fwd(b: &[u8]) -> Action {
        Forward(b.to_vec())
    }

    #[test]
    fn right_accepts_ghost() {
        let mut k = Keys::default();
        assert_eq!(k.handle(b"\x1b[C", ITEMS), vec![AcceptGhost]);
        assert_eq!(k.handle(b"\x1bOC", ITEMS), vec![AcceptGhost]);
    }

    #[test]
    fn right_without_ghost_forwards() {
        let mut k = Keys::default();
        assert_eq!(k.handle(b"\x1b[C", NONE), vec![fwd(b"\x1b[C")]);
    }

    #[test]
    fn plain_keys_forward_merged() {
        let mut k = Keys::default();
        assert_eq!(k.handle(b"ls -l", ITEMS), vec![fwd(b"ls -l")]);
    }

    #[test]
    fn tab_enters_list_and_cycles() {
        let mut k = Keys::default();
        assert_eq!(k.handle(b"\t", ITEMS), vec![Select(Some(0))]);
        assert_eq!(k.handle(b"\t", ITEMS), vec![Select(Some(1))]);
        assert_eq!(k.handle(b"\t", ITEMS), vec![Select(Some(2))]);
        assert_eq!(k.handle(b"\t", ITEMS), vec![Select(Some(0))]);
        assert!(k.in_list());
    }

    #[test]
    fn tab_without_items_goes_to_bash() {
        let mut k = Keys::default();
        assert_eq!(k.handle(b"\t", NONE), vec![fwd(b"\t")]);
    }

    #[test]
    fn shift_tab_goes_back_and_wraps() {
        let mut k = Keys::default();
        assert_eq!(k.handle(b"\x1b[Z", ITEMS), vec![Select(Some(2))]);
        assert_eq!(k.handle(b"\x1b[Z", ITEMS), vec![Select(Some(1))]);
    }

    #[test]
    fn up_down_only_in_list_mode() {
        let mut k = Keys::default();
        assert_eq!(k.handle(b"\x1b[A", ITEMS), vec![fwd(b"\x1b[A")]);
        k.handle(b"\t", ITEMS);
        assert_eq!(k.handle(b"\x1b[B", ITEMS), vec![Select(Some(1))]);
        assert_eq!(k.handle(b"\x1bOA", ITEMS), vec![Select(Some(0))]);
    }

    #[test]
    fn enter_in_list_accepts_and_leaves() {
        let mut k = Keys::default();
        k.handle(b"\t\t", ITEMS);
        assert_eq!(k.handle(b"\r", ITEMS), vec![AcceptItem(1)]);
        assert!(!k.in_list());
        assert_eq!(k.handle(b"\r", ITEMS), vec![fwd(b"\r")]);
    }

    #[test]
    fn right_in_list_mode_forwards() {
        let mut k = Keys::default();
        k.handle(b"\t", ITEMS);
        assert_eq!(k.handle(b"\x1b[C", ITEMS), vec![Select(None), fwd(b"\x1b[C")]);
    }

    #[test]
    fn other_key_leaves_list() {
        let mut k = Keys::default();
        k.handle(b"\t", ITEMS);
        assert_eq!(k.handle(b"x", ITEMS), vec![Select(None), fwd(b"x")]);
        assert!(!k.in_list());
    }

    #[test]
    fn lone_esc_in_list_is_held_then_leaves() {
        let mut k = Keys::default();
        k.handle(b"\t", ITEMS);
        assert_eq!(k.handle(b"\x1b", ITEMS), vec![]);
        assert!(k.pending());
        assert_eq!(k.flush(ITEMS), vec![Select(None)]);
        assert!(!k.in_list());
    }

    #[test]
    fn esc_outside_list_forwarded_on_flush() {
        let mut k = Keys::default();
        assert_eq!(k.handle(b"\x1b", ITEMS), vec![]);
        assert_eq!(k.flush(ITEMS), vec![fwd(b"\x1b")]);
    }

    #[test]
    fn alt_key_forwarded() {
        let mut k = Keys::default();
        assert_eq!(k.handle(b"\x1bb", ITEMS), vec![fwd(b"\x1bb")]);
    }

    #[test]
    fn keys_after_forward_in_same_read_are_plain() {
        // The view is stale once bash has new input; only bash may act on the rest.
        let mut k = Keys::default();
        assert_eq!(k.handle(b"a\t\x1b[C", ITEMS), vec![fwd(b"a\t\x1b[C")]);
    }

    #[test]
    fn right_arrow_split_at_every_offset() {
        let seq = b"\x1b[C";
        for i in 1..seq.len() {
            let mut k = Keys::default();
            let mut acts = k.handle(&seq[..i], ITEMS);
            acts.extend(k.handle(&seq[i..], ITEMS));
            assert_eq!(acts, vec![AcceptGhost], "split at {i}");
        }
    }

    #[test]
    fn shift_tab_split_at_every_offset() {
        let seq = b"\x1b[Z";
        for i in 1..seq.len() {
            let mut k = Keys::default();
            let mut acts = k.handle(&seq[..i], ITEMS);
            acts.extend(k.handle(&seq[i..], ITEMS));
            assert_eq!(acts, vec![Select(Some(2))], "split at {i}");
        }
    }

    fn joined(acts: &[Action]) -> Vec<u8> {
        let mut v = Vec::new();
        for a in acts {
            match a {
                Forward(b) => v.extend_from_slice(b),
                other => panic!("unexpected {other:?}"),
            }
        }
        v
    }

    #[test]
    fn paste_passes_tab_and_arrows_untouched() {
        let paste = b"\x1b[200~a\tb\x1b[Cc\r\x1b[201~";
        let mut k = Keys::default();
        assert_eq!(joined(&k.handle(paste, ITEMS)), paste.to_vec());
        // after the paste, keys work again
        assert_eq!(k.handle(b"\t", ITEMS), vec![Select(Some(0))]);
    }

    #[test]
    fn paste_split_at_every_offset() {
        let paste = b"\x1b[200~a\tb\x1b[Cc\x1b[201~";
        for i in 1..paste.len() {
            let mut k = Keys::default();
            let mut acts = k.handle(&paste[..i], ITEMS);
            acts.extend(k.handle(&paste[i..], ITEMS));
            assert_eq!(joined(&acts), paste.to_vec(), "split at {i}");
            assert!(!k.pending(), "split at {i}");
            assert_eq!(k.handle(b"\t", ITEMS), vec![Select(Some(0))], "split at {i}");
        }
    }
}

/// Keystrokes that turn the typed `line` (cursor at end) into `new`:
/// backspaces over the differing tail, then the new text typed as plain keys
/// (not bracketed paste: bash would leave it highlighted). None if `new`
/// contains control characters.
pub fn edit_bytes(line: &str, new: &str) -> Option<Vec<u8>> {
    if new.bytes().any(|b| b < 0x20 || b == 0x7f) {
        return None;
    }
    let common = line.bytes().zip(new.bytes()).take_while(|(a, b)| a == b).count();
    let mut v = vec![0x7f; line.len() - common];
    let tail = &new.as_bytes()[common..];
    v.extend_from_slice(tail);
    Some(v)
}

#[cfg(test)]
mod edit_tests {
    use super::edit_bytes;

    #[test]
    fn appends_suffix() {
        assert_eq!(edit_bytes("git s", "git status").unwrap(), b"tatus");
    }

    #[test]
    fn backspaces_differing_tail() {
        assert_eq!(edit_bytes("gst", "git status").unwrap(), b"\x7f\x7fit status");
    }

    #[test]
    fn types_plain_text_not_paste() {
        assert_eq!(edit_bytes("ls", "ls -la").unwrap(), b" -la");
    }

    #[test]
    fn rejects_control_chars() {
        assert!(edit_bytes("e", "echo\x03").is_none());
        assert!(edit_bytes("e", "echo\nrm").is_none());
    }

    #[test]
    fn only_backspaces_when_new_is_prefix() {
        assert_eq!(edit_bytes("cd src/x", "cd src/").unwrap(), b"\x7f");
    }
}
