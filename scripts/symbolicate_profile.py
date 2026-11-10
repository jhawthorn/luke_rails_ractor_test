#!/usr/bin/env python3
"""Symbolicate a samply profile offline and ask it questions about call paths.

`samply record --save-only` writes an *unsymbolicated* profile: function names
are raw hex addresses and symbolication only happens later, inside `samply
load`.  That is fine for browsing in the UI but useless for scripted questions
like "who calls rb_obj_id?".  This script resolves the addresses itself:

  * native frames  -> `nm -n` on the library, offset by its __TEXT vmaddr
  * YJIT frames    -> the /tmp/perf-<pid>.map that `ruby --yjit-perf` writes,
                      which samply records as a library in the profile

Examples
--------
Who calls rb_obj_id, and from which Ruby method?

    scripts/symbolicate_profile.py profile.json.gz --callers rb_obj_id

Several symbols at once, deeper chains, only paths seen 5+ times:

    scripts/symbolicate_profile.py profile.json.gz \
        --callers rb_obj_id --callers rb_obj_hash --depth 12 --min-samples 5

Where is time actually going?

    scripts/symbolicate_profile.py profile.json.gz --top 40

The YJIT map lived under a different pid (profile moved between machines/runs):

    scripts/symbolicate_profile.py profile.json.gz --callers rb_obj_id \
        --perf-map /tmp/perf-26516.map

Caveats
-------
Frames *above* a JIT boundary can be unreliable: samply unwinds with frame
pointers, and JIT'd code does not always maintain them, so mid-stack entries
may be stale stack slots.  Contiguous C prefixes are trustworthy; treat a long
chain that wanders through unrelated-looking functions with suspicion.

Static C functions resolve to the nearest *preceding* symbol, so a name may be
the enclosing symbol rather than the exact function.
"""

from __future__ import annotations

import argparse
import bisect
import collections
import gzip
import json
import os
import re
import subprocess
import sys

# Threads parked in the kernel are "idle" for our purposes: a 12-Ractor server
# spends most of its samples in libsystem_kernel waiting on something.
IDLE_LIB_PREFIXES = ("libsystem_kernel",)

# macOS ships these inside the dyld shared cache.  A stub file still exists on
# disk and `nm` happily reads its symbol table, but those addresses do not match
# the runtime layout, so resolving against it yields confidently-wrong names
# (a thread parked in a syscall gets reported as e.g. `mach_vm_protect`).
# Leave them as `lib!0xaddr` unless --system-symbols is passed.
SHARED_CACHE_PREFIXES = ("/usr/lib/", "/System/")


def in_shared_cache(path: str) -> bool:
    return path.startswith(SHARED_CACHE_PREFIXES)


def load_profile(path: str) -> dict:
    opener = gzip.open if path.endswith(".gz") else open
    with opener(path, "rb") as fh:
        return json.load(fh)


class NativeSymbols:
    """Address -> symbol for one on-disk binary, via `nm -n`."""

    def __init__(self, path: str) -> None:
        self.ok = False
        self.addrs: list[int] = []
        self.names: list[str] = []
        if not path or not os.path.exists(path):
            return
        base = self._text_vmaddr(path)
        if base is None:
            return
        try:
            out = subprocess.run(
                ["nm", "-n", path], capture_output=True, text=True, timeout=120
            ).stdout
        except (OSError, subprocess.SubprocessError):
            return
        pairs = []
        for line in out.splitlines():
            parts = line.split()
            if len(parts) < 3:
                continue
            addr, kind, name = parts[0], parts[1], " ".join(parts[2:])
            if kind.upper() not in ("T", "S"):  # text / absolute-ish symbols
                continue
            try:
                value = int(addr, 16)
            except ValueError:
                continue
            rel = value - base
            if rel < 0:
                continue
            pairs.append((rel, name.lstrip("_")))
        if not pairs:
            return
        pairs.sort()
        self.addrs = [a for a, _ in pairs]
        self.names = [n for _, n in pairs]
        self.ok = True

    @staticmethod
    def _text_vmaddr(path: str) -> int | None:
        """vmaddr of __TEXT, which samply subtracts to get relative addresses."""
        try:
            out = subprocess.run(
                ["otool", "-l", path], capture_output=True, text=True, timeout=120
            ).stdout
        except (OSError, subprocess.SubprocessError):
            return None
        in_text = False
        for line in out.splitlines():
            stripped = line.strip()
            if stripped.startswith("segname __TEXT"):
                in_text = True
            elif in_text and stripped.startswith("vmaddr"):
                try:
                    return int(stripped.split()[1], 16)
                except (IndexError, ValueError):
                    return None
        return None

    def lookup(self, rel: int) -> str | None:
        i = bisect.bisect_right(self.addrs, rel) - 1
        return self.names[i] if i >= 0 else None


