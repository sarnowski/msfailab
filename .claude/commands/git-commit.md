# Git Commit Command

Create a high-quality git commit from recorded changes in PENDING.md.

## Workflow

Execute these steps in order. Stop and report to the user if any step fails.

### Step 1: Read and Parse PENDING.md

Read `/PENDING.md` and extract all entries. Each entry starts with `## ` and ends with `---`.

If PENDING.md is empty (no entries, only the header comment), stop and tell the user:
```
No pending changes recorded in PENDING.md.
Record your changes using the recording-changes skill before committing.
```

### Step 2: Run mix precommit

Run `mix precommit` and wait for it to complete.

If it fails, stop and show the errors. Tell the user:
```
mix precommit failed. Fix the issues above before committing.
```

Do not proceed until precommit passes.

### Step 3: Compare Files

Get the list of files claimed in PENDING.md entries (from all `**Files:**` sections).
Get the list of actually changed files using `git diff --name-only HEAD` and `git ls-files --others --exclude-standard` (for untracked files).

Compare the two lists. If there's a mismatch, stop and present it clearly:

```
File mismatch detected between PENDING.md and actual changes.

Files changed but NOT documented in PENDING.md:
  - lib/msfailab/some_file.ex
  - test/some_test.exs

Files documented but NOT actually changed:
  - lib/msfailab/claimed_file.ex

Resolution required:
1. Add entries to PENDING.md for undocumented changes, OR
2. Remove entries for files that weren't changed, OR
3. Investigate unexpected changes

Cannot proceed until PENDING.md matches actual changes.
```

Do not proceed until files match.

### Step 4: Synthesize Commit Message

Create a commit message with:

**Summary line (first line):**
- Describe the combined VALUE of all changes
- Natural language, no type prefixes like "feat:" or "fix:"
- Maximum 72 characters
- Imperative mood ("Add feature" not "Added feature")

**Body (after blank line):**
- Include each PENDING.md entry, cleaned up
- Remove the `## category(scope):` prefix from headings, keep just the description
- Keep the Why, Approach, and Files sections
- Separate entries with blank lines

### Step 5: Present for Approval

Show the user:
1. The synthesized commit message
2. List of files to be committed
3. Number of PENDING.md entries being included

Ask if they want to:
- Proceed with the commit
- Edit the summary line
- Abort

### Step 6: Execute Commit

If approved:

```bash
git add -A
git commit -m "$(cat <<'EOF'
<commit message here>
EOF
)"
```

### Step 7: Clear PENDING.md

Reset PENDING.md to just the header template:

```markdown
# Pending Changes

<!--
Agents: Append entries below when completing tasks. One entry per logical change.

Format:
## category(scope): Short description

**Why:** Why was this change necessary? What problem does it solve?

**Approach:** How did you solve it? What alternatives were considered?

**Files:**
- path/to/file.ex
- path/to/other_file.ex (new)

---

Categories: feature, fix, refactor, test, docs, chore
Scope: The subsystem affected (tracks, containers, workspaces, etc.)

Keep entries concise but informative. Focus on WHY, not WHAT (the diff shows what).
-->

```

### Step 8: Report Success

Show:
- Commit hash
- Summary line
- Number of files committed
- Confirmation that PENDING.md was cleared

## Example Commit Message

For a PENDING.md with two entries (a feature and a fix), the commit message might be:

```
Enable real-time console streaming and fix container restart race

Real-time console output streaming
---------------------------------
Why: Users needed to see MSF console output as it happens rather than
waiting for command completion. This enables interactive research workflows.

Approach: Implemented Server-Sent Events from TrackServer to LiveView.
Added ConsoleBuffer GenServer to handle backpressure.

Files:
- lib/msfailab/tracks/track_server.ex
- lib/msfailab/tracks/console_buffer.ex (new)
- lib/msfailab_web/live/track_live.ex

Container restart race condition
--------------------------------
Why: Rapid restarts caused port conflicts because old process wasn't
fully terminated before new one started.

Approach: Added synchronous termination confirmation before starting
new container.

Files:
- lib/msfailab/containers/container.ex
```

## Important Notes

- Never skip the precommit check
- Never proceed with file mismatches
- Always get user approval before committing
- The summary line is critical—it should convey VALUE, not just list changes
