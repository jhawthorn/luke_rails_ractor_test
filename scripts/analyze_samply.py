#!/usr/bin/env python3
"""Symbolicate a samply profile (+ .syms.json sidecar) and summarize it.

usage: analyze_samply.py PROFILE.json.gz [--json OUT.json] [--top N]

CPU numbers are threadCPUDelta-weighted (real on-CPU time); "wall" numbers
count samples (1 ms each), so a thread parked in the kernel still shows wall.
"""
import argparse, bisect, collections, gzip, json, re, sys

ap = argparse.ArgumentParser()
ap.add_argument("profile")
ap.add_argument("--json")
ap.add_argument("--top", type=int, default=30)
ap.add_argument("--callers", action="append", default=[],
                help="leaf function to break down by its nearest interesting callers (repeatable)")
ap.add_argument("--under", action="append", default=[],
                help="function (substring match) to break down by what it spends CPU on: the "
                     "next frames below it on the stack, and the leaf (repeatable)")
ap.add_argument("--ruby-callers", action="append", default=[],
                help="C call chain, innermost first, as FUNC or FUNC<-CALLER<-... (adjacent frames, "
                     "exact names): break the samples containing it down by the nearest Ruby "
                     "([JIT]) frames above it (repeatable)")
ap.add_argument("--from", dest="t_from", type=float, default=None,
                help="only count samples at or after this many seconds into the profile")
ap.add_argument("--to", dest="t_to", type=float, default=None,
                help="only count samples before this many seconds into the profile")
ap.add_argument("--depth", type=int, default=8)
args = ap.parse_args()

prof = json.load(gzip.open(args.profile))
syms_path = re.sub(r"\.json\.gz$", ".json.syms.json", args.profile)
syms = json.load(open(syms_path))
strtab = syms["string_table"]

# lib name -> (sorted rvas, [(rva, size, name)])
symtabs = {}
for d in syms["data"]:
    entries = sorted((e["rva"], e["size"], strtab[e["symbol"]]) for e in d["symbol_table"])
    symtabs[d["debug_name"]] = ([e[0] for e in entries], entries)

def lookup(libname, addr):
    st = symtabs.get(libname)
    if not st:
        return None
    rvas, entries = st
    i = bisect.bisect_right(rvas, addr) - 1
    if i < 0:
        return None
    rva, size, name = entries[i]
    if size and addr >= rva + size + 64:  # past the symbol; samply sizes can be tight
        return None
    return name

# Buckets for a quick "where does the CPU go" view, matched against the full
# stack (inclusive) in this priority order.
INCLUSIVE_BUCKETS = [
    ("global GC", re.compile(r"^gc_start_global$")),
    ("GC barrier wait", re.compile(r"rb_vm_barrier|rb_ractor_sched_barrier|barrier_join|vm_barrier")),
    ("GC (local)", re.compile(r"^(gc_start|gc_marks|gc_sweep|gc_mark_|gc_rest|garbage_collect|gc_continue|gc_compact)")),
    ("VM lock", re.compile(r"^(rb_vm_lock_enter|vm_lock_enter|rb_vm_lock_body|rb_ractor_sched_lock)")),
    ("SQLite", re.compile(r"^sqlite3")),
    ("malloc/free", re.compile(r"^(_?malloc|_?free|realloc|calloc|_malloc_zone|_free|nanov2_|szone_|mfm_|xzm_)")),
]
LEAF_CATEGORIES = [
    ("kernel wait (cv/mutex/kevent)", re.compile(r"__psynch_cvwait|__psynch_mutexwait|kevent|__select|__semwait|poll|__ulock_wait|__workq_kernreturn|mach_msg")),
    ("kernel I/O", re.compile(r"^(read|write|__sendto|__recvfrom|writev|readv|__close|accept|__accept|__connect|fcntl|ioctl|__sendmsg|__recvmsg)")),
    ("spin/yield", re.compile(r"swtch_pri|sched_yield|thread_switch|_os_unfair_lock_lock_slow|os_unfair_lock")),
    ("YJIT code", re.compile(r"^\[JIT\]")),
    ("GC", re.compile(r"^(gc_|rb_gc_|rgengc|heap_|page_|objspace_|rb_objspace)")),
    ("malloc/free", re.compile(r"^(_?malloc|_?free|realloc|calloc|_malloc_zone|_free|nanov2_|szone_|mfm_|xzm_|tiny_|small_)")),
    ("interpreter", re.compile(r"^(vm_exec_core|vm_exec|rb_vm_exec|vm_call|vm_sendish|vm_search|rb_vm_|vm_)")),
]

