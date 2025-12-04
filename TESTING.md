# Testing Strategy

This document defines the testing strategy for msfailab, targeting **95%+ code coverage** while maintaining fast, reliable tests.

## Quick Reference

### The Golden Rules

1. **Every public function must have at least one test** (unless module is fully ignored)
2. **Every pattern-matching clause must be exercised** by at least one test
3. **Every event handler must have a test** (LiveView, GenServer, PubSub)
4. **Time sources must be injectable** - never call `System.monotonic_time` directly
5. **Timeouts must be configurable** - tests use 5-20ms, production uses seconds/minutes

### Coverage Targets

| Module Category | Target | Strategy |
|-----------------|--------|----------|
| Core modules (pure logic) | 95%+ | Unit test all branches |
| Context modules (API layer) | 90%+ | Integration tests |
| GenServers | 85%+ | Test callbacks with logic, ignore pure delegation |
| LiveView helpers | 95%+ | Unit test all branches |
| LiveView callbacks | 90%+ | Integration test every handler |
| LiveView render/components | N/A | coveralls-ignore if logic-free |
| **Overall** | **95%+** | |

---

## Core Principles

### 1. Test Every Public Function

Every `def` (public function) in a module **must** have at least one test, unless the entire module is marked as an ignored boundary.

```elixir
# If your module has these public functions:
defmodule MyModule do
  def format_prompt(prompt), do: ...
  def render_output(output), do: ...
  def escape(text), do: ...
end

# Your test file MUST have:
describe "format_prompt/1" do
  test "formats simple prompt" do ...
  # + tests for edge cases
end

describe "render_output/1" do
  test "renders output" do ...
end

describe "escape/1" do
  test "escapes special characters" do ...
end
```

### 2. Test Every Pattern-Matching Clause

When a function has multiple clauses, **every clause** must be exercised:

```elixir
# Production code with 4 clauses:
def format_error(:not_found), do: "Not found"
def format_error(:timeout), do: "Timeout"
def format_error({:validation, msg}), do: "Validation: #{msg}"
def format_error(other), do: inspect(other)

# Tests MUST cover ALL 4 clauses:
describe "format_error/1" do
  test "formats :not_found" do
    assert format_error(:not_found) == "Not found"
  end

  test "formats :timeout" do
    assert format_error(:timeout) == "Timeout"
  end

  test "formats validation tuple" do
    assert format_error({:validation, "bad input"}) == "Validation: bad input"
  end

  test "formats unknown errors" do
    assert format_error(:unknown) == ":unknown"
  end
end
```

### 3. Test Behavior, Not Implementation Details

Avoid brittle tests that break when implementation changes but behavior stays the same.

**Error Messages:**
```elixir
# Bad: Exact message matching (brittle)
assert {:error, "docker container ran into a timeout; restarting"} = result

# Good: Check for keyword when message content matters
assert {:error, message} = result
assert message =~ "timeout"

# Good: Check error exists when content doesn't matter
assert {:error, _message} = result

# Good: Check error type/struct
assert {:error, %TimeoutError{}} = result
```

**HTML/CSS Testing:**
```elixir
# Bad: Testing HTML structure (extremely brittle)
assert html =~ ~s(<div class="flex items-center gap-2">)

# Bad: Testing CSS classes
assert element(view, ".bg-red-500.rounded-lg")

# Good: Test that data is present
assert html =~ "Running"
assert has_element?(view, "#container-status")
```

### 4. Core Module Pattern

GenServers and LiveViews should be thin integration layers. Business logic lives in companion modules with pure functions.

**When to Extract to a Core Module:**

Extract when ANY of these apply:
- Function has more than 3 conditional branches
- Function is longer than 15 lines
- Function requires mocking external systems to test
- Multiple callbacks share similar logic
- `init/1` has more than 10 lines of logic

Do NOT extract when:
- Logic is a simple one-liner
- Function is pure delegation with no conditionals
- Extraction would create a module with only 1-2 trivial functions

**Example - GenServer with Core module:**

