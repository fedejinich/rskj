#!/usr/bin/env python3
"""Generates harness/SplitHarness.java and the split-* entries of harnesses.json.

A check too heavy for the per-harness time limit is split into parts that each fix Nondet.LO/HI to a
slice of its outermost enumeration (first key of Nondet.KEYS, leading-zero count, window length), and
optionally Nondet.LO2/HI2 to a slice of a second one (4-tuple parts).
The union of the parts is the original check; the unsplit entry is removed. Idempotent: rerun after
editing SPLITS."""
import json, os
HERE = os.path.dirname(os.path.abspath(__file__))
# (base id, class, call, parts [(lo, hi)], obligations, note, extra entry fields)
K = 12
# keyslice (prefix length, child length) parts split further by prefix offset (300 s timeout otherwise)
KEYSLICE_BY_OFFSET = {(8, 5)}
# serialized tries exceed JBMC's default field-sensitivity array size (64), so reads from a message
# become symbolic and every length parsed from it leaves the copy loops at their full bound; tracking
# arrays up to 512 elements element-wise only makes symbolic execution more precise (no semantic change)
FIELD_SENSITIVE = {"flags": ["--max-field-sensitivity-array-size", "512"]}
KEY_UNWINDSET = ",".join([
    "java::org.ethereum.crypto.Keccak256Helper.sameBytes:([B[B)Z.0:33",
    "java::java.lang.System.arraycopy:(Ljava/lang/Object;ILjava/lang/Object;II)V.0:76",
    "java::java.lang.System.arraycopy:(Ljava/lang/Object;ILjava/lang/Object;II)V.1:76"])
SPLITS = [
    ("trie-put-get", "TrieOpsHarness", "putGet()", [(i, i + 1) for i in range(K)],
     ["TRIE-OPS-02", "TRIE-OPS-03", "TRIE-OPS-07"], "first key = KEYS[{lo}]; all second keys and probes in KEYS; first value 1 or 33 bytes", {}),
    ("trie-put-delete-get", "TrieOpsHarness", "putDeleteGet(org.cprover.CProver.nondetBoolean())",
     [(i, i + 1, l, l + 1, m, m + 1) for i in range(K) for l in range(K) for m in range(2)],
     ["TRIE-OPS-04", "TRIE-OPS-05", "TRIE-OPS-08"],
     "first key = KEYS[{lo}], deleted key = KEYS[{lo2}]; all second keys and probes in KEYS; deletion via {lo3} (0 = delete(k), 1 = put(k, empty))", FIELD_SENSITIVE),
    ("trie-empty-value-is-delete", "TrieOpsHarness", "emptyValueIsDelete()", [(i, i + 1, j, j + 1) for i in range(K) for j in range(K)],
     ["TRIE-OPS-06"], "first key = KEYS[{lo}], second key = KEYS[{lo2}]; every deleted key in KEYS; first value 1 or 33 bytes; identical serialization", FIELD_SENSITIVE),
    ("parser-tree-size-varint", "ParserHarness", "treeSizeVarInt()", [(c, c + 1) for c in range(4)],
     ["TRIE-VARINT-02"], "VarInt size class {lo} (unsigned [0,253), [253,2^16), [2^16,2^32), [2^32,2^64) -> 1, 3, 5, 9 bytes); every long in it",
     {"unwind": 20}),
    ("trie-message-roundtrip", "TrieSerializationHarness", "roundTrip()",
     [(i, i + 1, j, j + 1) for i in range(K) for j in (range(i + 1, K) if i + 1 < K else [K])],
     ["TRIE-SER-01"], "first key = KEYS[{lo}], second key = KEYS[{lo2}] (none for the last first key: the one-key trie only); the one-key trie and every third key after the second, root and both children", FIELD_SENSITIVE),
    ("keyslice-rebuild-shared-path", "TrieKeySliceHarness", "rebuildSharedPathSemantics(org.cprover.CProver.nondetInt(), org.cprover.CProver.nondetInt(), org.cprover.CProver.nondetInt(), org.cprover.CProver.nondetInt(), org.cprover.CProver.nondetBoolean())",
     # (lo, hi, lo2, hi2) parts; a part that exceeded the time limit is split further by the prefix
     # offset (lo3, hi3), one part per offset 0..12-lo
     [p for i in range(13) for j in range(13) for p in
      ([(i, i + 1, j, j + 1, o, o + 1) for o in range(13 - i)] if (i, j) in KEYSLICE_BY_OFFSET else [(i, i + 1, j, j + 1)])],
     ["TRIE-PATH-05"],
     "length of the prefix slice = {lo}, of the child slice = {lo2}; every offset of both windows in 12 symbolic backing bits",
     # copies in rebuildSharedPath move at most lo+1+lo2 elements, so the System.arraycopy model loops
     # get lo+lo2+2 iterations instead of the default 130 (still checked by --unwinding-assertions)
     {"unwind": 28, "unwindset": "java::java.lang.System.arraycopy:(Ljava/lang/Object;ILjava/lang/Object;II)V.0:{ac},"
                                 "java::java.lang.System.arraycopy:(Ljava/lang/Object;ILjava/lang/Object;II)V.1:{ac}"}),
    ("key-strip-leading-zeroes", "KeyHarness", "stripLeadingZeroes()", [(i, min(i + 3, 33)) for i in range(0, 33, 3)],
     ["TRIE-KEY-08"], "leading zero bytes {lo}..{hi_incl}; first non-zero byte 01/80/ff; other bytes symbolic", {"unwind": 80}),
    ("key-storage-key", "KeyHarness", "storageKey()", [(i, i + 1, f, f + 1) for i in range(5) for f in range(3)],
     ["TRIE-KEY-06", "TRIE-KEY-08"], "leading zero bytes = ZEROS[{lo}] (0,1,16,31,32); first non-zero byte FIRST_BYTES[{lo2}] (01/80/ff); every address",
     # keccak inputs here are at most 32 bytes and copied arrays at most 74, so the oracle's input
     # comparison gets 33 iterations and the arraycopy model loops 76 instead of 65/130 (still
     # checked by --unwinding-assertions)
     {"unwind": 80, "unwindset": KEY_UNWINDSET}),
    ("key-injective", "KeyHarness", "injective()", [(i, i + 1, j, j + 1) for i in range(5) for j in range(5)],
     ["TRIE-KEY-09"], "first word with ZEROS[{lo}] leading zeros, second with ZEROS[{lo2}]; first non-zero byte 80; every address pair",
     {"unwind": 80, "unwindset": KEY_UNWINDSET}),
]

