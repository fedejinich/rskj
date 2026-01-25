use anyhow::Result;
use clap::{Parser, Subcommand};
use std::path::PathBuf;

use crate::{node, rsk};

#[derive(Parser)]
#[command(name = "race-poc", about = "RSKIP-144 race condition PoC")]
pub struct Cli {
    #[arg(long, env = "RPC_URL", default_value = "http://localhost:4444")]
    pub rpc_url: String,
    #[arg(long, env = "CONTRACT_ADDR")]
    pub contract_addr: Option<String>,
    #[arg(long, env = "ID_SEED", default_value = "race-poc-id")]
    pub id_seed: String,
    #[arg(
        long,
        env = "FUND_AMOUNT_WEI",
        default_value = "100000000000000000"
    )]
    pub fund_amount_wei: String,
    #[command(subcommand)]
    pub command: Commands,
}

#[derive(Subcommand)]
pub enum Commands {
    #[command(name = "node_start", alias = "node-start", alias = "node")]
    NodeStart,
    #[command(name = "node_stop", alias = "node-stop")]
    NodeStop,
    Simple,
    Union {
        #[arg(long, env = "AMOUNT_WEI", default_value = "1")]
        amount_wei: String,
    },
    Precheck {
        #[arg(long, env = "AMOUNT_WEI", default_value = "1")]
        amount_wei: String,
    },
    Verify {
        #[arg(long, env = "SLEEP_SECS", default_value = "10")]
        sleep_secs: u64,
        #[arg(long, env = "LOG_FILE")]
        log_file: Option<PathBuf>,
    },
}

pub fn run() -> Result<()> {
    let cli = Cli::parse();
    match &cli.command {
        Commands::NodeStart => node::run_node_start(),
        Commands::NodeStop => node::run_node_stop(),
        Commands::Simple => rsk::run_simple(&cli),
        Commands::Union { amount_wei } => rsk::run_union(&cli, amount_wei),
        Commands::Precheck { amount_wei } => rsk::run_precheck(&cli, amount_wei),
        Commands::Verify {
            sleep_secs,
            log_file,
        } => rsk::run_verify(&cli, *sleep_secs, log_file.as_ref()),
    }
}
