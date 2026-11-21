//! Fuzzy scorer: case-insensitive subsequence match, fzf-v1 style.
//! Works on bytes; ASCII is case-folded, other bytes must match exactly.

/// Score `cand` against `query`. None = no match. Higher = better.
pub fn score(query: &str, cand: &str) -> Option<i32> {
    let q = query.as_bytes();
    let c = cand.as_bytes();
    let penalty = (c.len() / 4) as i32;
    if q.is_empty() {
        return Some(-penalty);
    }
    // Forward pass: greedy, find where the match ends.
    let mut qi = 0;
    let mut end = 0;
    for (i, &b) in c.iter().enumerate() {
        if eq(b, q[qi]) {
            qi += 1;
            if qi == q.len() {
                end = i;
                break;
            }
        }
    }
    if qi < q.len() {
        return None;
    }
    // Backward pass from the end: tightest start.
    let mut qi = q.len();
    let mut start = 0;
    for i in (0..=end).rev() {
        if eq(c[i], q[qi - 1]) {
            qi -= 1;
            if qi == 0 {
                start = i;
                break;
            }
        }
    }
    // Score the window [start, end].
    let mut s = 0i32;
    let mut qi = 0;
    let mut prev_match = false;
    for i in start..=end {
        if qi < q.len() && eq(c[i], q[qi]) {
            s += 16;
            if i == 0 || matches!(c[i - 1], b' ' | b'/' | b'-' | b'_' | b'.') {
                s += 8;
            }
            if prev_match {
                s += 4;
            }
            prev_match = true;
            qi += 1;
        } else {
            s -= 1;
            prev_match = false;
        }
    }
    Some(s - penalty)
}

#[inline]
fn eq(a: u8, b: u8) -> bool {
    a.to_ascii_lowercase() == b.to_ascii_lowercase()
}

#[cfg(test)]
mod tests {
    use super::score;

    #[test]
    fn subsequence_matches() {
        assert!(score("gco", "git checkout").is_some());
        assert!(score("xyz", "git").is_none());
    }

    #[test]
    fn case_insensitive() {
        assert!(score("GIT", "git").is_some());
    }

    #[test]
    fn word_start_beats_middle() {
        assert!(score("gc", "git commit") > score("gc", "logcat"));
    }

    #[test]
    fn consecutive_beats_scattered() {
        assert!(score("com", "commit") > score("com", "cargo build -m"));
    }

    #[test]
    fn shorter_wins_tie() {
        assert!(score("ls", "ls") > score("ls", "lsblk"));
    }

    #[test]
    fn empty_query_matches() {
        assert!(score("", "anything").is_some());
    }
}
