//! Mirror of the terminal while bash shows a prompt, used to read the typed line.
//! Emulation runs only between "input start" and "command start" (CPU budget).

use std::num::NonZeroU16;

/// Rows the mirror keeps after they scroll off, so scrolling can be measured.
const SCROLLBACK: usize = 1000;

pub struct Screen {
    parser: Option<vt100::Parser>,
    /// Where the typed line begins (row may go negative after scrolling = lost).
    input_start: (i32, u16),
    seen_scrollback: usize,
    size: (u16, u16),
}

fn nz(v: u16) -> NonZeroU16 {
    NonZeroU16::new(v.max(1)).unwrap()
}

impl Screen {
    pub fn new(size: (u16, u16)) -> Self {
        Screen { parser: None, input_start: (0, 0), seen_scrollback: 0, size }
    }

    /// Begin mirroring at the real cursor position (0-based row, col).
    pub fn start(&mut self, cursor: (u16, u16)) {
        let mut p = vt100::Parser::new(nz(self.size.0), nz(self.size.1), SCROLLBACK);
        p.process(format!("\x1b[{};{}H", cursor.0 + 1, cursor.1 + 1).as_bytes());
        self.parser = Some(p);
        self.input_start = (cursor.0 as i32, cursor.1);
        self.seen_scrollback = 0;
    }

    pub fn stop(&mut self) {
        self.parser = None;
    }

    pub fn active(&self) -> bool {
        self.parser.is_some()
    }

    pub fn feed(&mut self, bytes: &[u8]) {
        let Some(p) = self.parser.as_mut() else { return };
        p.process(bytes);
        let sb = p.screen().scrollback_len();
        if sb > self.seen_scrollback {
            self.input_start.0 -= (sb - self.seen_scrollback) as i32;
            self.seen_scrollback = sb;
        }
    }

    /// Size changed: positions are unknown until the next prompt.
    pub fn resize(&mut self, size: (u16, u16)) {
        self.size = size;
        self.parser = None;
    }

    pub fn cursor(&self) -> Option<(u16, u16)> {
        self.parser.as_ref().map(|p| p.screen().cursor_position())
    }

    pub fn size(&self) -> (u16, u16) {
        self.size
    }

    /// The typed line and the cursor's index in it. None when unknown or unsafe
    /// to suggest for: not at a prompt, alt screen, cursor before the input,
    /// multi-line (PS2) input, or non-ASCII text.
    pub fn current_line(&self) -> Option<(String, usize)> {
        let scr = self.parser.as_ref()?.screen();
        if scr.alternate_screen() || self.input_start.0 < 0 {
            return None;
        }
        let (sr, sc) = (self.input_start.0 as u16, self.input_start.1);
        let (cr, cc) = scr.cursor_position();
        if (cr, cc) < (sr, sc) {
            return None;
        }
        // Every row from the start to the cursor must be a soft wrap (else PS2 input).
        if (sr..cr).any(|r| !scr.row_wrapped(r)) {
            return None;
        }
        let (rows, cols) = self.size;
        let mut er = cr;
        while scr.row_wrapped(er) && er + 1 < rows {
            er += 1;
        }
        let mut text = String::new();
        let mut idx = None;
        for r in sr..=er {
            let c0 = if r == sr { sc } else { 0 };
            for c in c0..cols {
                if (r, c) == (cr, cc) {
                    idx = Some(text.len());
                }
                let cell = scr.cell(r, c)?;
                if cell.is_wide() || cell.is_wide_continuation() {
                    return None;
                }
                match cell.contents() {
                    "" => text.push(' '),
                    s if s.len() == 1 && s.is_ascii() => text.push_str(s),
                    _ => return None,
                }
            }
        }
        let idx = idx.unwrap_or(text.len());
        let keep = text.trim_end().len().max(idx);
        text.truncate(keep);
        Some((text, idx))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn at_prompt(size: (u16, u16), cursor: (u16, u16)) -> Screen {
        let mut s = Screen::new(size);
        s.start(cursor);
        s
    }

    #[test]
    fn reads_typed_line() {
        let mut s = at_prompt((24, 80), (0, 2));
        s.feed(b"git st");
        assert_eq!(s.current_line(), Some(("git st".into(), 6)));
    }

    #[test]
    fn trailing_space_kept_up_to_cursor() {
        let mut s = at_prompt((24, 80), (5, 2));
        s.feed(b"git ");
        assert_eq!(s.current_line(), Some(("git ".into(), 4)));
    }

    #[test]
    fn cursor_mid_line() {
        let mut s = at_prompt((24, 80), (0, 2));
        s.feed(b"git st\x1b[2D");
        assert_eq!(s.current_line(), Some(("git st".into(), 4)));
    }

    #[test]
    fn inactive_before_start_and_after_stop() {
        let mut s = Screen::new((24, 80));
        s.feed(b"x");
        assert_eq!(s.current_line(), None);
        s.start((0, 0));
        s.stop();
        assert_eq!(s.current_line(), None);
    }

    #[test]
    fn alt_screen_hides() {
        let mut s = at_prompt((24, 80), (0, 2));
        s.feed(b"ls\x1b[?1049h");
        assert_eq!(s.current_line(), None);
    }

    #[test]
    fn wrapped_line_on_bottom_row() {
        let mut s = at_prompt((24, 80), (23, 2));
        let typed = "a".repeat(100);
        s.feed(typed.as_bytes());
        assert_eq!(s.current_line(), Some((typed, 100)));
    }

    #[test]
    fn scroll_below_keeps_line() {
        // What the renderer does to reserve rows at the bottom.
        let mut s = at_prompt((24, 80), (23, 2));
        s.feed(b"ls");
        s.feed(b"\n\n\n\x1b[3A");
        assert_eq!(s.current_line(), Some(("ls".into(), 2)));
        assert_eq!(s.cursor(), Some((20, 4)));
    }

    #[test]
    fn ps2_continuation_hides() {
        let mut s = at_prompt((24, 80), (0, 2));
        s.feed(b"for i in 1\r\n> do");
        assert_eq!(s.current_line(), None);
    }

    #[test]
    fn non_ascii_hides() {
        let mut s = at_prompt((24, 80), (0, 2));
        s.feed("echo ü".as_bytes());
        assert_eq!(s.current_line(), None);
    }

    #[test]
    fn resize_stops() {
        let mut s = at_prompt((24, 80), (0, 2));
        s.resize((30, 100));
        assert!(!s.active());
        assert_eq!(s.size(), (30, 100));
    }
}
