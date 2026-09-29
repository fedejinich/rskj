# JBMC environment

JBMC runs the real compiled rskj classes (`rskj-core/build/classes/java/main` at the pinned commit).
JBMC 6.11 has no JDK: its models library (`core-models.jar`) covers only part of `java.lang`, and
any method without bytecode silently becomes a nondet stub (`simple_method_stubbing.cpp`; the
`no-body` check never fires for Java). The environment below closes the gaps on the trie paths.
No `co.rsk.trie.*` class, `TrieKeyMapper`, `Uint8/16/24` or `VarInt` is modelled.

Classpath order used by `run-jbmc.sh` (first match wins):

1. `build/harness`: harness classes.
2. `build/models`: hand-written models from `src/`. The header comment of each file says what it
   replaces, why, and why it cannot change trie behaviour.
   - `java.lang.Object`: the models library's `Object` verbatim except `getClass()`. The library
     returns a new `Class` object on every call, so `a.getClass() == b.getClass()` was always false,
     which broke `Uint24.equals` (used at `Trie.java:847`), `Keccak256.equals`, `Trie.equals`,
     `DataWord.equals`, `RskAddress.equals` and `Coin.equals`. The model returns one canonical
     `Class` per listed class (`JbmcCanonicalClasses`). Each listed class is final or has no
     subclass in rskj-core, except `RskAddress`, whose only subclass is the REMASC address
     constant; no harness compares against it. Any other receiver is an assertion failure.
   - `java.lang.Math`: the models library's `Math` verbatim, except that `min`/`max` for int/long
     use the JDK expression instead of `nondet + assume`. Same function, but it keeps concrete
     values concrete; without it, symbolic execution of a concrete two-key trie did not finish.
   - `java.lang.Integer`: the models library's `Integer` verbatim except `min`/`max` (same change and
     reason as `Math`; `DataWord.valueOf` calls `Integer.min`).
   - `java.lang.System`: `arraycopy` for `byte[]` (JDK semantics, including exceptions); `exit` fails
     loudly.
   - `jdk.internal.util.ArraysSupport`: `mismatch(byte[],byte[],int)` (the only piece of the real
     `Arrays.equals(byte[],byte[])` JBMC cannot run) and `newLength` (JDK 17 source, used by
     `ByteArrayOutputStream`).
   - `java.nio.ByteBuffer`: heap buffer with exactly the members the trie code calls. It also
     writes the observation hook `jbmcenv.Observe.maxGetRequest`, which never affects behaviour.
   - `org.slf4j.LoggerFactory`: returns slf4j's real `NOPLogger`.
   - `org.ethereum.crypto.Keccak256Helper`: Keccak-256 as an idealised opaque function, in three modes
     chosen by the harness:
     - consistent collision-free oracle with nondet outputs (default);
     - unconstrained (`consistent = false`): every call returns fresh nondet bytes. This
       over-approximates every hash function, so a SUCCESS holds for any hash; a FAILURE can be
       spurious if the property compares hashes computed separately from equal inputs, so such
       properties use a consistent mode;
     - consistent with concrete distinct outputs (`concreteOutputs = true`). This is one particular
       collision-free assignment, used only where digests are just compared and copied, so the
       result carries over to every collision-free assignment (see the file header).
     At most `MAX_ENTRIES` = 16 distinct inputs per path; exceeding it is an assertion failure.
   - `jbmcenv.MemoryKeyValueDataSource`: in-memory `KeyValueDataSource` with `HashMapDB` semantics,
     backing the real `TrieStoreImpl`/`MultiTrieStore`. Unused bulk methods throw.
   - `jbmcenv.Observe`: observation hooks written by models, read by harnesses.
3. `core-models.jar`, `cprover-api.jar`: JBMC's own models library and `CProver` API.
4. `build/jdk17/java.base`: **real JDK 17 bytecode**, extracted by `run-jbmc.sh` with `jimage` from
   `$JDK17/lib/modules`: every top-level class of `java.util` (for example `Arrays`, `Optional`,
   `Objects`, `HashMap`, `ArrayList`, `Collections`) and `java.util.function`, plus
   `java.lang.Iterable`, `java.io.{ByteArrayOutputStream,OutputStream,IOException,Closeable,Flushable}`
   and `java.nio.Buffer{Over,Under}flowException`. The models library still wins for the classes
   it has (`java.util.Random`, regex).
