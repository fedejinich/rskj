#!/usr/bin/env python3
"""
Generate compliance/fixtures/block.json from an RSK node.

Usage:
  python scripts/gen_block_fixture.py --block latest
  python scripts/gen_block_fixture.py --block 0x7e9be3
  python scripts/gen_block_fixture.py --block 8297532 --rpc-url https://public-node.rsk.co/
"""

import argparse
import json
import pathlib
import sys
import urllib.request

DEFAULT_RPC = "https://public-node.rsk.co/"


def rpc_call(url: str, method: str, params):
    payload = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode()
    req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        data = resp.read()
    result = json.loads(data)
    if "error" in result:
        raise RuntimeError(f"RPC error: {result['error']}")
    return result["result"]


def normalize_block_number(arg: str | None, rpc_url: str) -> int:
    if arg is None or arg.lower() == "latest":
        return int(rpc_call(rpc_url, "eth_blockNumber", []), 16)
    arg = arg.strip()
    if arg.startswith("0x"):
        return int(arg, 16)
    return int(arg)


def build_header_dict(blk: dict) -> dict:
    return {
        "parentHash": blk["parentHash"],
        "unclesHash": blk.get("sha3Uncles") or blk.get("unclesHash") or "0x",
        "coinbase": blk.get("miner") or blk.get("coinbase"),
        "stateRoot": blk["stateRoot"],
        "transactionsRoot": blk["transactionsRoot"],
        "receiptsRoot": blk["receiptsRoot"],
        "logsBloom": blk.get("logsBloom", "0x"),
        "difficulty": blk["difficulty"],
        "number": blk["number"],
        "gasLimit": blk["gasLimit"],
        "gasUsed": blk.get("gasUsed", "0x0"),
        "timestamp": blk["timestamp"],
        "extraData": blk.get("extraData", "0x"),
        "paidFees": blk.get("paidFees", "0x0"),
        "minimumGasPrice": blk.get("minimumGasPrice", "0x0"),
        "uncleCount": hex(len(blk.get("uncles", []) or [])),
        "bitcoinMergedMiningHeader": blk.get("bitcoinMergedMiningHeader", "0x"),
        "bitcoinMergedMiningMerkleProof": blk.get("bitcoinMergedMiningMerkleProof", "0x"),
        "bitcoinMergedMiningCoinbaseTransaction": blk.get("bitcoinMergedMiningCoinbaseTransaction", "0x"),
    }


def main():
    parser = argparse.ArgumentParser(description="Generate compliance block.json from RSK node")
    parser.add_argument("--block", help="Block number (decimal or 0x...) or 'latest'", default="latest")
    parser.add_argument("--rpc-url", help="JSON-RPC endpoint", default=DEFAULT_RPC)
    parser.add_argument(
        "--out",
        help="Output path (defaults to compliance/fixtures/block.json)",
        default=None,
    )
    args = parser.parse_args()

    rpc_url = args.rpc_url
    height = normalize_block_number(args.block, rpc_url)
    blk = rpc_call(rpc_url, "eth_getBlockByNumber", [hex(height), False])
    if blk is None:
        raise RuntimeError(f"Block {height} not found via {rpc_url}")

    header = build_header_dict(blk)
    expected_hash = blk["hash"]

    data = {
        "header": header,
        "expectedHash": expected_hash,
    }

    repo_root = pathlib.Path(__file__).resolve().parent.parent
    default_out = repo_root / "compliance" / "fixtures" / "block.json"
    out_path = pathlib.Path(args.out) if args.out else default_out
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(data, indent=2))

    print(f"Wrote {out_path} for block {height} (hash {expected_hash})")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # pragma: no cover - helper script
        print(f"Error: {exc}", file=sys.stderr)
        sys.exit(1)
