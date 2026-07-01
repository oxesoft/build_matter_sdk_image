#!/usr/bin/env python3
"""Cherry-pick commits from a source branch or a single commit into the current branch.

When the argument is a branch, the script lists pending commits (those not
already present on the current branch by patch-id) and asks for confirmation
before applying. When the argument is a commit hash, it cherry-picks that
commit directly with no listing or confirmation.

In both cases, each cherry-pick is followed by a push and a comment on the
originating pull request (extracted from the commit subject's "(#N)" suffix).
"""

import argparse
import re
import subprocess
import sys


def run(cmd, check=True, capture=True):
    return subprocess.run(
        cmd,
        check=check,
        capture_output=capture,
        text=True,
    )


def get_repo():
    """Return (owner/repo slug, https url) parsed from origin remote."""
    url = run(["git", "remote", "get-url", "origin"]).stdout.strip()
    m = re.match(
        r"(?:https://github\.com/|git@github\.com:)([^/]+)/(.+?)(?:\.git)?$",
        url,
    )
    if not m:
        return None, None
    slug = f"{m.group(1)}/{m.group(2)}"
    return slug, f"https://github.com/{slug}"


def is_branch(name):
    return run(
        ["git", "show-ref", "--verify", "--quiet", f"refs/heads/{name}"],
        check=False,
    ).returncode == 0


def resolve_commit(ref):
    """Return the full SHA for ref, or None if it doesn't resolve to a commit."""
    result = run(["git", "rev-parse", "--verify", f"{ref}^{{commit}}"], check=False)
    return result.stdout.strip() if result.returncode == 0 else None


def commit_subject(sha):
    return run(["git", "log", "-1", "--format=%s", sha]).stdout.strip()


def list_commits(branch, limit=10):
    out = run(
        ["git", "log", branch, f"-n{limit}", "--oneline", "--no-decorate"],
    ).stdout.strip()
    return out.splitlines()


def extract_pr_number(subject):
    m = re.search(r"\(#(\d+)\)\s*$", subject)
    return int(m.group(1)) if m else None


def get_pending_commits(source, destination):
    """Commits on source not already in destination (oldest first).

    Uses git range-diff to pair commits by fuzzy similarity over their
    diffs, so commits already present on destination under a different
    hash and patch (e.g. from conflict resolution) are still detected
    as matches and excluded from the pending list.
    """
    base = run(["git", "merge-base", destination, source]).stdout.strip()
    if not base:
        sys.exit(f"Error: no merge-base between '{destination}' and '{source}'")
    out = run([
        "git", "range-diff", "--no-patch", "--abbrev=40",
        f"{base}..{destination}", f"{base}..{source}",
    ]).stdout
    # Lines of interest: "-:  ------- > N:  <sha40> <subject>"
    # — commits that exist only on source. The N is the source-side
    # ordinal (oldest = 1), used to restore source order. The leading
    # "-:" may be right-padded with spaces when either side has enough
    # commits to require multi-digit ordinals.
    pattern = re.compile(r"^\s*-:\s+-+\s+>\s+(\d+):\s+([0-9a-f]{40})\s+(.*)$")
    items = []
    for line in out.splitlines():
        m = pattern.match(line)
        if m:
            items.append((int(m.group(1)), m.group(2), m.group(3)))
    items.sort()
    return [(sha, subject) for _, sha, subject in items]


def apply_one(sha, subject, destination, repo_slug, comment_body):
    print(f"\nCherry-picking {sha[:9]}: {subject}")
    result = run(["git", "cherry-pick", sha], check=False, capture=False)
    if result.returncode != 0:
        sys.exit(
            f"Cherry-pick failed for {sha}. "
            f"Resolve conflicts and run 'git cherry-pick --continue', "
            f"or 'git cherry-pick --abort' to cancel."
        )

    print(f"  Pushing to origin/{destination}")
    result = run(
        ["git", "push", "origin", destination],
        check=False,
        capture=False,
    )
    if result.returncode != 0:
        sys.exit(
            f"Push failed for {sha}. The commit is local; the PR comment "
            f"will not be posted to avoid an inconsistent state."
        )

    pr = extract_pr_number(subject)
    if pr is None:
        print("  No PR number in subject; skipping comment.")
        return

    print(f"  Commenting on PR #{pr}")
    result = run(
        [
            "gh", "pr", "comment", str(pr),
            "--repo", repo_slug,
            "--body", comment_body,
        ],
        check=False,
        capture=False,
    )
    if result.returncode != 0:
        print(f"  Warning: failed to add comment to PR #{pr}", file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", help="Source branch name or commit hash")
    args = parser.parse_args()

    destination = run(["git", "branch", "--show-current"]).stdout.strip()
    if not destination:
        sys.exit("Error: not on any branch (detached HEAD?)")

    repo_slug, repo_url = get_repo()
    if not repo_slug:
        sys.exit("Error: could not parse GitHub repo URL from 'origin' remote")

    comment_body = (
        f"Cherry-picked to [{destination}]"
        f"({repo_url}/tree/{destination})"
    )

    if is_branch(args.source):
        if args.source == destination:
            sys.exit(f"Error: source and destination are both '{destination}'")

        print(f"Recent commits on destination '{destination}':")
        for line in list_commits(destination):
            print(f"  {line}")
        print()
        print(f"Recent commits on source '{args.source}':")
        for line in list_commits(args.source):
            print(f"  {line}")
        print()

        pending = get_pending_commits(args.source, destination)
        if not pending:
            print("No commits to cherry-pick.")
            return

        print(
            f"The following {len(pending)} commit(s) will be cherry-picked "
            f"into '{destination}' (oldest first):"
        )
        print()
        for sha, subject in pending:
            pr = extract_pr_number(subject)
            pr_str = f"PR #{pr}" if pr else "no PR found"
            print(f"  {sha[:9]}  {subject}  [{pr_str}]")
        print()

        reply = input("Proceed? [y/N]: ").strip().lower()
        if reply not in ("y", "yes"):
            print("Aborted.")
            return

        for sha, subject in pending:
            apply_one(sha, subject, destination, repo_slug, comment_body)

        print("\nDone.")
        return

    sha = resolve_commit(args.source)
    if sha is None:
        sys.exit(
            f"Error: '{args.source}' is neither a local branch nor a commit"
        )

    apply_one(sha, commit_subject(sha), destination, repo_slug, comment_body)
    print("\nDone.")


if __name__ == "__main__":
    main()
