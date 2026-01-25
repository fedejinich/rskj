use anyhow::{bail, Context, Result};
use std::fs;
use std::path::PathBuf;
use std::process::{Command, Output, Stdio};
use std::thread;
use std::time::Duration;

use crate::cli::Cli;
use crate::logs::{capture_log_offsets, fmt_log_files, read_log_tails, resolve_log_files};
use crate::util::{
    ensure_cmd, format_output, log_step, root_dir, run_cmd, run_cmd_allow_failure,
};

const BRIDGE_ADDR: &str = "0x0000000000000000000000000000000001000006";
const COW_PRIVKEY: &str =
    "0xc85ef7d79691fe79573b1a7064c19c1a9819ebdbd1faaab1a8ec92344438aaf4";
const AUTH_SEED: &str = "changeUnionBridgeContractAddressAuthorizer";
const DEFAULT_GAS_PRICE: &str = "1";
const RETRY_GAS_PRICE: &str = "2";

struct PocContext {
    root_dir: PathBuf,
    rpc_url: String,
    contract_addr_override: Option<String>,
    race_id: String,
    fund_amount_wei: String,
    auth_privkey: String,
    auth_addr: String,
}

pub fn run_simple(cli: &Cli) -> Result<()> {
    ensure_cmd("cast", Some("--version"))?;
    ensure_cmd("forge", Some("--version"))?;
    let ctx = build_context(cli)?;
    let contract_addr = get_contract_addr(&ctx)?;

    println!("contract: {}", contract_addr);
    println!("race id: {}", ctx.race_id);

    fund_senders(&ctx)?;
    log_step("reset + register");
    reset_contract(&ctx, &contract_addr);
    register_contract_with_retry(&ctx, &contract_addr)?;
    send_accepts_with_retry(
        &ctx,
        &contract_addr,
        "acceptSimple(bytes32)",
        &[ctx.race_id.clone()],
    )?;
    Ok(())
}

pub fn run_union(cli: &Cli, amount_wei: &str) -> Result<()> {
    ensure_cmd("cast", Some("--version"))?;
    ensure_cmd("forge", Some("--version"))?;
    let ctx = build_context(cli)?;
    let contract_addr = get_contract_addr(&ctx)?;

    println!("contract: {}", contract_addr);
    println!("race id: {}", ctx.race_id);
    println!("auth addr: {}", ctx.auth_addr);

    fund_senders(&ctx)?;
    fund_auth(&ctx)?;
    set_union_bridge(&ctx, &contract_addr)?;
    log_step("reset + register");
    reset_contract(&ctx, &contract_addr);
    register_contract_with_retry(&ctx, &contract_addr)?;
    send_accepts_with_retry(
        &ctx,
        &contract_addr,
        "acceptUnion(bytes32,uint256)",
        &[ctx.race_id.clone(), amount_wei.to_string()],
    )?;
    Ok(())
}

pub fn run_precheck(cli: &Cli, amount_wei: &str) -> Result<()> {
    ensure_cmd("cast", Some("--version"))?;
    ensure_cmd("forge", Some("--version"))?;
    let ctx = build_context(cli)?;
    let contract_addr = get_contract_addr(&ctx)?;

    println!("contract: {}", contract_addr);
    println!("race id: {}", ctx.race_id);
    println!("auth addr: {}", ctx.auth_addr);

    fund_senders(&ctx)?;
    fund_auth(&ctx)?;
    set_union_bridge(&ctx, &contract_addr)?;
    log_step("reset + register");
    reset_contract(&ctx, &contract_addr);
    register_contract_with_retry(&ctx, &contract_addr)?;
    send_accepts_with_retry(
        &ctx,
        &contract_addr,
        "acceptUnionPrecheck(bytes32,uint256)",
        &[ctx.race_id.clone(), amount_wei.to_string()],
    )?;
    Ok(())
}

pub fn run_verify(cli: &Cli, sleep_secs: u64, log_file: Option<&PathBuf>) -> Result<()> {
    ensure_cmd("cast", Some("--version"))?;
    ensure_cmd("forge", Some("--version"))?;
    let ctx = build_context(cli)?;
    let contract_addr = get_contract_addr(&ctx)?;
    let log_files = resolve_log_files(&ctx.root_dir, log_file)?;
    log_step(&format!("watch logs ({})", fmt_log_files(&log_files)));
    let offsets = capture_log_offsets(&log_files)?;

    println!("contract: {}", contract_addr);
    println!("race id: {}", ctx.race_id);

    thread::sleep(Duration::from_secs(sleep_secs));
    let tail = read_log_tails(&offsets)?;
    if tail.contains("INVALID_BLOCK") || tail.contains("invalid tx") {
        bail!("race still present: invalid block detected");
    }

    println!("no invalid block detected");
    Ok(())
}

