#!/usr/bin/env python3
"""Summarize and compare run directories made by scripts/profile_run.sh and
analyzed by scripts/analyze_samply.py (DIR/analysis/runN.json).

usage: compare_runs.py DIR [DIR ...]
"""
import json, re, statistics, sys
from pathlib import Path

def g(rx, text, conv=float):
    m = re.search(rx, text)
    return conv(m.group(1)) if m else None

def ms(v):
    if v is None:
        return None
    num, unit = v.split()
    return float(num) * {"ns": 1e-6, "µs": 1e-3, "us": 1e-3, "ms": 1, "s": 1000, "sec": 1000}[unit]

def runs(d):
    out = []
    for oha in sorted(Path(d).glob("oha_run*"), key=lambda p: int(p.name[7:])):
        n = int(oha.name[7:])
        o = oha.read_text()
        log = (Path(d) / f"cougar_run{n}.log").read_text(errors="replace")
        a = json.load(open(Path(d) / "analysis" / f"run{n}.json"))
        ok = sum(int(x) for x in re.findall(r"\[200\] (\d+) responses", o))
        tot = a["total_cpu_ms"]
        cps = a["cpu_ms_per_second"]
        mid = cps[6:-1]
        top = dict(a["top_self_cpu"])
        b = a["inclusive_buckets_cpu_ms"]
        logger = sum(v for c, v in a["callers"].get("__psynch_mutexwait", [])
                     if "ractor_send_basket" in c or "rb_ractor_sched_wakeup" in c)
        out.append({
            "run": n,
            "crashed": "[BUG]" in log,
            "isolation_errors": log.count("Ractor::IsolationError (can not"),
            "rps_oha": g(r"Requests/sec:\s+([\d.]+)", o),
            "ok": ok,
            "ok_rps": ok / 30.0,
            "p50": ms(g(r"50(?:\.00)?% in ([\d.]+ \S+)", o, str)),
            "p99": ms(g(r"99(?:\.00)?% in ([\d.]+ \S+)", o, str)),
            "p999": ms(g(r"99\.90% in ([\d.]+ \S+)", o, str)),
            "slowest": ms(g(r"Slowest:\s+([\d.]+ \S+)", o, str)),
            "cpu_ms": tot,
            "steady_cpu": statistics.median(mid) if mid else 0,
            "cpu_per_req": tot / ok if ok else None,
            "gc_local_pct": 100 * b.get("GC (local)", 0) / tot if tot else 0,
            "gc_global_ms": b.get("global GC", 0),
            "gc_barrier_pct": 100 * b.get("GC barrier wait", 0) / tot if tot else 0,
            "vm_lock_pct": 100 * b.get("VM lock", 0) / tot if tot else 0,
            "global_gcs": a["global_gc_episodes"],
            "global_gc_ms": sum(a["global_gc_episode_ms"]),
            "mutexwait_pct": 100 * top.get("__psynch_mutexwait", 0) / tot if tot else 0,
            "logger_lock_pct": 100 * logger / tot if tot else 0,
            "gc_split": a.get("gc_leaf_split_cpu_ms", {}),
            "gc_ms_per_req": b.get("GC (local)", 0) / ok if ok else None,
        })
    return out

def mean(xs):
    xs = [x for x in xs if x is not None]
    return statistics.mean(xs) if xs else float("nan")

def sd(xs):
    xs = [x for x in xs if x is not None]
    return statistics.stdev(xs) if len(xs) > 1 else 0.0

COLS = [("run", "{}"), ("ok_rps", "{:.0f}"), ("ok", "{}"), ("p50", "{:.2f}"), ("p99", "{:.2f}"),
        ("p999", "{:.1f}"), ("steady_cpu", "{:.0f}"), ("cpu_per_req", "{:.3f}"),
        ("gc_local_pct", "{:.1f}"), ("gc_ms_per_req", "{:.3f}"), ("global_gcs", "{}"),
        ("global_gc_ms", "{:.0f}"), ("gc_barrier_pct", "{:.2f}"), ("logger_lock_pct", "{:.1f}"),
        ("vm_lock_pct", "{:.2f}"), ("crashed", "{}"), ("isolation_errors", "{}")]

def fmt(v, f):
    return "-" if v is None else f.format(v)

all_sets = {}
for d in sys.argv[1:]:
    rs = runs(d)
    all_sets[d] = rs
    print(f"\n### {d}\n")
    print("| " + " | ".join(c for c, _ in COLS) + " |")
    print("|" + "---|" * len(COLS))
    for r in rs:
        print("| " + " | ".join(fmt(r[c], f) for c, f in COLS) + " |")
    good = [r for r in rs if not r["crashed"]]
    print(f"\nruns: {len(rs)}, crashed: {len(rs) - len(good)}")
    for c, f in COLS[1:-2]:
        vals = [r[c] for r in good]
        print(f"  {c:<16} mean {fmt(mean(vals), f):>9}  sd {sd(vals):8.3f}  min {fmt(min(v for v in vals if v is not None), f):>9}  max {fmt(max(v for v in vals if v is not None), f):>9}")
    split = {}
    for r in good:
        for k, v in r["gc_split"].items():
            split[k] = split.get(k, 0) + v / r["ok"] * 1000  # µs per request
    print("  GC leaf split, µs CPU per request (mean):",
          {k: round(v / len(good), 1) for k, v in sorted(split.items(), key=lambda kv: -kv[1])})
