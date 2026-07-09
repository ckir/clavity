//! Pure worker-lifecycle state machine (spec §4). No I/O: models the states and
//! the one-shot WORKER_RESTARTED notice so lifecycle decisions are unit-testable
//! without spawning a JVM.

use thiserror::Error;

/// Worker lifecycle state (spec §4: starting|ready|busy|crashed).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WorkerState {
    Starting,
    Ready,
    Busy,
    Crashed,
}

#[derive(Debug, Error, PartialEq, Eq)]
#[error("invalid worker transition from {from:?}: {event}")]
pub struct InvalidTransition {
    pub from: WorkerState,
    pub event: &'static str,
}

/// Tracks worker state plus the one-shot "restarted after crash" notice that must
/// surface EXACTLY once (spec §4: the next call after a crash returns WORKER_RESTARTED
/// once, so the agent knows unsaved edits were lost).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkerLifecycle {
    state: WorkerState,
    restart_notice_pending: bool,
    /// True once the worker has completed at least one successful init (reached Ready). A crash
    /// during the very first boot loses nothing, so it must NOT arm the WORKER_RESTARTED notice.
    ever_ready: bool,
}

impl Default for WorkerLifecycle {
    fn default() -> Self {
        Self {
            state: WorkerState::Starting,
            restart_notice_pending: false,
            ever_ready: false,
        }
    }
}

impl WorkerLifecycle {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn state(&self) -> WorkerState {
        self.state
    }

    /// Successful init handshake: Starting -> Ready.
    pub fn on_ready(&mut self) -> Result<(), InvalidTransition> {
        match self.state {
            WorkerState::Starting => {
                self.state = WorkerState::Ready;
                self.ever_ready = true;
                Ok(())
            }
            from => Err(InvalidTransition {
                from,
                event: "on_ready",
            }),
        }
    }

    /// Dispatch a call onto the executor: Ready -> Busy.
    pub fn on_dispatch(&mut self) -> Result<(), InvalidTransition> {
        match self.state {
            WorkerState::Ready => {
                self.state = WorkerState::Busy;
                Ok(())
            }
            from => Err(InvalidTransition {
                from,
                event: "on_dispatch",
            }),
        }
    }

    /// Call finished: Busy -> Ready.
    pub fn on_complete(&mut self) -> Result<(), InvalidTransition> {
        match self.state {
            WorkerState::Busy => {
                self.state = WorkerState::Ready;
                Ok(())
            }
            from => Err(InvalidTransition {
                from,
                event: "on_complete",
            }),
        }
    }

    /// Socket closed / process died: transition to Crashed from any state.
    pub fn on_crash(&mut self) {
        self.state = WorkerState::Crashed;
    }

    /// Begin a respawn: Crashed -> Starting, arming the one-shot restart notice.
    pub fn on_respawn(&mut self) -> Result<(), InvalidTransition> {
        match self.state {
            WorkerState::Crashed => {
                self.state = WorkerState::Starting;
                self.restart_notice_pending = self.ever_ready;
                Ok(())
            }
            from => Err(InvalidTransition {
                from,
                event: "on_respawn",
            }),
        }
    }

    /// Consume the one-shot WORKER_RESTARTED notice; true at most once per crash.
    pub fn take_restart_notice(&mut self) -> bool {
        std::mem::take(&mut self.restart_notice_pending)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn starts_in_starting() {
        assert_eq!(WorkerLifecycle::new().state(), WorkerState::Starting);
    }

    #[test]
    fn happy_path_starting_ready_busy_ready() {
        let mut w = WorkerLifecycle::new();
        w.on_ready().unwrap();
        assert_eq!(w.state(), WorkerState::Ready);
        w.on_dispatch().unwrap();
        assert_eq!(w.state(), WorkerState::Busy);
        w.on_complete().unwrap();
        assert_eq!(w.state(), WorkerState::Ready);
    }

    #[test]
    fn cannot_dispatch_before_ready() {
        let mut w = WorkerLifecycle::new();
        assert_eq!(
            w.on_dispatch(),
            Err(InvalidTransition {
                from: WorkerState::Starting,
                event: "on_dispatch"
            })
        );
    }

    #[test]
    fn cannot_ready_twice() {
        let mut w = WorkerLifecycle::new();
        w.on_ready().unwrap();
        assert!(w.on_ready().is_err());
    }

    #[test]
    fn crash_then_respawn_arms_restart_notice_exactly_once() {
        let mut w = WorkerLifecycle::new();
        w.on_ready().unwrap();
        w.on_dispatch().unwrap();
        w.on_crash(); // socket closed mid-call
        assert_eq!(w.state(), WorkerState::Crashed);
        w.on_respawn().unwrap();
        assert_eq!(w.state(), WorkerState::Starting);
        // WORKER_RESTARTED surfaces once, then never again for this crash.
        assert!(w.take_restart_notice());
        assert!(!w.take_restart_notice());
    }

    #[test]
    fn no_restart_notice_before_any_crash() {
        let mut w = WorkerLifecycle::new();
        assert!(!w.take_restart_notice());
    }

    #[test]
    fn cannot_respawn_a_live_worker() {
        let mut w = WorkerLifecycle::new();
        w.on_ready().unwrap();
        assert_eq!(
            w.on_respawn(),
            Err(InvalidTransition {
                from: WorkerState::Ready,
                event: "on_respawn"
            })
        );
    }

    #[test]
    fn crash_before_first_ready_does_not_arm_restart_notice() {
        let mut w = WorkerLifecycle::new(); // Starting, never reached Ready
        w.on_crash();
        w.on_respawn().unwrap();
        // Nothing was lost (we never ran a call), so no vacuous "unsaved edits lost" notice.
        assert!(!w.take_restart_notice());
    }
}
