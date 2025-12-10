#!/usr/bin/env python3
"""
Generate compliance test fixtures (block.json and blockhash-mini-chain.json) from an RSK node.

Subcommands:
  block     -> writes compliance/fixtures/block.json for a given block (default: latest)
  minichain -> writes compliance/fixtures/blockhash-mini-chain.json for the last N blocks (default: 10)

Examples:
  python scripts/gen_compliance_test_data.py block --block latest
  python scripts/gen_compliance_test_data.py block --block 0x7e9be3
  python scripts/gen_compliance_test_data.py minichain --count 10
  python scripts/gen_compliance_test_data.py minichain --start 0x7e9c3c --count 5
"""

import argparse
import json
import pathlib
import sys
import urllib.request

DEFAULT_RPC = "https://public-node.rsk.co/"
REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent


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


def write_block_fixture(args):
    rpc_url = args.rpc_url
    height = normalize_block_number(args.block, rpc_url)
    blk = rpc_call(rpc_url, "eth_getBlockByNumber", [hex(height), False])
    if blk is None:
        raise RuntimeError(f"Block {height} not found via {rpc_url}")

    header = build_header_dict(blk)
    expected_hash = blk["hash"]
    data = {"header": header, "expectedHash": expected_hash}

    default_out = REPO_ROOT / "compliance" / "fixtures" / "block.json"
    out_path = pathlib.Path(args.out) if args.out else default_out
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(data, indent=2))
    print(f"Wrote {out_path} for block {height} (hash {expected_hash})")


def write_minichain_fixture(args):
    rpc_url = args.rpc_url
    start_height = normalize_block_number(args.start, rpc_url)
    count = max(1, args.count)

    chain = []
    for h in range(start_height, start_height - count, -1):
        blk = rpc_call(rpc_url, "eth_getBlockByNumber", [hex(h), False])
        if blk is None:
            raise RuntimeError(f"Block {h} not found via {rpc_url}")
        chain.append({
            "tag": f"height-{int(blk['number'], 16)}",
            "header": build_header_dict(blk),
            "expectedHash": blk["hash"],
            "uncles": blk.get("uncles", []) or [],
        })

    data = {"chain": chain}
    default_out = REPO_ROOT / "compliance" / "fixtures" / "blockhash-mini-chain.json"
    out_path = pathlib.Path(args.out) if args.out else default_out
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(data, indent=2))
    print(f"Wrote {out_path} with {len(chain)} blocks starting at {start_height}")


def main():
    parser = argparse.ArgumentParser(description="Generate compliance test data from RSK node")
    subparsers = parser.add_subparsers(dest="command", required=True)

    p_block = subparsers.add_parser("block", help="Generate block.json fixture")
    p_block.add_argument("--block", default="latest", help="Block number (decimal or 0x...) or 'latest'")
    p_block.add_argument("--rpc-url", default=DEFAULT_RPC, help="JSON-RPC endpoint")
    p_block.add_argument("--out", default=None, help="Output path (default compliance/fixtures/block.json)")
    p_block.set_defaults(func=write_block_fixture)

    p_chain = subparsers.add_parser("minichain", help="Generate blockhash-mini-chain.json fixture")
    p_chain.add_argument("--start", default="latest", help="Starting block (decimal or 0x...), defaults to latest")
    p_chain.add_argument("--count", type=int, default=10, help="How many blocks to include (default 10)")
    p_chain.add_argument("--rpc-url", default=DEFAULT_RPC, help="JSON-RPC endpoint")
    p_chain.add_argument("--out", default=None, help="Output path (default compliance/fixtures/blockhash-mini-chain.json)")
    p_chain.set_defaults(func=write_minichain_fixture)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # pragma: no cover - helper script
        print(f"Error: {exc}", file=sys.stderr)
        sys.exit(1)