class PerfMap:
    """A /tmp/perf-<pid>.map written by `ruby --yjit-perf`.

    Lines are `<abs_hex_addr> <hex_size> <name>`.  samply registers the map as
    a library whose base is the lowest address in the file, so profile frame
    addresses are relative to that.
    """

    def __init__(self, path: str) -> None:
        self.ok = False
        self.entries: list[tuple[int, int, str]] = []
        self.base = 0
        if not path or not os.path.exists(path):
            return
        entries = []
        with open(path, errors="replace") as fh:
            for line in fh:
                parts = line.split(None, 2)
                if len(parts) < 3:
                    continue
                try:
                    entries.append(
                        (int(parts[0], 16), int(parts[1], 16), parts[2].strip())
                    )
                except ValueError:
                    continue
        if not entries:
            return
        entries.sort()
        self.entries = entries
        self.starts = [e[0] for e in entries]
        self.base = entries[0][0]
        self.ok = True

    def lookup(self, rel: int) -> str | None:
        absolute = self.base + rel
        i = bisect.bisect_right(self.starts, absolute) - 1
        if i < 0:
            return None
        start, size, name = self.entries[i]
        # Past the end of that entry: still report it, but flag the gap.
        return name if absolute < start + size else f"{name} (+0x{absolute - start - size:x})"


class Symbolicator:
    def __init__(
        self,
        profile: dict,
        perf_map_override: str | None = None,
        system_symbols: bool = False,
    ) -> None:
        self.libs = profile.get("libs", [])
        self._native: dict[int, NativeSymbols] = {}
        self._perf: dict[int, PerfMap] = {}
        self._override = perf_map_override
        self.system_symbols = system_symbols
        self.perf_lib_indices = [
            i
            for i, lib in enumerate(self.libs)
            if re.search(r"/perf-\d+\.map$", lib.get("path") or "")
        ]

    def _is_perf_lib(self, lib_index: int) -> bool:
        return lib_index in self.perf_lib_indices

    def lib_name(self, lib_index: int | None) -> str:
        if lib_index is None:
            return "<unmapped>"
        return self.libs[lib_index].get("name") or "?"

    def _native_for(self, lib_index: int) -> NativeSymbols:
        sym = self._native.get(lib_index)
        if sym is None:
            path = self.libs[lib_index].get("path") or ""
            if in_shared_cache(path) and not self.system_symbols:
                sym = NativeSymbols("")  # not ok -> falls back to lib!0xaddr
            else:
                sym = NativeSymbols(path)
            self._native[lib_index] = sym
        return sym

    def _perf_for(self, lib_index: int) -> PerfMap:
        pm = self._perf.get(lib_index)
        if pm is None:
            path = self._override or (self.libs[lib_index].get("path") or "")
            pm = PerfMap(path)
            self._perf[lib_index] = pm
        return pm

    def resolve(self, lib_index: int | None, address: int | None, fallback: str) -> str:
        if lib_index is None:
            return f"<unmapped>!{fallback}"
        lib_name = self.libs[lib_index].get("name") or "?"
        if address is None:
            return f"{lib_name}!{fallback}"
        if self._is_perf_lib(lib_index):
            pm = self._perf_for(lib_index)
            if pm.ok:
                name = pm.lookup(address)
                if name:
                    return name
            return f"[JIT]!{fallback}"
        sym = self._native_for(lib_index)
        if sym.ok:
            name = sym.lookup(address)
            if name:
                return name
        return f"{lib_name}!{fallback}"


class ThreadView:
    """Lazily-symbolicated frame names for one thread in the profile."""

    def __init__(self, thread: dict, symbolicator: Symbolicator) -> None:
        self.thread = thread
        self.sym = symbolicator
        strings = thread["stringArray"]
        func = thread["funcTable"]
        res = thread["resourceTable"]
        self.func_name = [
            strings[n] if n is not None else "?" for n in func["name"]
        ]
        self.func_resource = func["resource"]
        self.res_lib = [res["lib"][i] for i in range(res["length"])]
        frames = thread["frameTable"]
        self.frame_func = frames["func"]
        self.frame_addr = frames["address"]
        stacks = thread["stackTable"]
        self.stack_frame = stacks["frame"]
        self.stack_prefix = stacks["prefix"]
        self._cache: dict[int, str] = {}
        self._lib_cache: dict[int, str] = {}

    def _lib_index(self, frame_index: int) -> int | None:
        resource = self.func_resource[self.frame_func[frame_index]]
        if resource is not None and 0 <= resource < len(self.res_lib):
            return self.res_lib[resource]
        return None

    def frame_name(self, frame_index: int) -> str:
        cached = self._cache.get(frame_index)
        if cached is not None:
            return cached
        fn = self.frame_func[frame_index]
        name = self.sym.resolve(
            self._lib_index(frame_index), self.frame_addr[frame_index], self.func_name[fn]
        )
        self._cache[frame_index] = name
        return name

    def frame_lib(self, frame_index: int) -> str:
        cached = self._lib_cache.get(frame_index)
        if cached is None:
            cached = self.sym.lib_name(self._lib_index(frame_index))
            self._lib_cache[frame_index] = cached
        return cached

    def leaf_lib(self, stack_index: int) -> str:
        return self.frame_lib(self.stack_frame[stack_index])

    def stack_names(self, stack_index: int) -> list[str]:
        """Leaf-first list of symbolicated frame names."""
        out = []
        cur = stack_index
        while cur is not None:
            out.append(self.frame_name(self.stack_frame[cur]))
            cur = self.stack_prefix[cur]
        return out


