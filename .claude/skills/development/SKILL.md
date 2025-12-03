---
name: development
description: "MANDATORY for ALL behavioral code changes. Invoke BEFORE writing production code—features, fixes, refactors, or deletions. ESPECIALLY after debugging: once you identify a bug, STOP and invoke this skill to write a failing test BEFORE fixing it. Establishes TDD workflow (RED→GREEN→REFACTOR)."
---

# Development Workflow

This skill defines how we write code in this project. **All behavioral code changes follow Test-Driven Development.**

## When to Use This Skill

**ALWAYS use this skill when:**
- Adding new functions, modules, or features
- Fixing bugs (write a test that reproduces it FIRST)
- Changing existing behavior
- Refactoring code that affects behavior
- Deleting code that has behavioral impact

**OK to skip for:**
- Adding/modifying log statements only
- Adding/modifying code comments only
- Updating documentation files
- Pure formatting changes

**Common trap — DO NOT SKIP for:**
- "It's just a small fix" — Small fixes need tests too
- "I already know the fix" — Write the failing test first anyway
- "I'm in debugging mode" — Debugging identifies the problem; this skill fixes it properly
- "It's obvious what's wrong" — Obvious bugs still need regression tests
- "I started with logging" — If scope expanded beyond logging, STOP and invoke this skill

**Scope creep checkpoint:** If your "simple fix" grows to include:
- New functions or modified function signatures
- Changed return types (e.g., `{:ok, []}` → `{:error, reason}`)
- Modified control flow or error handling
- Any refactoring of existing code

**STOP and invoke this skill.** "I already started implementing" is not permission to skip TDD—it's a sign you should have invoked this skill earlier. Delete the implementation and start with the test.

### The Debugging → Development Handoff

If you used the `debugging` skill to investigate an issue:

1. **Debugging skill**: Investigate, identify root cause ✓
2. **STOP HERE** — Do not write the fix yet
3. **Invoke this skill**: Write a test that reproduces the bug
4. **Then fix**: Make the test pass
5. **Finishing-work skill**: Record changes, run checks

The correct flow is: `debugging` → `development` → `finishing-work`

NOT: `debugging` → implement fix → `finishing-work`

## TODO List Management (Critical for TDD)

TDD creates many small work units (one per behavior). Without tracking, context compaction will cause you to lose track of planned tests, forget edge cases, and produce incomplete implementations.

### When to Use the TODO List

**ALWAYS create a TODO list when:**
- The task requires more than one test
- You're implementing a new feature with multiple behaviors
- You're fixing a bug that has related edge cases
- The work might exceed a single context window

**Create the TODO list BEFORE writing any code.** Plan all the behaviors first, then execute one by one.

### What Makes a Good TODO Item

Each TODO must be **self-contained**—it should have enough detail to implement even if all prior context is lost to compaction.

**BAD TODO items** (too vague, depend on memory):
```
- Add validation
- Test error case
- Handle edge cases
- Fix the container bug
```

**GOOD TODO items** (self-contained, specific):
```
- Test: Containers.validate_name/1 returns {:error, :invalid_chars} when name contains spaces
- Test: Containers.validate_name/1 returns {:error, :too_long} when name exceeds 64 chars
- Test: Containers.validate_name/1 returns {:ok, name} when name is valid alphanumeric
- Test: Container.start/1 returns {:error, :already_running} when container status is :running
```

Each good item specifies:
- The module/function being tested
- The specific input condition
- The expected output

### TODO Workflow During TDD

1. **Before coding**: Create detailed TODO list with all planned behaviors
2. **Start first item**: Mark as `in_progress`, write the test (RED)
3. **After GREEN**: Mark as `completed` immediately—not after refactor, not in batches
4. **Discover new behavior?**: Add it to the TODO list before continuing
5. **Context getting long?**: Review TODO list, ensure remaining items are detailed enough to survive compaction

### Surviving Context Compaction

If you notice the context is getting long or you've been working for a while:

1. **Review your TODO list** — Are remaining items detailed enough?
2. **Add specifics** — Update vague items with function names, expected values, test assertions
3. **Note current state** — If mid-test, update the TODO item with what's done vs remaining
4. **Trust the TODO list** — After compaction, the TODO list is your source of truth

