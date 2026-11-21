#!/usr/bin/env python3
"""Fit the `mimic` mouse-dance model to a cursor recording (record.py output).
Usage: fit.py REC.tsv [MODEL.json]   (needs numpy + scipy:
  nix-shell -p "python3.withPackages(p:[p.numpy p.scipy])" --run "python3 fit.py rec1.tsv")

Model (run by danceMimic* in ~/.config/quickshell/bar/Fx.qml): the cursor, as a complex number
x + iy, is a sum of rotating circles (epicycles). Their sizes come from the recording's two-sided
spectrum, so the turning speed, loop sizes, clockwise/anticlockwise mix and even the human
"2/3 power law" between speed and curvature come out the same, but the path is new every time:
- `bands`: [frequency Hz (sign = turning direction), radius px]; each band is played by `per`
  circles at random frequencies inside the band (+-`bandw`/2 in log), random start phases, and a
  slow phase random walk (`jit` * sqrt|f| rad per sqrt s) so nothing ever repeats.
- `A`: 2x2 map applied to the sum so the area has the recorded width/height and tilt.
- time warp: the circles run on a clock that goes exp(e) times real time, e an Ornstein-Uhlenbeck
  drift (sd `eSd`, time constant `eTau` s), for the recorded bursts of fast and slow.
- `cx`, `cy`: area centre offset from the screen centre (fraction of width/height); px values
  are for a screen `refH` px high and scale with the screen.
Then it simulates the model and prints recording vs model stats side by side."""
import json, sys
import numpy as np
from scipy.ndimage import gaussian_filter1d
from scipy.signal import welch

FS = 60.0
SW, SH = 1920.0, 1080.0   # screen the recording was made on
SX, SY = 0.0, 540.0       # its top-left in layout pixels (eDP-1)

def stats(x, y):
    xs = gaussian_filter1d(x, 2); ys = gaussian_filter1d(y, 2)
    vx = np.gradient(xs, 1 / FS); vy = np.gradient(ys, 1 / FS)
    ax = np.gradient(vx, 1 / FS); ay = np.gradient(vy, 1 / FS)
    sp = np.hypot(vx, vy)
    k = (vx * ay - vy * ax) / np.maximum(sp, 1e-6) ** 3
    m = (sp > 150) & (np.abs(k) > 1e-5)
    law = np.polyfit(np.log(np.abs(k[m])), np.log(sp[m]), 1)
    s = np.sign(k); ch = np.flatnonzero(np.diff(s) != 0) + 1
    runs = {1: [], -1: []}
    for a, b in zip(ch[:-1], ch[1:]):
        if s[a] == 0 or np.median(sp[a:b]) < 150: continue
        runs[int(s[a])].append((b - a) / FS)
    return dict(xs=xs, ys=ys, sp=sp, k=k, m=m, law=law, runs=runs)

def acorr(z, lag):
    z = z - z.mean(); return (z[:-lag] * z[lag:]).mean() / z.var()

def fit(x, y):
    z = (x - x.mean()) + 1j * (y - y.mean())
    f, P = welch(z, fs=FS, nperseg=2048, return_onesided=False, detrend="constant")
    df = f[1] - f[0]
    edges = np.geomspace(0.03, 25, 41)
    bands = []
    for sg in (1, -1):
        for a, b in zip(edges[:-1], edges[1:]):
            m = (sg * f >= a) & (sg * f < b)
            if m.any():
                bands.append([round(float(sg * np.sqrt(a * b)), 4), round(float(np.sqrt(P[m].sum() * df)), 3)])
    # speed bursts: log speed, minus its mean, as an OU process
    sp = np.hypot(np.gradient(gaussian_filter1d(x, 2), 1 / FS), np.gradient(gaussian_filter1d(y, 2), 1 / FS))
    ls = np.log(np.maximum(sp, 50)); ls -= ls.mean()
    lags = np.arange(1, 900)
    ac = np.array([acorr(ls, l) for l in lags])
    tau = lags[np.argmax(ac < np.exp(-1))] / FS
    return {"bands": bands, "per": 3, "bandw": round(float(np.log(edges[1] / edges[0])), 4), "jit": 0.05,
            "eSd": 0.3, "eTau": round(float(tau), 3), "A": [[1, 0], [0, 1]],
            "cx": round(float((x.mean() - SX) / SW - 0.5), 4), "cy": round(float((y.mean() - SY) / SH - 0.5), 4),
            "refH": SH}