# Leaf-function split of GC work (self time), independent of what triggered it.
GC_LEAF_SUB = [
    ("sweep", re.compile(r"sweep|gc_page_sweep|heap_page_freelist|rb_gc_obj_free|obj_free")),
    ("write barrier", re.compile(r"writebarrier|gc_writebarrier|rgengc_remember|rb_gc_writebarrier")),
    ("mark", re.compile(r"mark|gc_marks|gc_aging|rgengc_rememberset|gc_grey|push_mark|pop_mark|shref|shareable_bits")),
    ("alloc", re.compile(r"new_obj|newobj|heap_prepare|heap_next_free|ractor_cache|rb_ec_newobj|rb_wb_protected_newobj|rb_wb_unprotected_newobj")),
    ("compact/move", re.compile(r"compact|gc_move|update_ref|gc_ref_update")),
]
GC_FN = re.compile(r"^(gc_|rb_gc_|rgengc|heap_|objspace|rb_objspace|newobj|rb_ec_newobj|rb_wb_|obj_free|rb_gc_obj_free|mark_|push_mark|pop_mark)")

def gc_sub(name):
    if not GC_FN.search(name):
        return None
    for cat, rx in GC_LEAF_SUB:
        if rx.search(name):
            return cat
    return "other gc"

# GC phase of a sample: the frame nearest the leaf that names a phase wins, so
# free() under gc_sweep_page counts as sweep, and marking done inside a global
# GC counts as global.
GC_PHASES = [
    ("global GC", re.compile(r"^gc_start_global$")),
    ("sweep", re.compile(r"^(gc_sweep|gc_page_sweep|gc_sweep_page|gc_sweep_step|gc_sweep_rest|gc_sweep_continue|gc_sweep_finish|gc_sweep_start)")),
    ("mark: rememberset", re.compile(r"^(rgengc_rememberset_mark|rgengc_rememberset)")),
    ("mark: roots", re.compile(r"^(gc_mark_roots|rb_gc_mark_roots|rb_gc_mark_machine_context|pinned_roots_mark|gc_mark_pinned)")),
    ("mark: finish", re.compile(r"^gc_marks_finish$")),
    ("mark: traverse", re.compile(r"^(gc_mark_stacked_objects|gc_marks_rest|gc_marks_continue|gc_marks_step|gc_marks_start|gc_marks)")),
    ("compact", re.compile(r"^(gc_compact|gc_move|gc_update_references|gc_ref_update)")),
]
GC_ENTRY = re.compile(r"^(gc_start|gc_continue|garbage_collect|gc_rest|rb_gc_impl_start)$")

def gc_phase(fs):
    for name in fs:
        for ph, rx in GC_PHASES:
            if rx.search(name):
                return ph
    if any(GC_ENTRY.search(x) for x in fs):
        return "gc: other (enter/exit, stats, hooks)"
    return None

def leaf_category(name):
    for cat, rx in LEAF_CATEGORIES:
        if rx.search(name):
            return cat
    return "other C"

threads_out = []
proc_self_cpu = collections.Counter()
proc_incl_cpu = collections.Counter()
proc_self_wall = collections.Counter()
proc_cat_cpu = collections.Counter()
proc_bucket_cpu = collections.Counter()
proc_gc_sub_cpu = collections.Counter()
proc_gc_phase_cpu = collections.Counter()
timeline = collections.Counter()  # second -> worker CPU ms
gc_global_samples_times = []
callers = {name: collections.Counter() for name in args.callers}
under_callees = {name: collections.Counter() for name in args.under}
under_leaves = {name: collections.Counter() for name in args.under}
ruby_callers = {spec: collections.Counter() for spec in args.ruby_callers}
ruby_callers_samples = {spec: collections.Counter() for spec in args.ruby_callers}
SKIP = re.compile(r"^(_?pthread_|__psynch|rb_native_|native_|thread_sched_|coroutine_|_?os_unfair|___chkstk)")
total_cpu = 0.0
start = prof["meta"]["startTime"]
libs = prof["libs"]

