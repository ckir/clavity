"""Unit tests for the C3 pane-state classifier (agy_tmux.classify_pane).

Fixtures are verbatim captures from the live psmux/agy session taken during design
spikes, so these tests pin the *observed* idle/busy footer behavior.
"""

from agy_tmux import BUSY, IDLE, UNKNOWN, changed, classify_pane

# Real IDLE capture: footer shows "? for shortcuts" under an empty '>' prompt.
IDLE_CAPTURE = """\
  I have sent the  TMUX-WAKE-OK-4421  signal to Claude via  memory_signal_send . Stopping now.

────────────────────────────────────────────────────────────
>
────────────────────────────────────────────────────────────
? for shortcuts                                                        Gemini 3.1 Pro (High)
"""

# Real BUSY capture: spinner line + footer "esc to cancel". Note an empty '>' prompt
# line is *also* present while busy — the classifier must not let that read as idle.
BUSY_CAPTURE = """\
> Write one short paragraph (about 120 words) on why git worktrees are useful.
⡿  Generating...
────────────────────────────────────────────────────────────
>
────────────────────────────────────────────────────────────
esc to cancel                                                          Gemini 3.1 Pro (High)
"""


def test_idle_capture_classifies_idle():
    assert classify_pane(IDLE_CAPTURE) == IDLE


def test_busy_capture_classifies_busy():
    assert classify_pane(BUSY_CAPTURE) == BUSY


def test_busy_marker_wins_over_empty_prompt():
    # The busy capture contains a bare '>' prompt line; BUSY must still win.
    assert classify_pane(BUSY_CAPTURE) == BUSY


def test_no_markers_is_unknown():
    assert classify_pane("a screen with neither footer marker present") == UNKNOWN


def test_empty_is_unknown():
    assert classify_pane("") == UNKNOWN


# --- marker-free activity detection (changed) -------------------------------------------
# Verified live: idle captures are byte-identical 2s apart; busy (generating) captures
# differ. `changed` is the pure core of that fallback detector.


def test_changed_true_when_a_pair_differs():
    assert changed(["screen-A", "screen-A", "screen-B"]) is True


def test_changed_false_when_all_identical():
    assert changed(["same", "same", "same"]) is False


def test_changed_false_for_single_or_empty():
    # No consecutive pairs -> no observed activity.
    assert changed(["only"]) is False
    assert changed([]) is False