```elixir
# GenServer (glue code - thin layer)
defmodule Msfailab.Containers.Container do
  use GenServer
  alias Msfailab.Containers.Container.Core

  def handle_call(:get_status, _from, state) do
    {:reply, Core.build_status(state), state}
  end

  def handle_info({:docker, event}, state) do
    {:noreply, Core.handle_docker_event(state, event)}
  end
end

# Core module (pure functions - comprehensive testing)
defmodule Msfailab.Containers.Container.Core do
  def build_status(state), do: ...
  def handle_docker_event(state, event), do: ...
end
```

**Example - Complex init extraction:**

```elixir
# Bad: Complex init that's hard to test
def init(args) do
  workspace = Repo.get!(Workspace, args.workspace_id)
  track = Repo.get!(Track, args.track_id)
  entries = Tracks.list_chat_entries(track.id)
  tool_invocations = rebuild_tool_invocations(entries)
  # ... 50 more lines of setup
  {:ok, state}
end

# Good: Thin init that delegates to testable Core
def init(args) do
  case Core.initialize(args) do
    {:ok, state, actions} ->
      Enum.each(actions, &execute_action/1)
      {:ok, state}
    {:error, reason} ->
      {:stop, reason}
  end
end

# Core.initialize/1 is now a pure function that's easy to unit test
```

### 5. Speed Requirements

| Test Type | Target | Max Allowed |
|-----------|--------|-------------|
| Unit test | < 10ms | 50ms |
| Integration test | < 100ms | 200ms |
| Full suite | < 30s | 60s |

Tests exceeding these limits indicate design problems, not testing problems.

### 6. Async by Default

All tests should run with `async: true` unless they:
- Share global Mox expectations (use `set_mox_private` to enable async)
- Require sequential database operations on the same records
- Test cross-process coordination that can't be isolated

---

## LiveView Testing

### The Logic-Free Template Pattern

Templates should contain **zero conditional logic**. All decisions are made by functions that can be unit tested.

**Before (untestable):**
```heex
<div class={if @status in [:running, :finished], do: "visible", else: "hidden"}>
  <%= if @container.health == :healthy and @console_ready do %>
    <span class="text-green-500">Ready</span>
  <% else %>
    <span class="text-yellow-500">Starting...</span>
  <% end %>
</div>
```

**After (testable):**
```heex
<div class={visibility_class(@status)}>
  <.status_indicator ready={ready_for_commands?(@container, @console_ready)} />
</div>
```

```elixir
# In a helpers module - easily unit tested
def visibility_class(status) when status in [:running, :finished], do: "visible"
def visibility_class(_status), do: "hidden"

def ready_for_commands?(%{health: :healthy}, true), do: true
def ready_for_commands?(_, _), do: false
```

### Test Every Event Handler

**Every `handle_event/3` clause must have at least one integration test.** If a LiveView has 10 event handlers, there should be 10+ tests.

```elixir
defmodule MsfailabWeb.WorkspaceLiveTest do
  use MsfailabWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  # Test EVERY event handler
  describe "handle_event toggle_input_menu" do
    test "toggles input menu visibility", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/workspace/test")

      # Menu starts hidden
      refute has_element?(view, "#input-menu.visible")

      # Toggle on
      view |> element("#toggle-menu-btn") |> render_click()
      assert has_element?(view, "#input-menu")
    end
  end

  describe "handle_event select_model" do
    test "updates selected model", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/workspace/test/#{track.slug}")

      view |> element("#model-selector") |> render_click(%{"model" => "claude-3"})

      # Verify model was updated
      updated_track = Tracks.get_track!(track.id)
      assert updated_track.current_model == "claude-3"
    end
  end

  # ... test for EVERY other event handler
end
```

### Test Every PubSub Handler

Every `handle_info/2` that processes a PubSub event must be tested:

```elixir
describe "handle_info ConsoleChanged" do
  test "updates console state when track matches", %{conn: conn, track: track} do
    {:ok, view, _html} = live(conn, ~p"/workspace/test/#{track.slug}")

    # Simulate PubSub event
    send(view.pid, %ConsoleChanged{
      track_id: track.id,
      status: :ready,
      prompt: "msf6 > "
    })

    # Verify state updated
    assert render(view) =~ "msf6 &gt;"
  end

  test "ignores console changes for other tracks", %{conn: conn, track: track} do
    {:ok, view, _html} = live(conn, ~p"/workspace/test/#{track.slug}")

    # Event for different track
    send(view.pid, %ConsoleChanged{track_id: track.id + 999, status: :ready})

    # No crash, state unchanged
    assert render(view)
  end
end
```

