"""Regression test: the bridge must commit/merge the sub-agent's work even when the
target repo installs a BLOCKING pre-commit hook (e.g. lefthook `pnpm verify:fast`).

Before the --no-verify fix, the hook silently failed the worktree commit, the branch
stayed put, the merge was a no-op, and the work was discarded yet reported success.
This drives the real isolation functions (no agent/API needed)."""

import asyncio
import os
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from isolation import cleanup_worktree, commit_worktree, create_worktree  # noqa: E402


def _git(cwd, *args):
    subprocess.run(["git", "-C", cwd, *args], check=True, capture_output=True)


async def main() -> int:
    sandbox = tempfile.mkdtemp(prefix="claudavity-hooktest-")
    task_id = "hooktest"
    try:
        _git(sandbox, "init", "-q")
        with open(os.path.join(sandbox, "README.md"), "w") as f:
            f.write("# hook sandbox\n")
        _git(sandbox, "add", "-A")
        _git(
            sandbox,
            "-c",
            "user.email=t@t",
            "-c",
            "user.name=t",
            "commit",
            "-qm",
            "init",
        )
        base = subprocess.run(
            ["git", "-C", sandbox, "rev-parse", "HEAD"], capture_output=True, text=True
        ).stdout.strip()

        # Install a BLOCKING pre-commit hook (shared by worktrees via .git/hooks).
        hook = os.path.join(sandbox, ".git", "hooks", "pre-commit")
        with open(hook, "w", newline="\n") as f:
            f.write("#!/bin/sh\necho 'pre-commit: blocked' >&2\nexit 1\n")
        os.chmod(hook, 0o755)

        # Sanity: a normal commit in the sandbox is indeed blocked by the hook.
        with open(os.path.join(sandbox, "probe.txt"), "w") as f:
            f.write("x")
        _git(sandbox, "add", "-A")
        blocked = subprocess.run(
            ["git", "-C", sandbox, "commit", "-m", "should fail"], capture_output=True
        )
        assert blocked.returncode != 0, (
            "hook did not block a normal commit — test invalid"
        )
        _git(sandbox, "reset", "-q", "--hard", base)  # undo the staged probe

        # Now exercise the bridge path.
        wt = await create_worktree(sandbox, task_id)
        with open(os.path.join(wt, "artifact.md"), "w") as f:
            f.write("delegated work\n")

        files = await commit_worktree(sandbox, task_id)
        assert files == ["artifact.md"], f"expected ['artifact.md'], got {files}"

        await cleanup_worktree(sandbox, task_id, success=True)

        merged = os.path.join(sandbox, "artifact.md")
        assert os.path.exists(merged), "artifact.md did not merge into the sandbox"
        head = subprocess.run(
            ["git", "-C", sandbox, "rev-parse", "HEAD"], capture_output=True, text=True
        ).stdout.strip()
        assert head != base, "HEAD did not advance — merge was a no-op"

        print(
            "PASS: hook-blocked repo committed + merged via --no-verify "
            f"(HEAD {base[:7]} -> {head[:7]}, files={files})"
        )
        return 0
    finally:
        subprocess.run(["git", "-C", sandbox, "worktree", "prune"], capture_output=True)
        import shutil

        shutil.rmtree(sandbox, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
