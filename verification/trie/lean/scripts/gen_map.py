#!/usr/bin/env python3
"""Generate lean/obligations-map.json from the obligation theorems.

* theorem names / files / lines: scanned from RskjTrie/Obligations/*.lean (`theorem trie_...`);
* axioms: parsed from `#print axioms` output (Lean), never written by hand;
* hypotheses: the Prop-typed leading binders of each theorem, pretty-printed by Lean (MetaM).

Exits non-zero if an obligation has no theorem, a theorem depends on `sorryAx`, or the audit
file does not compile.  Usage (from verification/trie/lean, after `lake build`):
    python3 scripts/gen_map.py
"""
import json, os, re, subprocess, sys

LEAN = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPEC = os.path.join(LEAN, "..", "spec", "obligations.json")
OUT = os.path.join(LEAN, "obligations-map.json")
AUDIT = os.path.join(LEAN, ".lake", "gen", "ObligationsAudit.lean")
NS = "RskjTrie.Obligations."

# Obligations whose statement is Java's behaviour although the item is marked unclear: the
# counterexample refutes the *other* reading.
PROVED_DESPITE_CX = {"TRIE-KEY-07", "TRIE-PATH-01", "TRIE-PATH-02", "TRIE-VAL-04", "TRIE-HASH-02"}
PARTIAL = {
    "TRIE-OPS-08": "Pure layer: tries are immutable Lean values, so t is unchanged by t.put(...) and its "
                   "get/getHash are functions of its contents. Operational layer (trie_ops_08_operational): the "
                   "receiver whose caches put mutates still represents t, so its getHash/get are unchanged. Not "
                   "modelled: Java array aliasing (mutating the array passed to put or returned by get); objects "
                   "shared between the old and new trie are modelled as copies (MODEL.md, aliasing).",
    "TRIE-SER-05": "Termination and 'returns a node or an error' hold (fromMessage is a total Lean function). "
                   "Memory is not modelled: proved instead that on 50 ff fe ffffff7f the parser computes "
                   "lencoded = 268435456 (the byte[] Java allocates before reading) from a 7-byte input, then "
                   "fails. Error classes (RuntimeException vs others) are not distinguished (errors are strings).",
}
NOTES = {
    "TRIE-KEY-05": "Java stores ONE_BYTE_ARRAY = [0x01] (MutableRepository.java:56,105-109), not 0x00.",
    "TRIE-KEY-10": "Values are stored as given; no type byte is prepended (RSKIP112 text).",
    "TRIE-OPS-09": "Refuted: deleteRecursive(k) removes the subtree iff k itself has a value; a value-less "
                   "branching node exactly at k (the {0100: aa, 0180: bb} root at key 01, confirmed by a Java "
                   "probe) leaves the trie unchanged. trie_ops_09_sanity proves the reproducer_hint run.",
    "TRIE-VAL-03": "Proved for nodes with the value in memory and consistent caches (every node of a reachable "
                   "trie). For a node parsed from a crafted store the property fails: see TRIE-VAL-06.",
    "TRIE-HASH-03": "Ideal-hash hypotheses: H injective (all inputs) and 32-byte outputs; keys shorter than 2^28 "
                    "bytes (shared paths fit Java's int).",
    "TRIE-HASH-04": "Refuted on the crafted store of cases/reproducers.cases (repro-hash-04-*), operational "
                    "layer, decide +kernel with real Keccak-256; outputs equal Java's. The java-behaviour "
                    "theorem proves, via the operational/pure bridge, that for a store written by save the "
                    "hash does not depend on loads (hypotheses: 32-byte H, injective on the trie's messages and "
                    "values, shared paths < 2^31 bits, non-empty trie).",
    "TRIE-SER-01": "Every node with consistent caches whose shared paths are < 2^31 bits; H yields 32 bytes.",
    "TRIE-SER-07": "Shared paths < 2^16 bits (int16 length field); long values need the value in the store.",
    "TRIE-SER-08": "Refuted with Java's own bytes (probe run on the pinned classes): an embedded long-value "
                   "child is re-emitted by TrieDTO.toMessage in its sync form (value inline). The java-behaviour "
                   "theorem only restates the modelled TrieDTO.toMessage (TrieDTO.java:417-470); the agreement "
                   "of TrieDTO fields with Trie.fromMessage is not proved.",
    "TRIE-STORE-01": "Non-empty tries: H injective on the trie's messages and values, 32-byte outputs, keys "
                     "< 2^28 bytes. The empty trie is covered by trie_store_01_empty.",
    "TRIE-STORE-02": "Refuted for the empty root only: H(80) -> 40 is not content-addressed.",
    "TRIE-STORE-06": "Refuted: collect copies nothing (the retrieved root is marked saved); Java probe "
                     "and Lean (decide +kernel) agree: present, present, absent after 3 collects.",
}


def run(cmd, **kw):
    return subprocess.run(cmd, cwd=LEAN, capture_output=True, text=True, **kw)