for t in prof["threads"]:
    n = t["samples"]["length"]
    if n == 0:
        continue
    sa = t["stringArray"]
    ft, fu, rt, st = t["frameTable"], t["funcTable"], t["resourceTable"], t["stackTable"]

    func_names = []
    for f in range(fu["length"]):
        name = sa[fu["name"][f]]
        r = fu["resource"][f]
        if name.startswith("0x") and r is not None:
            lib = libs[rt["lib"][r]]["name"] if rt["lib"][r] is not None else None
            sym = lookup(lib, int(name, 16)) if lib else None
            name = sym if sym else f"{lib}+{name}"
        func_names.append(name)

    frame_func = ft["func"]
    # stack -> list of func names, leaf first (cached)
    stack_cache = {}
    def stack_funcs(s):
        out = []
        cur = s
        while cur is not None:
            if cur in stack_cache:
                out.extend(stack_cache[cur])
                break
            out.append(func_names[frame_func[st["frame"][cur]]])
            cur = st["prefix"][cur]
        stack_cache[s] = out
        return out

    cpu_delta = t["samples"].get("threadCPUDelta") or [0] * n
    weights = t["samples"].get("weight") or [1] * n
    times = t["samples"]["time"]
    tcpu = 0.0
    twall = 0
    tcat = collections.Counter()
    for i in range(n):
        s = t["samples"]["stack"][i]
        w = weights[i] or 1
        c = (cpu_delta[i] or 0) / 1000.0  # ms
        twall += w
        if s is None:
            continue
        if args.t_from is not None and times[i] < args.t_from * 1000:
            continue
        if args.t_to is not None and times[i] >= args.t_to * 1000:
            continue
        fs = stack_funcs(s)
        leaf = fs[0]
        proc_self_wall[leaf] += w
        for spec in args.ruby_callers:
            chain = spec.split("<-")
            # outermost match, so the Ruby frames above it are the ones that asked
            idx = max((j for j in range(len(fs) - len(chain) + 1) if fs[j:j + len(chain)] == chain),
                      default=None)
            if idx is not None:
                rb = [x.removeprefix("[JIT] ") for x in fs[idx + len(chain):] if x.startswith("[JIT] ")]
                key = " <- ".join(rb[:args.depth]) or "(no Ruby frame)"
                ruby_callers[spec][key] += c
                ruby_callers_samples[spec][key] += w
        if c <= 0:
            continue
        tcpu += c
        proc_self_cpu[leaf] += c
        for name in set(fs):
            proc_incl_cpu[name] += c
        ph = gc_phase(fs)
        if ph:
            proc_gc_phase_cpu[ph] += c
        sub = gc_sub(leaf)
        if sub:
            proc_gc_sub_cpu[sub] += c
        cat = leaf_category(leaf)
        tcat[cat] += c
        proc_cat_cpu[cat] += c
        for bname, rx in INCLUSIVE_BUCKETS:
            if any(rx.search(x) for x in fs):
                proc_bucket_cpu[bname] += c
                break
        timeline[int(times[i] / 1000)] += c
        if leaf in callers:
            chain = [x for x in fs[1:] if not SKIP.search(x)][:args.depth]
            callers[leaf][" <- ".join(chain)] += c
        for name in args.under:
            # outermost frame matching, so recursion counts once
            idx = max((j for j, x in enumerate(fs) if name in x), default=None)
            if idx is not None:
                below = [x for x in reversed(fs[:idx]) if not SKIP.search(x)][:args.depth]
                under_callees[name][" -> ".join(below) or "(self)"] += c
                under_leaves[name][leaf_category(leaf) + ": " + leaf] += c
        if any(x == "gc_start_global" for x in fs):
            gc_global_samples_times.append(times[i])
    total_cpu += tcpu
    threads_out.append({"name": t["name"], "tid": t["tid"], "samples": n, "wall_ms": twall,
                        "cpu_ms": round(tcpu, 1), "categories": {k: round(v, 1) for k, v in tcat.most_common()}})