### Example: Planning a Feature

User asks: "Add name validation to containers"

**Step 1: Plan behaviors and create TODO list**
```
- Test: validate_name/1 returns {:ok, name} for valid alphanumeric names (e.g., "my-container-1")
- Test: validate_name/1 returns {:error, :empty} for empty string
- Test: validate_name/1 returns {:error, :invalid_chars} for names with spaces
- Test: validate_name/1 returns {:error, :invalid_chars} for names with special chars except hyphen
- Test: validate_name/1 returns {:error, :too_long} for names > 64 characters
- Test: validate_name/1 returns {:error, :invalid_start} for names starting with hyphen
- Integrate: Call validate_name/1 from Containers.create/1 changeset
```

**Step 2: Work through list one by one, marking complete after each GREEN**

This detailed list survives compaction and ensures complete implementation.

## Before You Write Any Code

1. **Read `/TESTING.md`** - Contains project-specific patterns, coverage targets, and examples
2. **Understand the change** - What behavior are you adding, modifying, or removing?
3. **Identify the test location** - Core module unit test? Context integration test? LiveView test?

## The TDD Cycle

Every code change follows RED → GREEN → REFACTOR. No exceptions.

### RED: Write a Failing Test First

**CRITICAL: "Failing test" means an assertion failure, NOT a compilation error.**

A compilation error is not RED—it's broken. The test must:
1. Compile successfully
2. Run to completion
3. Fail on an assertion (wrong return value, missing behavior)

#### The Correct Flow

**Step 1: Write the test**
```elixir
test "returns error when container not found" do
  assert {:error, :not_found} = Containers.get_container("nonexistent")
end
```

**Step 2: Create stubs so it compiles**

If the module or function doesn't exist, create minimal stubs:
```elixir
defmodule Msfailab.Containers do
  @doc "Retrieves a container by ID."
  @spec get_container(String.t()) :: {:ok, Container.t()} | {:error, atom()}
  def get_container(_id) do
    # Stub - returns wrong value to make test fail
    {:ok, nil}
  end
end
```

**Step 3: Run the test—watch it FAIL on the assertion**
```
1) test returns error when container not found
   match (=) failed
   left:  {:error, :not_found}
   right: {:ok, nil}
```

This is a valid RED state. The code compiles, the test runs, and it fails because the behavior isn't implemented.

#### Invalid RED States

| Situation | Problem | Fix |
|-----------|---------|-----|
| `** (UndefinedFunctionError)` | Function doesn't exist | Add stub function |
| `** (CompileError)` | Module doesn't exist | Create module with stubs |
| `** (ArgumentError)` | Wrong arity | Fix stub signature |

These are not "failing tests"—they're broken code. Fix them before claiming RED.

### GREEN: Make It Pass

Write the **simplest code** that makes the test pass. Nothing more.

```elixir
def get_container(id) do
  case Repo.get(Container, id) do
    nil -> {:error, :not_found}
    container -> {:ok, container}
  end
end
```

### REFACTOR: Clean Up

With tests green, improve the code:
- Better names
- Remove duplication
- Simplify logic

Run tests after each change. They must stay green.

### Repeat

Move to the next behavior. One test at a time.

## Why Test-First Is Non-Negotiable

- **Design feedback**: You experience your API as a user before implementing it
- **Confidence**: Tests that failed first actually verify behavior
- **Small steps**: Bugs are caught immediately, not after building on broken foundations
- **Documentation**: Tests describe what the code does

If you wrote production code first, **delete it** and start with the test.

## Project Patterns

### Core Module Pattern

GenServers are thin integration layers. Business logic lives in `Core` modules:

```elixir
# GenServer (glue code - minimal testing needed)
defmodule Msfailab.Containers.Container do
  alias Msfailab.Containers.Container.Core

  def handle_info({:docker, event}, state) do
    {:noreply, Core.handle_docker_event(state, event)}
  end
end

# Core module (pure functions - comprehensive testing)
defmodule Msfailab.Containers.Container.Core do
  def handle_docker_event(state, event), do: ...
end
```

