//! Box post-processing: clipping, table-row merging, duplicate removal.
use crate::atspi::{Rect, MIN_SIZE};
use std::collections::{HashMap, HashSet};

pub const MAX_RECTS: usize = 400;
const MAX_ROW_H: i32 = 64;

pub fn clip(r: Rect, (cx, cy, cw, ch): Rect) -> Option<Rect> {
    let (x2, y2) = (r.0.saturating_add(r.2).min(cx.saturating_add(cw)), r.1.saturating_add(r.3).min(cy.saturating_add(ch)));
    let (x, y) = (r.0.max(cx), r.1.max(cy));
    (x2 - x >= MIN_SIZE && y2 - y >= MIN_SIZE).then_some((x, y, x2 - x, y2 - y))
}

/// Table cells side by side in one row all do the same thing, so a row gets one box.
pub fn merge_rows(mut cells: Vec<Rect>) -> Vec<Rect> {
    cells.sort_by_key(|c| (c.1, c.3));
    let mut lines: Vec<Vec<Rect>> = vec![];
    for c in cells {
        match lines.last_mut() {
            Some(l) if (l[0].1 - c.1).abs() <= 2 && (l[0].3 - c.3).abs() <= 2 => l.push(c),
            _ => lines.push(vec![c]),
        }
    }
    let mut rows: Vec<Rect> = vec![];
    for mut line in lines {
        line.sort();
        let mut cur: Option<usize> = None;
        for (x, y, w, h) in line {
            match cur {
                Some(i) if x <= rows[i].0 + rows[i].2 + 8 => {
                    rows[i].2 = (rows[i].0 + rows[i].2).max(x + w) - rows[i].0;
                }
                _ => {
                    rows.push((x, y, w, h));
                    cur = Some(rows.len() - 1);
                }
            }
        }
    }
    let before = rows.len();
    rows.retain(|r| r.3 <= MAX_ROW_H);
    if rows.len() != before {
        eprintln!("hintd: {} table rows taller than {MAX_ROW_H}px left out", before - rows.len());
    }
    rows
}

/// Drop exact duplicates and the bigger of two boxes covering the same thing.
pub fn dedupe(rects: Vec<Rect>) -> Vec<Rect> {
    let mut seen = HashSet::new();
    let mut rects: Vec<Rect> = rects.into_iter().filter(|r| seen.insert(*r)).collect();
    rects.sort_by_key(|r| r.2 as i64 * r.3 as i64); // stable: ties keep input order
    const C: i32 = 64;
    let mut keep: Vec<Rect> = vec![];
    let mut grid: HashMap<(i32, i32), Vec<usize>> = HashMap::new();
    for r in rects {
        let cells: Vec<(i32, i32)> = (r.0.div_euclid(C)..=(r.0 + r.2).div_euclid(C))
            .flat_map(|i| (r.1.div_euclid(C)..=(r.1 + r.3).div_euclid(C)).map(move |j| (i, j)))
            .collect();
        let redundant = cells.iter().any(|c| {
            grid.get(c).is_some_and(|ks| {
                ks.iter().any(|&k| {
                    let k = keep[k];
                    let ix = (r.0 + r.2).min(k.0 + k.2) - r.0.max(k.0);
                    let iy = (r.1 + r.3).min(k.1 + k.3) - r.1.max(k.1);
                    ix > 0 && iy > 0 && (ix as i64 * iy as i64) * 10 >= 8 * (k.2 as i64 * k.3 as i64)
                        && r.2 as i64 * r.3 as i64 <= 4 * (k.2 as i64 * k.3 as i64)
                })
            })
        });
        if !redundant {
            keep.push(r);
            for c in cells {
                grid.entry(c).or_default().push(keep.len() - 1);
            }
        }
    }
    keep
}
