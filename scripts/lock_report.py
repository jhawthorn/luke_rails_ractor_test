#!/usr/bin/env python3
"""Which locks does a samply profile spend its time in, and from where?

usage: lock_report.py PROFILE.json.gz [--top N] [--depth N]

Needs the .syms.json sidecar from `samply record --unstable-presymbolicate`.
For every sample, the innermost lock-acquiring frame on the stack (VM lock,
barrier, native mutex, Ruby Mutex, scheduler lock, ...) names the lock; the
first frames above it that are not lock plumbing name the call site. A
sampling profiler sees time spent in a lock (waiting or acquiring), not how
many times it was taken. Both CPU ms (threadCPUDelta) and wall samples (1 ms
each) are reported: a thread blocked in the kernel has wall but little CPU.

Barrier joins are waits for someone else's barrier, so the initiators
(rb_ractor_sched_barrier_start) are also listed by their callers.
"""
import argparse, bisect, collections, gzip, json, re

ap = argparse.ArgumentParser()
ap.add_argument("profile")
ap.add_argument("--top", type=int, default=25)
ap.add_argument("--depth", type=int, default=4)
args = ap.parse_args()

prof = json.load(gzip.open(args.profile))
syms = json.load(open(re.sub(r"\.json\.gz$", ".json.syms.json", args.profile)))
strtab = syms["string_table"]
symtabs = {}
for d in syms["data"]:
    entries = sorted((e["rva"], e["size"], strtab[e["symbol"]]) for e in d["symbol_table"])
    symtabs[d["debug_name"]] = ([e[0] for e in entries], entries)

def lookup(lib, addr):
    st = symtabs.get(lib)
    if not st:
        return None
    rvas, entries = st
    i = bisect.bisect_right(rvas, addr) - 1
    if i < 0:
        return None
    rva, size, name = entries[i]
    if size and addr >= rva + size + 64:
        return None
    return name

# (lock kind, frame regex). Among the lock frames in the run of lock plumbing
# at the leaf end of the stack, the one listed first here wins, so a pthread
# mutex wait inside vm_lock_enter -> barrier_join is reported as the join.
LOCKS = [
    ("idle: Ractor.receive (not contention)", re.compile(r"^ractor_port_receive$")),
    ("SQLite busy wait (sleep in busy_handler_timeout)", re.compile(r"busy_handler_timeout")),
    ("idle: sleep (not contention)", re.compile(r"^rb_f_sleep$")),
    ("VM barrier join (waiting for another Ractor's barrier)", re.compile(r"^(rb_ractor_sched_barrier_join|ractor_sched_barrier_join_wait_locked)$")),
    ("VM barrier start (stopping all Ractors)", re.compile(r"^(rb_ractor_sched_barrier_start|rb_vm_barrier)$")),
    ("VM lock (RB_VM_LOCK)", re.compile(r"^(vm_lock_enter|rb_vm_lock_enter_body|rb_vm_lock_body|rb_vm_lock_enter_body_cr|rb_vm_lock_enter_body_nb)$")),
    ("YJIT with_vm_lock", re.compile(r"with_vm_lock")),
    ("Ruby Mutex / Monitor", re.compile(r"^(rb_mutex_lock|do_mutex_lock|rb_mutex_synchronize|monitor_enter|rb_monitor_enter)$")),
    ("Ractor lock", re.compile(r"^(ractor_lock|ractor_lock_self|RACTOR_LOCK)$")),
    ("thread scheduler lock", re.compile(r"^(thread_sched_lock_|thread_sched_lock|ractor_sched_lock|thread_sched_wait_running_turn)$")),
    ("SQLite file/shm lock", re.compile(r"^(unixShmLock|unixLock|unixFileLock|posixUnlock|sqlite3OsLock|pagerLockDb)$")),
    ("native mutex (pthread)", re.compile(r"^(rb_native_mutex_lock|pthread_mutex_lock|_pthread_mutex_firstfit_lock_slow|_pthread_mutex_firstfit_lock_wait)$")),
    ("os_unfair_lock (libsystem)", re.compile(r"os_unfair_lock_lock")),
]
PLUMBING = re.compile(r"^(_?pthread_|__psynch|rb_native_|native_|thread_sched_|coroutine_|_?os_unfair|___chkstk|"
                      r"vm_lock_enter|rb_vm_lock|rb_ractor_sched_barrier|ractor_sched_barrier|rb_threadptr_execute_interrupts$|"
                      r"rb_ec_check_ints|rb_thread_check_ints|RUBY_VM_CHECK_INTS|vm_call_cfunc_with_frame_$|vm_exec_core$|rb_vm_exec$)")