def iter_samples(profile: dict, symbolicator: Symbolicator, thread_filter=None):
    """Yield (thread, leaf-first stack names, leaf lib name) per sample."""
    for thread in profile["threads"]:
        if thread_filter and thread_filter not in (thread.get("name") or ""):
            continue
        view = ThreadView(thread, symbolicator)
        for stack in thread["samples"]["stack"]:
            if stack is None:
                continue
            yield thread, view.stack_names(stack), view.leaf_lib(stack)


def is_idle(leaf_lib: str) -> bool:
    """A sample whose innermost frame is a kernel wait, i.e. a parked thread."""
    return leaf_lib.startswith(IDLE_LIB_PREFIXES)


def cmd_summary(profile, symbolicator, args) -> None:
    total = sum(t["samples"]["length"] for t in profile["threads"])
    idle = active = 0
    idle_libs = collections.Counter()
    for _thread, _names, leaf_lib in iter_samples(profile, symbolicator, args.thread):
        if is_idle(leaf_lib):
            idle += 1
        else:
            active += 1
        idle_libs[leaf_lib] += 1
    pids = {t.get("pid") for t in profile["threads"]}
    print(f"profile:        {args.profile}")
    print(f"threads:        {len(profile['threads'])}")
    print(f"processes:      {len(pids)}")
    print(f"samples:        {total}")
    print(f"  idle (kernel):{idle:>8}  ({100.0 * idle / max(total, 1):.1f}%)")
    print(f"  active:       {active:>8}  ({100.0 * active / max(total, 1):.1f}%)")
    print("samples by library:")
    for lib, count in idle_libs.most_common(8):
        print(f"  {count:8d}  {lib}")
    if symbolicator.perf_lib_indices:
        for i in symbolicator.perf_lib_indices:
            print(f"YJIT perf map:  {symbolicator.libs[i].get('path')}")
    else:
        print(
            "YJIT perf map:  MISSING -- JIT frames will not resolve to Ruby methods.\n"
            "                Re-record with `ruby --yjit-perf`, keep /tmp/perf-<pid>.map,\n"
            "                or pass --perf-map."
        )


def cmd_top(profile, symbolicator, args) -> None:
    self_counts = collections.Counter()
    for _thread, names, leaf_lib in iter_samples(profile, symbolicator, args.thread):
        if not args.idle and is_idle(leaf_lib):
            continue
        if names:
            self_counts[names[0]] += 1
    total = sum(self_counts.values())
    print(f"=== hottest {args.top} leaf functions ({total} samples) ===")
    for name, count in self_counts.most_common(args.top):
        print(f"{count:8d}  {100.0 * count / max(total, 1):5.1f}%  {name}")


