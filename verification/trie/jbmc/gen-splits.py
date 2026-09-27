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
# the oracle table (Keccak256Helper.MAX_ENTRIES) is per execution, so checks that hash tries for many
# key pairs are split to one (first key, second key) pair per part; the model is unchanged
ORACLE_UNWINDSET = ("java::org.ethereum.crypto.Keccak256Helper.sameBytes:([B[B)Z.0:129,"
                    "java::array[byte].clone:()Ljava/lang/Object;.0:129")
NODE_OBL = ["TRIE-NODE-01", "TRIE-NODE-03", "TRIE-NODE-04", "TRIE-NODE-05", "TRIE-NODE-06", "TRIE-NODE-07", "TRIE-NODE-08",
            "TRIE-NODE-09", "TRIE-LSH-04", "TRIE-EMB-01", "TRIE-EMB-04", "TRIE-EMB-05", "TRIE-VAL-01", "TRIE-VAL-02", "TRIE-VAL-04",
            "TRIE-SIZE-01", "TRIE-SIZE-02", "TRIE-SER-04"]
def pairs(js):
    """(i, i + 1, j, j + 1) for each first key i and each second key j in js(i); a first key without
    second keys gets the part (i, i + 1, K, K + 1), which runs only what the harness does outside the j loop."""
    return [(i, i + 1, j, j + 1) for i in range(K) for j in (js(i) or [K])]
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
    ("ops-history-independent-hash", "OpsExtraHarness", "historyIndependentHash()", pairs(lambda i: list(range(i + 1, K))),
     ["TRIE-CMP-03"], "keys KEYS[{lo}] and KEYS[{lo2}] inserted in both orders; concrete values; consistent oracle with concrete outputs", {}),
    ("hash-node-hash", "HashHarness", "nodeHash()", pairs(lambda i: list(range(i + 1, K))),
     ["TRIE-HASH-01"], "one-key trie KEYS[{lo}] and, with KEYS[{lo2}] added (33-byte value), the two-key trie; consistent oracle, concrete outputs",
     {"unwind": 100, "unwindset": ORACLE_UNWINDSET}),
    ("store-save-retrieve", "StoreHarness", "saveRetrieve()", pairs(lambda i: list(range(-1, K, 4))),
     ["TRIE-STORE-01"], "first key KEYS[{lo}] (inline and long value), second key KEYS[{lo2}] (-1: none); every probe in KEYS; TrieStoreImpl over the memory KeyValueDataSource model",
     {"unwind": 100, "unwindset": ORACLE_UNWINDSET}),
    ("store-content-addressed", "StoreHarness", "contentAddressedStore()", pairs(lambda i: list(range(-1, K, 4))),
     ["TRIE-STORE-02"], "first key KEYS[{lo}] (inline and long value), second key KEYS[{lo2}] (-1: none): all entries content-addressed; every part also checks the empty trie (keccak(80) -> 40)",
     {"unwind": 100, "unwindset": ORACLE_UNWINDSET}),
    ("orchid-layout", "OrchidHarness", "orchidLayout()", pairs(lambda i: list(range(i + 1, K, 3))),
     ["TRIE-SER-06", "TRIE-SER-04"], "keys KEYS[{lo}] (inline and long value) and KEYS[{lo2}], both secure flags on fresh tries",
     {"unwind": 100, "unwindset": ORACLE_UNWINDSET}),
    ("orchid-parse", "OrchidHarness", "orchidParse()", pairs(lambda i: list(range(i + 1, K, 3))),
     ["TRIE-SER-07"], "keys KEYS[{lo}] (inline and long value, long value retrieved from the store) and KEYS[{lo2}], both secure flags on fresh tries",
     {"unwind": 100, "unwindset": ORACLE_UNWINDSET}),
    ("dto-roundtrip-inline", "DtoHarness", "dtoRoundTripInline()", pairs(lambda i: list(range(i, K, 3))),
     ["TRIE-SER-08"], "keys KEYS[{lo}] and KEYS[{lo2}], inline values", {"unwind": 100, "unwindset": ORACLE_UNWINDSET}),
    # checks over key pairs that exceeded the time limit unsplit: one (first key, second key) pair per part
    ("node-format-2", "NodeHarness", "format2()", pairs(lambda i: [j for j in range(K) if j != i]), NODE_OBL,
     "two-key trie KEYS[{lo}] (value 1 or 33 bytes), KEYS[{lo2}]; independent re-derivation of every message field from the node's accessors",
     {"unwind": 100, "unwindset": ORACLE_UNWINDSET, "bounds": {"keys": "KEYS, 2 keys"}}),
    ("node-format-3", "NodeHarness", "format3()", pairs(lambda i: list(range(i + 1, K))), NODE_OBL,
     "three-key tries KEYS[{lo}], KEYS[{lo2}], every later third key, and their deletions; independent re-derivation of every message field",
     {"unwind": 100, "unwindset": ORACLE_UNWINDSET, "bounds": {"keys": "KEYS, 3 keys + delete"}}),
    ("node-encoding-injective", "NodeHarness", "encodingInjective()", pairs(lambda i: list(range(K))), ["TRIE-SER-02"],
     "two-key trie from KEYS[{lo}] against the one- and two-key tries from KEYS[{lo2}], symbolic 1-byte values",
     {"unwind": 100, "unwindset": ORACLE_UNWINDSET}),
    ("ops-empty-and-null-are-delete", "OpsExtraHarness", "emptyAndNullAreDelete()", pairs(lambda i: list(range(K))), ["TRIE-OPS-06"],
     "keys KEYS[{lo}], KEYS[{lo2}], every deleted key in KEYS: put(k,[]), put(k,null), delete(k) give the same message and lookups",
     {"bounds": {"keys": "KEYS triples"}}),
    ("ops-immutable", "OpsExtraHarness", "immutable()", pairs(lambda i: list(range(K))), ["TRIE-OPS-08"],
     "keys KEYS[{lo}], KEYS[{lo2}] x every key: put/delete/deleteRecursive leave t unchanged; argument and result arrays are copies",
     {"bounds": {"keys": "KEYS pairs x KEYS"}}),
    ("ops-delete-recursive", "OpsExtraHarness", "deleteRecursiveWithValue()", pairs(lambda i: list(range(K))), ["TRIE-OPS-09"],
     "Java behaviour: keys KEYS[{lo}], KEYS[{lo2}], k with a value", {"bounds": {"keys": "KEYS pairs"}}),
    ("ops-canonical-shape", "OpsExtraHarness", "canonicalShape()", pairs(lambda i: list(range(K))), ["TRIE-CMP-01"],
     "one-key trie KEYS[{lo}] and its deletion, then second key KEYS[{lo2}] and every third put or delete",
     {"bounds": {"keys": "KEYS, <=3 ops"}}),
    ("ops-history-independent", "OpsExtraHarness", "historyIndependent()", pairs(lambda i: list(range(i + 1, K))), ["TRIE-CMP-02", "TRIE-CMP-03"],
     "keys KEYS[{lo}], KEYS[{lo2}] in both insertion orders, plus put+delete of every third key: same message at every node",
     {"bounds": {"keys": "KEYS pairs + 1"}}),
    ("hash-binds-map", "HashHarness", "hashBindsMap()", pairs(lambda i: list(range(i, K))), ["TRIE-HASH-03"],
     "one-key tries KEYS[{lo}] and KEYS[{lo2}], symbolic 1-byte values, consistent collision-free oracle",
     {"unwind": 40, "unwindset": ORACLE_UNWINDSET}),
    ("store-saved-entries", "StoreHarness", "savedEntries()", pairs(lambda i: list(range(i + 1, K, 2))), ["TRIE-STORE-03", "TRIE-STORE-04"],
     "3-key tries KEYS[{lo}] (inline and long value), KEYS[{lo2}], and the key 3 places after it in KEYS (mod 12)", {"unwind": 100, "unwindset": ORACLE_UNWINDSET}),
    ("parser-version-not-checked", "ParserHarness", "versionNotChecked()", [(i, i + 1, 1, 2) for i in range(4)] + [(4, 5, 0, 1)], ["TRIE-NODE-02"],
     "reproducer NODE02[{lo}] (4: none) and, for LO2 = 0 only, every version prefix of f 01", {"unwind": 20}),
    ("parser-total", "ParserHarness", "parserTotal()", [(n, n + 1) for n in range(5)], ["TRIE-SER-05"],
     "every message of {lo} symbolic bytes: returns or throws a RuntimeException (termination and exception class only; memory: see parser-huge-lshared)",
     {"unwind": 50, "flags": ["--throw-runtime-exceptions"], "bounds": {"message_bytes": "0..4 symbolic"}}),
]

def main():
    methods, entries = [], []
    for base, cls, call, parts, obl, note, extra in SPLITS:
        for part in parts:
            lo, hi = part[:2]
            two = len(part) >= 4  # second dimension Nondet.LO2/HI2
            three = len(part) == 6  # third dimension Nondet.LO3/HI3
            sfx = "%d_%s" % (lo, str(part[2]).replace("-", "m")) if two else "%d" % lo  # m1: second index -1 (none)
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
            pid = "%02d-%s" % (lo, "none" if part[2] < 0 else "%02d" % part[2]) if two else "%02d" % lo
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
            e.update({k: v.format(**fmt) if isinstance(v, str) else v for k, v in extra.items() if k != "bounds"})
            e["bounds"].update(extra.get("bounds", {}))  # the check's own bounds, then the part's split
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
