---
name: finishing-work
description: "STOP. Did you modify code? Invoke this BEFORE telling user 'done'. Mandatory completion ritual: runs precommit checks + records changes to PENDING.md. Skipping = broken commits. Use when: task complete, user says 'done'/'commit'/'looks good', switching topics, or session ending."
---

# Finishing Work

**STOP. Before you tell the user the task is complete, invoke this skill.**

This is the mandatory completion ritual for any work that modified code. It ensures quality checks pass AND changes are recorded for commit.

## When to Invoke

Invoke this skill when ANY of these are true:

- You finished implementing/fixing something
- User says: "done", "that's good", "commit", "looks good", "ship it"
- You're about to summarize results to the user
- Conversation is switching to a different topic
- Session appears to be ending

**If you modified .ex, .exs, .heex, or test files → you MUST invoke this skill.**

## The Completion Checklist

### Step 1: Run Precommit

```bash
mix precommit
```

**Must pass with zero issues.** If it fails:

1. Fix issues in priority order: compiler → dialyzer → sobelow → tests → credo
2. Re-run `mix precommit`
3. Repeat until clean

Do NOT proceed to Step 2 until precommit passes.

### Step 2: Record Changes to PENDING.md

Append an entry to `/PENDING.md` for each logical change:

```markdown
## category(scope): Short description

**Why:** Why was this change necessary? What problem does it solve?

**Approach:** How did you solve it? What alternatives were considered?

**Files:**
- path/to/file.ex
- path/to/other_file.ex (new)
- path/to/deleted.ex (deleted)

---
```

#### Categories

| Category | Use for |
|----------|---------|
| `feature` | New functionality |
| `fix` | Bug fixes |
| `refactor` | Code restructuring without behavior change |
| `test` | Test additions or modifications |
| `docs` | Documentation changes |
| `chore` | Build, tooling, dependencies |

#### Scope

The subsystem affected: `tracks`, `containers`, `workspaces`, `events`, `web`, `llm`, etc.

### Step 3: Verify

Before responding to user:

- [ ] `mix precommit` passed
- [ ] PENDING.md entry added
- [ ] Files list in entry matches actual changes

## Quality Standards for PENDING.md

### Focus on WHY, not WHAT

The diff shows what changed. Your entry explains why.

**Bad:**
```markdown
**Why:** Changed the timeout from 5000 to 10000.
```

**Good:**
```markdown
**Why:** Container startup was timing out on slower machines during initial image pull.
```

### Be Specific About Files

List every file you modified. Mark new files with `(new)` and deleted files with `(deleted)`.

### One Entry Per Logical Change

If you did two unrelated things, write two entries. Related changes (feature + its tests) can be one entry.

## What Happens If You Skip This

- `/git-commit` command validates PENDING.md against actual diff
- Mismatches block the commit
- User has to manually reconcile changes
- Trust is damaged

## Example Complete Flow

```
1. [You complete a feature]
2. [STOP - invoke finishing-work]
3. Run: mix precommit
4. [Fix any issues, re-run until clean]
5. Append entry to PENDING.md
6. [Now respond to user with summary]
```

## Quick Reference

```
Modified code? → STOP → mix precommit → PENDING.md → respond to user
```