def cmd_callers(profile, symbolicator, args) -> None:
    targets = set(args.callers)
    chains = collections.Counter()
    immediate = collections.Counter()
    ruby_frames = collections.Counter()
    per_target = collections.Counter()
    per_thread = collections.Counter()
    below_chains = collections.Counter()
    below_leaf_lib = collections.Counter()
    matched = scanned = suppressed_idle = 0

    for thread, names, leaf_lib in iter_samples(profile, symbolicator, args.thread):
        hit = next((i for i, n in enumerate(names) if n in targets), None)
        if not args.idle and is_idle(leaf_lib):
            # Count what the idle filter is hiding: a thread blocked *inside* the
            # target (e.g. waiting on the VM lock) parks in the kernel, so the
            # most interesting samples can be exactly the ones filtered out.
            if hit is not None:
                suppressed_idle += 1
            continue
        scanned += 1
        if hit is None:
            continue
        matched += 1
        below_leaf_lib[leaf_lib] += 1
        if hit > 0:
            below_chains[tuple(names[:hit][-args.depth :])] += 1
        per_target[names[hit]] += 1
        per_thread[thread.get("name") or f"tid {thread.get('tid')}"] += 1
        chains[tuple(names[hit : hit + args.depth])] += 1
        if hit + 1 < len(names):
            immediate[names[hit + 1]] += 1
        jit = next((n for n in names[hit:] if n.startswith("[JIT]")), None)
        if jit:
            ruby_frames[jit] += 1

    pct = 100.0 * matched / max(scanned, 1)
    print(f"=== {', '.join(sorted(targets))} ===")
    print(f"{matched} of {scanned} scanned samples ({pct:.2f}%) have it on the stack")
    if suppressed_idle:
        print(
            f"NOTE: {suppressed_idle} further matches are on kernel-parked stacks, hidden"
            " by the idle filter. A thread blocked inside the target (waiting on a"
            " lock) looks idle. Re-run with --idle to see them."
        )
    print()

    if not matched:
        print("No matching frames. Check the symbol name, or run with --top to see")
        print("what did resolve; if everything looks like 0x..., symbolication failed.")
        return

    print("--- matched symbol ---")
    for name, count in per_target.most_common():
        print(f"{count:8d}  {name}")

    print("\n--- immediate caller ---")
    for name, count in immediate.most_common(args.limit):
        print(f"{count:8d}  {name}")

    if ruby_frames:
        print("\n--- nearest Ruby (JIT) frame ---")
        for name, count in ruby_frames.most_common(args.limit):
            print(f"{count:8d}  {name}")
    else:
        print(
            "\n--- nearest Ruby (JIT) frame ---\n"
            "     none: no JIT frames on these stacks (see perf-map note in --summary)"
        )

    if below_chains:
        print("\n--- below the target (what it is doing / blocked in) ---")
        for lib, count in below_leaf_lib.most_common(args.limit):
            marker = "  <- parked" if is_idle(lib) else ""
            print(f"{count:8d}  leaf in {lib}{marker}")
        print()
        shown = 0
        for chain, count in below_chains.most_common():
            if count < args.min_samples or shown >= 3:
                break
            shown += 1
            print(f"  {count} samples, innermost first:")
            for depth, name in enumerate(chain):
                print(f"    {depth:2d}: {name}")

    print("\n--- threads ---")
    for name, count in per_thread.most_common(10):
        print(f"{count:8d}  {name}")

    print(f"\n--- call chains (target -> root), >= {args.min_samples} samples ---")
    shown = 0
    for chain, count in chains.most_common():
        if count < args.min_samples or shown >= args.limit:
            break
        shown += 1
        print(f"\n  {count} samples")
        for depth, name in enumerate(chain):
            print(f"    {depth:2d}: {name}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("profile", help="samply profile (.json or .json.gz)")
    parser.add_argument(
        "--callers",
        action="append",
        default=[],
        metavar="SYMBOL",
        help="aggregate call paths through SYMBOL (repeatable)",
    )
    parser.add_argument(
        "--top", type=int, metavar="N", help="show the N hottest leaf functions"
    )
    parser.add_argument(
        "--depth", type=int, default=16, help="frames per call chain (default 16)"
    )
    parser.add_argument(
        "--limit", type=int, default=20, help="max rows per section (default 20)"
    )
    parser.add_argument(
        "--min-samples",
        type=int,
        default=1,
        help="hide call chains below this sample count (default 1)",
    )
    parser.add_argument(
        "--thread", metavar="SUBSTR", help="only threads whose name contains SUBSTR"
    )
    parser.add_argument(
        "--idle",
        action="store_true",
        help="include samples parked in libsystem_kernel (excluded by default)",
    )
    parser.add_argument(
        "--perf-map",
        metavar="PATH",
        help="use this YJIT perf map instead of the path recorded in the profile",
    )
    parser.add_argument(
        "--system-symbols",
        action="store_true",
        help="also resolve /usr/lib and /System frames via nm. Off by default: "
        "those libraries live in the dyld shared cache and the on-disk stub's "
        "addresses do not match the runtime layout, so the names come out wrong.",
    )
    args = parser.parse_args(argv)

    if not os.path.exists(args.profile):
        print(f"no such profile: {args.profile}", file=sys.stderr)
        return 1

    profile = load_profile(args.profile)
    symbolicator = Symbolicator(profile, args.perf_map, args.system_symbols)

    if args.callers:
        cmd_callers(profile, symbolicator, args)
    elif args.top:
        cmd_top(profile, symbolicator, args)
    else:
        cmd_summary(profile, symbolicator, args)
    return 0


if __name__ == "__main__":
    sys.exit(main())