fn register_contract_with_retry(ctx: &PocContext, contract_addr: &str) -> Result<()> {
    match register_contract(ctx, contract_addr) {
        Ok(()) => Ok(()),
        Err(err) if is_gas_price_bump_error(&err) => {
            log_step(&format!(
                "register bump detected, retrying with gas price {}",
                RETRY_GAS_PRICE
            ));
            match register_contract_with_gas_price(ctx, contract_addr, RETRY_GAS_PRICE) {
                Ok(()) => Ok(()),
                Err(err) => {
                    log_step(&format!(
                        "register bump retry failed: {}; continuing",
                        err
                    ));
                    Ok(())
                }
            }
        }
        Err(err) => Err(err),
    }
}

fn send_accepts_with_retry(
    ctx: &PocContext,
    contract_addr: &str,
    method_sig: &str,
    args: &[String],
) -> Result<()> {
    match send_accepts(ctx, contract_addr, method_sig, args) {
        Ok(()) => Ok(()),
        Err(err) if is_gas_price_bump_error(&err) => {
            log_step(&format!(
                "accepts bump detected, retrying with gas price {}",
                RETRY_GAS_PRICE
            ));
            match send_accepts_with_gas_price(ctx, contract_addr, method_sig, args, RETRY_GAS_PRICE)
            {
                Ok(()) => Ok(()),
                Err(err) => {
                    log_step(&format!(
                        "accepts bump retry failed: {}; continuing",
                        err
                    ));
                    Ok(())
                }
            }
        }
        Err(err) => Err(err),
    }
}

fn is_gas_price_bump_error(err: &anyhow::Error) -> bool {
    err.to_string()
        .to_lowercase()
        .contains("gas price not enough to bump")
}

fn build_context(cli: &Cli) -> Result<PocContext> {
    let root_dir = root_dir();
    let race_id = cast_keccak(&cli.id_seed)?;
    let auth_privkey = cast_keccak(AUTH_SEED)?;
    let auth_addr = cast_wallet_address(&auth_privkey)?;

    Ok(PocContext {
        root_dir,
        rpc_url: cli.rpc_url.clone(),
        contract_addr_override: cli.contract_addr.clone(),
        race_id,
        fund_amount_wei: cli.fund_amount_wei.clone(),
        auth_privkey,
        auth_addr,
    })
}

fn fund_senders(ctx: &PocContext) -> Result<()> {
    log_step("fund 4 senders");
    let min_wei = parse_wei(&ctx.fund_amount_wei)?;
    for i in 1..=4 {
        let addr = sender_addr(i)?;
        if has_min_balance(&ctx.rpc_url, &addr, min_wei)? {
            continue;
        }
        let args = vec!["--value".to_string(), ctx.fund_amount_wei.clone(), addr];
        cast_send_allow_pending_duplicate_retry(&ctx.rpc_url, COW_PRIVKEY, &args)?;
    }
    Ok(())
}

fn fund_auth(ctx: &PocContext) -> Result<()> {
    log_step("fund auth addr");
    let min_wei = parse_wei(&ctx.fund_amount_wei)?;
    if has_min_balance(&ctx.rpc_url, &ctx.auth_addr, min_wei)? {
        return Ok(());
    }
    let args = vec![
        "--value".to_string(),
        ctx.fund_amount_wei.clone(),
        ctx.auth_addr.clone(),
    ];
    cast_send_allow_pending_duplicate_retry(&ctx.rpc_url, COW_PRIVKEY, &args)?;
    Ok(())
}

fn set_union_bridge(ctx: &PocContext, contract_addr: &str) -> Result<()> {
    log_step("set union bridge addr");
    let args = vec![
        "--gas-limit".to_string(),
        "500000".to_string(),
        BRIDGE_ADDR.to_string(),
        "setUnionBridgeContractAddressForTestnet(address)".to_string(),
        contract_addr.to_string(),
    ];
    cast_send(&ctx.rpc_url, &ctx.auth_privkey, &args)?;
    Ok(())
}

fn reset_contract(ctx: &PocContext, contract_addr: &str) {
    let args = vec![
        contract_addr.to_string(),
        "reset(bytes32)".to_string(),
        ctx.race_id.clone(),
    ];
    let _ = cast_send_allow_failure(&ctx.rpc_url, COW_PRIVKEY, &args);
}

fn register_contract(ctx: &PocContext, contract_addr: &str) -> Result<()> {
    register_contract_with_gas_price(ctx, contract_addr, DEFAULT_GAS_PRICE)
}