### Testing View Helpers

Most LiveView logic should be in helper functions that are trivially testable:

```elixir
defmodule MsfailabWeb.WorkspaceLive.HelpersTest do
  use ExUnit.Case, async: true
  alias MsfailabWeb.WorkspaceLive.Helpers

  describe "ready_for_commands?/2" do
    test "returns true when container healthy and console ready" do
      container = %{health: :healthy}
      assert Helpers.ready_for_commands?(container, true)
    end

    test "returns false when container unhealthy" do
      container = %{health: :starting}
      refute Helpers.ready_for_commands?(container, true)
    end

    test "returns false when console not ready" do
      container = %{health: :healthy}
      refute Helpers.ready_for_commands?(container, false)
    end
  end
end
```

### Ignoring Render Functions

```elixir
# coveralls-ignore-start
# Reason: Logic-free template, all conditional logic tested via Helpers module
def render(assigns) do
  ~H"""
  ...
  """
end
# coveralls-ignore-stop
```

This is acceptable **only when**:
1. Template contains no inline conditionals (`if`, `case`, `cond`)
2. All helper functions called by template are tested
3. Template only calls functions and iterates over data

---

## Testing Temporal/Timing Code

Code involving timing, delays, retries, or duration calculations requires special patterns.

### Principle: Make Time Injectable

Production code must **never** call time functions directly. Accept time sources as parameters.

**Bad - Direct time calls (untestable):**
```elixir
def retry_until_ready(try_fn, timing) do
  start_time = System.monotonic_time(:millisecond)  # Can't control in tests
  do_retry(try_fn, start_time, timing)
end

defp do_retry(try_fn, start_time, timing) do
  elapsed = System.monotonic_time(:millisecond) - start_time  # Can't control
  if elapsed > timing.max_wait_time do
    {:error, :timeout}
  else
    case try_fn.() do
      {:error, :busy} ->
        Process.sleep(timing.delay)  # Tests must actually wait
        do_retry(try_fn, start_time, timing)
      result -> result
    end
  end
end
```

**Good - Injectable time and sleep (fully testable):**
```elixir
def retry_until_ready(try_fn, timing, opts \\ []) do
  time_fn = Keyword.get(opts, :time_fn, &System.monotonic_time/1)
  sleep_fn = Keyword.get(opts, :sleep_fn, &Process.sleep/1)
  start_time = time_fn.(:millisecond)
  do_retry(try_fn, start_time, timing, time_fn, sleep_fn)
end

defp do_retry(try_fn, start_time, timing, time_fn, sleep_fn) do
  elapsed = time_fn.(:millisecond) - start_time
  if elapsed > timing.max_wait_time do
    {:error, :timeout}
  else
    case try_fn.() do
      {:error, :busy} ->
        sleep_fn.(timing.delay)
        do_retry(try_fn, start_time, timing, time_fn, sleep_fn)
      result -> result
    end
  end
end
```

**Test with controlled time:**
```elixir
test "times out after max_wait_time" do
  timing = %{delay: 100, max_wait_time: 500}

  # Simulate time advancing 200ms per call
  {:ok, time_agent} = Agent.start_link(fn -> 0 end)
  time_fn = fn :millisecond ->
    Agent.get_and_update(time_agent, fn t -> {t, t + 200} end)
  end

  # No-op sleep - instant execution
  sleep_fn = fn _ms -> :ok end

  try_fn = fn -> {:error, :busy} end

  # Will "timeout" after 3 calls (0, 200, 400, 600 > 500)
  assert {:error, :timeout} =
    MyModule.retry_until_ready(try_fn, timing, time_fn: time_fn, sleep_fn: sleep_fn)

  Agent.stop(time_agent)
end
```

### Configurable Timeouts

All timeout values must be configurable with production defaults and test-friendly overrides.

```elixir
# Production code
@default_timing %{
  initial_delay: 100,
  max_delay: 2_000,
  max_wait_time: 60_000
}

def timing_config do
  case Application.get_env(:msfailab, :executor_timing) do
    nil -> @default_timing
    overrides when is_map(overrides) -> Map.merge(@default_timing, overrides)
    _ -> @default_timing
  end
end
```