kind_cpu, kind_wall = collections.Counter(), collections.Counter()
site_cpu, site_wall = collections.Counter(), collections.Counter()
init_cpu, init_wall = collections.Counter(), collections.Counter()
total_cpu = total_wall = 0.0
libs = prof["libs"]

for t in prof["threads"]:
    n = t["samples"]["length"]
    if not n:
        continue
    sa, ft, fu, rt, st = t["stringArray"], t["frameTable"], t["funcTable"], t["resourceTable"], t["stackTable"]
    names = []
    for f in range(fu["length"]):
        name = sa[fu["name"][f]]
        r = fu["resource"][f]
        if name.startswith("0x") and r is not None and rt["lib"][r] is not None:
            lib = libs[rt["lib"][r]]["name"]
            name = lookup(lib, int(name, 16)) or f"{lib}+{name}"
        names.append(name)
    cache = {}
    def funcs(s):
        out, cur = [], s
        while cur is not None:
            if cur in cache:
                out.extend(cache[cur])
                break
            out.append(names[ft["func"][st["frame"][cur]]])
            cur = st["prefix"][cur]
        cache[s] = out
        return out
    cpu = t["samples"].get("threadCPUDelta") or [0] * n
    wts = t["samples"].get("weight") or [1] * n
    for i in range(n):
        s = t["samples"]["stack"][i]
        if s is None:
            continue
        c, w = (cpu[i] or 0) / 1000.0, wts[i] or 1
        total_cpu += c
        total_wall += w
        fs = funcs(s)
        hit = None  # (priority, depth, kind, fn)
        for j, fn in enumerate(fs):
            for p, (kind, rx) in enumerate(LOCKS):
                if rx.search(fn):
                    if hit is None or p < hit[0]:
                        hit = (p, j, kind, fn)
                    break
            else:
                if not PLUMBING.search(fn) and not fn.startswith(("__", "_platform", "sleep_hrtime", "ractor_wait", "rb_ractor_sched_wait")):
                    break
        if not hit:
            continue
        _, j, kind, fn = hit
        site = [x for x in fs[j + 1:] if not PLUMBING.search(x)][:args.depth]
        key = f"[{kind}] {fn} <- " + " <- ".join(site)
        kind_cpu[kind] += c
        kind_wall[kind] += w
        site_cpu[key] += c
        site_wall[key] += w
        k = next((k for k, x in enumerate(fs) if x == "rb_ractor_sched_barrier_start"), None)
        if k is not None:
            ikey = " <- ".join([x for x in fs[k + 1:] if not PLUMBING.search(x)][:args.depth + 2])
            init_cpu[ikey] += c
            init_wall[ikey] += w

print(f"== {args.profile}")
print(f"total: {total_cpu:.0f} CPU ms, {total_wall:.0f} wall samples")
print(f"\nby lock (CPU ms, % of total CPU, wall samples):")
for k, v in kind_cpu.most_common():
    print(f"  {v:>8.0f} {100 * v / total_cpu:5.1f}% {kind_wall[k]:>8.0f}  {k}")
print(f"\ntop lock sites by CPU ms (CPU ms, wall samples):")
for k, v in site_cpu.most_common(args.top):
    print(f"  {v:>8.0f} {site_wall[k]:>8.0f}  {k}")
print(f"\ntop lock sites by wall samples (CPU ms, wall samples):")
for k, v in site_wall.most_common(args.top):
    print(f"  {site_cpu[k]:>8.0f} {v:>8.0f}  {k}")
print(f"\nbarrier initiators: callers of rb_ractor_sched_barrier_start (CPU ms, wall samples):")
for k, v in init_wall.most_common(args.top):
    print(f"  {init_cpu[k]:>8.0f} {v:>8.0f}  {k}")
