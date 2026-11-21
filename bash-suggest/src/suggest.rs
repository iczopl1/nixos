//! Rank suggestions for the typed line from all sources.

use crate::fuzzy::score;
use crate::sources::{char_mask, list_dir, subcommands, History};
use std::path::Path;

pub struct Ctx<'a> {
    pub history: &'a History,
    /// PATH executables + aliases + functions, deduped.
    pub commands: &'a [String],
    pub cwd: &'a Path,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Suggestion {
    /// The full new line if accepted.
    pub text: String,
    /// Missing suffix when `text` starts with the typed line (shown as gray ghost).
    pub ghost: Option<String>,
}

/// Max directory entries read per keystroke.
const MAX_DIR: usize = 500;
/// Prefix matches always rank above fuzzy-only ones.
const PREFIX_BONUS: i32 = 10_000;

struct Cand {
    text: String,
    prefix: bool,
    /// 0 = history line, 1 = word completion.
    group: u8,
    rank: i32,
}

pub fn suggest(line: &str, ctx: &Ctx, max: usize) -> Vec<Suggestion> {
    if line.trim().is_empty() || max == 0 {
        return Vec::new();
    }
    let mut cands: Vec<Cand> = Vec::new();

    // Whole history lines. Prefix matches rank first and the list holds `max`,
    // so when enough of them exist, fuzzy scoring and word completion are skipped.
    let h = ctx.history;
    let newest = h.newest();
    let bonus = |e: &crate::sources::Entry| {
        let recent = if newest - e.last < 100 { 5 } else { 0 };
        recent + (2.0 * (e.count as f32).ln()) as i32
    };
    // (rank, entry index); no allocation per match.
    let mut hits: Vec<(i32, u32)> = Vec::new();
    for (i, e) in h.entries.iter().enumerate() {
        if e.text.len() > line.len() && e.text.starts_with(line) {
            let len_pen = (e.text.len() / 4) as i32;
            hits.push((PREFIX_BONUS + 40 + bonus(e) - len_pen, i as u32));
        }
    }
    let enough_prefix = hits.len() >= max;
    if !enough_prefix {
        let qmask = char_mask(line);
        for (i, e) in h.entries.iter().enumerate() {
            if e.mask & qmask != qmask || e.text.starts_with(line) {
                continue; // prefix ones (and the exact line) handled above
            }
            if let Some(s) = score(line, &e.text) {
                hits.push((s + bonus(e), i as u32));
            }
        }
    }
    top_k(&mut hits, max);
    for &(rank, i) in &hits {
        let text = h.entries[i as usize].text.to_string();
        cands.push(Cand { prefix: rank >= PREFIX_BONUS, text, group: 0, rank });
    }
    if enough_prefix {
        return finish(cands, line, max);
    }

    // Completions for the word under the cursor (cursor is at end of line).
    let ws = line.rfind(char::is_whitespace).map_or(0, |i| i + 1);
    let (before, word) = line.split_at(ws);
    let n_before = before.split_whitespace().count();
    let mut words: Vec<String> = Vec::new();
    if n_before == 0 {
        let wmask = char_mask(word);
        words.extend(ctx.commands.iter().filter(|c| char_mask(c) & wmask == wmask).cloned());
    } else {
        if n_before == 1 {
            words.extend(subcommands(h, before.split_whitespace().next().unwrap_or("")));
        }
        words.extend(list_dir(ctx.cwd, word, MAX_DIR));
    }
    for w in words {
        if w == word {
            continue;
        }
        let Some(s) = score(word, &w) else { continue };
        let prefix = w.starts_with(word);
        cands.push(Cand {
            text: format!("{before}{w}"),
            prefix,
            group: 1,
            rank: s + if prefix { PREFIX_BONUS } else { 0 },
        });
    }
    finish(cands, line, max)
}

/// Keep the `k` highest-ranked hits (unordered).
fn top_k(hits: &mut Vec<(i32, u32)>, k: usize) {
    if hits.len() > k && k > 0 {
        hits.select_nth_unstable_by(k - 1, |a, b| b.0.cmp(&a.0));
        hits.truncate(k);
    }
}

