# Metasploit Framework AI Lab - Collaborative security research with AI agents
# Copyright (C) 2025 Tobias Sarnowski
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.

defmodule Msfailab.Containers.Container do
  @moduledoc """
  GenServer managing the lifecycle of a Docker container and its console sessions.

  Each active container database record has one Container GenServer that orchestrates:
  - Docker container lifecycle (start, stop, health checks)
  - MSGRPC authentication (token management)
  - Spawning and monitoring Console GenServers (on-demand, when registered)
  - Bash command execution (parallel, fire-and-forget tasks)
  - Event emission for status changes

  ## Separation of Concerns

  Container GenServer has **no knowledge of Tracks**. It manages consoles for
  opaque `track_id` identifiers. This eliminates cyclic dependencies and creates
  a clean separation:

  - **Container**: Manages Docker + MSGRPC infrastructure, spawns consoles for registered tracks
  - **TrackServer**: Declares intent (registers for console), listens to events, builds history
  - **Console**: Manages single MSGRPC console session, emits events

  ```
  ┌─────────────────────────────────────────────────────────────────────────────────────┐
  │                             TrackServer GenServer                                    │
  │                                                                                      │
  │  Responsibilities:                                                                   │
  │  - Register console with Container on init (declare intent)                          │
  │  - Unregister console on terminate                                                   │
  │  - Subscribe to ConsoleUpdated events (to track console status and output)           │
  │  - Build block-based history (startup blocks, command blocks)                        │
  │  - Broadcast TrackStateUpdated for LiveView                                          │
  │                                                                                      │
  │  NOTE: TrackServer does NOT track Container status - just registers and listens      │
  └─────────────────────────────────────────────────────────────────────────────────────┘
            │                                         ▲
            │ register_console (once)                 │ PubSub events
            ▼                                         │
  ┌─────────────────────────────────────────────────────────────────────────────────────┐
  │                              Container GenServer                                     │
  │                                                                                      │
  │  Responsibilities:                                                                   │
  │  - Docker container lifecycle (start, stop, health checks)                           │
  │  - MSGRPC authentication (token management)                                          │
  │  - Spawning and monitoring Console GenServers (on-demand, when asked)                │
  │  - Emitting ContainerUpdated events on status changes                                │
  │  - Emitting ConsoleUpdated(:offline) when Console dies                               │
  │                                                                                      │
  │  IMPORTANT: Container has NO knowledge of Tracks. It only knows track_ids            │
  │  as opaque identifiers for console routing.                                          │
  └─────────────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        │ spawns + monitors
                                        ▼
  ┌─────────────────────────────────────────────────────────────────────────────────────┐
  │                          Msgrpc.Console GenServer                                    │
  │                                                                                      │
  │  Responsibilities:                                                                   │
  │  - Single MSGRPC console session lifecycle                                           │
  │  - Polling for output (handles busy flag)                                            │
  │  - Emitting ConsoleUpdated events (:starting, :ready, :busy)                         │
  │  - Command execution                                                                 │
  └─────────────────────────────────────────────────────────────────────────────────────┘
  ```

  ## State Machine

  Container transitions through three states during its lifecycle:

  ```
                      ┌────────────────────┐
                      │                    │
           ┌─────────►│     :offline       │◄──────────┐
           │          │                    │           │
           │          └─────────┬──────────┘           │
           │                    │                      │
           │                    │ start docker         │
           │                    ▼                      │
           │          ┌────────────────────┐           │
           │          │                    │           │
           │          │     :starting      │───────────┤ docker/msgrpc failure
           │          │                    │           │ (retry with backoff)
           │          └─────────┬──────────┘           │
           │                    │                      │
           │                    │ msgrpc authenticated │
           │                    ▼                      │
           │          ┌────────────────────┐           │
           │          │                    │           │
           └──────────│     :running       │───────────┘
         docker dies  │                    │
                      └────────────────────┘
  ```

  ### State Descriptions

  | State       | Description                                                      |
  |-------------|------------------------------------------------------------------|
  | `:offline`  | GenServer alive, no Docker container or MSGRPC connection.       |
  |             | Base/safe state. Console registration still accepted.            |
  | `:starting` | Docker container starting or MSGRPC authenticating.              |
  |             | Transitional state. Console spawns deferred until `:running`.    |
  | `:running`  | Fully operational. Consoles can be spawned, commands accepted.   |
  |             | Health checks running. Token available for MSGRPC operations.    |

  ### State Transitions

  | From        | To          | Trigger                              |
  |-------------|-------------|--------------------------------------|
  | (init)      | `:offline`  | GenServer starts                     |
  | `:offline`  | `:starting` | Docker container starts              |
  | `:starting` | `:running`  | MSGRPC authenticated                 |
  | `:starting` | `:offline`  | Docker/MSGRPC failure (retry)        |
  | `:running`  | `:offline`  | Docker dies or health check fails    |

  ## Console Registration Model

  TrackServer **declares intent** to have a console, but Container **owns the lifecycle**.
  This separation ensures:

  - TrackServer doesn't need to track Container status
  - TrackServer doesn't need to handle container restart scenarios
  - Container is the single source of truth for console lifecycle
  - Simple TrackServer implementation (just register and listen to events)

  ### Registration Flow

  ```
  TrackServer starts
      │
      ▼
  Container.register_console(container_id, track_id) → :ok (always succeeds)
      │
      ▼
  TrackServer subscribes to ConsoleUpdated events
      │
      ▼
  (Container handles everything internally)
      │
      ├─► If Container is :running → spawns Console immediately
      │       │
      │       ▼
      │   ConsoleUpdated(:starting) → ConsoleUpdated(:ready)
      │
      └─► If Container not :running → stores track_id in registered_tracks
              │
              ▼
          When Container becomes :running → spawns Console
              │
              ▼
          ConsoleUpdated(:starting) → ConsoleUpdated(:ready)
  ```

  ### Console Lifecycle Within Container

  1. `register_console(track_id)` → adds to `registered_tracks`, spawns Console if `:running`
  2. When Container reaches `:running` → spawns Console for each track in `registered_tracks`
  3. When Console dies → emit `:offline`, schedule restart (stays in `registered_tracks`)
  4. When Container goes `:offline` → all Consoles die, emit `:offline` for each
  5. When Container becomes `:running` again → re-spawn all registered consoles
  6. `unregister_console(track_id)` → removes from `registered_tracks`, destroys Console if exists

  **Key insight:** Container emits `ConsoleUpdated(:offline)` when Console dies,
  because a dead process cannot emit events.

  ## Error Handling and Recovery

  ### Container Recovery Strategy

  **Docker/MSGRPC failures:**
  - Exponential backoff: 1s, 2s, 4s, 8s, ... up to 60s max
  - Maximum 5 restart attempts before giving up
  - On success, restart count resets after 5 minutes of stable operation

  ### Console Recovery Strategy

  **Console process failures:**
  - Exponential backoff: 1s, 2s, 4s, ... up to 30s max
  - Maximum 10 restart attempts per console
  - Only restarts if track still registered AND container is `:running`

  ### Crash Handling

  | Component          | Crash Handling                                            |
  |--------------------|-----------------------------------------------------------|
  | Container GenServer| Supervisor restarts, Container re-adopts or creates Docker|
  | Console GenServer  | Container detects via monitor, emits :offline, schedules  |
  |                    | restart with backoff                                      |

  ### Why No `:error` State?

  An `:error` state is problematic because:
  - No clear recovery path
  - User confusion ("it's broken, now what?")
  - Anti-pattern: GenServers should crash on unrecoverable errors, not sit in limbo

  Instead:
  - **Transient failures** → Retry with backoff, stay in current state
  - **Persistent failures** → Go `:offline`, auto-recreate later
  - **Unexpected errors** → Crash, let supervisor handle

  ## Bash Command Execution

  Bash commands are handled differently from Metasploit commands. While Metasploit
  commands go through a stateful Console GenServer (one at a time), bash commands
  run as **stateless, fire-and-forget Tasks** that can execute in parallel.

  ### Comparison: Metasploit vs Bash Commands

  | Aspect      | Metasploit           | Bash                      |
  |-------------|----------------------|---------------------------|
  | Handler     | Console GenServer    | BashExecution Task        |
  | State       | Stateful (sequential)| Stateless (parallel)      |
  | Concurrency | One command at a time| Multiple in parallel      |
  | Lifecycle   | Long-lived process   | Fire-and-forget           |
  | Tracking    | Console tracks cmd   | Container tracks Tasks    |

  ### Bash Command Flow

  ```
  Containers.send_bash_command(container_id, track_id, "ls -la")
      │
      ▼
  Container GenServer receives call
      │
      ├─► Generates command_id
      ├─► Broadcasts CommandIssued event
      ├─► Spawns Task for execution
      ├─► Monitors the Task (Process.monitor)
      └─► Stores in state:
            running_bash_commands[command_id] = %{
              pid: task_pid,
              ref: monitor_ref,
              track_id: track_id,
              command: command,
              started_at: DateTime.t()
            }
      │
      ▼
  Task executes:
      │
      ├─► Calls Docker exec API
      ├─► Sends {:bash_output, cmd_id, output} to Container
      └─► Sends {:bash_finished, cmd_id, exit_code} when done
      │
      ▼
  Container receives {:DOWN, ref, :process, pid, reason}
      │
      └─► Removes command_id from running_bash_commands
  ```

  ### Container Shutdown Cleanup

  When Container goes offline or terminates, it emits error events for all running
  bash commands so subscribers know they were interrupted.

  ## Event Emission Responsibility

  | Event                         | Emitted By    | When                           |
  |-------------------------------|---------------|--------------------------------|
  | `ContainerUpdated(:offline)`  | Container     | Docker dies, Container stops   |
  | `ContainerUpdated(:starting)` | Container     | Docker starting                |
  | `ContainerUpdated(:running)`  | Container     | MSGRPC authenticated           |
  | `ConsoleUpdated(:offline)`    | **Container** | Console crashes/stops          |
  |                               |               | (dead process can't emit)      |
  | `ConsoleUpdated(:starting)`   | Console       | After console.create           |
  | `ConsoleUpdated(:ready)`      | Console       | Init complete or cmd complete  |
  | `ConsoleUpdated(:busy)`       | Console       | Command sent, with output      |
  | `CommandIssued`               | Container     | Bash command accepted          |
  | `CommandResult`               | Container     | Bash output/completion/error   |

  ## Process State Structure

  The Container GenServer maintains comprehensive state for managing Docker,
  MSGRPC, consoles, and bash commands:

  ```elixir
  %{
    # Container identification
    container_record_id: integer(),
    workspace_id: integer(),
    workspace_slug: String.t(),
    container_slug: String.t(),
    container_name: String.t(),
    docker_image: String.t(),

    # Docker state
    docker_container_id: String.t() | nil,
    rpc_endpoint: %{host: String.t(), port: pos_integer()} | nil,
    status: :offline | :starting | :running,
    restart_count: non_neg_integer(),
    started_at: DateTime.t() | nil,

    # MSGRPC state
    msgrpc_token: String.t() | nil,
    msgrpc_connect_attempts: non_neg_integer(),

    # Console registration and tracking
    registered_tracks: MapSet.t(integer()),   # Tracks that want consoles
    consoles: %{track_id => console_info()},  # Running Console processes

    # Bash command tracking
    running_bash_commands: %{command_id => bash_command_info()}
  }
  ```

  ## Process Registration

  Container processes are registered via `Msfailab.Containers.Registry` using
  the container_record_id as the key. This enables lookup by ID without storing PIDs.

  ## Key Design Decisions

  ### Container Has No Knowledge of Tracks

  **Decision:** Container GenServer knows nothing about Track entities. It only
  manages Docker + MSGRPC infrastructure and spawns Console GenServers on-demand
  when asked. Track IDs are treated as opaque identifiers for console routing.

  **Rationale:**
  - Eliminates cyclic dependencies (Container doesn't need to query Tracks)
  - Clear separation of concerns (Container = infrastructure, TrackServer = business logic)
  - Simpler Container implementation (no event subscriptions for track lifecycle)
  - Easier testing (Container can be tested without Track dependencies)

  ### Container Auto-Restarts Consoles

  **Decision:** When Container becomes `:running`, it automatically spawns Console
  for every track in `registered_tracks`. When Container restarts, registered tracks
  persist and consoles are re-spawned automatically.

  **Rationale:**
  - No coordination needed between TrackServer and Container on restart
  - TrackServer just receives events (ConsoleUpdated) passively
  - Container owns its resources end-to-end
  - Simpler mental model (register = "I always want a console here")

  ### Container Emits :offline for Dead Consoles

  **Decision:** When Console GenServer dies, Container emits `ConsoleUpdated(:offline)`
  on its behalf.

  **Rationale:**
  - Dead process cannot emit events
  - Container already monitors Consoles
  - Ensures no gaps in event stream
  """

  use GenServer, restart: :transient

  require Logger

  alias Msfailab.Containers.Command
  alias Msfailab.Containers.Container.Core
  alias Msfailab.Containers.DockerAdapter
  alias Msfailab.Containers.Msgrpc.Console
  alias Msfailab.Containers.PortAllocator
  alias Msfailab.Events
  alias Msfailab.Events.CommandIssued
  alias Msfailab.Events.CommandResult
  alias Msfailab.Events.ConsoleUpdated
  alias Msfailab.Events.WorkspaceChanged
  alias Msfailab.Trace

  # Configuration accessors for timing values (allows test overrides)
  defp health_check_interval_ms,
    do: get_timing(:health_check_interval_ms, 30_000)

  defp max_restart_count,
    do: get_timing(:max_restart_count, 5)

  defp base_backoff_ms,
    do: get_timing(:base_backoff_ms, 1_000)

  defp max_backoff_ms,
    do: get_timing(:max_backoff_ms, 60_000)

  defp success_reset_ms,
    do: get_timing(:success_reset_ms, 300_000)

  defp msgrpc_initial_delay_ms,
    do: get_timing(:msgrpc_initial_delay_ms, 5_000)

  defp msgrpc_max_connect_attempts,
    do: get_timing(:msgrpc_max_connect_attempts, 10)

  defp msgrpc_connect_base_backoff_ms,
    do: get_timing(:msgrpc_connect_base_backoff_ms, 2_000)

  defp console_restart_base_backoff_ms,
    do: get_timing(:console_restart_base_backoff_ms, 1_000)

  defp console_restart_max_backoff_ms,
    do: get_timing(:console_restart_max_backoff_ms, 30_000)

  defp console_max_restart_attempts,
    do: get_timing(:console_max_restart_attempts, 10)

  defp get_timing(key, default) do
    :msfailab
    |> Application.get_env(:container_timing, [])
    |> Keyword.get(key, default)
  end

  @typedoc "Container status"
  @type container_status :: :offline | :starting | :running

  @typedoc "Console info tracked in Container state"
  @type console_info :: %{
          pid: pid() | nil,
          ref: reference() | nil,
          restart_attempts: non_neg_integer(),
          last_restart_at: DateTime.t() | nil
        }

  @typedoc "Running bash command info"
  @type bash_command_info :: %{
          pid: pid(),
          ref: reference(),
          track_id: integer(),
          command: Command.t(),
          started_at: DateTime.t()
        }

  @typedoc "Container process state"
  @type state :: %{
          # Container identification
          container_record_id: integer(),
          workspace_id: integer(),
          workspace_slug: String.t(),
          container_slug: String.t(),
          container_name: String.t(),
          docker_image: String.t(),
          # Docker container state
          docker_container_id: String.t() | nil,
          rpc_endpoint: %{host: String.t(), port: pos_integer()} | nil,
          status: container_status(),
          restart_count: non_neg_integer(),
          started_at: DateTime.t() | nil,
          # MSGRPC state
          msgrpc_token: String.t() | nil,
          msgrpc_connect_attempts: non_neg_integer(),
          # Console registration and tracking
          registered_tracks: MapSet.t(integer()),
          consoles: %{integer() => console_info()},
          # Running bash commands
          running_bash_commands: %{String.t() => bash_command_info()}
        }

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Starts a Container process linked to the calling process.

  ## Options

  - `:container_record_id` - Required. The database ID of the container record.
  - `:workspace_id` - Required. The database ID of the workspace.
  - `:workspace_slug` - Required. The slug of the workspace.
  - `:container_slug` - Required. The slug of the container.
  - `:container_name` - Required. The display name of the container.
  - `:docker_image` - Required. The Docker image to run.
  - `:docker_container_id` - Optional. If provided, adopts this existing Docker container.
  - `:auto_start` - Optional. If true, starts Docker container immediately.
    Defaults to false. In production, Reconciler calls `start_new/1` or
    `adopt_docker_container/2` after Container is registered. Tests should
    pass `auto_start: true` when starting Container directly.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    container_record_id = Keyword.fetch!(opts, :container_record_id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(container_record_id))
  end

  @doc """
  Returns the via tuple for Registry lookup by container_record_id.
  """
  @spec via_tuple(integer()) :: {:via, Registry, {module(), integer()}}
  def via_tuple(container_record_id) do
    {:via, Registry, {Msfailab.Containers.Registry, container_record_id}}
  end

  @doc """
  Looks up the pid of a Container GenServer by container_record_id.
  """
  @spec whereis(integer()) :: pid() | nil
  def whereis(container_record_id) do
    case Registry.lookup(Msfailab.Containers.Registry, container_record_id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @doc """
  Gets the current container status and docker container ID.
  """
  @spec get_status(integer()) :: {container_status(), String.t() | nil}
  def get_status(container_record_id) do
    GenServer.call(via_tuple(container_record_id), :get_status)
  end

  @doc """
  Gets the full state snapshot for querying console statuses.
  """
  @spec get_state_snapshot(integer()) :: map()
  def get_state_snapshot(container_record_id) do
    GenServer.call(via_tuple(container_record_id), :get_state_snapshot)
  end

  @doc """
  Registers a console for a track.

  Always succeeds immediately. If Container is `:running`, spawns Console
  immediately. Otherwise, spawns when Container reaches `:running`.
  """
  @spec register_console(integer(), integer()) :: :ok
  def register_console(container_record_id, track_id) do
    GenServer.call(via_tuple(container_record_id), {:register_console, track_id})
  end

  @doc """
  Unregisters a console for a track.

  Removes track from registered_tracks and destroys Console if running.
  """
  @spec unregister_console(integer(), integer()) :: :ok
  def unregister_console(container_record_id, track_id) do
    GenServer.call(via_tuple(container_record_id), {:unregister_console, track_id})
  end

  @doc """
  Sends a Metasploit command to a track's console.

  Returns `{:ok, command_id}` if accepted, `{:error, reason}` if rejected.
  """
  @spec send_metasploit_command(integer(), integer(), String.t()) ::
          {:ok, String.t()} | {:error, atom()}
  def send_metasploit_command(container_record_id, track_id, command) do
    GenServer.call(via_tuple(container_record_id), {:metasploit_command, track_id, command})
  end

  @doc """
  Sends a bash command to the container for a specific track.

  Returns `{:ok, command_id}` if accepted, `{:error, reason}` if rejected.
  """
  @spec send_bash_command(integer(), integer(), String.t()) ::
          {:ok, String.t()} | {:error, atom()}
  def send_bash_command(container_record_id, track_id, command) do
    GenServer.call(via_tuple(container_record_id), {:bash_command, track_id, command})
  end

  @doc """
  Gets running bash commands.
  """
  @spec get_running_bash_commands(integer()) :: [bash_command_info()]
  def get_running_bash_commands(container_record_id) do
    GenServer.call(via_tuple(container_record_id), :get_running_bash_commands)
  end

  @doc """
  Gets the RPC endpoint for the container.
  """
  @spec get_rpc_endpoint(integer()) :: {:ok, map()} | {:error, term()}
  def get_rpc_endpoint(container_record_id) do
    GenServer.call(via_tuple(container_record_id), :get_rpc_endpoint)
  end

  @doc """
  Gets the full RPC context for the container, including endpoint and auth token.

  Returns `{:ok, %{client: module, endpoint: map, token: string}}` if the container
  is running and MSGRPC is connected, or `{:error, :not_available}` otherwise.

  This is used for making RPC calls to the Metasploit Framework, such as
  deserializing Ruby Marshal data in notes.
  """
  @spec get_rpc_context(integer()) :: {:ok, map()} | {:error, :not_available}
  def get_rpc_context(container_record_id) do
    GenServer.call(via_tuple(container_record_id), :get_rpc_context)
  end

  @doc """
  Notifies the Container GenServer to adopt an existing Docker container.

  Called by Reconciler when it discovers a running Docker container that
  matches this container record. The GenServer will adopt it instead of
  starting a new one.
  """
  @spec adopt_docker_container(integer(), String.t()) :: :ok
  def adopt_docker_container(container_record_id, docker_container_id) do
    GenServer.cast(via_tuple(container_record_id), {:adopt_docker_container, docker_container_id})
  end

  @doc """
  Tells the Container GenServer to start a new Docker container.

  Called by Reconciler when no existing Docker container was found to adopt.
  """
  @spec start_new(integer()) :: :ok
  def start_new(container_record_id) do
    GenServer.cast(via_tuple(container_record_id), :start_new)
  end

  # ===========================================================================
  # GenServer Callbacks
  # ===========================================================================

  # coveralls-ignore-start
  # Reason: GenServer integration shell requiring Docker/MSGRPC infrastructure.
  # Core business logic tested in Container.Core module (100% coverage).

  @impl true
  def init(opts) do
    container_record_id = Keyword.fetch!(opts, :container_record_id)
    workspace_id = Keyword.fetch!(opts, :workspace_id)
    workspace_slug = Keyword.fetch!(opts, :workspace_slug)
    container_slug = Keyword.fetch!(opts, :container_slug)
    container_name = Keyword.fetch!(opts, :container_name)
    docker_image = Keyword.fetch!(opts, :docker_image)
    existing_docker_container_id = Keyword.get(opts, :docker_container_id)
    auto_start = Keyword.get(opts, :auto_start, false)

    # Set process-level metadata for all subsequent logs
    Logger.metadata(
      container_id: container_record_id,
      workspace_id: workspace_id,
      container_name: container_name
    )

    state = %{
      container_record_id: container_record_id,
      workspace_id: workspace_id,
      workspace_slug: workspace_slug,
      container_slug: container_slug,
      container_name: container_name,
      docker_image: docker_image,
      docker_container_id: existing_docker_container_id,
      rpc_port: nil,
      rpc_endpoint: nil,
      status: :offline,
      restart_count: 0,
      started_at: nil,
      msgrpc_token: nil,
      msgrpc_connect_attempts: 0,
      registered_tracks: MapSet.new(),
      consoles: %{},
      running_bash_commands: %{}
    }

    # Broadcast initial offline status
    broadcast_container_status(state)

    # Start behavior depends on how we were started:
    # - docker_container_id provided: Start immediately (adopting existing container)
    # - auto_start: true: Start immediately (for tests that start Container directly)
    # - Otherwise: Wait for Reconciler to call start_new or adopt_docker_container
    if existing_docker_container_id || auto_start do
      send(self(), :start_container)
    end

    {:ok, state}
  end

  # ---------------------------------------------------------------------------
  # Handle Calls
  # ---------------------------------------------------------------------------

  @impl true
  def handle_call(:get_status, _from, state) do
    {:reply, {state.status, state.docker_container_id}, state}
  end

  def handle_call(:get_state_snapshot, _from, state) do
    snapshot = %{
      status: state.status,
      docker_container_id: state.docker_container_id,
      registered_tracks: state.registered_tracks,
      consoles: state.consoles
    }

    {:reply, snapshot, state}
  end

  def handle_call({:register_console, track_id}, _from, state) do
    new_registered = MapSet.put(state.registered_tracks, track_id)
    new_state = %{state | registered_tracks: new_registered}

    # If already running, spawn console immediately
    new_state =
      if state.status == :running do
        spawn_console(new_state, track_id)
      else
        # Console will be spawned when we reach :running
        new_state
      end

    {:reply, :ok, new_state}
  end

  def handle_call({:unregister_console, track_id}, _from, state) do
    new_registered = MapSet.delete(state.registered_tracks, track_id)
    new_state = %{state | registered_tracks: new_registered}

    # Stop console if running
    new_state = stop_console(new_state, track_id)

    {:reply, :ok, new_state}
  end

  def handle_call({:metasploit_command, track_id, command}, _from, state) do
    case Core.validate_console_for_command(state, track_id) do
      {:error, reason} ->
        {:reply, {:error, reason}, state}

      {:ok, pid} ->
        case Console.send_command(pid, command) do
          {:ok, command_id} ->
            {:reply, {:ok, command_id}, state}

          # Translate Console errors to more descriptive atoms
          {:error, :starting} ->
            {:reply, {:error, :console_starting}, state}

          {:error, :busy} ->
            {:reply, {:error, :console_busy}, state}

          {:error, :write_failed} ->
            # Console will crash and be restarted automatically
            {:reply, {:error, :console_write_failed}, state}
        end
    end
  end

  def handle_call({:bash_command, track_id, command}, _from, state) do
    if state.status != :running do
      {:reply, {:error, :container_not_running}, state}
    else
      cmd = Command.new(:bash, command)

      # Broadcast CommandIssued
      broadcast_command_issued(state, track_id, cmd)

      # Start async task for bash execution
      parent = self()
      cmd_id = cmd.id
      docker_container_id = state.docker_container_id

      {:ok, task_pid} =
        Task.start(fn ->
          execute_bash_command(parent, cmd_id, docker_container_id, command)
        end)

      ref = Process.monitor(task_pid)

      bash_info = %{
        pid: task_pid,
        ref: ref,
        track_id: track_id,
        command: cmd,
        started_at: DateTime.utc_now()
      }

      new_bash_commands = Map.put(state.running_bash_commands, cmd.id, bash_info)
      {:reply, {:ok, cmd.id}, %{state | running_bash_commands: new_bash_commands}}
    end
  end

  def handle_call(:get_running_bash_commands, _from, state) do
    commands =
      state.running_bash_commands
      |> Map.values()
      |> Enum.map(fn info ->
        %{
          command_id: info.command.id,
          track_id: info.track_id,
          container_id: state.container_record_id,
          command: info.command.command,
          started_at: info.started_at
        }
      end)

    {:reply, commands, state}
  end

  def handle_call(:get_rpc_endpoint, _from, state) do
    result =
      if state.status == :running && state.rpc_endpoint do
        {:ok, state.rpc_endpoint}
      else
        {:error, :not_available}
      end

    {:reply, result, state}
  end

  def handle_call(:get_rpc_context, _from, state) do
    if state.status == :running && state.rpc_endpoint do
      # Get a fresh token to avoid using an expired one
      case msgrpc_client().login(state.rpc_endpoint, msgrpc_password(), "msf") do
        {:ok, token} ->
          new_state = %{state | msgrpc_token: token}

          result =
            {:ok,
             %{
               client: msgrpc_client(),
               endpoint: state.rpc_endpoint,
               token: token
             }}

          {:reply, result, new_state}

        {:error, _reason} ->
          {:reply, {:error, :not_available}, state}
      end
    else
      {:reply, {:error, :not_available}, state}
    end
  end

  # ---------------------------------------------------------------------------
  # Handle Cast - Container Start Commands from Reconciler
  # ---------------------------------------------------------------------------

  @impl true
  def handle_cast({:adopt_docker_container, docker_container_id}, %{status: :offline} = state) do
    # Reconciler found an existing Docker container to adopt
    new_state = %{state | docker_container_id: docker_container_id}
    send(self(), :start_container)
    {:noreply, new_state}
  end

  def handle_cast({:adopt_docker_container, _docker_container_id}, state) do
    # Already starting or running, ignore
    {:noreply, state}
  end

  def handle_cast(:start_new, %{status: :offline} = state) do
    # Reconciler says no existing Docker container, start a new one
    send(self(), :start_container)
    {:noreply, state}
  end

  def handle_cast(:start_new, state) do
    # Already starting or running, ignore
    {:noreply, state}
  end

  # ---------------------------------------------------------------------------
  # Handle Info - Container Lifecycle
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info(:start_container, state) do
    new_state = %{state | status: :starting}
    broadcast_container_status(new_state)

    result =
      if state.docker_container_id do
        adopt_existing_container(new_state)
      else
        start_new_container(new_state)
      end

    case result do
      {:ok, running_state} ->
        schedule_health_check()
        maybe_schedule_restart_reset(running_state)

        # Schedule MSGRPC connection
        schedule_msgrpc_connect(msgrpc_initial_delay_ms())

        {:noreply, running_state}

      {:error, reason} ->
        handle_start_failure(new_state, reason)
    end
  end

  def handle_info(:health_check, state) do
    if state.status == :running do
      case docker_adapter().container_running?(state.docker_container_id) do
        true ->
          schedule_health_check()
          {:noreply, state}

        false ->
          Logger.warning("Container health check failed: container not running",
            docker_container_id: state.docker_container_id
          )

          handle_container_crash(state)
      end
    else
      {:noreply, state}
    end
  end

  def handle_info(:reset_restart_count, %{status: :running} = state) do
    {:noreply, %{state | restart_count: 0}}
  end

  def handle_info(:reset_restart_count, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Handle Info - MSGRPC Connection
  # ---------------------------------------------------------------------------

  def handle_info(:connect_msgrpc, %{status: :starting, rpc_endpoint: endpoint} = state)
      when not is_nil(endpoint) do
    new_attempts = state.msgrpc_connect_attempts + 1
    Logger.info("Connecting to MSGRPC", attempt: new_attempts)

    state = %{state | msgrpc_connect_attempts: new_attempts}

    case msgrpc_client().login(endpoint, msgrpc_password(), "msf") do
      {:ok, token} ->
        Logger.info("MSGRPC authenticated")
        new_state = %{state | msgrpc_token: token, status: :running}

        # Now we're fully running - broadcast and spawn all registered consoles
        broadcast_container_status(new_state)
        new_state = spawn_all_consoles(new_state)

        {:noreply, new_state}

      {:error, reason} ->
        Logger.warning("MSGRPC login failed", reason: inspect(reason))
        handle_msgrpc_connect_failure(state, reason)
    end
  end

  def handle_info(:connect_msgrpc, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Handle Info - Console Monitoring
  # ---------------------------------------------------------------------------

  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    # Check if this is a Console process
    case Core.find_console_by_ref(state.consoles, ref) do
      {track_id, _console_info} ->
        handle_console_down(state, track_id, reason)

      nil ->
        # Check if this is a bash command task
        case Core.find_bash_command_by_ref(state.running_bash_commands, ref) do
          {cmd_id, _bash_info} ->
            # Just remove from tracking - the task sent its own result messages
            new_bash_commands = Map.delete(state.running_bash_commands, cmd_id)
            {:noreply, %{state | running_bash_commands: new_bash_commands}}

          nil ->
            {:noreply, state}
        end
    end
  end

  # Console restart timer
  def handle_info({:restart_console, track_id}, state) do
    if MapSet.member?(state.registered_tracks, track_id) && state.status == :running do
      Logger.info("Executing console restart", track_id: track_id)
      {:noreply, spawn_console(state, track_id)}
    else
      Logger.warning(
        "Console restart skipped: track_registered=#{MapSet.member?(state.registered_tracks, track_id)}, status=#{state.status}",
        track_id: track_id
      )

      {:noreply, state}
    end
  end

  # ---------------------------------------------------------------------------
  # Handle Info - Bash Command Results
  # ---------------------------------------------------------------------------

  def handle_info({:bash_output, cmd_id, output}, state) do
    case Map.get(state.running_bash_commands, cmd_id) do
      nil ->
        {:noreply, state}

      bash_info ->
        cmd = Command.append_output(bash_info.command, output)
        broadcast_command_result(state, bash_info.track_id, cmd)

        new_bash_info = %{bash_info | command: cmd}
        new_bash_commands = Map.put(state.running_bash_commands, cmd_id, new_bash_info)
        {:noreply, %{state | running_bash_commands: new_bash_commands}}
    end
  end

  def handle_info({:bash_finished, cmd_id, exit_code}, state) do
    case Map.get(state.running_bash_commands, cmd_id) do
      nil ->
        {:noreply, state}

      bash_info ->
        cmd = Command.finish(bash_info.command, exit_code: exit_code)
        broadcast_command_result(state, bash_info.track_id, cmd)

        new_bash_commands = Map.delete(state.running_bash_commands, cmd_id)
        {:noreply, %{state | running_bash_commands: new_bash_commands}}
    end
  end

  def handle_info({:bash_error, cmd_id, reason}, state) do
    case Map.get(state.running_bash_commands, cmd_id) do
      nil ->
        {:noreply, state}

      bash_info ->
        cmd = Command.error(bash_info.command, reason)
        broadcast_command_result(state, bash_info.track_id, cmd)

        new_bash_commands = Map.delete(state.running_bash_commands, cmd_id)
        {:noreply, %{state | running_bash_commands: new_bash_commands}}
    end
  end

  # ---------------------------------------------------------------------------
  # Terminate
  # ---------------------------------------------------------------------------

  @impl true
  def terminate(reason, state) do
    Logger.info("Container terminating", reason: inspect(reason))

    # Emit :offline for all consoles
    for {track_id, _console_info} <- state.consoles do
      broadcast_console_offline(state, track_id)
    end

    # Emit :error for all running bash commands
    for {_cmd_id, bash_info} <- state.running_bash_commands do
      cmd = Command.error(bash_info.command, :container_stopped)
      broadcast_command_result(state, bash_info.track_id, cmd)
    end

    # Stop Docker container if running
    if state.docker_container_id && state.status in [:starting, :running] do
      docker_adapter().stop_container(state.docker_container_id)
    end

    :ok
  end

  # ===========================================================================
  # Private Functions - Container Lifecycle
  # ===========================================================================

  defp start_new_container(state) do
    name = Core.container_name(state.workspace_slug, state.container_slug)

    labels =
      Core.build_container_labels(
        state.container_record_id,
        state.workspace_slug,
        state.container_slug
      )

    # Allocate a unique RPC port, avoiding ports used by other containers
    used_ports = get_used_rpc_ports()

    case PortAllocator.allocate_port(used_ports) do
      {:ok, rpc_port} ->
        Logger.info("Starting Docker container", docker_name: name, rpc_port: rpc_port)
        do_start_container(state, name, labels, rpc_port)

      {:error, :no_ports_available} ->
        Logger.error("No RPC ports available in range")
        {:error, :no_ports_available}
    end
  end

  defp do_start_container(state, name, labels, rpc_port) do
    with {:ok, docker_container_id} <- docker_adapter().start_container(name, labels, rpc_port),
         {:ok, rpc_endpoint} <- docker_adapter().get_rpc_endpoint(docker_container_id) do
      Logger.info("Docker container started",
        docker_container_id: docker_container_id,
        rpc_host: rpc_endpoint.host,
        rpc_port: rpc_endpoint.port
      )

      new_state = %{
        state
        | docker_container_id: docker_container_id,
          rpc_port: rpc_port,
          rpc_endpoint: rpc_endpoint,
          status: :starting,
          started_at: DateTime.utc_now()
      }

      {:ok, new_state}
    end
  end

  defp adopt_existing_container(state) do
    Logger.info("Adopting existing Docker container",
      docker_container_id: state.docker_container_id
    )

    if docker_adapter().container_running?(state.docker_container_id) do
      case docker_adapter().get_rpc_endpoint(state.docker_container_id) do
        {:ok, rpc_endpoint} ->
          # Get the port from the endpoint (it was read from container labels)
          new_state = %{
            state
            | rpc_port: rpc_endpoint.port,
              rpc_endpoint: rpc_endpoint,
              status: :starting,
              started_at: DateTime.utc_now()
          }

          {:ok, new_state}

        {:error, _reason} ->
          start_new_container(%{state | docker_container_id: nil})
      end
    else
      start_new_container(%{state | docker_container_id: nil})
    end
  end

  defp handle_start_failure(state, reason) do
    Logger.error("Failed to start container", reason: inspect(reason))
    handle_container_crash(state)
  end

  defp handle_container_crash(state) do
    new_restart_count = state.restart_count + 1

    # Emit offline for all consoles before going offline
    for {track_id, _console_info} <- state.consoles do
      broadcast_console_offline(state, track_id)
    end

    if new_restart_count > max_restart_count() do
      Logger.error("Container exceeded max restarts", restart_count: new_restart_count)

      new_state = %{
        state
        | status: :offline,
          docker_container_id: nil,
          rpc_endpoint: nil,
          msgrpc_token: nil,
          consoles: %{}
      }

      broadcast_container_status(new_state)
      {:noreply, new_state}
    else
      backoff = Core.calculate_backoff(new_restart_count, base_backoff_ms(), max_backoff_ms())
      Logger.info("Scheduling container restart", backoff_ms: backoff, attempt: new_restart_count)

      Process.send_after(self(), :start_container, backoff)

      new_state = %{
        state
        | docker_container_id: nil,
          rpc_endpoint: nil,
          status: :offline,
          restart_count: new_restart_count,
          msgrpc_token: nil,
          msgrpc_connect_attempts: 0,
          consoles: %{}
      }

      broadcast_container_status(new_state)
      {:noreply, new_state}
    end
  end

  # NOTE: calculate_backoff is in Container.Core module

  # ===========================================================================
  # Private Functions - MSGRPC Connection
  # ===========================================================================

  defp handle_msgrpc_connect_failure(state, _reason) do
    if state.msgrpc_connect_attempts >= msgrpc_max_connect_attempts() do
      Logger.error("MSGRPC connection failed after max attempts",
        attempts: state.msgrpc_connect_attempts
      )

      handle_container_crash(state)
    else
      backoff = msgrpc_connect_base_backoff_ms() * state.msgrpc_connect_attempts
      Logger.info("Retrying MSGRPC connection", backoff_ms: backoff)
      schedule_msgrpc_connect(backoff)
      {:noreply, state}
    end
  end

  defp schedule_msgrpc_connect(delay_ms) do
    Process.send_after(self(), :connect_msgrpc, delay_ms)
  end

  # ===========================================================================
  # Private Functions - Console Management
  # ===========================================================================

  defp spawn_all_consoles(state) do
    Enum.reduce(state.registered_tracks, state, fn track_id, acc_state ->
      spawn_console(acc_state, track_id)
    end)
  end

  defp spawn_console(state, track_id) do
    # Get current restart attempts from state (may be nil if first spawn)
    current_attempts = get_in(state.consoles, [track_id, :restart_attempts]) || 0

    Logger.debug("Attempting to spawn console",
      track_id: track_id,
      attempt: current_attempts + 1
    )

    # Obtain fresh token for each console spawn (and update stored token for RPC context)
    case msgrpc_client().login(state.rpc_endpoint, msgrpc_password(), "msf") do
      {:ok, token} ->
        # Update stored token so get_rpc_context returns a fresh token
        state = %{state | msgrpc_token: token}

        opts = [
          endpoint: state.rpc_endpoint,
          token: token,
          workspace_id: state.workspace_id,
          container_id: state.container_record_id,
          track_id: track_id
        ]

        # Use start (not start_link) to avoid linking - we monitor instead
        # to handle console crashes gracefully and restart
        case Console.start(opts) do
          {:ok, pid} ->
            ref = Process.monitor(pid)

            console_info = %{
              pid: pid,
              ref: ref,
              restart_attempts: 0,
              last_restart_at: nil
            }

            Logger.info("Spawned console", track_id: track_id)
            %{state | consoles: Map.put(state.consoles, track_id, console_info)}

          {:error, reason} ->
            Logger.error("Failed to spawn console process",
              track_id: track_id,
              attempt: current_attempts + 1,
              reason: inspect(reason)
            )

            handle_spawn_failure(state, track_id, current_attempts)
        end

      {:error, reason} ->
        Logger.error("Failed to authenticate for console",
          track_id: track_id,
          attempt: current_attempts + 1,
          reason: inspect(reason)
        )

        handle_spawn_failure(state, track_id, current_attempts)
    end
  end

  # Handle console spawn failure with proper retry tracking
  defp handle_spawn_failure(state, track_id, current_attempts) do
    new_attempts = current_attempts + 1

    if new_attempts <= console_max_restart_attempts() do
      schedule_console_restart(track_id, new_attempts)

      # Update state to track restart attempts
      updated_info = %{
        pid: nil,
        ref: nil,
        restart_attempts: new_attempts,
        last_restart_at: DateTime.utc_now()
      }

      %{state | consoles: Map.put(state.consoles, track_id, updated_info)}
    else
      Logger.error("Console spawn exceeded max attempts, giving up",
        track_id: track_id,
        attempts: new_attempts,
        max_attempts: console_max_restart_attempts()
      )

      broadcast_console_offline(state, track_id)
      %{state | consoles: Map.delete(state.consoles, track_id)}
    end
  end

  defp stop_console(state, track_id) do
    case Map.get(state.consoles, track_id) do
      nil ->
        state

      %{pid: nil} ->
        %{state | consoles: Map.delete(state.consoles, track_id)}

      %{pid: pid, ref: ref} ->
        Process.demonitor(ref, [:flush])
        Console.go_offline(pid)
        broadcast_console_offline(state, track_id)
        %{state | consoles: Map.delete(state.consoles, track_id)}
    end
  end

  defp handle_console_down(state, track_id, reason) do
    Logger.warning("Console process died", track_id: track_id, reason: inspect(reason))

    # Emit offline event on behalf of dead process
    broadcast_console_offline(state, track_id)

    console_info = Map.get(state.consoles, track_id)
    new_restart_attempts = (console_info && console_info.restart_attempts + 1) || 1

    if MapSet.member?(state.registered_tracks, track_id) && state.status == :running do
      if new_restart_attempts <= console_max_restart_attempts() do
        # Schedule restart
        schedule_console_restart(track_id, new_restart_attempts)

        # Update console info to track restart attempts
        updated_info = %{
          pid: nil,
          ref: nil,
          restart_attempts: new_restart_attempts,
          last_restart_at: DateTime.utc_now()
        }

        {:noreply, %{state | consoles: Map.put(state.consoles, track_id, updated_info)}}
      else
        Logger.error("Console exceeded max restarts, giving up",
          track_id: track_id,
          attempts: new_restart_attempts,
          max_attempts: console_max_restart_attempts()
        )

        {:noreply, %{state | consoles: Map.delete(state.consoles, track_id)}}
      end
    else
      Logger.warning(
        "Console down but cannot restart: track_registered=#{MapSet.member?(state.registered_tracks, track_id)}, status=#{state.status}",
        track_id: track_id
      )

      {:noreply, %{state | consoles: Map.delete(state.consoles, track_id)}}
    end
  end

  defp schedule_console_restart(track_id, attempt) do
    backoff =
      Core.calculate_backoff(
        attempt,
        console_restart_base_backoff_ms(),
        console_restart_max_backoff_ms()
      )

    Logger.info("Scheduling console restart",
      track_id: track_id,
      attempt: attempt,
      backoff_ms: backoff
    )

    Process.send_after(self(), {:restart_console, track_id}, backoff)
  end

  # NOTE: Console/command lookup and validation logic is in Container.Core module

  # ===========================================================================
  # Private Functions - Bash Execution
  # ===========================================================================

  defp execute_bash_command(parent, cmd_id, docker_container_id, command) do
    case docker_adapter().exec(docker_container_id, command) do
      {:ok, output, exit_code} ->
        # Process completed - trace with actual exit code
        Trace.bash(command, output, exit_code)
        send(parent, {:bash_output, cmd_id, output})
        send(parent, {:bash_finished, cmd_id, exit_code})

      {:error, reason} ->
        # Infrastructure failure - couldn't run the process
        send(parent, {:bash_error, cmd_id, reason})
    end
  end

  # ===========================================================================
  # Private Functions - Scheduling
  # ===========================================================================

  defp schedule_health_check do
    Process.send_after(self(), :health_check, health_check_interval_ms())
  end

  defp maybe_schedule_restart_reset(%{restart_count: count}) when count > 0 do
    Process.send_after(self(), :reset_restart_count, success_reset_ms())
  end

  defp maybe_schedule_restart_reset(_state), do: :ok

  # ===========================================================================
  # Private Functions - Event Broadcasting
  # ===========================================================================

  defp broadcast_container_status(state) do
    Events.broadcast(WorkspaceChanged.new(state.workspace_id))
  end

  defp broadcast_console_offline(state, track_id) do
    event = ConsoleUpdated.offline(state.workspace_id, state.container_record_id, track_id)
    Events.broadcast(event)
  end

  defp make_command_issued(state, track_id, %Command{} = cmd) do
    CommandIssued.new(
      state.workspace_id,
      state.container_record_id,
      track_id,
      cmd.id,
      cmd.type,
      cmd.command
    )
  end

  defp broadcast_command_issued(state, track_id, %Command{} = cmd) do
    event = make_command_issued(state, track_id, cmd)
    Events.broadcast(event)
  end

  defp broadcast_command_result(state, track_id, %Command{} = cmd) do
    issued = make_command_issued(state, track_id, cmd)

    event =
      case cmd.status do
        :finished ->
          CommandResult.finished(issued, cmd.output, exit_code: cmd.exit_code, prompt: cmd.prompt)

        :error ->
          CommandResult.error(issued, cmd.error)

        _ ->
          CommandResult.running(issued, cmd.output, prompt: cmd.prompt)
      end

    Events.broadcast(event)
  end

  # ===========================================================================
  # Private Functions - Helpers
  # ===========================================================================

  # NOTE: container_name and build_container_labels are in Container.Core module

  defp docker_adapter do
    Application.get_env(:msfailab, :docker_adapter, DockerAdapter.Cli)
  end

  defp msgrpc_client do
    Application.get_env(:msfailab, :msgrpc_client, Msfailab.Containers.Msgrpc.Client.Http)
  end

  defp msgrpc_password do
    Application.get_env(:msfailab, :msf_rpc_pass, "secret")
  end

  # Get RPC ports currently in use by other Container GenServers
  defp get_used_rpc_ports do
    Registry.select(Msfailab.Containers.Registry, [{{:_, :"$1", :_}, [], [:"$1"]}])
    |> Enum.map(fn pid ->
      try do
        case :sys.get_state(pid, 100) do
          %{rpc_port: port} when is_integer(port) -> port
          _ -> nil
        end
      catch
        :exit, _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  # coveralls-ignore-stop
end
