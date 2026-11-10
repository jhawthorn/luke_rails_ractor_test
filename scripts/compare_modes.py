#!/usr/bin/env python3
"""Compare two run sets (A, B) overall and within GC mode (low-GC vs normal).

usage: compare_modes.py DIR_A DIR_B
"""
import json, re, statistics as st, sys, math
from pathlib import Path

INCL = ["gc_start", "gc_marks_finish", "gc_mark_stacked_objects", "gc_sweep", "newobj_refill",
        "gc_marks_start", "rb_gc_writebarrier"]

def load(d):
    out = []
    for n in range(1, 11):
        o = (Path(d) / f"oha_run{n}").read_text()
        ok = sum(int(x) for x in re.findall(r"\[200\] (\d+) responses", o))
        a = json.load(open(Path(d) / "analysis" / f"run{n}.json"))
        full = json.load(open(Path(d) / "analysis" / f"full{n}.json"))
        tot = a["total_cpu_ms"]
        gc = a["inclusive_buckets_cpu_ms"].get("GC (local)", 0)
        ph = a["gc_phase_cpu_ms"]
        incl = dict(full["top_inclusive_cpu"])
        r = {"run": n, "rps": ok / 30, "cpu_us_req": 1000 * tot / ok, "gc_pct": 100 * gc / tot,
             "gc_us_req": 1000 * gc / ok, "nongc_us_req": 1000 * (tot - gc) / ok,
             "mark_us_req": 1000 * sum(v for k, v in ph.items() if k.startswith("mark")) / ok,
             "sweep_us_req": 1000 * ph.get("sweep", 0) / ok,
             "p99": None}
        m = re.search(r"99(?:\.00)?% in ([\d.]+) (\S+)", o)
        r["p99"] = float(m.group(1)) * (1000 if m.group(2) in ("sec", "s") else 1)
        for f in INCL:
            r[f] = 1000 * incl.get(f, 0) / ok
        r["low"] = r["gc_pct"] < 8
        out.append(r)
    return out

def mw_p(x, y):
    """Two-sided Mann-Whitney U, normal approximation with tie correction."""
    allv = sorted((v, i) for i, v in enumerate(x + y))
    ranks = [0.0] * len(allv)
    i = 0
    while i < len(allv):
        j = i
        while j + 1 < len(allv) and allv[j + 1][0] == allv[i][0]:
            j += 1
        for k in range(i, j + 1):
            ranks[allv[k][1]] = (i + j) / 2 + 1
        i = j + 1
    n1, n2 = len(x), len(y)
    if n1 == 0 or n2 == 0:
        return float("nan")
    u = sum(ranks[:n1]) - n1 * (n1 + 1) / 2
    mu, sd = n1 * n2 / 2, math.sqrt(n1 * n2 * (n1 + n2 + 1) / 12)
    z = (u - mu) / sd if sd else 0
    return math.erfc(abs(z) / math.sqrt(2))

A, B = load(sys.argv[1]), load(sys.argv[2])
keys = ["rps", "p99", "cpu_us_req", "nongc_us_req", "gc_pct", "gc_us_req", "mark_us_req", "sweep_us_req"] + INCL
print("low-GC runs: A", [r["run"] for r in A if r["low"]], " B", [r["run"] for r in B if r["low"]])
for label, sel in [("all runs", lambda r: True), ("low-GC mode", lambda r: r["low"]),
                   ("normal mode", lambda r: not r["low"])]:
    a = [r for r in A if sel(r)]; b = [r for r in B if sel(r)]
    print(f"\n## {label} (A n={len(a)}, B n={len(b)})\n")
    print("| metric | A mean | B mean | B vs A | MW p |\n|---|---|---|---|---|")
    for k in keys:
        xa, xb = [r[k] for r in a], [r[k] for r in b]
        ma, mb = st.mean(xa), st.mean(xb)
        d = 100 * (mb - ma) / ma if ma else float("nan")
        print(f"| {k} | {ma:.2f} | {mb:.2f} | {d:+.1f}% | {mw_p(xa, xb):.2f} |")
