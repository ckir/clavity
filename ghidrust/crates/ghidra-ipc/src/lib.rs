//! Wire types, framing, JSON-RPC, and address canonicalization for the
//! host <-> Ghidra-worker socket. No Ghidra dependency: pure, unit-testable.
pub mod address;
pub mod error;
pub mod error_map;
pub mod frame;
pub mod protocol;
pub mod rpc;
