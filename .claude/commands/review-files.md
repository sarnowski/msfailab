# Code Review Command

Review the specified file(s) against project standards and best practices.

## Setup

1. Read @TESTING.md and @LOGGING.md completely
2. Read @CLAUDE.md for architecture context
3. Identify and read key dependencies (imports, callers)

## Review Criteria

### Category 1: Architecture & Patterns

| ID | Check | Severity |
|----|-------|----------|
| A1 | Core Module Pattern: Is business logic extracted from GenServers into pure `Core` modules? | Major |
| A2 | Thin GenServers: Are GenServer callbacks just delegation without conditional logic? | Major |
| A3 | Event-Driven Communication: Is `Events.broadcast` used instead of direct process calls for cross-module communication? | Minor |
| A4 | Mocking Boundaries: Are external systems (Docker, MSGRPC) accessed only through behavior-backed modules? | Major |

### Category 2: Testing

| ID | Check | Severity |
|----|-------|----------|
| T1 | Test Existence: Do tests exist for all public functions? | Major |
| T2 | Core Module Coverage: Are Core modules covered at 95%+? | Major |
| T3 | Behavior Testing: Do tests verify behavior, not implementation (no HTML/CSS assertions)? | Minor |
| T4 | Async Tests: Are tests `async: true` unless documented why not? | Minor |
| T5 | coveralls-ignore Justification: Is every exclusion documented with a reason? | Minor |

### Category 3: Logging & Observability

| ID | Check | Severity |
|----|-------|----------|
| L1 | Correct Log Levels: error/warning/info/debug used per LOGGING.md definitions? | Minor |
| L2 | Structured Metadata: Logs use keyword metadata, not string interpolation? | Minor |
| L3 | No Sensitive Data: Credentials, tokens never logged at info level or above? | Critical |
| L4 | Logger.metadata Set: Process context (workspace_id, track_id) set early? | Minor |

### Category 4: Code Quality

| ID | Check | Severity |
|----|-------|----------|
| Q1 | No Legacy/Backwards Compatibility: Code is clean without deprecated accommodations? | Major |
| Q2 | YAGNI: No over-engineering, unused abstractions, or speculative features? | Minor |
| Q3 | Documentation Accuracy: @moduledoc and @doc match actual behavior? | Minor |
| Q4 | Module Complexity: Should the module be split? (>300 LOC, >10 public functions) | Suggestion |

### Category 5: Elixir/OTP Idioms

| ID | Check | Severity |
|----|-------|----------|
| E1 | Pattern Matching: Proper use of pattern matching instead of conditionals? | Minor |
| E2 | Error Tuples: Consistent `{:ok, _}` / `{:error, _}` return patterns? | Major |
| E3 | Type Specs: Public functions have `@spec` definitions? | Suggestion |
| E4 | Supervision: Correct restart strategies and process linking? | Major |
| E5 | start_supervised! in Tests: Tests use `start_supervised!/1`, not raw `start_link`? | Minor |
| E6 | Structs over Maps: Are structs used instead of freeform maps for type safety? Prefer composition over duplicating fields or mapping data between structs. | Major |
| E7 | Struct Size: Are large structs (>10 fields) justified? Could they be composed from smaller structs or indicate technical debt? | Minor |
| E8 | Let It Crash: No overly defensive code? Avoid nil/empty/`:not_found` checks for conditions that should never occur in practice. Let the process crash to surface bugs instead of silently handling impossible states. | Major |

### Category 6: Security

| ID | Check | Severity |
|----|-------|----------|
| S1 | Input Validation: External inputs validated at boundaries? | Critical |
| S2 | No Command Injection: Shell commands properly escaped/sanitized? | Critical |
| S3 | Authorization: Workspace/track access properly scoped? | Critical |

## Output Format

For each finding, report:

```
### [SEVERITY] ID: Brief Title

**Location:** `file_path:line_number`
**Description:** What is wrong
**Recommendation:** How to fix it
**Effort:** Low/Medium/High
```

## Gemini Cross-Review

After completing your analysis, invoke Gemini:

```bash
gemini -p "Review the following Elixir file for an OTP/Phoenix application.

<criteria>
[Paste the criteria table above]
</criteria>

<file path=\"$FILE_PATH\">
[File contents]
</file>

Report findings in this exact format:
- ID: [matching ID from criteria or NEW-n for novel findings]
- Severity: Critical/Major/Minor/Suggestion
- Location: file:line
- Issue: [description]
- Fix: [recommendation]"
```

## Reconciliation

After receiving Gemini's report:

1. **Merge findings** - Combine unique findings from both reviews
2. **Resolve conflicts** - If you disagree with Gemini, explain why
3. **Prioritize** - Order by: Critical > Major > Minor > Suggestion
4. **Estimate effort** - Tag each fix as Low/Medium/High effort

## Final Report Structure

```markdown
# Code Review: [filename]

## Summary
- Files reviewed: N
- Critical: N | Major: N | Minor: N | Suggestions: N
- Estimated total effort: X hours

## Critical Findings
[List all critical findings]

## Major Findings
[List all major findings]

## Minor Findings
[List all minor findings]

## Suggestions
[Optional improvements]

## Agreements/Disagreements with Gemini
[Where reviews aligned or differed]
```

## Instructions

Now review the following file(s): $ARGUMENTS
