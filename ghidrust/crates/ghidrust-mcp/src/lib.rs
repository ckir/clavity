//! Library surface of the ghidrust-mcp crate (used by integration tests + the binary).
pub mod config;
pub mod execute;
pub mod logging;
pub mod paths;
pub mod poison;
pub mod server;
pub mod skill_asset;
pub mod state;
pub mod tools;
pub mod worker_asset;

use std::path::Path;

/// Extract the embedded worker script into `dir` (panics on IO error — test/boot helper).
pub fn worker_asset_extract(dir: &Path) {
    worker_asset::extract_worker(dir).expect("extract worker script");
}