# The same generator as Fx.qml danceMimic*, in Python, to check the fit.
def simulate(M, secs, seed=1):
    rng = np.random.default_rng(seed)
    n = int(secs * FS); dt = 1 / FS
    e = np.zeros(n)
    for i in range(1, n):
        e[i] = e[i - 1] - e[i - 1] * dt / M["eTau"] + M["eSd"] * np.sqrt(2 * dt / M["eTau"]) * rng.normal()
    clock = np.cumsum(np.exp(e - M["eSd"] ** 2 / 2)) * dt
    Z = np.zeros(n, complex)
    for fc, amp in M["bands"]:
        for _ in range(M["per"]):
            fr = fc * np.exp(rng.uniform(-0.5, 0.5) * M["bandw"])
            ph = rng.uniform(0, 2 * np.pi) + np.cumsum(rng.normal(0, M["jit"] * np.sqrt(abs(fr) * dt), n))
            Z += amp / np.sqrt(M["per"]) * np.exp(1j * (2 * np.pi * fr * clock + ph))
    A = np.array(M["A"])
    X = A[0, 0] * Z.real + A[0, 1] * Z.imag
    Y = A[1, 0] * Z.real + A[1, 1] * Z.imag
    return X + SW * (0.5 + M["cx"]) + SX, Y + SH * (0.5 + M["cy"]) + SY

def sqrtm(C):
    w, V = np.linalg.eigh(C); return V @ np.diag(np.sqrt(w)) @ V.T

def calibrate(M, x, y):
    # shape: map the model's area covariance onto the recorded one
    X, Y = simulate(M, 600, seed=7)
    Cm = np.cov(np.vstack([X, Y])); Cr = np.cov(np.vstack([x, y]))
    M["A"] = np.round(sqrtm(Cr) @ np.linalg.inv(sqrtm(Cm)), 4).tolist()
    # bursts: pick the drift size whose 1 s speed autocorrelation matches the recording
    S = stats(x, y); want = acorr(np.log(np.maximum(S["sp"], 1)), 60)
    best = None
    for sd in (0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8):
        M["eSd"] = sd
        G = stats(*simulate(M, 300, seed=3))
        err = abs(acorr(np.log(np.maximum(G["sp"], 1)), 60) - want)
        if best is None or err < best[0]: best = (err, sd)
    M["eSd"] = best[1]
    return M

if __name__ == "__main__":
    d = np.loadtxt(sys.argv[1]); t, x, y = d.T
    ti = np.arange(0, t[-1], 1 / FS); x = np.interp(ti, t, x); y = np.interp(ti, t, y)
    M = calibrate(fit(x, y), x, y)
    out = sys.argv[2] if len(sys.argv) > 2 else "model.json"
    json.dump(M, open(out, "w"))
    print(f"wrote {out}: {len(M['bands'])} bands, A={M['A']}, eSd={M['eSd']}, eTau={M['eTau']}")
    S = stats(x, y); G = stats(*simulate(M, 180))
    def row(name, a, b): print(f"{name:26s} rec {a!s:36s} model {b!s}")
    pc = lambda z, q: np.percentile(z, q).round(0).tolist()
    row("speed px/s p25/50/75/90", pc(S["sp"], [25, 50, 75, 90]), pc(G["sp"], [25, 50, 75, 90]))
    row("loop radius px p25/50/75", pc(1 / np.abs(S["k"][S["m"]]), [25, 50, 75]), pc(1 / np.abs(G["k"][G["m"]]), [25, 50, 75]))
    row("power law slope", round(S["law"][0], 3), round(G["law"][0], 3))
    for sg in (1, -1):
        row(f"turn run s median ({sg:+d})", round(float(np.median(S["runs"][sg])), 3), round(float(np.median(G["runs"][sg])), 3))
    row("x/y spread px", (round(S["xs"].std()), round(S["ys"].std())), (round(G["xs"].std()), round(G["ys"].std())))
    row("speed autocorr 1 s", round(acorr(np.log(np.maximum(S["sp"], 1)), 60), 2), round(acorr(np.log(np.maximum(G["sp"], 1)), 60), 2))
    row("anticlockwise share", round(float((S["k"][S["m"]] > 0).mean()), 2), round(float((G["k"][G["m"]] > 0).mean()), 2))
