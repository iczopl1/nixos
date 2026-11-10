//! The picture analysis must give the same boxes as the first (single-thread, row-allocating) version.
//! `ref_*` below are that version, unchanged. Real-screen check: HINTD_TEST_PPM=<file.ppm> cargo test --release -- --nocapture --ignored
use super::*;

/// Sobel (|gx| + |gy|) then hysteresis: weak edges count only when they touch a strong one.
fn ref_canny(g: &[u8], w: usize, h: usize, lo: i32, hi: i32) -> Vec<u8> {
    let mut mag = vec![0i16; w * h];
    for y in 1..h.saturating_sub(1) {
        for x in 1..w.saturating_sub(1) {
            let p = |dx: usize, dy: usize| g[(y + dy - 1) * w + x + dx - 1] as i32;
            let gx = (p(2, 0) + 2 * p(2, 1) + p(2, 2)) - (p(0, 0) + 2 * p(0, 1) + p(0, 2));
            let gy = (p(0, 2) + 2 * p(1, 2) + p(2, 2)) - (p(0, 0) + 2 * p(1, 0) + p(2, 0));
            mag[y * w + x] = (gx.abs() + gy.abs()).min(i16::MAX as i32) as i16;
        }
    }
    let mut out = vec![0u8; w * h];
    let mut stack: Vec<usize> = (0..w * h).filter(|&i| mag[i] as i32 > hi).collect();
    for &i in &stack {
        out[i] = 255;
    }
    while let Some(i) = stack.pop() {
        let (x, y) = (i % w, i / w);
        for ny in y.saturating_sub(1)..=(y + 1).min(h - 1) {
            for nx in x.saturating_sub(1)..=(x + 1).min(w - 1) {
                let j = ny * w + nx;
                if out[j] == 0 && mag[j] as i32 > lo {
                    out[j] = 255;
                    stack.push(j);
                }
            }
        }
    }
    out
}

/// Rectangular dilation, anchor in the middle like OpenCV; horizontal then vertical pass.
fn ref_dilate(e: &[u8], w: usize, h: usize, kw: usize, kh: usize) -> Vec<u8> {
    let (ax, ay) = (kw / 2, kh / 2);
    let mut tmp = vec![0u8; w * h];
    for y in 0..h {
        let row = &e[y * w..(y + 1) * w];
        let mut pre = vec![0u32; w + 1];
        for x in 0..w {
            pre[x + 1] = pre[x] + (row[x] != 0) as u32;
        }
        for x in 0..w {
            let (a, b) = (x.saturating_sub(kw - 1 - ax), (x + ax + 1).min(w));
            if pre[b] > pre[a] {
                tmp[y * w + x] = 255;
            }
        }
    }
    let mut out = vec![0u8; w * h];
    for x in 0..w {
        let mut pre = vec![0u32; h + 1];
        for y in 0..h {
            pre[y + 1] = pre[y] + (tmp[y * w + x] != 0) as u32;
        }
        for y in 0..h {
            let (a, b) = (y.saturating_sub(kh - 1 - ay), (y + ay + 1).min(h));
            if pre[b] > pre[a] {
                out[y * w + x] = 255;
            }
        }
    }
    out
}



/// Bounding box of every 8-connected blob.
fn ref_components(e: &[u8], w: usize, h: usize) -> Vec<Rect> {
    let mut seen = vec![false; w * h];
    let mut out = vec![];
    let mut stack = vec![];
    for s in 0..w * h {
        if e[s] == 0 || seen[s] {
            continue;
        }
        seen[s] = true;
        stack.push(s);
        let (mut x0, mut y0, mut x1, mut y1) = (w, h, 0, 0);
        while let Some(i) = stack.pop() {
            let (x, y) = (i % w, i / w);
            x0 = x0.min(x);
            x1 = x1.max(x);
            y0 = y0.min(y);
            y1 = y1.max(y);
            for ny in y.saturating_sub(1)..=(y + 1).min(h - 1) {
                for nx in x.saturating_sub(1)..=(x + 1).min(w - 1) {
                    let j = ny * w + nx;
                    if e[j] != 0 && !seen[j] {
                        seen[j] = true;
                        stack.push(j);
                    }
                }
            }
        }
        out.push((x0 as i32, y0 as i32, (x1 - x0 + 1) as i32, (y1 - y0 + 1) as i32));
    }
    out
}

fn lcg(seed: &mut u64) -> u32 {
    *seed = seed.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
    (*seed >> 33) as u32
}

