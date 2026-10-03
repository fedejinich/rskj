#!/usr/bin/env python3
"""Render obligations.md from obligations.json (the JSON is the source of truth).
Usage: python3 verification/trie/spec/render_md.py"""
import json, os

HERE = os.path.dirname(os.path.abspath(__file__))
doc = json.load(open(os.path.join(HERE, "obligations.json")))
obs = doc["obligations"]

# every quoted line must appear verbatim in the cited RSKIP files (the "..." separators are ours)
ips = os.path.join(doc["rskips_clone"], "IPs")
if os.path.isdir(ips):
    import re
    for o in obs:
        cited = set(re.findall(r"RSKIP(\d+)", o["rskip"] + " " + o["file"] + " " + o["lines"]))
        text = "\n".join(open(os.path.join(ips, f"RSKIP{n}.md"), encoding="utf-8").read() for n in cited)
        for line in o["quote"].split("\n"):
            assert line in ("", "...") or line.strip() in text, (o["id"], line)

AREAS = [("KEY", "Key mapping"), ("PATH", "Bit-path encoding"), ("LSH", "Shared-prefix length compression"),
         ("VARINT", "VarInt"), ("NODE", "Node format"), ("EMB", "Embedded nodes"), ("VAL", "Long values"),
         ("OPS", "put / get / delete"), ("CMP", "Compression and canonical shape"), ("HASH", "Node and root hash"),
         ("SER", "Serialization and parser"), ("SIZE", "treeSize / childrenSize"), ("STORE", "TrieStore")]


def cell(s):
    return s.replace("|", "\\|").replace("\n", " ")


def cite(o):
    return f"`{o['file']}:{o['lines']}`"


JAVA_ROOT = "rskj-core/src/main/java/"


def java(o):
    # the disclaimer and the source root are stated once in the intro
    refs = ", ".join(f"`{r[len(JAVA_ROOT):]}`" if r.startswith(JAVA_ROOT) else r for r in o["java"]["refs"])
    note = o["java"]["note"].replace("Code reading only, not a verification verdict.", "").strip()
    return f"**{o['java']['reading']}**{': ' + note if note else ''} ({refs})"


out = []
w = out.append
w("# Trie obligations from the RSKIPs (Stage 1)\n")
w("Generated from `obligations.json` by `render_md.py`; edit the JSON, not this file.\n")
w("## Sources\n")
w(f"- RSKIPs: read-only clone `{doc['rskips_clone']}` at `{doc['rskips_commit']}`.")
w(f"- rskj: `{doc['rskj_commit']}`; Java cited as `path:line` at that commit. In the tables below, paths are relative to"
  f" `{JAVA_ROOT}` (the JSON keeps full repo-relative paths), and every Java reading is a code reading, not a verification verdict.")
w("- `co.rsk.bitcoinj.core.VarInt` from `bitcoinj-thin-0.14.4-rsk-18.jar` (on `rskj_classpath`), read with `javap -c`.")
w("- `rskip-index.md` lists every RSKIP read and why it is in or out of scope.\n")
w("## RSKIPs used\n")
w("- **In scope:** RSKIP107 (node format, the core of Stage 1), RSKIP108 (key mapping), RSKIP24 (design goals, immutability),"
  " RSKIP16 (Unitrie layout, field selectors), RSKIP64 (epoch stores, only for `MultiTrieStore`)."
  " RSKIP240 is cited only for its node-version numbering and the 32-byte threshold; RSKIP242/244 only for the 44-byte"
  " embedding threshold; RSKIP112 is recorded as one informational obligation.")
w("- **Out of scope:** gas, rent, parallel execution and code merkleization proposals (RSKIP109, 113, 144, 173, 239, 240's rent"
  " mechanics, 243, 244's gas); none changes the Stage 1 trie code at this commit. RSKIP126 has no file in the clone; its"
  " activation is still the evidence that the RSKIP107 hash is consensus.\n")
w("## Applicability\n")
for k, v in doc["applicability_notes"].items():
    w(f"- **{k}:** {v}")
w("")
w("## Conventions\n")
for k, v in doc["conventions"].items():
    w(f"- **{k}:** {v}")
w("- **kind:** `requirement` = the RSKIP states it (quoted); `derived` = implied by the quoted text; `ambiguity` = the text"
  " is contradictory, underspecified or silent, and the statement records the reading Java implements.\n")
counts = {}
for o in obs:
    counts.setdefault(o["java"]["reading"], 0)
    counts[o["java"]["reading"]] += 1
s1 = [o for o in obs if o["stage"] == 1]
w(f"{len(s1)} Stage 1 obligations and {len(obs) - len(s1)} Stage 2 obligations. Java readings across all of them:"
  f" {counts.get('conforms', 0)} conforms, {counts.get('diverges', 0)} diverges, {counts.get('unclear', 0)} unclear.\n")

for area, title in AREAS:
    rows = [o for o in s1 if o["area"] == area]
    if not rows:
        continue
    w(f"## {area}: {title}\n")
    w("| ID | Kind | Statement | Citation | Java reading |")
    w("| --- | --- | --- | --- | --- |")
    for o in rows:
        w(f"| {o['id']} | {o['kind']} | **{cell(o['title'])}.** {cell(o['statement'])} | {cite(o)} | {cell(java(o))} |")
    w("")

w("## Ambiguities and suspected divergences\n")
w("Every obligation of kind `ambiguity` or with Java reading `diverges`/`unclear`, with its reproducer hint."
  " Hints marked *Sanity run* were run against the real classes by `sanity/ReproHints.jsh`"
  " (output: `sanity/ReproHints.out`). That run only confirms the hint behaves as described; it is not a verification result.\n")
for o in obs:
    if o["stage"] != 1 or (o["kind"] != "ambiguity" and o["java"]["reading"] == "conforms"):
        continue
    w(f"### {o['id']}: {o['title']} ({o['kind']}, Java {o['java']['reading']})\n")
    w(f"- RSKIP: {cite(o)} ({o['section']})")
    w("- Quote:\n")
    w("  > " + o["quote"].replace("\n", "\n  > "))
    w("")
    w(f"- Statement: {o['statement']}")
    w(f"- Java: {java(o)}")
    if o["reproducer_hint"]:
        w(f"- Reproducer: {o['reproducer_hint']}")
    if o["notes"]:
        w(f"- Notes: {o['notes']}")
    w("")

w("## Stage 2 (follow-up)\n")
w("| ID | Kind | Statement | Citation | Java reading |")
w("| --- | --- | --- | --- | --- |")
for o in obs:
    if o["stage"] == 2:
        w(f"| {o['id']} | {o['kind']} | **{cell(o['title'])}.** {cell(o['statement'])} | {cite(o)} | {cell(java(o))} |")
w("")
w("RSKIP92 (Adopted, \"Merkle Proof serialization\") is about the Bitcoin merged-mining coinbase proof, not Unitrie proofs; it is not used here.")

open(os.path.join(HERE, "obligations.md"), "w").write("\n".join(out) + "\n")
print(f"wrote obligations.md ({len(obs)} obligations)")