fn finish(mut cands: Vec<Cand>, line: &str, max: usize) -> Vec<Suggestion> {
    cands.sort_unstable_by(|a, b| {
        b.prefix
            .cmp(&a.prefix)
            .then(a.group.cmp(&b.group))
            .then(b.rank.cmp(&a.rank))
            .then(a.text.cmp(&b.text))
    });
    let mut out: Vec<Suggestion> = Vec::with_capacity(max);
    for c in cands {
        if out.len() == max {
            break;
        }
        if out.iter().any(|s| s.text == c.text) {
            continue;
        }
        let ghost = c.text.strip_prefix(line).filter(|g| !g.is_empty()).map(str::to_owned);
        out.push(Suggestion { text: c.text, ghost });
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::sources::testutil::tempdir;

    fn ctx_with(lines: &[&str], commands: &[&str], f: impl FnOnce(&Ctx)) {
        let d = tempdir();
        let p = d.join("hist");
        std::fs::write(&p, lines.join("\n") + "\n").unwrap();
        let h = History::load(&p);
        let cmds: Vec<String> = commands.iter().map(|s| s.to_string()).collect();
        let ctx = Ctx { history: &h, commands: &cmds, cwd: &d };
        f(&ctx);
    }

    #[test]
    fn prefix_history_first_with_ghost() {
        ctx_with(&["ls", "git status", "git push", "git status"], &[], |c| {
            let s = suggest("git s", c, 8);
            assert_eq!(s[0].text, "git status");
            assert_eq!(s[0].ghost.as_deref(), Some("tatus"));
        });
    }

    #[test]
    fn fuzzy_match_has_no_ghost() {
        ctx_with(&["git status"], &[], |c| {
            let s = suggest("gst", c, 8);
            let hit = s.iter().find(|x| x.text == "git status").unwrap();
            assert_eq!(hit.ghost, None);
        });
    }

    #[test]
    fn first_word_from_commands() {
        ctx_with(&[], &["cargo"], |c| {
            assert_eq!(suggest("carg", c, 8)[0].text, "cargo");
        });
    }

    #[test]
    fn later_word_from_files() {
        ctx_with(&[], &[], |c| {
            std::fs::create_dir(c.cwd.join("src")).unwrap();
            let s = suggest("cd sr", c, 8);
            assert!(s.iter().any(|x| x.text == "cd src/"));
        });
    }

    #[test]
    fn second_word_from_subcommands() {
        ctx_with(&["git commit -m x", "ls"], &[], |c| {
            let s = suggest("git co", c, 8);
            assert!(s.iter().any(|x| x.text == "git commit"));
        });
    }

    #[test]
    fn empty_line_gives_nothing() {
        ctx_with(&["ls"], &["ls"], |c| {
            assert!(suggest("", c, 8).is_empty());
            assert!(suggest("   ", c, 8).is_empty());
        });
    }

    #[test]
    fn capped_and_unique() {
        let lines: Vec<String> = (0..50).map(|i| format!("echo {i}")).collect();
        let refs: Vec<&str> = lines.iter().map(|s| s.as_str()).collect();
        ctx_with(&refs, &["echo"], |c| {
            let s = suggest("ec", c, 8);
            assert!(s.len() <= 8);
            let mut t: Vec<_> = s.iter().map(|x| &x.text).collect();
            t.sort();
            t.dedup();
            assert_eq!(t.len(), s.len());
        });
    }

    #[test]
    fn exact_line_is_not_suggested() {
        ctx_with(&["ls"], &["ls"], |c| {
            assert!(suggest("ls", c, 8).iter().all(|x| x.text != "ls"));
        });
    }
}

#[cfg(test)]
mod bench {
    use super::*;
    use crate::sources::testutil::tempdir;

    /// cargo test --release bench_50k -- --ignored --nocapture
    #[test]
    #[ignore]
    fn bench_50k() {
        let d = tempdir();
        let p = d.join("hist");
        let words = ["git", "cargo", "nix", "ls", "cd", "systemctl", "journalctl", "rg", "fd", "vim"];
        let lines: Vec<String> = (0..50_000)
            .map(|i| format!("{} sub{} --flag{} path/to/file{}.txt", words[i % 10], i % 37, i % 101, i))
            .collect();
        std::fs::write(&p, lines.join("\n") + "\n").unwrap();
        let h = History::load(&p);
        let cmds: Vec<String> = (0..3000).map(|i| format!("cmd{i}")).collect();
        let ctx = Ctx { history: &h, commands: &cmds, cwd: &d };
        for max in [8, 60] {
            for q in ["g", "git s", "cargo sub1", "xyz", "sysctl jou"] {
                let t = std::time::Instant::now();
                let n = 20;
                for _ in 0..n {
                    std::hint::black_box(suggest(q, &ctx, max));
                }
                println!("max {max:>2} {q:>12}: {:?}/call", t.elapsed() / n);
            }
        }
    }
}
