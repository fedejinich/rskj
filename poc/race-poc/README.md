# RSKIP-144 Race Condition PoC

## Overview

This PoC reproduces the RSKIP-144 race condition where duplicate transactions
(with the same calldata but different senders) are scheduled as parallel even
though the success path calls a disallowed precompile (Bridge). During actual
parallel execution, a duplicate can reach the Bridge precompile and the block
is invalidated.

It provides two variants in the same contract:

- `acceptSimple(bytes32)` calls the Bridge precompile using
  `getUnionBridgeLockingCap()`.
- `acceptUnion(bytes32,uint256)` calls `requestUnionBridgeRbtc(uint256)` and
  reverts if the return code is non-zero (mirrors `acceptPegin`).
- `acceptUnionPrecheck(bytes32,uint256)` calls a Bridge precompile before the
  status check to force sequentiality, then proceeds like `acceptUnion`.

A third command (`cargo run -- verify`) replays the race and fails if an
`INVALID_BLOCK` appears, so it can be used as a regression check after a fix.

## Requirements

- Java (for running RSKJ)
- Foundry (`forge`, `cast`)
- Rust + Cargo (for the PoC runner)

## Build + Run RSKJ (regtest)

RSKIP-144 is disabled by default in regtest, so this PoC uses a custom config
that enables it and sets the database directory inside the repo.

Build the fat jar:

```bash
./gradlew rskj-core:fatJar
```

Start the node (logs go to `poc/race-poc/logs/rskj.log`):

```bash
cd poc/race-poc
cargo run -- node_start
```

Stop the node and clear the regtest db/mempool:

```bash
cd poc/race-poc
cargo run -- node_stop
```

## PoC A: Simple Bridge call

```bash
cd poc/race-poc
cargo run -- simple
```

Expected: RSKJ logs show `invalid tx` / `INVALID_BLOCK` in
`poc/race-poc/logs/rskj.log`.

## PoC B: requestUnionBridgeRbtc

This variant sets the Union Bridge contract address to the PoC contract using
an authorized regtest key (seed: `changeUnionBridgeContractAddressAuthorizer`).
The script derives and funds that key automatically.

```bash
cd poc/race-poc
cargo run -- union
```

Expected: same `invalid tx` / `INVALID_BLOCK` behavior.

## PoC C: precheck (forced Bridge call)

This variant does a Bridge call **before** checking the status, to mimic the
`acceptPegin` ordering and force the tx into the sequential path.

```bash
cd poc/race-poc
cargo run -- precheck
```

Expected: use this to see if the workaround prevents invalid blocks.

## PoC D: Verify Fix

This script replays the race and **fails** if an invalid block is detected.
It should fail on the current buggy behavior and pass once the fix is applied.

```bash
cd poc/race-poc
cargo run -- verify
```

## Notes

- Funding uses the pre-mined `cow` account (privkey is embedded in the runner).
- The four senders are derived deterministically from `poc-sender-1..4` seeds.
- If you want to reuse a deployed contract, set `CONTRACT_ADDR=0x...`.
- For log inspection, set `LOG_FILE=/path/to/rsk.log` if the runner cannot find it.
- The race depends on multiple duplicate txs being included in the same block.
  The custom config sets `miner.client.delayBetweenBlocks = 5 seconds` to make
  that window larger.
- The precheck uses `getBtcBlockchainBestChainHeight()` as a stand-in for
  `getBtcTransactionConfirmations`, which requires full SPV inputs.
