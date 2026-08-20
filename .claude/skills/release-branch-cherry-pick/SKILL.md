---
name: release-branch-cherry-pick
description: >
  Cherry-pick pending commits from one certification-tool release branch into another
  (e.g. v2.15.1-beta1+summer2026 -> v2.16-beta2+summer2026), correctly resolving the
  recurring backend/cli/frontend submodule conflicts and docker-compose.yml /
  docs/Matter_TH_User_Guide conflicts this repo produces, then pushing and commenting
  on each originating PR. Replaces the old tools/cherrypick.py script.
  Use when: (1) porting fixes between release branches in this repo, (2) a cherry-pick
  hits "Failed to merge submodule ... (commits don't follow merge-base)", (3) a
  cherry-pick says "previous cherry-pick is now empty", (4) resolving conflicts in
  backend/cli/frontend gitlinks, docker-compose.yml image tags, or the user guide
  .adoc/.pdf revision history.
  Keywords: cherry-pick, release branch, submodule conflict, backend, cli, frontend,
  docker-compose, range-diff, gh pr comment, v2.16-develop, v2.16-cli-develop.
version: "1.0.0"
---

# Release-branch cherry-pick (certification-tool)

Ports pending commits from a source release branch into a destination release branch,
handling this repo's recurring conflict shapes without ever regressing a submodule or
silently dropping content. Do every step below directly with `git`/`gh`, using judgment
at each conflict the way a human reviewer would.

## Why this exists

The `certification-tool` repo maintains multiple parallel release lines (e.g.
`v2.15.1-beta1+summer2026`, `v2.16-beta1+summer2026`, `v2.16-beta2+summer2026`), each
pinning the `backend`, `cli`, and `frontend` submodules independently. The same
upstream PR routinely gets cherry-picked into more than one line, landing under a
**different commit hash** each time. That makes plain `git cherry-pick` conflict on
submodule gitlinks constantly ("commits don't follow merge-base") even when the
destination already has equivalent content — resolving these requires checking content
equivalence, not just picking a side.

## Before starting

1. `git status` — must be clean (only expected untracked files). `git rev-parse -q
   --verify CHERRY_PICK_HEAD` — must be empty (no cherry-pick already in progress).
2. `git branch --show-current` — confirm you're on the intended destination branch.
3. `git fetch origin --quiet` and diff local vs `origin/<branch>` for both source and
   destination — do not proceed on stale refs.
4. **Re-check all three right before every commit, skip, and push** — not just once at
   the start. If the branch, HEAD, or staged files ever don't match what you expect,
   **stop and ask the user** whether something else (another terminal, script, editor)
   is touching the same checkout concurrently. Do not guess past this — a mid-operation
   branch swap happened once during development of this workflow and silently
   contaminated an in-progress conflict resolution.

## Step 1 — Compute the pending list

```bash
base=$(git merge-base <destination> <source>)
git range-diff --no-patch --abbrev=40 "$base..<destination>" "$base..<source>"
```

Lines matching `^\s*-:\s+-+\s+>\s+(\d+):\s+([0-9a-f]{40})\s+(.*)$` are commits that exist
only on `<source>` — these are pending, ordered by the captured ordinal (oldest first).
Lines with `=` or `!` pairing a source and destination commit are already applied
(possibly reworded/rebased) — leave them alone.

This fuzzy match is not perfect: a commit you resolve using a *different-but-equivalent*
submodule hash than the original will keep showing up as "pending" on later runs even
though it's already satisfied. That's expected — see Step 3's empty-commit handling,
which makes re-attempting it a harmless no-op.

For each PR referenced by a pending commit's subject, extract the number with
`\(#(\d+)\)\s*$` — you'll need it in Step 4.

## Step 2 — Attempt the cherry-pick

```bash
git cherry-pick <sha>
```

Three outcomes:

- **Clean, non-empty.** Nothing else to do here — go to Step 4.
- **Clean or conflict-free but "previous cherry-pick is now empty".** The content is
  already present on the destination (usually under a different hash). Confirm with
  `git diff --name-only --diff-filter=U` (should be empty), then `git cherry-pick
  --skip`. Do **not** `git commit --allow-empty`. Do **not** push or comment — nothing
  changed.
- **Non-zero exit with unmerged paths.** Real conflict — go to Step 3. First confirm
  it's actually mid-cherry-pick: `git rev-parse -q --verify CHERRY_PICK_HEAD` must
  resolve. If it doesn't, something failed before the pick even started — stop and
  investigate the git output rather than assuming a submodule conflict.

## Step 3 — Resolve real conflicts

### Submodule gitlinks (`backend`, `cli`, `frontend`)

Never resolve these with `git checkout --ours/--theirs -- <submodule>` or a plain `git
add <submodule>` — both re-read the submodule's *checked-out worktree HEAD*, which is
almost never the commit you actually want, and `git add` will silently clobber a
correct resolution you just staged. Always finish a submodule resolution with:

```bash
git update-index --cacheinfo 160000,<resolved-sha>,<submodule-path>
```

...and run it **last** for that submodule — never `git add <submodule>` afterward.

To find `<resolved-sha>`:

