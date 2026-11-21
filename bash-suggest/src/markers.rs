//! Finds shell-integration markers in bash's output stream without copying it.
//! OSC 133 A/B/C (prompt start / input start / command start) and readline's
//! bracketed-paste switch (`ESC[?2004h` / `ESC[?2004l`). Bytes are never
//! removed: the caller writes the whole buffer to the terminal unchanged.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Mark {
    PromptStart,
    InputStart,
    CmdStart,
    PasteOn,
    PasteOff,
}

const OSC: &[u8] = b"\x1b]133;";
const CSI_PASTE: &[u8] = b"\x1b[?2004";
const MAX_SEQ: usize = 64;

#[derive(Default)]
pub struct Scanner {
    /// Bytes of a possibly-matching sequence, starting with ESC. Survives across reads.
    seq: Vec<u8>,
}

enum Check {
    Partial,
    Done(Option<Mark>),
    NoMatch,
}

impl Scanner {
    /// Scan `data`; call `f(end, mark)` for each marker, where `end` is the
    /// offset in `data` just after the marker's last byte.
    pub fn scan(&mut self, data: &[u8], mut f: impl FnMut(usize, Mark)) {
        let mut i = 0;
        while i < data.len() {
            if self.seq.is_empty() {
                // Ground state: jump straight to the next ESC.
                match memchr::memchr(0x1b, &data[i..]) {
                    None => return,
                    Some(k) => {
                        self.seq.push(0x1b);
                        i += k + 1;
                        continue;
                    }
                }
            }
            let b = data[i];
            i += 1;
            self.seq.push(b);
            match self.check() {
                Check::Partial => {}
                Check::Done(m) => {
                    self.seq.clear();
                    if let Some(m) = m {
                        f(i, m);
                    }
                }
                Check::NoMatch => {
                    self.seq.clear();
                    if b == 0x1b {
                        self.seq.push(0x1b);
                    }
                }
            }
        }
    }

    fn check(&self) -> Check {
        let s = &self.seq[..];
        if OSC.starts_with(s) || CSI_PASTE.starts_with(s) {
            return Check::Partial;
        }
        if let Some(rest) = s.strip_prefix(OSC) {
            let mark = match rest[0] {
                b'A' => Some(Mark::PromptStart),
                b'B' => Some(Mark::InputStart),
                b'C' => Some(Mark::CmdStart),
                _ => None, // D and others: recognised, ignored
            };
            let last = *s.last().unwrap();
            if rest.len() > 1 && last == 0x07 {
                return Check::Done(mark);
            }
            if rest.len() > 2 && last == b'\\' && s[s.len() - 2] == 0x1b {
                return Check::Done(mark);
            }
            if s.len() > MAX_SEQ || (last == 0x1b && rest.len() == 1) {
                return Check::NoMatch;
            }
            return Check::Partial;
        }
        if let Some(rest) = s.strip_prefix(CSI_PASTE) {
            return match rest[0] {
                b'h' => Check::Done(Some(Mark::PasteOn)),
                b'l' => Check::Done(Some(Mark::PasteOff)),
                _ => Check::NoMatch,
            };
        }
        Check::NoMatch
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn run(parts: &[&[u8]]) -> Vec<(usize, Mark)> {
        let mut s = Scanner::default();
        let mut out = Vec::new();
        let mut base = 0;
        for p in parts {
            s.scan(p, |end, m| out.push((base + end, m)));
            base += p.len();
        }
        out
    }

    const STREAM: &[u8] = b"ab\x1b]133;A\x07$ \x1b]133;B\x07\x1b[?2004hls\x1b[?2004l\x1b]133;C\x1b\\out";

    fn expected() -> Vec<(usize, Mark)> {
        let pos = |pat: &[u8]| {
            STREAM.windows(pat.len()).position(|w| w == pat).unwrap() + pat.len()
        };
        vec![
            (pos(b"133;A\x07"), Mark::PromptStart),
            (pos(b"133;B\x07"), Mark::InputStart),
            (pos(b"2004h"), Mark::PasteOn),
            (pos(b"2004l"), Mark::PasteOff),
            (pos(b"133;C\x1b\\"), Mark::CmdStart),
        ]
    }

    #[test]
    fn whole_buffer() {
        assert_eq!(run(&[STREAM]), expected());
    }

    #[test]
    fn split_at_every_offset() {
        for k in 0..=STREAM.len() {
            assert_eq!(run(&[&STREAM[..k], &STREAM[k..]]), expected(), "split at {k}");
        }
    }

    #[test]
    fn other_sequences_ignored() {
        assert!(run(&[b"\x1b]0;title\x07\x1b[31mred\x1b[0m\x1b]133;D;0\x07"]).is_empty());
    }

    #[test]
    fn esc_inside_partial_restarts() {
        assert_eq!(run(&[b"\x1b]13\x1b]133;B\x07"]).len(), 1);
    }
}
