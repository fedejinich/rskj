use anyhow::Result;

mod cli;
mod logs;
mod node;
mod rsk;
mod util;

fn main() -> Result<()> {
    cli::run()
}