```elixir
# config/test.exs
config :msfailab, :executor_timing, %{
  initial_delay: 1,
  max_delay: 5,
  max_wait_time: 20
}
```

### Test Timeout Selection

| Scenario | Timeout | Rationale |
|----------|---------|-----------|
| Immediate success | N/A | No timeout needed |
| Single retry | 5-10ms | Just enough for one retry cycle |
| Multiple retries | 10-20ms | Allow retry loop to execute |
| Timeout behavior | 10-20ms | Fast enough, won't flake |
| **Never use** | > 100ms | Too slow for unit tests |

### Duration Calculations

When calculating durations, accept timestamps as parameters rather than fetching them internally.

**Bad:**
```elixir
def execute_with_timing(fun) do
  start = System.monotonic_time(:millisecond)
  result = fun.()
  duration = System.monotonic_time(:millisecond) - start
  {result, duration}
end
```

**Good:**
```elixir
def execute_with_timing(fun, start_time, end_time_fn \\ &System.monotonic_time/1) do
  result = fun.()
  duration = end_time_fn.(:millisecond) - start_time
  {result, duration}
end

# Test with fixed duration
test "calculates duration correctly" do
  fun = fn -> :ok end
  start_time = 1000
  end_time_fn = fn :millisecond -> 1500 end

  assert {:ok, 500} = MyModule.execute_with_timing(fun, start_time, end_time_fn)
end
```

### Warning Signs of Bad Timing Tests

- Tests take > 50ms each
- Tests flake on CI but pass locally
- Tests use `Process.sleep` without injectable alternative
- Tests assert on wall-clock time differences
- Tests have comments like "increase timeout if flaky"

---

## Test Categories

### Unit Tests (Target: 70% of tests)

Pure function tests with no external dependencies.

```elixir
defmodule Msfailab.Containers.Container.CoreTest do
  use ExUnit.Case, async: true
  alias Msfailab.Containers.Container.Core

  describe "handle_docker_event/2" do
    test "transitions from starting to running on healthy event" do
      state = %{status: :starting, container_id: "abc123"}
      event = {:healthy, %{status: "running"}}

      new_state = Core.handle_docker_event(state, event)

      assert new_state.status == :running
    end
  end
end
```

**Characteristics:**
- No database, no processes, no mocks
- Test all branches and edge cases
- Use property-based testing for complex transformations
- Run in milliseconds

### Integration Tests (Target: 25% of tests)

Test module boundaries with mocked external systems.

```elixir
defmodule Msfailab.ContainersTest do
  use Msfailab.ContainersCase, async: false
  import Mox

  describe "start_container/1" do
    setup [:create_workspace_and_container]

    test "starts container and returns pid", %{container: container} do
      expect(DockerAdapterMock, :start_container, fn _name, _labels ->
        {:ok, "container_123"}
      end)

      expect(DockerAdapterMock, :get_rpc_endpoint, fn "container_123" ->
        {:ok, %{host: "localhost", port: 55553}}
      end)

      assert {:ok, pid} = Containers.start_container(container)
      assert is_pid(pid)
    end
  end
end
```

### Lifecycle/State Tests (Target: 5% of tests)

Test complex state machines and event flows.

```elixir
defmodule Msfailab.Containers.ContainerLifecycleTest do
  use Msfailab.ContainersCase, async: false

  describe "container lifecycle" do
    test "transitions through startup sequence" do
      expect_docker_startup_sequence()

      {:ok, container} = create_container()
      {:ok, pid} = Containers.start_container(container)

      assert_receive %ContainerUpdated{status: :starting}, 100
      assert_receive %ContainerUpdated{status: :running}, 100
      assert_receive %ConsoleUpdated{state: :ready}, 100

      assert {:ok, %{status: :running}} = Containers.get_status(container.id)
    end
  end
end
```

---

## Mocking Strategy

### What We Mock

| System | Mock Module | Behavior |
|--------|------------|----------|
| Docker API | `DockerAdapterMock` | `Msfailab.Containers.DockerAdapter` |
| Metasploit RPC | `MsgrpcClientMock` | `Msfailab.Containers.Msgrpc.Client` |