/// Text-like test picture: flat background, random filled boxes of random gray, a little noise.
fn picture(w: usize, h: usize, seed: u64) -> Vec<u8> {
    let mut s = seed;
    let mut g = vec![(lcg(&mut s) % 256) as u8; w * h];
    for _ in 0..(w * h / 400).max(2) {
        let (bw, bh) = (1 + lcg(&mut s) as usize % 40, 1 + lcg(&mut s) as usize % 12);
        let (bx, by) = (lcg(&mut s) as usize % w, lcg(&mut s) as usize % h);
        let v = (lcg(&mut s) % 256) as u8;
        for y in by..(by + bh).min(h) {
            for x in bx..(bx + bw).min(w) {
                g[y * w + x] = v;
            }
        }
    }
    for p in g.iter_mut() {
        if lcg(&mut s) % 16 == 0 {
            *p = p.wrapping_add((lcg(&mut s) % 90) as u8);
        }
    }
    g
}

const SIZES: [(usize, usize); 12] = [(1, 1), (2, 2), (3, 3), (3, 9), (9, 3), (5, 4), (13, 7), (64, 48), (65, 49), (333, 211), (700, 500), (1001, 17)];

#[test]
fn canny_same_as_reference() {
    for (i, &(w, h)) in SIZES.iter().enumerate() {
        let g = picture(w, h, i as u64 + 1);
        for (lo, hi) in [(70, 220), (10, 50), (0, 0), (300, 600)] {
            assert_eq!(canny(&g, w, h, lo, hi), ref_canny(&g, w, h, lo, hi), "canny {w}x{h} lo {lo} hi {hi}");
        }
    }
}

#[test]
fn dilate_same_as_reference() {
    for (i, &(w, h)) in SIZES.iter().enumerate() {
        let g = picture(w, h, 100 + i as u64);
        let e = ref_canny(&g, w, h, 40, 120);
        for (kw, kh) in [(8, 6), (1, 1), (2, 2), (3, 2), (7, 5), (20, 9)] {
            assert_eq!(dilate(&e, w, h, kw, kh), ref_dilate(&e, w, h, kw, kh), "dilate {w}x{h} k {kw}x{kh}");
        }
    }
}

#[test]
fn analyse_same_as_reference() {
    for (i, &(w, h)) in SIZES.iter().enumerate() {
        let g = picture(w, h, 200 + i as u64);
        let want = ref_components(&ref_dilate(&ref_canny(&g, w, h, 70, 220), w, h, 8, 6), w, h);
        assert_eq!(analyse(&g, w, h, 70, 220, 8, 6), want, "analyse {w}x{h}");
    }
}

#[test]
fn white_picture_has_no_boxes() {
    assert!(analyse(&vec![255; 200 * 100], 200, 100, 70, 220, 8, 6).is_empty());
}

fn best_of<T>(n: usize, mut f: impl FnMut() -> T) -> (std::time::Duration, T) {
    let mut best = std::time::Duration::MAX;
    let mut last = None;
    for _ in 0..n {
        let t = std::time::Instant::now();
        let r = f();
        best = best.min(t.elapsed());
        last = Some(r);
    }
    (best, last.unwrap())
}

/// Parity and speed on a real screenshot: HINTD_TEST_PPM=<ppm>.
#[test]
#[ignore]
fn real_screen() {
    let path = std::env::var("HINTD_TEST_PPM").expect("HINTD_TEST_PPM");
    let (w, h, g) = gray_from_ppm(&std::fs::read(path).unwrap()).unwrap();
    let (t_old, old) = best_of(5, || ref_components(&ref_dilate(&ref_canny(&g, w, h, 70, 220), w, h, 8, 6), w, h));
    let (t_new, new) = best_of(5, || analyse(&g, w, h, 70, 220, 8, 6));
    let e = canny(&g, w, h, 70, 220);
    let d = dilate(&e, w, h, 8, 6);
    let (t_canny, _) = best_of(5, || canny(&g, w, h, 70, 220));
    let (t_dil, _) = best_of(5, || dilate(&e, w, h, 8, 6));
    let (t_comp, _) = best_of(5, || components(&d, w, h));
    let (t_old_canny, _) = best_of(5, || ref_canny(&g, w, h, 70, 220));
    let (t_old_dil, _) = best_of(5, || ref_dilate(&e, w, h, 8, 6));
    eprintln!("{w}x{h}: boxes old {} new {}", old.len(), new.len());
    eprintln!("old total {t_old:?} (canny {t_old_canny:?}, dilate {t_old_dil:?})");
    eprintln!("new total {t_new:?} (canny {t_canny:?}, dilate {t_dil:?}, components {t_comp:?})");
    assert_eq!(old, new);
}

/// Blob finder alone, on random 0/255 images of several densities (including touching diagonals).
#[test]
fn components_same_as_reference() {
    for (i, &(w, h)) in SIZES.iter().enumerate() {
        for density in [2u32, 4, 8, 30, 90] {
            let mut s = 300 + i as u64 * 7 + density as u64;
            let e: Vec<u8> = (0..w * h).map(|_| if lcg(&mut s) % 100 < density { 255 } else { 0 }).collect();
            assert_eq!(components(&e, w, h), ref_components(&e, w, h), "components {w}x{h} density {density}%");
        }
    }
}
