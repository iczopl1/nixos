//! Escape sequences that draw and erase the ghost text and the list.
//! Pure: builds bytes, the caller writes them in one `write`.
//! Assumes the real terminal has output post-processing off (raw mode), so
//! LF moves straight down and keeps the column.

/// What is currently on screen, needed to erase it.
#[derive(Debug, Default, Clone, Copy, PartialEq)]
pub struct Drawn {
    pub rows_below: u16,
    pub ghost_len: u16,
}

impl Drawn {
    pub fn is_empty(&self) -> bool {
        self.rows_below == 0 && self.ghost_len == 0
    }
}

/// Bytes that make room for `k` rows under the cursor (scrolling at the bottom)
/// and return to the same column. Feed them to the screen mirror as well.
pub fn reserve(k: u16) -> Vec<u8> {
    if k == 0 {
        return Vec::new();
    }
    let mut v = vec![b'\n'; k as usize];
    v.extend_from_slice(format!("\x1b[{k}A").as_bytes());
    v
}

/// Draw ghost text after the cursor and the list under it. Call after `reserve(items.len())`.
/// `cursor` is (row, col), 0-based; `cols` is the terminal width.
pub fn draw(out: &mut Vec<u8>, ghost: Option<&str>, items: &[String], selected: Option<usize>, cursor: (u16, u16), cols: u16) -> Drawn {
    let col = cursor.1;
    let mut d = Drawn::default();
    out.extend_from_slice(b"\x1b[?2026h");
    // Never write into the last column: that would trigger a pending wrap.
    let avail = cols.saturating_sub(1).saturating_sub(col) as usize;
    if let Some(g) = ghost.filter(|_| avail > 0) {
        let g: String = g.chars().take(avail).collect();
        let n = g.chars().count() as u16;
        if n > 0 {
            out.extend_from_slice(b"\x1b[90m");
            out.extend_from_slice(g.as_bytes());
            out.extend_from_slice(format!("\x1b[0m\x1b[{n}D").as_bytes());
            d.ghost_len = n;
        }
    }
    let width = cols.saturating_sub(1) as usize;
    for (i, it) in items.iter().enumerate() {
        out.extend_from_slice(b"\n\r\x1b[2K");
        out.extend_from_slice(if selected == Some(i) { b"\x1b[7m" } else { b"\x1b[2m" });
        let t: String = it.chars().take(width).collect();
        out.extend_from_slice(t.as_bytes());
        out.extend_from_slice(b"\x1b[0m");
    }
    if !items.is_empty() {
        d.rows_below = items.len() as u16;
        out.extend_from_slice(format!("\x1b[{}A\x1b[{}G", items.len(), col + 1).as_bytes());
    }
    out.extend_from_slice(b"\x1b[?2026l");
    d
}

/// Remove what `draw` put on screen; cursor must be where it was at draw time.
pub fn erase(out: &mut Vec<u8>, d: &Drawn, cursor: (u16, u16)) {
    if d.is_empty() {
        return;
    }
    out.extend_from_slice(b"\x1b[?2026h");
    if d.ghost_len > 0 {
        out.extend_from_slice(b"\x1b[K");
    }
    if d.rows_below > 0 {
        out.extend_from_slice(format!("\n\r\x1b[J\x1b[1A\x1b[{}G", cursor.1 + 1).as_bytes());
    }
    out.extend_from_slice(b"\x1b[?2026l");
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::num::NonZeroU16;

    fn term(rows: u16, cols: u16) -> vt100::Parser {
        vt100::Parser::new(NonZeroU16::new(rows).unwrap(), NonZeroU16::new(cols).unwrap(), 0)
    }

    fn row(p: &vt100::Parser, r: u16) -> String {
        p.screen().contents_between(r, 0, r, p.screen().size().1.get())
    }

    fn items() -> Vec<String> {
        vec!["git status".into(), "git stash".into()]
    }

    #[test]
    fn draws_ghost_and_list_then_erases() {
        let mut p = term(10, 40);
        p.process(b"git s");
        let mut out = reserve(2);
        let d = draw(&mut out, Some("tatus"), &items(), Some(1), (0, 5), 40);
        p.process(&out);
        assert_eq!(row(&p, 0), "git status");
        assert_eq!(row(&p, 1), "git status");
        assert_eq!(row(&p, 2), "git stash");
        assert_eq!(p.screen().cursor_position(), (0, 5));
        assert!(p.screen().cell(2, 0).unwrap().inverse(), "selected row reversed");
        assert!(!p.screen().cell(1, 0).unwrap().inverse());

        let mut out = Vec::new();
        erase(&mut out, &d, (0, 5));
        p.process(&out);
        assert_eq!(row(&p, 0), "git s");
        assert_eq!(row(&p, 1), "");
        assert_eq!(row(&p, 2), "");
        assert_eq!(p.screen().cursor_position(), (0, 5));
    }

    #[test]
    fn bottom_row_scrolls_first() {
        let mut p = term(10, 40);
        p.process(b"\x1b[10;1Hgit s");
        let mut out = reserve(2);
        draw(&mut out, None, &items(), None, (7, 5), 40);
        p.process(&out);
        assert_eq!(row(&p, 7), "git s");
        assert_eq!(row(&p, 8), "git status");
        assert_eq!(row(&p, 9), "git stash");
        assert_eq!(p.screen().cursor_position(), (7, 5));
    }

    #[test]
    fn ghost_hidden_at_last_column() {
        let mut out = Vec::new();
        let d = draw(&mut out, Some("x"), &[], None, (0, 39), 40);
        assert_eq!(d.ghost_len, 0);
    }

    #[test]
    fn ghost_truncated_to_width() {
        let mut out = Vec::new();
        let d = draw(&mut out, Some("abcdefghij"), &[], None, (0, 35), 40);
        assert_eq!(d.ghost_len, 4);
    }

    #[test]
    fn long_items_truncated() {
        let mut p = term(5, 10);
        let mut out = reserve(1);
        draw(&mut out, None, &["0123456789abc".into()], None, (0, 0), 10);
        p.process(&out);
        assert_eq!(row(&p, 1), "012345678");
    }

    #[test]
    fn nothing_drawn_erases_nothing() {
        let mut out = Vec::new();
        erase(&mut out, &Drawn::default(), (0, 0));
        assert!(out.is_empty());
    }
}