5. The real rskj classes, then `slf4j-api` (for `Logger`/`NOPLogger`), `bitcoinj-thin` (`VarInt`,
   `Utils`), `guava` (`Preconditions`, used by `Keccak256`), `commons-lang3` (`Pair` and
   `ArrayUtils`, used by `TrieDTO`) and `bclcrypto-jdk15on` (`org.bouncycastle.util.Arrays`, used by
   `DataWord.getData`).

Every run also passes `--java-cp-include-files` so that, of `org.ethereum.datasource`, only the
interfaces `KeyValueDataSource`, `DataSource` and `DataSourceKeyIterator` are loaded. Otherwise
the other implementations (`HashMapDB`, caches, LevelDB/RocksDB) become interface-dispatch targets
on infeasible paths, and symbolic execution slows down by orders of magnitude.

Faithfulness checks, randomized differential tests against the real classes on the JVM
(`models-test/run.sh`):
- `System.arraycopy`, `ArraysSupport.mismatch`/`newLength` and `ByteBuffer` against the JDK.
  The model packages are renamed to `jbmcmodel.*` so both load in one JVM.
- `MemoryKeyValueDataSource` against `HashMapDB` (put/get/delete/close sequences, including
  reference identity of returned values).
- The values `static-values.json` gives `TrieKeyMapper` against the real class's initialised fields.

`Object`/`Math` cannot be loaded next to the real JDK classes, so they are justified by the diff
against the library source (only `getClass`/`min`/`max` change). Keccak is idealised on purpose;
`ModelSanityHarness.keccakOracle` checks the oracle inside JBMC.

## `static-values.json`

Passed to every run as `--static-values`. For each class listed, JBMC replaces the class's static
initialiser by assignments of the listed fields (unlisted static fields keep their default
0/null); classes not listed run their real `<clinit>`.

- `co.rsk.bitcoinj.core.Utils: {}`. Its `<clinit>` builds a charset-encoded header, a guava `Joiner`,
  a guava `BaseEncoding` and `TimeZone.getTimeZone("UTC")`, none of which JBMC can execute.
  `VarInt` only calls `Utils.uint32ToByteArrayLE`, `uint64ToByteArrayLE`, `readUint32` and
  `readInt64`, which contain no `getstatic` and no call (`javap -c`).
- `co.rsk.core.RskAddress: {}`. Its `<clinit>` parses a hex string (`ZERO_ADDRESS`) and builds a
  lambda comparator. The constructor from `byte[]`, `getBytes`, `equals` and `hashCode` read no
  static field; `LENGTH_IN_BYTES` is a compile-time constant.
- `org.ethereum.db.TrieKeyMapper`: `DOMAIN_PREFIX = [00]`, `STORAGE_PREFIX = [00]`,
  `CODE_PREFIX = [80]`, `REMASC_ACCOUNT_KEY_SIZE = 11`. These are exactly the values the real
  initialiser computes (checked by `models-test`). The real `<clinit>` reaches
  `RemascTransaction.REMASC_ADDRESS`, whose class initialisation pulls in `Constants` and
  `BigInteger` arithmetic that JBMC cannot execute.

- `org.ethereum.vm.DataWord`: `ZERO_DATA = 32x00`, `ZERO = DataWord(32x00)`, `ONE = DataWord(0...01)`
  (checked against the real class by `models-test`); `_2_256` and `MAX_VALUE` stay null. The real
  `<clinit>` computes them with `BigInteger`, which JBMC has no model for (the stubs returned null and
  the initialiser threw). The paths checked (`valueOf(byte[32])`, `getData`, `equals`) never read them;
  only DataWord arithmetic does.

## `benign-stubs.json`

Methods JBMC stubbed (no bytecode) that were reviewed and found off every property path, with the
reason. `run-jbmc.sh` marks a result `stub_audit: "none on property path"` only if all its stubs are
listed there; anything else shows up as `REVIEW: ...`.
