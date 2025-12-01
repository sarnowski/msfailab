# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

msfailab is a collaborative security research platform that orchestrates Metasploit Framework environments through a shared web interface. It treats AI agents as first-class research partners with console access and workspace visibility alongside human researchers.

## Mandatory Workflows

### After Any Task That Modifies Code

**STOP before telling the user you're done. Invoke the `finishing-work` skill.**

This is mandatory. The skill runs quality checks and records changes to PENDING.md. Without it:
- Commits will fail validation
- Changes won't be properly documented
- Quality issues slip through

Trigger phrases: "done", "that's good", "commit", "looks good", finishing a feature/fix, switching topics.

### Before Completing Any Task

**Always run `mix precommit` before claiming a task is finished.** This command must complete with zero issues. Fix any warnings or errors—even if you believe they originate from a different session or pre-existing code.

### Code Quality Standards

**Never disable or skip quality checks** (tests, linter, credo, dialyzer, coverage, etc.). If a check cannot be made to pass, you must get explicit user approval before proceeding.

### No Backwards Compatibility

This project is pre-release and requires no backwards compatibility. Always write the cleanest solution without legacy accommodations, refactor dependent code when making changes, and remove deprecated patterns entirely.

### Database Migrations

Since this is pre-release, **modify existing migrations** instead of creating new incremental migrations. After changing a migration, run `mix ecto.reset` and `MIX_ENV=test mix ecto.reset`.

## Development Commands

```bash
# Initial setup
mix setup                    # Install deps, create DB, build assets

# Development server
iex -S mix phx.server        # Start interactive server (localhost:4000)

# Pre-commit (REQUIRED before completing tasks)
mix precommit                # Runs: deps.unlock --unused, format, check

# Testing
mix test                     # Run all tests
mix test test/path_test.exs  # Run specific test file
mix test --failed            # Re-run failed tests
PRINT_LOGS=true mix test     # Run tests with log output visible

# Quality checks (always use mix check to apply project configuration)
mix check                    # Run all checks
mix check --only credo       # Code linting
mix check --only dialyzer    # Static type checking
mix check --only sobelow     # Security analysis

# Database
mix ecto.reset               # Drop and recreate database
mix ecto.gen.migration name  # Generate new migration
```

## Architecture

### Organizational Model

- **Workspaces**: Top-level isolation units representing engagements/projects. URL: `/<workspace-name>`
- **Tracks**: Active research sessions within workspaces with dedicated Metasploit console and AI assistant. URL: `/<workspace-name>/<track-name>`
- **Knowledge Base**: Shared per-workspace store for hosts, services, vulnerabilities, credentials, and notes

### Technology Stack

- **Elixir/OTP**: Concurrent process management, fault tolerance
- **Phoenix 1.8**: Web framework with WebSocket support
- **Phoenix LiveView 1.1**: Real-time UI without custom JavaScript
- **PostgreSQL**: Database via Ecto
- **Tailwind CSS v4**: Styling (no tailwind.config.js needed)
- **Docker**: Isolated container environments for research tracks

### Supervision Tree

```
Msfailab.Supervisor
├── MsfailabWeb.Telemetry
├── Msfailab.Repo
├── DNSCluster
├── Phoenix.PubSub
├── Containers.Registry (process lookup by container_record_id)
├── Tracks.Registry (process lookup by track_id)
├── Containers.Supervisor
│   ├── ContainerSupervisor (DynamicSupervisor)
│   │   └── Container GenServers (one per container_record)
│   └── Reconciler (starts containers on boot)
├── Tracks.Supervisor
│   ├── TrackSupervisor (DynamicSupervisor)
│   │   └── TrackServer GenServers (one per active track)
│   └── Reconciler (starts track servers on boot)
└── MsfailabWeb.Endpoint
```

### Core Contexts

| Context | Purpose |
|---------|---------|
| `Msfailab.Workspaces` | Workspace CRUD, isolation boundaries |
| `Msfailab.Tracks` | Track lifecycle, TrackServer management |
| `Msfailab.Containers` | Docker container orchestration, Metasploit RPC |
| `Msfailab.Events` | PubSub event broadcasting |

### Key Modules

| Module | Responsibility |
|--------|----------------|
| `Containers.Container` | GenServer managing a Docker container and its console sessions |
| `Containers.Container.Core` | Pure business logic for container state (testable without processes) |
| `Containers.Msgrpc.Client` | Metasploit RPC client (Mox behavior for testing) |
| `Containers.Msgrpc.Console` | Console session state machine |
| `Containers.DockerAdapter` | Docker API abstraction (Mox behavior for testing) |
| `Tracks.TrackServer` | GenServer managing track session state and command history |

## Design Patterns

### Core Module Pattern

GenServers should be thin integration layers. Business logic lives in companion `Core` modules:

```elixir
# GenServer (glue code)
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

### Event-Driven Communication

Use `Msfailab.Events` for cross-process communication:

```elixir
# Subscribe in LiveView mount
Events.subscribe(:containers)
Events.subscribe({:workspace, workspace_id})

# Broadcast from GenServers
Events.broadcast(%ContainerUpdated{...})
```

### Mocking External Systems

Use Mox behaviors for Docker and Metasploit RPC:

```elixir
# test/support/containers_case.ex sets up mocks
expect(DockerAdapterMock, :start_container, fn name, _labels ->
  {:ok, "container_id"}
end)
```

## Code Guidelines

### HTTP Requests
Use the included `Req` library. Avoid `:httpoison`, `:tesla`, `:httpc`.

### LiveView Templates
- Always wrap content with `<Layouts.app flash={@flash} ...>`
- Use `<.icon name="hero-x-mark">` for icons (never Heroicons modules)
- Use `<.input>` component for form inputs
- Use `to_form/2` for forms, never pass changesets directly to templates
- Always use streams for collections (`phx-update="stream"`)

### Elixir Patterns
- Use `Enum.at/2` for list index access (no bracket syntax)
- Bind block expression results: `socket = if ... do ... end`
- Use `Ecto.Changeset.get_field/2` for changeset field access
- Use `start_supervised!/1` in tests; avoid `Process.sleep/1`

### License Header

All Elixir files must start with the AGPL license header (see existing files for format).

## Testing Strategy

Target **85%+ code coverage**. See `TESTING.md` for full details.

### Test Categories
- **Unit tests (70%)**: Pure functions in Core modules
- **Integration tests (25%)**: Context APIs with Mox
- **Lifecycle tests (5%)**: State machine workflows

### Key Patterns
- Extract logic to Core modules for unit testing
- Use `async: true` unless tests share global state
- Test behavior, not implementation (avoid testing HTML structure)

## Logging

See `LOGGING.md` for full details.

- **error**: Unrecoverable unexpected situations
- **warning**: Recoverable unexpected situations
- **info**: Runtime state changes (lifecycle events)
- **debug**: Data flow tracing (dev only)

Use `Msfailab.Trace` for full request/response dumps in development.
