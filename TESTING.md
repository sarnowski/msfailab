# Testing Strategy

This document defines the testing strategy for msfailab, targeting **85%+ code coverage** while maintaining fast, reliable tests.

## Core Principles

### 1. Test Business Logic, Not Framework Glue

We test code that makes decisions, not code that delegates. This means:

- **Test**: Validation logic, state transformations, business rules, event handling decisions
- **Skip**: Phoenix/Ecto boilerplate, pure delegation, OTP callbacks that only forward calls

### 2. Test Behavior, Not Implementation Details

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
assert html =~ ~s(<span class="text-green-500">Running</span>)

# Bad: Testing CSS classes
assert element(view, ".bg-red-500.rounded-lg")

# Good: Test that data is present (if needed at all)
assert html =~ "Running"
assert has_element?(view, "#container-status")
```

### 3. Core Module Pattern

GenServers should be thin integration layers. Business logic lives in companion `Core` modules:

```elixir
# GenServer (glue code - minimal testing)
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

**Benefits:**
- Core modules are pure functions: easy to test, no process setup
- GenServer tests become integration tests verifying wiring
- Most coverage comes from fast unit tests

### 4. Speed Requirements

| Test Type | Target | Max Allowed |
|-----------|--------|-------------|
| Unit test | < 10ms | 50ms |
| Integration test | < 100ms | 200ms |
| Full suite | < 15s | 30s |

Tests exceeding these limits indicate design problems, not testing problems.

### 5. Async by Default

All tests should run with `async: true` unless they:
- Share global Mox expectations (use `set_mox_private` to enable async)
- Require sequential database operations on the same records
- Test cross-process coordination that can't be isolated

## LiveView and Template Testing

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

### What to Test in LiveViews

**Test (state management):**
- `mount/3` sets correct initial assigns
- `handle_event/3` updates assigns correctly
- `handle_info/2` processes messages correctly
- Helper functions make correct decisions

**Don't Test (presentation):**
- HTML structure
- CSS classes
- Element ordering
- Text formatting

### LiveView Test Pattern

```elixir
defmodule MsfailabWeb.ContainerLiveTest do
  use MsfailabWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "mount/3" do
    test "loads container data into assigns", %{conn: conn} do
      container = insert(:container, status: :running)

      {:ok, view, _html} = live(conn, ~p"/containers/#{container.id}")

      # Test assigns, not HTML
      assert view |> element("#container-status") |> has_element?()
    end
  end

  describe "handle_event start_container" do
    test "transitions container to starting state", %{conn: conn} do
      container = insert(:container, status: :stopped)
      {:ok, view, _html} = live(conn, ~p"/containers/#{container.id}")

      # Trigger event
      view |> element("#start-button") |> render_click()

      # Verify state change occurred (not HTML output)
      assert Containers.get_container!(container.id).status == :starting
    end
  end
end
```

### Testing View Helpers (Preferred Approach)

Most LiveView logic should be in helper functions that are trivially testable:

```elixir
defmodule MsfailabWeb.ContainerLive.HelpersTest do
  use ExUnit.Case, async: true

  alias MsfailabWeb.ContainerLive.Helpers

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

  describe "visibility_class/1" do
    test "returns visible for running status" do
      assert Helpers.visibility_class(:running) == "visible"
    end

    test "returns visible for finished status" do
      assert Helpers.visibility_class(:finished) == "visible"
    end

    test "returns hidden for other statuses" do
      assert Helpers.visibility_class(:stopped) == "hidden"
      assert Helpers.visibility_class(:starting) == "hidden"
    end
  end
end
```

### Coverage Strategy for LiveViews

| Component | Strategy | Target |
|-----------|----------|--------|
| Helper functions | Unit test all branches | 95%+ |
| `mount/3` | Integration test with database | 85%+ |
| `handle_event/3` | Integration test state changes | 85%+ |
| `handle_info/2` | Integration test message handling | 85%+ |
| `render/1` | coveralls-ignore (logic-free) | N/A |

**Ignoring render functions:**
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
1. Template contains no inline conditionals
2. All helper functions are tested
3. Template only calls functions and iterates over data

### Component Testing

Components follow the same pattern—extract logic to testable functions:

```elixir
defmodule MsfailabWeb.Components.StatusBadge do
  use Phoenix.Component

  # Testable helper
  def badge_color(:running), do: "green"
  def badge_color(:stopped), do: "gray"
  def badge_color(:error), do: "red"
  def badge_color(_), do: "yellow"

  # coveralls-ignore-start
  # Reason: Pure presentation, badge_color/1 tested separately
  def status_badge(assigns) do
    ~H"""
    <span class={["badge", "badge-#{badge_color(@status)}"]}>
      <%= @status %>
    </span>
    """
  end
  # coveralls-ignore-stop
end
```

