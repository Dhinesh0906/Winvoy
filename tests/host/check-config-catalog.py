#!/usr/bin/env python3
"""Every option the code reads must be in Settings › All settings.

Regenerates the catalog in memory from the sources (build/tools/gen-config-catalog.py)
and fails when app/Madeira/ConfigCatalog.generated.swift differs, so a new
madeira.cfg key or env switch cannot be added without appearing in Settings.
Also checks the hand-built Memory & sync rows: swap sizes include 3 GB and the
coverage picker defaults to large allocations only (classic); JIT pool and
video memory have pickers of their own."""
import os, re, subprocess, sys
R = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
rc = subprocess.run([sys.executable, os.path.join(R, "build/tools/gen-config-catalog.py"), "--check"]).returncode
lib = open(os.path.join(R, "app/Madeira/Library.swift")).read()
gen = open(os.path.join(R, "app/Madeira/ConfigCatalog.generated.swift")).read()
ok = rc == 0
for what, cond in [
    ("swap sizes include 3072", "swapChoices = [0, 1024, 2048, 3072, 4096]" in lib),
    ("coverage picker: large-only default, blocks, wide", '("", "Large allocations (8 MB+)")' in lib and '("blocks"' in lib and '("wide"' in lib),
    ("JIT pool and video memory pickers in Memory & sync", 'key: "pool"' in lib and 'key: "vram-mb"' in lib),
    ("eco mode toggle in Memory & sync, off unless set", 'MadeiraConfig.set("eco", on ? "1" : nil)' in lib and 'MadeiraConfig.bool("eco", default: false)' in lib),
    ("catalog lists swap-mb with a 3 GB choice", re.search(r'key: "swap-mb".*\("3072", "3 GB"\)', gen) is not None),
    ("catalog lists env.MADEIRA_SWAP_COVERAGE", 'key: "env.MADEIRA_SWAP_COVERAGE"' in gen),
]:
    print(("ok   " if cond else "FAIL ") + what)
    ok &= cond
print("PASS" if ok else "FAILED")
sys.exit(0 if ok else 1)