def main():
    spec = json.load(open(SPEC))
    obs = [o for o in spec["obligations"] if o["stage"] == 1]

    thms = []  # (name, file, line)
    odir = os.path.join(LEAN, "RskjTrie", "Obligations")
    for fn in sorted(os.listdir(odir)):
        rel = os.path.join("RskjTrie", "Obligations", fn)
        for i, line in enumerate(open(os.path.join(odir, fn)), 1):
            m = re.match(r"theorem (trie_\w+)", line)
            if m:
                thms.append((m.group(1), rel, i))

    names = [t[0] for t in thms]
    os.makedirs(os.path.dirname(AUDIT), exist_ok=True)
    with open(AUDIT, "w") as f:
        f.write("import Lean\nimport RskjTrie\nopen Lean Meta\n\n")
        for n in names:
            f.write(f"#print axioms {NS}{n}\n")
        f.write("\n#eval show MetaM Unit from do\n")
        f.write("  for n in [" + ", ".join(f"`{NS}{n}" for n in names) + "] do\n")
        f.write("    let ci ← getConstInfo n\n")
        f.write("    forallTelescope ci.type fun xs _ => do\n")
        f.write("      for x in xs do\n")
        f.write("        let ty ← inferType x\n")
        f.write("        if ← isProp ty then\n")
        f.write("          let s := toString (← ppExpr ty)\n")
        f.write("          IO.println s!\"HYP\\t{n}\\t{s.replace \"\\n\" \" \"}\"\n")
    r = run(["lake", "env", "lean", AUDIT])
    out = r.stdout + r.stderr
    if r.returncode != 0 or re.search(r"^\S+:\d+:\d+: error", out, re.M):
        sys.stderr.write(out)
        sys.exit("FAIL: audit file did not compile")

    axioms = {}
    flat = re.sub(r"\s+", " ", out)
    for m in re.finditer(r"'" + re.escape(NS) + r"(\w+)' depends on axioms: \[([^\]]*)\]", flat):
        axioms[m.group(1)] = [a.strip() for a in m.group(2).split(",") if a.strip()]
    for m in re.finditer(r"'" + re.escape(NS) + r"(\w+)' does not depend on any axioms", flat):
        axioms[m.group(1)] = []
    hyps = {n: [] for n in names}
    for line in out.splitlines():
        if line.startswith("HYP\t"):
            _, n, s = line.split("\t", 2)
            hyps[n[len(NS):]].append(re.sub(r"\s+", " ", s).strip())

    missing = [n for n in names if n not in axioms]
    if missing:
        sys.exit(f"FAIL: no #print axioms output for {missing}")

    by_id, errors = [], []
    for o in obs:
        area, nn = o["id"].split("-")[1:]
        base = f"trie_{area.lower()}_{nn}"
        mine = [t for t in thms if t[0] == base or t[0].startswith(base + "_")]
        if not any(t[0] == base for t in mine):
            errors.append(f"{o['id']}: no theorem {base}")
        # refuted by a counterexample (even if the spec's code reading said "conforms", e.g. OPS-09)
        refuted = any(t[0].endswith("_rskip_counterexample") for t in mine) and o["id"] not in PROVED_DESPITE_CX
        diverging = (o["java"]["reading"] != "conforms" and o["id"] not in PROVED_DESPITE_CX) or refuted
        entries = []
        for n, f, ln in mine:
            ax = axioms[n]
            if n.endswith("_rskip_counterexample"):
                role = "rskip-counterexample"
            elif diverging:
                role = "java-behaviour"
            else:
                role = "obligation"
            status = "failed" if "sorryAx" in ax else "proved"
            if status == "failed":
                errors.append(f"{n} depends on sorryAx")
            entries.append({"name": NS + n, "file": f"lean/{f}", "line": ln, "role": role, "status": status,
                            "hypotheses": hyps[n], "axioms": ax})
        has_cx = any(e["role"] == "rskip-counterexample" and e["status"] == "proved" for e in entries)
        if any(e["status"] == "failed" for e in entries):
            st = "partial"
        elif o["id"] in PARTIAL:
            st = "partial"
        elif has_cx and o["id"] not in PROVED_DESPITE_CX:
            st = "refuted"
        else:
            st = "proved"
        note = PARTIAL.get(o["id"]) or NOTES.get(o["id"], "")
        if o["id"] in PROVED_DESPITE_CX:
            note = (note + " " if note else "") + ("The statement is Java's behaviour and is proved; the "
                    "counterexample refutes the alternative RSKIP reading.")
        by_id.append({"id": o["id"], "theorems": entries, "lean_status": st, "note": note})

    json.dump(by_id, open(OUT, "w"), indent=1, ensure_ascii=False)
    open(OUT, "a").write("\n")
    counts = {}
    for e in by_id:
        a = e["id"].split("-")[1]
        counts.setdefault(a, {}).setdefault(e["lean_status"], 0)
        counts[a][e["lean_status"]] += 1
    allax = sorted({a for e in by_id for t in e["theorems"] for a in t["axioms"]})
    print(f"{len(by_id)} obligations, {len(thms)} theorems; axioms used: {allax}")
    for a, c in counts.items():
        print(f"  {a}: {c}")
    if errors:
        sys.exit("FAIL:\n  " + "\n  ".join(errors))


if __name__ == "__main__":
    main()