### Mock Configuration

```elixir
# test/test_helper.exs
Mox.defmock(Msfailab.Containers.DockerAdapterMock,
  for: Msfailab.Containers.DockerAdapter
)

Mox.defmock(Msfailab.Containers.Msgrpc.ClientMock,
  for: Msfailab.Containers.Msgrpc.Client
)
```

### Mock Usage Patterns

**Explicit expectations (preferred):**
```elixir
expect(DockerAdapterMock, :start_container, fn name, _labels ->
  assert String.starts_with?(name, "msfailab-")
  {:ok, "container_id"}
end)
```

**Stub for irrelevant calls:**
```elixir
stub(DockerAdapterMock, :health_check, fn _id -> {:ok, :healthy} end)
```

### Enabling Async with Mox

Use `set_mox_private` instead of `set_mox_global` when possible:

```elixir
setup :set_mox_private
setup :verify_on_exit!
```

---

## Coverage Exclusions

### Modules That Should Be Fully Ignored (0% expected)

These module types contain no testable business logic:

| Module Type | Example | Reason |
|-------------|---------|--------|
| Application | `application.ex` | OTP supervision setup |
| Release | `release.ex` | Production-only tooling |
| Supervisor | `*_supervisor.ex` | Pure OTP child specs |
| Repo | `repo.ex` | Ecto framework macro |
| Endpoint | `endpoint.ex` | Phoenix framework config |
| Gettext | `gettext.ex` | I18n framework macro |
| Behaviour definitions | `docker_adapter.ex` | Only `@callback` specs |
| Pure structs | `tool.ex` | Only `defstruct`, no functions |

**Format for full-module ignore:**
```elixir
# coveralls-ignore-start
# Reason: Pure OTP application setup, no business logic
defmodule Msfailab.Application do
  use Application
  # ...
end
# coveralls-ignore-stop
```

### What Counts as "Pure Delegation" (OK to ignore)

```elixir
# ✅ OK to ignore - no conditional logic
def handle_call(:get_state, _from, state) do
  {:reply, state, state}
end

def handle_info(:timeout, state) do
  {:noreply, state}
end

# ❌ Do NOT ignore - has conditional logic
def handle_call(:get_state, _from, state) do
  if state.ready do
    {:reply, state, state}
  else
    {:reply, :not_ready, state}
  end
end
```

### Logger Statements

Logger calls are diagnostic code, not business logic. Mark with inline ignore:

```elixir
def process_event(event, state) do
  # coveralls-ignore-next-line
  Logger.info("Processing event: #{inspect(event)}")

  # Business logic here - NOT ignored
  new_state = apply_event(state, event)

  # coveralls-ignore-next-line
  Logger.debug("State updated: #{inspect(new_state)}")

  new_state
end
```

Or extract logging to end of function:

```elixir
def process_event(event, state) do
  new_state = apply_event(state, event)
  log_event_processed(event, new_state)
  new_state
end

# coveralls-ignore-start
defp log_event_processed(event, state) do
  Logger.info("Processed #{inspect(event)}, new state: #{inspect(state)}")
end
# coveralls-ignore-stop
```

### Required Format for Ignore Blocks

```elixir
# coveralls-ignore-start
# Reason: [MUST explain why this is ignored]
def some_function do
  # ...
end
# coveralls-ignore-stop
```

### Never Exclude

- Conditional logic (`if`, `case`, `cond`, pattern matching with multiple clauses)
- Error handling paths
- State transformations
- Event broadcasting decisions
- Validation logic
- Any function with more than one clause

### Red Flags

If you're ignoring more than 10 lines consecutively, the code likely needs refactoring:
- Extract business logic to a Core module
- The function is doing too much

---

## Test Organization

### File Structure

```
test/
  msfailab/
    containers/
      container/
        core_test.exs          # Unit tests for Core module
      container_test.exs       # Integration tests for GenServer
      container_lifecycle_test.exs  # State machine tests
    containers_test.exs        # Context API tests
  msfailab_web/
    live/
      workspace_live_test.exs  # LiveView integration tests
      workspace_live/
        helpers_test.exs       # Unit tests for helpers
  support/
    containers_case.ex         # Test case with container setup
    fixtures/                  # Shared test data builders
```

