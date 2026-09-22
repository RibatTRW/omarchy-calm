#!/usr/bin/env python3
"""Verify each shipped loop is seamless at its loop point.

Why this test is shaped the way it is:

The loops are built so the splice point is two *consecutive* samples of the
source recording (the source tail is crossfaded into the source head). So the
content either side of the loop point is literally an ordinary moment of the
original recording. That means a fixed dB tolerance is the wrong yardstick: a
campfire naturally jumps 10-20 dB between 100 ms windows, while steady rain
barely moves.

So the test is self-calibrating. It measures the level step across the loop
point and compares it against the distribution of level steps measured at
hundreds of ordinary interior positions of the SAME track. The loop point is
seamless when its step is no larger than the track's own natural variation
(95th percentile). A fixed-tolerance version of this test mis-flags `fire`
simply for being a crackling fire -- the boundary sits at its 86th percentile,
i.e. an unremarkable moment in that recording.

`--self-test` proves the check has teeth by injecting an artificial 16 dB step
at the loop point, which must then be rejected.
"""
import argparse
import glob
import math
import os
import random
import struct
import subprocess
import sys

WIN = int(0.1 * 48000)      # 100 ms comparison window
SAMPLES = 300               # interior positions used to calibrate
PCTL = 0.95


def pcm(path, sr=48000):
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-ar", str(sr),
         "-f", "s16le", "-"], capture_output=True, check=True).stdout
    n = len(raw) // 2
    return list(struct.unpack("<%dh" % n, raw[: n * 2])), sr


def rms(x, i, n=WIN):
    seg = x[i:i + n]
    if not seg:
        return 0.0
    return math.sqrt(sum(s * s for s in seg) / len(seg))


def step_db(x, i):
    pre, post = rms(x, i - WIN), rms(x, i)
    if pre <= 0:
        return None
    return 20 * math.log10(max(post, 1e-9) / max(pre, 1e-9))


def check(path, seed=7):
    x, sr = pcm(path)
    L = len(x)
    # Loop point: the last WIN samples of the file run into the first WIN.
    # (Cannot use step_db(x, L) -- index L is one past the end.)
    pre, post = rms(x, L - WIN), rms(x, 0)
    boundary = abs(20 * math.log10(max(post, 1e-9) / max(pre, 1e-9))) if pre > 0 else float("inf")

    rng = random.Random(seed)
    natural = []
    while len(natural) < SAMPLES:
        i = rng.randint(2 * WIN, L - 3 * WIN)
        d = step_db(x, i)
        if d is not None:
            natural.append(abs(d))
    natural.sort()
    threshold = natural[int(PCTL * (len(natural) - 1))]
    pctile = sum(1 for d in natural if d < boundary) / len(natural)

    return {
        "file": os.path.basename(path),
        "len_s": round(L / sr, 1),
        "boundary_db": round(boundary, 2),
        "natural_p95_db": round(threshold, 2),
        "pctile": round(pctile * 100, 1),
        "pass": boundary <= threshold,
    }


def inject_step(src, dst, step_db=-16.0, secs=0.5):
    g = 10 ** (step_db / 20)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", src,
                    "-af", f"volume=enable='lt(t,{secs})':volume={g}",
                    "-c:a", "libvorbis", "-q:a", "2", dst], check=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dir")
    ap.add_argument("--self-test", action="store_true")
    a = ap.parse_args()

    rows = [check(p) for p in sorted(glob.glob(a.dir + "/*.ogg"))]
    if not rows:
        print("no loops found in", a.dir)
        return 1

    print(f"{'loop':14s} {'len':>5s} {'loop-point step':>16s} "
          f"{'natural p95':>12s} {'percentile':>10s}  verdict")
    ok = True
    for r in rows:
        ok &= r["pass"]
        print(f"{r['file']:14s} {r['len_s']:>5} {r['boundary_db']:>13.2f}dB "
              f"{r['natural_p95_db']:>9.2f}dB {r['pctile']:>9.1f}%  "
              f"{'SEAMLESS' if r['pass'] else 'NOT SEAMLESS'}")

    if a.self_test:
        os.makedirs("control", exist_ok=True)
        inject_step(rows[0]["file"] if os.path.isabs(rows[0]["file"])
                    else os.path.join(a.dir, rows[0]["file"]),
                    "control/broken.ogg")
        c = check("control/broken.ogg")
        print(f"\nself-test (artificial 16 dB step at the loop point): "
              f"{'rejected' if not c['pass'] else 'MISSED - check is toothless'}")
        ok = ok and not c["pass"]

    print("\nALL LOOPS SEAMLESS" if ok else "\nFAILURES PRESENT")
    return 0 if ok else 1


sys.exit(main())
