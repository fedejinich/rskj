#!/usr/bin/env python3
"""Regression check for the heavy queue's admission race (no heavy job, temporary lock directory):
two callers that both observe a free queue must not both acquire. Each holder snapshot sleeps before
returning, so without the flock transaction both callers see the same empty queue. Cases: lean vs
jbmc at cap 1 (never mixed) and jbmc vs jbmc at a thermal cap of 1 with 3 configured slots.
    python3 heavy_run_race_check.py    # exit 0 iff no case over-admits
"""
import os, re, sys, tempfile, threading, time
from unittest.mock import patch

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import heavy_run as h

real = h._holders


def slow_holders():
    held = real()
    time.sleep(0.3)  # the window in which another caller would decide on the same snapshot
    return held


def race(tools, slots, thermal):
    with tempfile.TemporaryDirectory() as tmp, \
         patch.object(h, "LOCK_DIR", tmp), patch.object(h, "JBMC_SLOTS", slots), \
         patch.object(h, "THERMAL_GUARD", thermal), patch.object(h, "_thermal_cap", return_value=1), \
         patch.object(h, "_admit_ok", return_value=True), patch.object(h, "_holders", side_effect=slow_holders):
        got = [None] * len(tools)
        ts = [threading.Thread(target=lambda i=i, t=t: got.__setitem__(i, h._try_acquire(t))) for i, t in enumerate(tools)]
        for t in ts:
            t.start()
        for t in ts:
            t.join(10)
        return sorted(os.path.basename(g) for g in got if g)


# pgrep excludes itself, but not another thread's identical pgrep process.
# Match every real Gradle launcher, never the command line of a concurrent probe.
with patch.object(h.subprocess, "run") as probe:
    probe.return_value.returncode = 1
    assert not h._gradle_running()
    argv = probe.call_args.args[0]
    pattern = argv[-1]
    assert not re.search(pattern, " ".join(argv))
    for launcher in ("org.gradle.launcher.daemon.bootstrap.GradleDaemon",
                     "org.gradle.wrapper.GradleWrapperMain", "gradle-launcher-8.jar"):
        assert re.search(pattern, "java " + launcher)
    probe.return_value.returncode = 0
    assert h._gradle_running()
print("Gradle probe matches launchers, not other probes: ok")

ok = True
for tools, slots, thermal in [(("lean", "jbmc"), 1, False), (("jbmc", "jbmc"), 3, True)]:
    got = race(tools, slots, thermal)
    good = len(got) == 1
    ok &= good
    print("%-14s slots=%d thermal-cap=%s -> acquired %s: %s" % ("+".join(tools), slots, 1 if thermal else "-", got, "ok" if good else "OVER-ADMITTED"))
sys.exit(0 if ok else 1)
