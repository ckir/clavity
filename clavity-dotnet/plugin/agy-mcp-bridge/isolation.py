import os
import asyncio


async def run_git_command(cwd: str, *args) -> tuple[int, str, str]:
    process = await asyncio.create_subprocess_exec(
        "git",
        *args,
        cwd=cwd,
        stdin=asyncio.subprocess.DEVNULL,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    stdout, stderr = await process.communicate()
    return process.returncode, stdout.decode(), stderr.decode()


async def create_worktree(target_dir: str, task_id: str) -> str:
    # Check if target is a git repo
    code, _, err = await run_git_command(target_dir, "status")
    if code != 0:
        raise ValueError(
            f"Target directory {target_dir} is not a valid git repository. Error: {err}"
        )

    branch_name = f"agy-task-{task_id}"
    worktree_path = os.path.join(target_dir, ".agent", "worktrees", f"task-{task_id}")

    # Ensure the parent directory exists
    os.makedirs(os.path.dirname(worktree_path), exist_ok=True)

    # Create the branch and worktree
    code, _, err = await run_git_command(
        target_dir, "worktree", "add", worktree_path, "-b", branch_name
    )
    if code != 0:
        raise RuntimeError(f"Failed to create git worktree: {err}")

    return worktree_path


async def commit_worktree(target_dir: str, task_id: str) -> list[str]:
    """Stage and commit everything the sub-agent left in its worktree, returning the
    repo-relative paths in that commit. Returns [] if the agent changed nothing.

    This is the source of truth for "did the task do work" — git history, not the
    agent's self-reported JSON, which it frequently truncates (e.g. ends its turn
    mid-`files_changed`). Committing here lets the caller derive the outcome from disk
    and makes the subsequent merge in cleanup_worktree a no-op on the commit side.

    The commit runs with `--no-verify`: this is an internal transport commit on a
    throwaway branch, and target repos commonly install a blocking `pre-commit` hook
    (e.g. lefthook `pnpm verify:fast`). Without bypassing it the hook silently fails
    the commit, leaving the branch unchanged so the later merge is a no-op — the
    sub-agent's work is discarded but reported as success. The human/master agent still
    gates the eventual push (e.g. `pre-push` verify:full)."""
    worktree_path = os.path.join(target_dir, ".agent", "worktrees", f"task-{task_id}")
    if not os.path.exists(worktree_path):
        return []

    await run_git_command(worktree_path, "add", "-A")
    _, status_out, _ = await run_git_command(worktree_path, "status", "--porcelain")
    if not status_out.strip():
        return []

    code, _, err = await run_git_command(
        worktree_path,
        "-c",
        "user.email=agy@bridge",
        "-c",
        "user.name=agy-subagent",
        "commit",
        "--no-verify",
        "-m",
        f"agy task {task_id}",
    )
    if code != 0:
        # Commit genuinely failed — never report phantom success on a no-op branch.
        raise RuntimeError(f"Worktree commit failed for task {task_id}: {err.strip()}")

    _, files_out, _ = await run_git_command(
        worktree_path, "show", "--name-only", "--format=", "HEAD"
    )
    return [line.strip() for line in files_out.splitlines() if line.strip()]


async def cleanup_worktree(target_dir: str, task_id: str, success: bool = False):
    branch_name = f"agy-task-{task_id}"
    worktree_path = os.path.join(target_dir, ".agent", "worktrees", f"task-{task_id}")

    if not os.path.exists(worktree_path):
        return

    if success:
        # The sub-agent leaves its work UNCOMMITTED in the worktree, and `git merge`
        # only transfers committed history — so commit the worktree's changes onto
        # its branch BEFORE removing it, otherwise the force-remove discards them.
        await run_git_command(worktree_path, "add", "-A")
        _, status_out, _ = await run_git_command(worktree_path, "status", "--porcelain")
        if status_out.strip():
            await run_git_command(
                worktree_path,
                "-c",
                "user.email=agy@bridge",
                "-c",
                "user.name=agy-subagent",
                "commit",
                "--no-verify",  # internal transport commit; bypass target-repo hooks
                "-m",
                f"agy task {task_id}",
            )

        # Now the branch carries the commit; remove the worktree and merge it back.
        await run_git_command(target_dir, "worktree", "remove", "-f", worktree_path)
        code, out, err = await run_git_command(target_dir, "merge", branch_name)
        if code != 0:
            await run_git_command(target_dir, "merge", "--abort")
            raise RuntimeError(
                f"Merge conflict detected. The branch {branch_name} has been preserved for manual review. Git error: {err}"
            )

        # Delete branch after successful merge
        await run_git_command(target_dir, "branch", "-D", branch_name)
    else:
        # Task failed/timed out: discard the worktree and its branch entirely.
        await run_git_command(target_dir, "worktree", "remove", "-f", worktree_path)
        await run_git_command(target_dir, "branch", "-D", branch_name)
