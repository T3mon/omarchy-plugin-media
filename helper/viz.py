#!/usr/bin/env python3
"""Audio levels for the media visualizer.

Records what's going to the default output (its monitor, via pw-record) and
prints one line per frame: N integers 0..100, bass on the left, treble on
the right. Standard library only.

    viz.py [--bars 24] [--fps 30]

Exits when stdout closes, when pw-record ends, or when the parent dies.
"""
import argparse
import cmath
import ctypes
import math
import os
import signal
import subprocess
import sys

RATE = 16000
FFT_SIZE = 512
F_MIN, F_MAX = 50.0, 7000.0
PR_SET_PDEATHSIG = 1


def die_with_parent():
    try:
        ctypes.CDLL(None).prctl(PR_SET_PDEATHSIG, signal.SIGTERM, 0, 0, 0)
    except Exception:
        pass


def make_fft(n):
    levels = n.bit_length() - 1
    rev = [int(format(i, "0%db" % levels)[::-1], 2) for i in range(n)]
    tw = [cmath.exp(-2j * math.pi * k / n) for k in range(n // 2)]

    def fft(x):
        a = [x[r] for r in rev]
        size = 2
        while size <= n:
            half, step = size // 2, n // size
            for start in range(0, n, size):
                k = 0
                for i in range(start, start + half):
                    t = a[i + half] * tw[k]
                    a[i + half] = a[i] - t
                    a[i] += t
                    k += step
            size *= 2
        return a

    return fft


def band_edges(bars):
    # Log-spaced bands, each at least one FFT bin wide.
    hz_per_bin = RATE / FFT_SIZE
    edges, last = [], 1
    for b in range(bars + 1):
        f = F_MIN * (F_MAX / F_MIN) ** (b / bars)
        i = max(last, int(round(f / hz_per_bin)))
        edges.append(i)
        last = i + 1 if b < bars else i
    return [(edges[b], max(edges[b] + 1, edges[b + 1])) for b in range(bars)]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bars", type=int, default=24)
    ap.add_argument("--fps", type=int, default=30)
    args = ap.parse_args()
    bars = max(4, min(64, args.bars))
    hop = max(1, RATE // max(5, min(60, args.fps)))

    die_with_parent()
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)

    rec = subprocess.Popen(
        ["pw-record", "--rate", str(RATE), "--channels", "1", "--format", "s16",
         "--latency", "20ms",
         "-P", "{ stream.capture.sink = true, media.name = \"Media visualizer\", "
               "application.name = \"Media visualizer\" }",
         "-"],
        stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        preexec_fn=die_with_parent)

    fft = make_fft(FFT_SIZE)
    window = [0.5 - 0.5 * math.cos(2 * math.pi * i / (FFT_SIZE - 1)) for i in range(FFT_SIZE)]
    bands = band_edges(bars)
    samples = [0.0] * FFT_SIZE
    shown = [0.0] * bars
    peak = 1e-3  # slowly adapting loudness reference (auto gain)
    fd = rec.stdout.fileno()
    pending = b""

    try:
        while True:
            need = hop * 2 - len(pending)
            chunk = os.read(fd, need) if need > 0 else b""
            if not chunk and need > 0:
                break
            pending += chunk
            if len(pending) < hop * 2:
                continue
            frame, pending = pending[:hop * 2], pending[hop * 2:]
            new = [int.from_bytes(frame[i:i + 2], "little", signed=True) / 32768.0
                   for i in range(0, len(frame), 2)]
            samples = samples[len(new):] + new

            spec = fft([s * w for s, w in zip(samples, window)])
            mags = []
            for lo, hi in bands:
                m = max(abs(spec[i]) for i in range(lo, hi))
                # Treble is naturally quieter; tilt it up a little.
                mags.append(m * (1.0 + 2.0 * lo / (FFT_SIZE / 2)))

            loudest = max(mags)
            peak = max(loudest, peak * 0.995, 1e-3)
            out = []
            for b, m in enumerate(mags):
                v = m / peak if loudest > 1e-3 else 0.0
                v = math.sqrt(max(0.0, min(1.0, v)))
                # Rise fast, fall slowly.
                shown[b] = v if v > shown[b] else shown[b] * 0.82 + v * 0.18
                out.append(int(round(shown[b] * 100)))
            sys.stdout.write(" ".join(map(str, out)) + "\n")
            sys.stdout.flush()
    except (BrokenPipeError, KeyboardInterrupt):
        pass
    finally:
        rec.terminate()


if __name__ == "__main__":
    main()