# Distinct global GCs: cluster gc_start_global samples that are >5ms apart.
gc_global_samples_times.sort()
episodes = []
for tm in gc_global_samples_times:
    if episodes and tm - episodes[-1][1] < 5:
        episodes[-1][1] = tm
    else:
        episodes.append([tm, tm])

top = args.top
res = {
    "profile": args.profile,
    "total_cpu_ms": round(total_cpu, 1),
    "threads": sorted(threads_out, key=lambda x: -x["cpu_ms"]),
    "leaf_categories_cpu_ms": {k: round(v, 1) for k, v in proc_cat_cpu.most_common()},
    "inclusive_buckets_cpu_ms": {k: round(v, 1) for k, v in proc_bucket_cpu.most_common()},
    "gc_phase_cpu_ms": {k: round(v, 1) for k, v in proc_gc_phase_cpu.most_common()},
    "gc_leaf_split_cpu_ms": {k: round(v, 1) for k, v in proc_gc_sub_cpu.most_common()},
    "top_self_cpu": [(k, round(v, 1)) for k, v in proc_self_cpu.most_common(top)],
    "top_inclusive_cpu": [(k, round(v, 1)) for k, v in proc_incl_cpu.most_common(top)],
    "top_self_wall": [(k, v) for k, v in proc_self_wall.most_common(top)],
    "cpu_ms_per_second": [round(timeline[s], 0) for s in range(0, max(timeline) + 1)] if timeline else [],
    "callers": {k: [(ch, round(v, 1)) for ch, v in cnt.most_common(top)] for k, cnt in callers.items()},
    "under": {k: {"callees": [(ch, round(v, 1)) for ch, v in under_callees[k].most_common(top)],
                  "leaves": [(ch, round(v, 1)) for ch, v in under_leaves[k].most_common(top)]}
              for k in args.under},
    "ruby_callers": {k: [(ch, round(v, 1), ruby_callers_samples[k][ch]) for ch, v in cnt.most_common(top)]
                     for k, cnt in ruby_callers.items()},
    "global_gc_episodes": len(episodes),
    "global_gc_episode_ms": [round(b - a + 1, 1) for a, b in episodes],
}
if args.json:
    json.dump(res, open(args.json, "w"), indent=1)

print(f"== {args.profile}")
print(f"total CPU: {res['total_cpu_ms']:.0f} ms")
print("threads (top by CPU):")
for th in res["threads"][:16]:
    print(f"  {th['name']:<22} cpu={th['cpu_ms']:>8.0f}ms wall={th['wall_ms']:>6}  {dict(list(th['categories'].items())[:4])}")
print("leaf category CPU ms:", res["leaf_categories_cpu_ms"])
print("inclusive buckets CPU ms:", res["inclusive_buckets_cpu_ms"])
print("GC phase CPU ms:", res["gc_phase_cpu_ms"])
print("GC leaf split CPU ms:", res["gc_leaf_split_cpu_ms"])
print(f"global GC episodes: {res['global_gc_episodes']}  durations(ms): {res['global_gc_episode_ms'][:40]}")
print("CPU ms per second:", res["cpu_ms_per_second"])
print("top self CPU:")
for k, v in res["top_self_cpu"]:
    print(f"  {v:>8.0f}  {k}")
print("top inclusive CPU:")
for k, v in res["top_inclusive_cpu"]:
    print(f"  {v:>8.0f}  {k}")
for k, lst in res["callers"].items():
    print(f"callers of {k}:")
    for ch, v in lst[:15]:
        print(f"  {v:>8.0f}  {ch}")
for k, d in res["under"].items():
    print(f"under {k}: callees ({args.depth} frames below it)")
    for ch, v in d["callees"][:15]:
        print(f"  {v:>8.0f}  {ch}")
    print(f"under {k}: leaves")
    for ch, v in d["leaves"][:15]:
        print(f"  {v:>8.0f}  {ch}")
for k, lst in res["ruby_callers"].items():
    print(f"Ruby callers of {k} (CPU ms, wall samples):")
    for ch, v, n in lst[:args.top]:
        print(f"  {v:>8.0f} {n:>6}  {ch}")
