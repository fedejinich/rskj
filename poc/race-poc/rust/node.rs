use anyhow::{bail, Context, Result};
use std::fs;
use std::fs::OpenOptions;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, SystemTime};

use crate::util::{ensure_cmd, log_step, root_dir, run_cmd, run_cmd_allow_failure};

pub fn run_node_start() -> Result<()> {
    ensure_cmd("java", Some("-version"))?;
    ensure_cmd("ps", Some("-ax"))?;
    let root_dir = root_dir();
    let conf = root_dir.join("regtest-rskip144.conf");
    let log_dir = root_dir.join("logs");
    let jar_dir = root_dir.join("../../rskj-core/build/libs");
    let pid_path = pid_file(&root_dir);

    if let Some(pid) = read_pid(&pid_path)? {
        if process_running(pid) {
            bail!("rskj already running (pid {})", pid);
        }
        let _ = fs::remove_file(&pid_path);
    }
    let existing = find_rskj_pids(&conf)?;
    if !existing.is_empty() {
        bail!("rskj already running (pid(s) {})", fmt_pids(&existing));
    }

    fs::create_dir_all(&log_dir)
        .with_context(|| format!("create log dir: {}", log_dir.display()))?;
    fs::create_dir_all(root_dir.join(".rsk/regtest/database"))?;

    let jar = find_latest_jar(&jar_dir)?;
    log_step(&format!("start rskj ({})", jar.display()));
    let log_path = log_dir.join("rskj.log");
    let log_file = OpenOptions::new()
        .create(true)
        .append(true)
        .open(&log_path)
        .with_context(|| format!("open log file: {}", log_path.display()))?;

    let mut cmd = Command::new("java");
    cmd.arg(format!("-Drsk.conf.file={}", conf.display()))
        .arg("-cp")
        .arg(&jar)
        .arg("co.rsk.Start")
        .arg("--regtest")
        .stdout(Stdio::from(log_file.try_clone()?))
        .stderr(Stdio::from(log_file));

    let child = cmd.spawn().context("start rskj")?;
    let pid = child.id();
    fs::write(&pid_path, format!("{pid}"))?;
    println!("rskj started (pid {})", pid);
    Ok(())
}

pub fn run_node_stop() -> Result<()> {
    ensure_cmd("kill", Some("-0"))?;
    ensure_cmd("ps", Some("-ax"))?;
    let root_dir = root_dir();
    let conf = root_dir.join("regtest-rskip144.conf");
    let pid_path = pid_file(&root_dir);
    let mut target_pids = Vec::new();

    if let Some(pid) = read_pid(&pid_path)? {
        if process_running(pid) && pid_matches_conf(pid, &conf)? {
            target_pids.push(pid);
        }
    }
    if target_pids.is_empty() {
        target_pids = find_rskj_pids(&conf)?;
    }
    if target_pids.is_empty() {
        log_step("rskj not running");
    } else {
        for pid in target_pids {
            log_step(&format!("stop rskj ({})", pid));
            stop_process(pid)?;
        }
    }

    let _ = fs::remove_file(&pid_path);

    clean_db(&root_dir)?;
    Ok(())
}

fn pid_file(root_dir: &Path) -> PathBuf {
    root_dir.join("logs/rskj.pid")
}

fn fmt_pids(pids: &[i32]) -> String {
    pids.iter()
        .map(|pid| pid.to_string())
        .collect::<Vec<_>>()
        .join(", ")
}

fn pid_matches_conf(pid: i32, conf: &Path) -> Result<bool> {
    let conf_arg = format!("-Drsk.conf.file={}", conf.display());
    let args = vec![
        "-p".to_string(),
        pid.to_string(),
        "-o".to_string(),
        "command=".to_string(),
    ];
    let output = run_cmd_allow_failure("ps", args, None)?;
    if !output.status.success() {
        return Ok(false);
    }
    let cmdline = String::from_utf8_lossy(&output.stdout);
    Ok(cmdline.contains("co.rsk.Start")
        && cmdline.contains("--regtest")
        && cmdline.contains(&conf_arg))
}

fn find_rskj_pids(conf: &Path) -> Result<Vec<i32>> {
    let conf_arg = format!("-Drsk.conf.file={}", conf.display());
    let args = vec![
        "-ax".to_string(),
        "-o".to_string(),
        "pid=".to_string(),
        "-o".to_string(),
        "command=".to_string(),
    ];
    let output = run_cmd("ps", args, None)?;
    let stdout = String::from_utf8_lossy(&output.stdout);
    let mut matches = Vec::new();
    for line in stdout.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        let mut parts = trimmed.splitn(2, |c: char| c.is_whitespace());
        let pid_str = parts.next().unwrap_or("");
        let cmdline = parts.next().unwrap_or("").trim();
        let pid: i32 = match pid_str.parse() {
            Ok(pid) => pid,
            Err(_) => continue,
        };
        if cmdline.contains("co.rsk.Start")
            && cmdline.contains("--regtest")
            && cmdline.contains(&conf_arg)
        {
            matches.push(pid);
        }
    }
    Ok(matches)
}

fn read_pid(path: &Path) -> Result<Option<i32>> {
    if !path.exists() {
        return Ok(None);
    }
    let contents = fs::read_to_string(path)?;
    let pid: i32 = contents.trim().parse().context("invalid pid file")?;
    Ok(Some(pid))
}

fn process_running(pid: i32) -> bool {
    Command::new("kill")
        .arg("-0")
        .arg(pid.to_string())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

fn stop_process(pid: i32) -> Result<()> {
    Command::new("kill")
        .arg(pid.to_string())
        .status()
        .context("send SIGTERM")?;

    for _ in 0..20 {
        if !process_running(pid) {
            return Ok(());
        }
        thread::sleep(Duration::from_millis(250));
    }

    Command::new("kill")
        .arg("-9")
        .arg(pid.to_string())
        .status()
        .context("send SIGKILL")?;
    Ok(())
}

fn clean_db(root_dir: &Path) -> Result<()> {
    let db_dir = root_dir.join(".rsk/regtest/database");
    log_step("clean db");
    if let Err(err) = fs::remove_dir_all(&db_dir) {
        if err.kind() != std::io::ErrorKind::NotFound {
            return Err(err.into());
        }
    }
    let cache_file = root_dir.join(".cache/contract.addr");
    let _ = fs::remove_file(cache_file);
    Ok(())
}

fn find_latest_jar(jar_dir: &Path) -> Result<PathBuf> {
    let mut latest: Option<(SystemTime, PathBuf)> = None;
    let entries = fs::read_dir(jar_dir)
        .with_context(|| format!("read jar dir: {}", jar_dir.display()))?;
    for entry in entries {
        let entry = entry?;
        let path = entry.path();
        if path.extension().and_then(|s| s.to_str()) != Some("jar") {
            continue;
        }
        let file_name = path.file_name().and_then(|s| s.to_str()).unwrap_or("");
        if !file_name.contains("all") {
            continue;
        }
        let modified = entry
            .metadata()
            .and_then(|m| m.modified())
            .unwrap_or(SystemTime::UNIX_EPOCH);
        let replace = match &latest {
            Some((best, _)) => modified > *best,
            None => true,
        };
        if replace {
            latest = Some((modified, path));
        }
    }

    if let Some((_, path)) = latest {
        return Ok(path);
    }
    bail!("fat jar not found. build with: ./gradlew rskj-core:fatJar")
}