1. `git ls-files -u -- <submodule>` gives you base/ours/theirs SHAs (stages 1/2/3).
2. Check ancestry both ways inside the submodule:
   ```bash
   git -C <submodule> merge-base --is-ancestor <ours> <theirs>
   git -C <submodule> merge-base --is-ancestor <theirs> <ours>
   ```
   If one is a straight ancestor of the other, keep the descendant (never regress to
   an older commit). This is the easy case.
3. If neither is an ancestor of the other (the common case here — independent
   cherry-picks of the same PR into different lines), don't try to merge the
   submodule. Instead find the commit that already carries equivalent content on the
   destination's line:
   ```bash
   git -C <submodule> fetch origin --quiet
   git -C <submodule> log --all --oneline --grep="<theirs' commit subject>" -i
   ```
   Check whether any match is a descendant of `<ours>`
   (`merge-base --is-ancestor <ours> <candidate>`). Then diff the actual patch content
   (not just the message) to confirm it's the same change:
   ```bash
   diff <(git -C <submodule> show <theirs> -- <path>) <(git -C <submodule> show <candidate> -- <path>)
   ```
   Also check the submodule's own current-line development branch — this repo names
   them `v<X.Y>-develop` (`backend`, `frontend`) and `v<X.Y>-cli-develop` (`cli`). Their
   tips are usually the correct, most-advanced equivalent, **provided** they don't pull
   in content meant for a *later, separate* pending commit you haven't reached yet — if
   the tip is ahead of just this one PR's content, pick the earliest commit on that
   branch that's still a superset of `<theirs>`, not necessarily the tip.
4. If you cannot find any commit — on any branch — that's both a descendant of `<ours>`
   and content-equivalent to `<theirs>`, this is a genuine divergence, not a hash
   mismatch. **Stop and ask the user** which side (or manual submodule merge) is
   correct. Do not guess; silently picking "ours" here can drop a real feature, and
   picking "theirs" can regress unrelated work.

### Plain-text conflicts (`docker-compose.yml`, `docs/**/*.adoc`)

- `docker-compose.yml` image tags: once you know which submodule hash you're keeping,
  the correct tag is that same short hash — resolve the conflict marker accordingly.
- `docs/Matter_TH_User_Guide/Matter_TH_User_Guide.adoc` revision-history table: check
  whether "theirs" row is already present in "ours" under a different row number (same
  author/date/description) — if so it's a duplicate, keep "ours" verbatim. Also grep
  for the actual prose section the PR added (not just the revision-history row) to
  confirm the real content, not just the changelog line, is already present:
  ```bash
  grep -n "<distinctive phrase from theirs' diff>" docs/Matter_TH_User_Guide/Matter_TH_User_Guide.adoc
  ```
  If "theirs" adds a row/section genuinely absent from "ours", keep ours *and* append
  theirs' unique addition — don't drop real new content.

### Binary conflicts (`docs/Matter_TH_User_Guide/Matter_TH_User_Guide.pdf`)

Never attempt to merge PDF bytes. If the `.adoc` conflict resolved to pure "ours" (no
unique content from theirs merged in), take `git checkout --ours -- <pdf>`. If the
`.adoc` resolution pulled in real unique content from "theirs", flag to the user that
the PDF should be regenerated from the resolved `.adoc` rather than picked from either
side.

### After resolving everything for this commit

Stage all resolved paths, then check whether there's anything left to commit:

```bash
git diff --cached --stat
```

- **Empty** → the whole cherry-pick nets to no change (everything you kept was already
  present). `git cherry-pick --skip`. No push, no PR comment.
- **Non-empty** → `git commit --no-edit` to finalize the pick, then continue to Step 4.

## Step 4 — Push and comment (confirm with the user first)

Pushing to `origin` and commenting on a PR are externally visible — ask for
confirmation before doing either, same as any other action of that weight.

```bash
git push origin <destination>
```

For each commit that was actually committed (not skipped-as-empty) in this run, extract
its PR number and comment once per PR:

```bash
repo_slug=$(git remote get-url origin | sed -E 's#(https://github.com/|git@github.com:)([^/]+/[^/.]+)(\.git)?$#\2#')
gh pr comment <PR_NUMBER> --repo "$repo_slug" \
  --body "Cherry-picked to [<destination>](https://github.com/$repo_slug/tree/<destination>)"
```

Before commenting, check the PR doesn't already have this exact comment (in case this
workflow is being re-run after an interruption):

```bash
gh pr view <PR_NUMBER> --repo "$repo_slug" --comments \
  | grep -F "Cherry-picked to [<destination>]"
```

Skip the comment if it's already there.

## Quick reference: outcome → action

| Cherry-pick result | Submodules/content check | Action |
|---|---|---|
| Clean, non-empty | — | commit exists; push + comment |
| Clean, empty | no unmerged paths | `--skip`, no push, no comment |
| Conflict, resolved to empty | staged diff empty after resolution | `--skip`, no push, no comment |
| Conflict, resolved to non-empty | staged diff non-empty | `commit --no-edit`; push + comment |
| Conflict, no equivalent found anywhere | — | stop, ask the user |
| Branch/HEAD/status looks wrong mid-run | — | stop, ask the user |