Test file:
```elixir
defmodule MsfailabWeb.Components.StatusBadgeTest do
  use ExUnit.Case, async: true

  alias MsfailabWeb.Components.StatusBadge

  describe "badge_color/1" do
    test "returns green for running" do
      assert StatusBadge.badge_color(:running) == "green"
    end

    test "returns gray for stopped" do
      assert StatusBadge.badge_color(:stopped) == "gray"
    end

    test "returns red for error" do
      assert StatusBadge.badge_color(:error) == "red"
    end

    test "returns yellow for unknown statuses" do
      assert StatusBadge.badge_color(:unknown) == "yellow"
      assert StatusBadge.badge_color(:pending) == "yellow"
    end
  end
end
```

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

**Characteristics:**
- Use Mox for external system boundaries (Docker, MSGRPC)
- Use database sandbox for isolation
- Test happy paths and key error scenarios
- Verify correct coordination between components

### Lifecycle/State Tests (Target: 5% of tests)

Test complex state machines and event flows.

```elixir
defmodule Msfailab.Containers.ContainerLifecycleTest do
  use Msfailab.ContainersCase, async: false

  describe "container lifecycle" do
    test "transitions through startup sequence" do
      # Setup with Mox expectations for full lifecycle
      expect_docker_startup_sequence()

      {:ok, container} = create_container()
      {:ok, pid} = Containers.start_container(container)

      # Verify state transitions via events
      assert_receive %ContainerUpdated{status: :starting}, 100
      assert_receive %ContainerUpdated{status: :running}, 100
      assert_receive %ConsoleUpdated{state: :ready}, 100

      # Verify final state
      assert {:ok, %{status: :running}} = Containers.get_status(container.id)
    end
  end
end
```

**Characteristics:**
- Test complete workflows, not individual steps
- Use event subscriptions to verify state transitions
- Keep timeouts tight (100ms assertions)
- Document the expected lifecycle in test names

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

This allows tests to run concurrently while maintaining isolated expectations.

## Coverage Exclusions

### When to Use coveralls-ignore

Only exclude code that:
1. Is pure delegation with no conditional logic
2. Cannot fail in ways we care about testing
3. Would require extensive mocking for trivial verification

### Required Format

```elixir
# coveralls-ignore-start
# Reason: Pure OTP callback delegation, no business logic
def handle_call(:get_state, _from, state) do
  {:reply, state, state}
end
# coveralls-ignore-stop
```

### Never Exclude

- Conditional logic (`if`, `case`, `cond`, pattern matching with multiple clauses)
- Error handling paths
- State transformations
- Event broadcasting decisions
- Validation logic

### Red Flags

If you're ignoring more than 10 lines consecutively, the code likely needs refactoring:
- Extract business logic to a Core module
- The function is doing too much

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
  support/
    containers_case.ex         # Test case with container infrastructure
    fixtures/                  # Shared test data builders
```

### Naming Conventions

- `*_test.exs` - Standard test files
- `*_lifecycle_test.exs` - State machine / workflow tests
- `*_core_test.exs` - Pure function unit tests

### Setup Composition

```elixir
describe "feature" do
  setup [:create_workspace, :create_container, :start_container]

  test "does something", %{container: container, pid: pid} do
    # Test with fully initialized state
  end
end
```

## Testing Checklist

### For New Modules

- [ ] Core module exists with extracted business logic
- [ ] Unit tests cover all Core module functions
- [ ] Integration tests cover public API
- [ ] Mox expectations for external calls
- [ ] Coverage exclusions documented with reasons
- [ ] All tests pass with `async: true` or documented why not

### For Bug Fixes

- [ ] Regression test added that fails without fix
- [ ] Test covers the specific edge case
- [ ] Related edge cases identified and tested

### For Refactoring

- [ ] Existing tests still pass
- [ ] Coverage percentage maintained or improved
- [ ] No new coverage exclusions without justification

## Running Tests

```bash
# Full test suite
mix test

# With coverage report
mix test --cover

# Specific file
mix test test/msfailab/containers_test.exs

# Failed tests only
mix test --failed

# Watch mode (requires mix_test_watch)
mix test.watch
```

## Coverage Targets

| Module Category | Strategy | Target |
|----------------|----------|--------|
| Core modules (pure logic) | Unit test all branches | 95%+ |
| Context modules (API layer) | Integration tests | 85%+ |
| GenServers (integration) | Test callbacks with logic, ignore pure delegation | 70%+ |
| LiveView helpers | Unit test all branches | 95%+ |
| LiveView callbacks | Integration test state changes | 85%+ |
| LiveView render/components | coveralls-ignore if logic-free | N/A |
| **Overall** | | **85%+** |

**Key insight:** Lower targets for GenServers and render functions reflect that they should contain minimal logic. If they need high coverage to reach targets, they need refactoring:
- GenServer with complex logic → extract to Core module
- Template with conditionals → extract to helper functions