fn register_contract_with_gas_price(
    ctx: &PocContext,
    contract_addr: &str,
    gas_price: &str,
) -> Result<()> {
    let args = vec![
        contract_addr.to_string(),
        "register(bytes32)".to_string(),
        ctx.race_id.clone(),
    ];
    cast_send_with_gas_price(&ctx.rpc_url, COW_PRIVKEY, &args, gas_price)?;
    Ok(())
}

fn send_accepts(
    ctx: &PocContext,
    contract_addr: &str,
    method_sig: &str,
    args: &[String],
) -> Result<()> {
    send_accepts_with_gas_price(ctx, contract_addr, method_sig, args, DEFAULT_GAS_PRICE)
}

fn send_accepts_with_gas_price(
    ctx: &PocContext,
    contract_addr: &str,
    method_sig: &str,
    args: &[String],
    gas_price: &str,
) -> Result<()> {
    log_step(&format!("send 4 tx ({})", method_sig));
    let mut children = Vec::new();
    for i in 1..=4 {
        let pk = sender_privkey(i)?;
        let mut call_args = vec![
            "--gas-limit".to_string(),
            "500000".to_string(),
            "--async".to_string(),
            contract_addr.to_string(),
            method_sig.to_string(),
        ];
        call_args.extend(args.iter().cloned());
        let args = build_cast_send_args_with_gas_price(&ctx.rpc_url, &pk, &call_args, gas_price);
        let child = Command::new("cast")
            .args(args)
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .context("spawn cast send")?;
        children.push((i, child));
    }

    for (index, mut child) in children {
        let output = child.wait_with_output()?;
        if output.status.success() {
            continue;
        }
        let combined = format_output(&output);
        if is_known_tx_message(&combined) {
            log_step(&format!("accept tx {} already pending; continuing", index));
            continue;
        }
        bail!("cast send failed: {}", combined);
    }
    Ok(())
}

fn get_contract_addr(ctx: &PocContext) -> Result<String> {
    if let Some(addr) = &ctx.contract_addr_override {
        if !addr.trim().is_empty() {
            log_step("use CONTRACT_ADDR");
            return Ok(addr.trim().to_string());
        }
    }

    let cache = ctx.root_dir.join(".cache/contract.addr");
    if let Ok(contents) = fs::read_to_string(&cache) {
        let trimmed = contents.trim();
        if !trimmed.is_empty() {
            log_step("reuse cached contract");
            return Ok(trimmed.to_string());
        }
    }

    let addr = deploy_contract(ctx)?;
    if let Some(parent) = cache.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(cache, &addr)?;
    Ok(addr)
}

fn deploy_contract(ctx: &PocContext) -> Result<String> {
    log_step("forge build");
    run_cmd("forge", vec!["build".to_string()], Some(&ctx.root_dir))?;

    log_step("deploy contract");
    let args = vec![
        "create".to_string(),
        "--rpc-url".to_string(),
        ctx.rpc_url.clone(),
        "--private-key".to_string(),
        COW_PRIVKEY.to_string(),
        "--legacy".to_string(),
        "--gas-price".to_string(),
        "1".to_string(),
        "--broadcast".to_string(),
        "src/RacePoc.sol:RacePoc".to_string(),
    ];
    let output = run_cmd("forge", args, Some(&ctx.root_dir))?;
    parse_deployed_address(&output).context("parse contract address from forge output")
}

fn parse_deployed_address(output: &Output) -> Result<String> {
    let combined = format_output(output);
    for line in combined.lines() {
        if let Some(rest) = line.split("Deployed to:").nth(1) {
            if let Some(addr) = rest.split_whitespace().next() {
                return Ok(addr.to_string());
            }
        }
    }
    bail!("deployment address not found in forge output")
}

fn sender_privkey(index: u8) -> Result<String> {
    cast_keccak(&format!("poc-sender-{}", index))
}

fn sender_addr(index: u8) -> Result<String> {
    let pk = sender_privkey(index)?;
    cast_wallet_address(&pk)
}

fn cast_keccak(seed: &str) -> Result<String> {
    let args = vec!["keccak".to_string(), seed.to_string()];
    let output = run_cmd("cast", args, None)?;
    parse_single_value(&output, "cast keccak")
}

fn cast_wallet_address(privkey: &str) -> Result<String> {
    let args = vec![
        "wallet".to_string(),
        "address".to_string(),
        "--private-key".to_string(),
        privkey.to_string(),
    ];
    let output = run_cmd("cast", args, None)?;
    parse_single_value(&output, "cast wallet address")
}

fn cast_send(rpc_url: &str, privkey: &str, extra_args: &[String]) -> Result<()> {
    cast_send_with_gas_price(rpc_url, privkey, extra_args, DEFAULT_GAS_PRICE)
}