### Naming Conventions

- `*_test.exs` - Standard test files
- `*_lifecycle_test.exs` - State machine / workflow tests
- `*_core_test.exs` - Pure function unit tests
- `*/helpers_test.exs` - LiveView helper function tests

### Setup Composition

```elixir
describe "feature" do
  setup [:create_workspace, :create_container, :start_container]

  test "does something", %{container: container, pid: pid} do
    # Test with fully initialized state
  end
end
```

---

## Testing Checklists

### For New Modules

- [ ] Every public function has at least one test
- [ ] Every pattern-matching clause is exercised
- [ ] Core module exists if GenServer/LiveView has complex logic
- [ ] Unit tests cover all Core module functions
- [ ] Integration tests cover public API
- [ ] Mox expectations for external calls
- [ ] Time sources are injectable (if timing-related)
- [ ] Timeouts are configurable (if applicable)
- [ ] Coverage exclusions documented with reasons
- [ ] All tests pass with `async: true` or documented why not

### For New LiveViews

- [ ] Every `handle_event/3` clause has a test
- [ ] Every `handle_info/2` PubSub handler has a test
- [ ] `mount/3` test verifies initial assigns
- [ ] Helper functions extracted and unit tested
- [ ] `render/1` marked ignore ONLY if logic-free
- [ ] All conditional logic moved to helpers

### For New GenServers

- [ ] Complex `init/1` logic extracted to Core module
- [ ] Every `handle_call/3` with logic has a test
- [ ] Every `handle_cast/2` with logic has a test
- [ ] Every `handle_info/2` with logic has a test
- [ ] Pure delegation callbacks marked ignore with reason
- [ ] Timing-dependent code uses injectable time sources

### For Bug Fixes

- [ ] Regression test added that fails without fix
- [ ] Test covers the specific edge case
- [ ] Related edge cases identified and tested

### For Timing-Related Code

- [ ] Time source is injectable (not called directly)
- [ ] Sleep/delay function is injectable
- [ ] Timeout values come from config or parameters
- [ ] Test config uses small timeouts (1-20ms)
- [ ] Tests don't rely on wall-clock assertions
- [ ] Duration calculations accept start time as parameter
- [ ] No `Process.sleep` in production code without injectable alternative

---

## Running Tests

```bash
# Full test suite
mix test

# With coverage report
mix test --cover

# Run coverage check (fails if below threshold)
mix check --only coveralls

# Specific file
mix test test/msfailab/containers_test.exs

# Specific test by line number
mix test test/msfailab/containers_test.exs:42

# Failed tests only
mix test --failed

# With logging visible
PRINT_LOGS=true mix test

# Watch mode (requires mix_test_watch)
mix test.watch
```

---

## Troubleshooting Coverage

### "Why is my coverage low?"

1. **Check for untested public functions** - Every `def` needs a test
2. **Check for untested pattern clauses** - Every clause needs to execute
3. **Check for untested event handlers** - Every LiveView/GenServer handler
4. **Check for missing ignore markers** - Framework boilerplate should be ignored

### "Should I ignore this code?"

Ask these questions:
1. Does it have conditional logic? → **Don't ignore, test it**
2. Is it pure delegation with no branching? → **OK to ignore**
3. Is it Logger/telemetry code? → **OK to ignore**
4. Is it a render function with no inline conditionals? → **OK to ignore**
5. Is it OTP boilerplate (supervisor, application)? → **OK to ignore**
6. Would ignoring hide a bug? → **Don't ignore**

### "My timing tests are flaky"

1. Are you using `Process.sleep`? → Make sleep injectable
2. Are you calling `System.monotonic_time` directly? → Make time injectable
3. Are timeouts > 100ms? → Reduce to 10-20ms with injectable time
4. Are you asserting on wall-clock differences? → Use controlled time

### "Coverage shows 0% but I have tests"

1. Check if module is accidentally marked with coveralls-ignore
2. Check if tests are actually calling the production code (not mocks)
3. Check if async test isolation is preventing instrumentation
4. Run `mix test --cover` and check the HTML report for details