**Why**: Core modules are pure functions—easy to test, no process setup, fast execution.

### What to Test

| Test | Skip |
|------|------|
| Validation logic | Phoenix/Ecto boilerplate |
| State transformations | Pure delegation |
| Business rules | OTP callbacks that only forward |
| Event handling decisions | HTML/CSS structure |

### Test Behavior, Not Implementation

```elixir
# Bad: Brittle, breaks when message changes
assert {:error, "docker container ran into a timeout; restarting"} = result

# Good: Tests the behavior
assert {:error, message} = result
assert message =~ "timeout"
```

### Mocking External Systems

Use Mox for Docker and Metasploit RPC:

```elixir
expect(DockerAdapterMock, :start_container, fn name, _labels ->
  {:ok, "container_id"}
end)
```

Mock at system boundaries, not internal modules.

### LiveView Testing

Extract logic to helper functions that are trivially testable:

```elixir
# In helpers module - unit test this
def ready_for_commands?(%{health: :healthy}, true), do: true
def ready_for_commands?(_, _), do: false

# In template - no logic to test
<.status_indicator ready={ready_for_commands?(@container, @console_ready)} />
```

## Workflow by Task Type

### New Feature

1. **Plan**: Identify all behaviors and create detailed TODO list (see "TODO List Management" above)
2. **For each TODO item**:
   - Mark as `in_progress`
   - Write a test for the behavior (RED)
   - Create stubs so the test compiles
   - Run the test—verify it fails on an assertion
   - Implement minimal code to pass (GREEN)
   - Mark as `completed` immediately
   - Refactor if needed
3. Extract to Core module if logic belongs outside GenServer
4. Verify coverage with `mix check`

### Bug Fix (IMPORTANT: Do Not Skip This)

**If you came from the debugging skill, this is where you are now.**

The bug fix workflow ensures every bug becomes a regression test:

1. **Write a test that reproduces the bug (RED)**
   - This test documents the defect
   - It MUST fail, proving the bug exists
   - If you can't write a failing test, you don't understand the bug yet

2. **Verify the test fails for the right reason**
   - The assertion should fail because of the bug behavior
   - Not because of compilation errors or unrelated issues

3. **Fix with minimal code (GREEN)**
   - Only now do you write the fix
   - Write the simplest code that makes the test pass

4. **Identify related edge cases** — If multiple, add them to the TODO list:
   - What similar inputs might trigger the same bug?
   - What boundary conditions exist?
   - Create a detailed TODO item for each edge case test

5. **For each edge case TODO**: RED → GREEN → mark complete

6. **Refactor if needed**

**Why this order matters:** A bug without a test will recur. The test is the proof the bug existed and the proof it's now fixed.

### Refactoring

1. Verify existing tests pass—they define correct behavior
2. Make changes in small steps, running tests after each
3. Maintain or improve coverage
4. No new `coveralls-ignore` without documented reason

### Deleting Code

1. Identify tests that cover the code being removed
2. Verify those tests will fail or become irrelevant
3. Remove the code
4. Remove or update tests accordingly
5. Verify no coverage regressions elsewhere

## Commands

```bash
mix test                           # Full suite
mix test test/path_test.exs        # Single file
mix test test/path_test.exs:42     # Single test at line
mix test --failed                  # Re-run failures
PRINT_LOGS=true mix test           # With log output
mix check                          # Full quality check including coverage
```

## Coverage Targets

| Category | Target |
|----------|--------|
| Core modules (pure logic) | 95%+ |
| Context modules (API layer) | 85%+ |
| GenServers | 70%+ |
| LiveView helpers | 95%+ |
| **Overall** | **85%+** |

Lower GenServer targets reflect that they should contain minimal logic. If a GenServer needs high coverage, extract logic to a Core module.

## Quality Gates

Before marking any task complete:

1. All tests pass
2. `mix check` passes (includes coverage)
3. No skipped or pending tests without justification
4. New code follows Core Module Pattern where applicable

Then invoke the `finishing-work` skill to record changes and run final checks.