fn cast_send_with_gas_price(
    rpc_url: &str,
    privkey: &str,
    extra_args: &[String],
    gas_price: &str,
) -> Result<()> {
    let args = build_cast_send_args_with_gas_price(rpc_url, privkey, extra_args, gas_price);
    run_cmd("cast", args, None)?;
    Ok(())
}

fn cast_send_allow_failure(
    rpc_url: &str,
    privkey: &str,
    extra_args: &[String],
) -> Result<()> {
    let args = build_cast_send_args(rpc_url, privkey, extra_args);
    let _ = run_cmd_allow_failure("cast", args, None)?;
    Ok(())
}

fn cast_send_allow_pending_duplicate(
    rpc_url: &str,
    privkey: &str,
    extra_args: &[String],
) -> Result<()> {
    let args = build_cast_send_args(rpc_url, privkey, extra_args);
    let output = run_cmd_allow_failure("cast", args, None)?;
    if output.status.success() {
        return Ok(());
    }
    let combined = format_output(&output);
    if combined.contains("pending transaction with same hash already exists")
        || combined.contains("already known")
    {
        return Ok(());
    }
    bail!("command failed: cast\n{}", combined)
}

fn cast_send_allow_pending_duplicate_retry(
    rpc_url: &str,
    privkey: &str,
    extra_args: &[String],
) -> Result<()> {
    match cast_send_allow_pending_duplicate(rpc_url, privkey, extra_args) {
        Ok(()) => Ok(()),
        Err(err) if is_gas_price_bump_error(&err) => {
            log_step(&format!(
                "funding bump detected, retrying with gas price {}",
                RETRY_GAS_PRICE
            ));
            let args = build_cast_send_args_with_gas_price(
                rpc_url,
                privkey,
                extra_args,
                RETRY_GAS_PRICE,
            );
            let output = run_cmd_allow_failure("cast", args, None)?;
            if output.status.success() {
                return Ok(());
            }
            let combined = format_output(&output);
            if combined.contains("pending transaction with same hash already exists")
                || combined.contains("already known")
                || combined.to_lowercase().contains("gas price not enough to bump")
                || combined
                    .to_lowercase()
                    .contains("replacement transaction underpriced")
            {
                return Ok(());
            }
            bail!("command failed: cast\n{}", combined)
        }
        Err(err) => Err(err),
    }
}

fn build_cast_send_args(rpc_url: &str, privkey: &str, extra: &[String]) -> Vec<String> {
    build_cast_send_args_with_gas_price(rpc_url, privkey, extra, DEFAULT_GAS_PRICE)
}

fn build_cast_send_args_with_gas_price(
    rpc_url: &str,
    privkey: &str,
    extra: &[String],
    gas_price: &str,
) -> Vec<String> {
    let mut args = vec![
        "send".to_string(),
        "--rpc-url".to_string(),
        rpc_url.to_string(),
        "--private-key".to_string(),
        privkey.to_string(),
        "--legacy".to_string(),
        "--gas-price".to_string(),
        gas_price.to_string(),
    ];
    args.extend(extra.iter().cloned());
    args
}

fn is_known_tx_message(msg: &str) -> bool {
    let lower = msg.to_lowercase();
    lower.contains("pending transaction with same hash already exists")
        || lower.contains("already known")
}

fn parse_single_value(output: &Output, label: &str) -> Result<String> {
    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);
    let text = if !stdout.trim().is_empty() {
        stdout.trim()
    } else {
        stderr.trim()
    };
    let value = text
        .split_whitespace()
        .next()
        .ok_or_else(|| anyhow::anyhow!("no output from {}", label))?;
    Ok(value.to_string())
}

fn cast_balance(rpc_url: &str, addr: &str) -> Result<u128> {
    let args = vec![
        "balance".to_string(),
        "--rpc-url".to_string(),
        rpc_url.to_string(),
        addr.to_string(),
    ];
    let output = run_cmd("cast", args, None)?;
    let value = parse_single_value(&output, "cast balance")?;
    parse_wei(&value)
}

fn has_min_balance(rpc_url: &str, addr: &str, min_wei: u128) -> Result<bool> {
    let balance = cast_balance(rpc_url, addr)?;
    Ok(balance >= min_wei)
}

fn parse_wei(value: &str) -> Result<u128> {
    let trimmed = value.trim();
    if let Some(hex) = trimmed.strip_prefix("0x") {
        return u128::from_str_radix(hex, 16)
            .map_err(|err| anyhow::anyhow!("invalid hex balance: {}", err));
    }
    trimmed
        .parse::<u128>()
        .map_err(|err| anyhow::anyhow!("invalid balance: {}", err))
}