def main():
    methods, entries = [], []
    for base, cls, call, parts, obl, note, extra in SPLITS:
        for part in parts:
            lo, hi = part[:2]
            two = len(part) >= 4  # second dimension Nondet.LO2/HI2
            three = len(part) == 6  # third dimension Nondet.LO3/HI3
            sfx = "%d_%d" % (lo, part[2]) if two else "%d" % lo
            if three:
                sfx += "_o%d" % part[4]
            m = "%s_%s" % (base.replace("-", "_"), sfx)
            sets = "        Nondet.LO = %d;\n        Nondet.HI = %d;\n" % (lo, hi)
            if two:
                sets += "        Nondet.LO2 = %d;\n        Nondet.HI2 = %d;\n" % part[2:4]
            if three:
                sets += "        Nondet.LO3 = %d;\n        Nondet.HI3 = %d;\n" % part[4:6]
            methods.append("    public static void %s() {\n%s        %s.%s;\n    }\n" % (m, sets, cls, call))
            bnd = "%s.%s with Nondet.LO=%d, HI=%d" % (cls, call.split("(")[0], lo, hi)
            if two:
                bnd += ", LO2=%d, HI2=%d" % part[2:4]
            if three:
                bnd += ", LO3=%d, HI3=%d" % part[4:6]
            pid = "%02d-%02d" % (lo, part[2]) if two else "%02d" % lo
            if three:
                pid += "-o%02d" % part[4]
            e = {"id": "%s-part%s" % (base, pid), "obligations": obl,
                 "role": "property", "class": "SplitHarness",
                 "method": m, "unwind": 40, "expect": "SUCCESS", "split_of": base,
                 "note": "split part of %s: %s" % (base, note.format(lo=lo, hi_incl=hi - 1, lo2=part[2] if two else "",
                                                               lo3=part[4] if three else "")
                                                   + ("; prefix offset = %d" % part[4] if three and "{lo3}" not in note else "")),
                 "bounds": {"split": bnd}}
            fmt = dict(lo=lo, hi=hi, lo2=part[2] if two else 0, ac=lo + (part[2] if two else 0) + 2)
            e.update({k: v.format(**fmt) if isinstance(v, str) else v for k, v in extra.items()})
            entries.append(e)
    src = ("/** Generated by gen-splits.py: split parts of checks too heavy for one run (see Nondet.LO/HI). */\n"
           "public class SplitHarness {\n" + "\n".join(methods) + "}\n")
    open(os.path.join(HERE, "harness", "SplitHarness.java"), "w").write(src)
    p = os.path.join(HERE, "harnesses.json")
    h = json.load(open(p))
    bases = {s[0] for s in SPLITS}
    kept, pos = [], None
    for e in h["harnesses"]:
        if e.get("split_of") in bases:
            continue
        if e["id"] in bases:
            pos = len(kept) if pos is None else pos
            kept.append({"__split__": e["id"]})
            continue
        kept.append(e)
    out = []
    for e in kept:
        if "__split__" in e:
            out += [x for x in entries if x["split_of"] == e["__split__"]]
        else:
            out.append(e)
    have = {x.get("split_of") for x in out}
    out += [x for x in entries if x["split_of"] not in have]
    h["harnesses"] = out
    json.dump(h, open(p, "w"), indent=1)
    print("%d split entries for %d checks" % (len(entries), len(SPLITS)))

main()
