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

defmodule Msfailab.Containers.Msgrpc.Console do
  @moduledoc """
  GenServer managing a single MSGRPC console session.

  Each Console GenServer:
  - Creates an MSGRPC console session on start
  - Polls for output during initialization and command execution
  - Emits ConsoleUpdated events (:starting, :ready, :busy)
  - Executes commands sequentially (one at a time)

  ## MSGRPC Console API

  The Metasploit RPC API provides console management through these key calls:

  | Method            | Purpose                                           |
  |-------------------|---------------------------------------------------|
  | `console.create`  | Creates a new console, returns console ID         |
  | `console.write`   | Sends input to console (commands must end \\n)    |
  | `console.read`    | Reads output, returns `{data, busy, prompt}`      |
  | `console.destroy` | Destroys a console session                        |

  ### Key API Behaviors

  - **`console.read` is destructive**: Each read drains the buffer. If you don't
    capture the output, it's lost forever. This is why Console polls continuously.

  - **`busy: true`**: Means the console is executing a command. Keep polling
    until `busy: false` to capture all output.

  - **`prompt`**: Indicates console state (e.g., `"msf6 > "`, `"msf6 exploit(handler) > "`).
    Changes based on current module context.

  - **Initialization output**: After `console.create`, the console prints banner
    and startup output while `busy: true`. Poll until `busy: false` to capture.

  ## State Machine

  Console transitions through three operational states:

  ```
                      ┌────────────────────┐
                      │                    │◄───────────────────────┐
           ┌─────────►│     :offline       │                        │
           │          │                    │◄──────────┐            │
           │          └─────────┬──────────┘           │            │
           │                    │                      │            │
           │                    │ container :running   │            │
           │                    │ + console.create     │            │
           │                    ▼                      │            │
           │          ┌────────────────────┐           │            │
           │          │                    │           │ API        │
           │          │     :starting      │───────────┤ failure    │ container
           │          │                    │           │ (destroy   │ offline
           │          └─────────┬──────────┘           │ + recreate)│
           │                    │                      │            │
           │                    │ busy=false (ready)   │            │
           │                    ▼                      │            │
           │          ┌────────────────────┐           │            │
           │          │                    │───────────┘            │
           └──────────│      :ready        │────────────────────────┤
         container    │                    │◄──────────┐            │
         offline      └─────────┬──────────┘           │            │
                                │                      │            │
                                │ send_command         │ command    │
                                ▼                      │ complete   │
                      ┌────────────────────┐           │            │
                      │                    │───────────┘            │
                      │      :busy         │────────────────────────┘
                      │                    │
                      └────────────────────┘
  ```

  ### State Descriptions

  | State      | Description                                                       |
  |------------|-------------------------------------------------------------------|
  | `:offline` | Not connected. Container not running, or console destroyed.       |
  |            | This state is tracked by Container, not by Console itself         |
  |            | (Console process doesn't exist when offline).                     |
  | `:starting`| Console created via `console.create`, reading initialization.     |
  |            | Polling for startup banner and init output until `busy: false`.   |
  | `:ready`   | Idle, can accept commands. Prompt available.                      |
  | `:busy`    | Command executing, polling for output until `busy: false`.        |

  ### State Transitions

  | From        | To          | Trigger                                        |
  |-------------|-------------|------------------------------------------------|
  | (spawn)     | `:starting` | Console GenServer starts, calls `console.create` |
  | `:starting` | `:ready`    | First `console.read` returns `busy: false`     |
  | `:ready`    | `:busy`     | `send_command` called                          |
  | `:busy`     | `:ready`    | `console.read` returns `busy: false`           |
  | any         | (dead)      | Container goes offline or persistent API failure|

  **Note:** Console doesn't have an `:offline` state internally. When the console
  goes offline, the process terminates and Container emits `ConsoleUpdated(:offline)`.

  ## Lifecycle Flow

  ```
  start_link(opts)
       │
       ▼
  init/1: Store endpoint/token, send :create_console message
       │
       ▼
  handle_info(:create_console):
       ├─► Call console.create API
       ├─► Store console_id
       └─► Schedule :poll_output
       │
       ▼
  :starting state (polling loop):
       ├─► Call console.read
       ├─► If data present: emit ConsoleUpdated(:starting, output: data)
       ├─► If busy=true: schedule next poll
       └─► If busy=false: transition to :ready, emit ConsoleUpdated(:ready)
       │
       ▼
  :ready state (waiting for commands):
       └─► On send_command:
             ├─► Call console.write
             ├─► Transition to :busy
             ├─► Emit ConsoleUpdated(:busy, command_id, command)
             └─► Schedule :poll_output
       │
       ▼
  :busy state (polling loop):
       ├─► Call console.read
       ├─► If data present: emit ConsoleUpdated(:busy, output: data)
       ├─► If busy=true: schedule next poll
       └─► If busy=false: transition to :ready, emit ConsoleUpdated(:ready)
  ```

  ## Command Execution Semantics

  Commands are only accepted when console is `:ready`:

  | Console State | send_command Result | Behavior                           |
  |---------------|---------------------|------------------------------------|
  | `:starting`   | `{:error, :starting}` | Rejected, still initializing     |
  | `:ready`      | `{:ok, command_id}` | Accepted, transitions to `:busy`   |
  | `:busy`       | `{:error, :busy}`   | Rejected, command in progress      |

  **No command queuing:** Commands are rejected immediately if the console is not
  ready. Callers (TrackServer, LiveView) must handle rejection and retry or inform
  the user. This keeps the system simple and provides clear feedback.

  ### Command Flow Detail

  ```elixir
  # In handle_call({:send_command, command}, ...)
  def handle_call({:send_command, command}, _from, %{status: :ready} = state) do
    command_id = generate_command_id()

    # Write to console (add newline if needed)
    case console_write(state, command <> "\\n") do
      {:ok, _} ->
        new_state = %{
          state |
          status: :busy,
          current_command_id: command_id,
          current_command: command,
          accumulated_output: ""
        }

        broadcast_busy(new_state, "")
        schedule_poll()

        {:reply, {:ok, command_id}, new_state}

      {:error, reason} ->
        {:reply, {:error, :write_failed}, state}
    end
  end
  ```

  ## Polling Mechanism

  Console uses a simple polling loop to read output from MSGRPC:

  - **Poll interval:** 100ms (configurable via `@poll_interval_ms`)
  - **Triggered by:** `Process.send_after(self(), :poll_output, @poll_interval_ms)`
  - **Continues while:** Console is `:starting` or `:busy`
  - **Stops when:** `console.read` returns `busy: false`

  ### Output Accumulation

  During command execution, output is accumulated in `accumulated_output` and
  emitted via ConsoleUpdated events as it arrives. Each event contains only the
  *delta* (new output since last event), not the full accumulated output.

  ## Error Handling and Recovery

  ### Retry Strategy for API Failures

  **Transient failures (network blips, timeouts):**
  - Small fixed delays: 100ms, 200ms, 400ms (3 attempts)
  - Retries tracked in `retry_count`
  - On success, retry count resets to 0

  **Persistent failures (max retries exceeded):**
  - Console process stops with error reason
  - Container detects via process monitor
  - Container emits `ConsoleUpdated(:offline)`
  - Container schedules console restart with backoff

  ### Why Console Doesn't Emit :offline

  A dead process cannot emit events. When Console terminates (crash, persistent
  failure, graceful shutdown), the Container GenServer:

  1. Receives `{:DOWN, ref, :process, pid, reason}` from process monitor
  2. Emits `ConsoleUpdated(:offline)` on Console's behalf
  3. Schedules restart if track is still registered and container is `:running`

  This ensures subscribers always receive the offline event.

  ## Event Emission

  Console emits ConsoleUpdated events during normal operation:

  | Status      | When Emitted                      | Event Contents                  |
  |-------------|-----------------------------------|---------------------------------|
  | `:starting` | During initialization polling     | `output: <chunk>`               |
  | `:ready`    | Init complete or command complete | `prompt: <current prompt>`      |
  | `:busy`     | During command execution polling  | `command_id, command, output`   |

  **Important:** When this process crashes or stops, the Container GenServer emits
  `ConsoleUpdated(:offline)` on its behalf. The dead process cannot emit events.

  ## Process State Structure

  ```elixir
  %{
    # Connection (provided by Container on spawn)
    endpoint: %{host: String.t(), port: pos_integer()},
    token: String.t(),
    console_id: String.t() | nil,

    # Status
    status: :starting | :ready | :busy,

    # Current operation
    current_command_id: String.t() | nil,
    current_command: String.t() | nil,
    accumulated_output: String.t(),
    current_prompt: String.t(),

    # Retry tracking
    retry_count: non_neg_integer(),

    # Event routing
    workspace_id: integer(),
    container_id: integer(),
    track_id: integer()
  }
  ```

  ## Usage

  This module is internal to the Containers context. Container GenServer spawns
  and monitors Console processes. External callers should use the `Containers`
  context API.

  ### Example: Container spawning a Console

  ```elixir
  defp spawn_console(state, track_id) do
    opts = [
      endpoint: state.rpc_endpoint,
      token: state.msgrpc_token,
      workspace_id: state.workspace_id,
      container_id: state.container_record_id,
      track_id: track_id
    ]

    case Console.start_link(opts) do
      {:ok, pid} ->
        ref = Process.monitor(pid)
        # Store console_info in state.consoles[track_id]
        ...
      {:error, reason} ->
        # Schedule retry
        ...
    end
  end
  ```

  ## Key Design Decisions

  ### No Command Queuing

  **Decision:** `send_command` returns error if console not `:ready`. No queuing.

  **Rationale:**
  - Simpler implementation
  - Clear feedback to user ("console is busy/offline")
  - Caller (UI) can decide how to handle (show error, disable button, etc.)

  ### Container Emits :offline for Dead Consoles

  **Decision:** When Console dies, Container emits `ConsoleUpdated(:offline)`.

  **Rationale:**
  - Dead process cannot emit events
  - Container already monitors Consoles via `Process.monitor/1`
  - Ensures no gaps in event stream for subscribers

  ### Status Returns :offline for Missing GenServers

  **Decision:** `get_consoles` returns `:offline` status for registered tracks
  without running Console GenServers.

  **Rationale:**
  - Unified API regardless of GenServer existence
  - No special "not started" state
  - `:offline` accurately describes the situation (no console available)
  """

  use GenServer, restart: :temporary

  require Logger

  alias Msfailab.Events
  alias Msfailab.Events.ConsoleUpdated
  alias Msfailab.Trace

  # Get the configured MSGRPC client implementation
  defp msgrpc_client do
    Application.get_env(:msfailab, :msgrpc_client, Msfailab.Containers.Msgrpc.Client.Http)
  end

  # Configuration accessors for timing values (allows test overrides)
  defp poll_interval_ms,
    do: get_timing(:poll_interval_ms, 100)

  defp keepalive_interval_ms,
    do: get_timing(:keepalive_interval_ms, 60_000)

  defp max_retries,
    do: get_timing(:max_retries, 3)

  defp retry_delays_ms,
    do: get_timing(:retry_delays_ms, [100, 200, 400])

  defp get_timing(key, default) do
    :msfailab
    |> Application.get_env(:console_timing, [])
    |> Keyword.get(key, default)
  end

  @typedoc "Console status"
  @type status :: :starting | :ready | :busy

  @typedoc "Console GenServer state"
  @type state :: %{
          # Connection (provided by Container)
          endpoint: %{host: String.t(), port: pos_integer()},
          token: String.t(),
          console_id: String.t() | nil,
          # Status
          status: status(),
          # Current operation
          current_command_id: String.t() | nil,
          current_command: String.t() | nil,
          accumulated_output: String.t(),
          current_prompt: String.t(),
          # Retry tracking
          retry_count: non_neg_integer(),
          # Event routing
          workspace_id: integer(),
          container_id: integer(),
          track_id: integer()
        }

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Starts a Console GenServer.

  The process automatically creates an MSGRPC console session and begins
  polling for initialization output. Events are emitted as the console
  initializes.

  ## Options

  - `:endpoint` - Required. The MSGRPC endpoint `%{host: String.t(), port: pos_integer()}`
  - `:token` - Required. The authenticated MSGRPC token
  - `:workspace_id` - Required. For event routing
  - `:container_id` - Required. For event routing
  - `:track_id` - Required. For event routing
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Starts a Console process without linking.

  Use this when the caller will monitor the process and handle crashes
  independently (e.g., Container GenServer that needs to restart consoles).
  """
  @spec start(keyword()) :: GenServer.on_start()
  def start(opts) do
    GenServer.start(__MODULE__, opts)
  end

  @doc """
  Sends a command to the console.

  Returns `{:ok, command_id}` if the command was accepted.
  Returns `{:error, :busy}` if a command is already executing.
  Returns `{:error, :starting}` if the console is still initializing.
  Returns `{:error, :write_failed}` if the write failed (process will crash and restart).
  """
  @spec send_command(pid(), String.t()) ::
          {:ok, String.t()} | {:error, :busy | :starting | :write_failed}
  def send_command(pid, command) do
    GenServer.call(pid, {:send_command, command})
  end

  @doc """
  Gets the current console status.
  """
  @spec get_status(pid()) :: status()
  def get_status(pid) do
    GenServer.call(pid, :get_status)
  end

  @doc """
  Gets the current prompt string.

  Returns the prompt if available, empty string otherwise.
  """
  @spec get_prompt(pid()) :: String.t()
  def get_prompt(pid) do
    GenServer.call(pid, :get_prompt)
  end

  @doc """
  Notifies the console that the container is going offline.

  This triggers graceful cleanup (console.destroy) before the process stops.
  """
  @spec go_offline(pid()) :: :ok
  def go_offline(pid) do
    GenServer.cast(pid, :go_offline)
  end

  # ===========================================================================
  # GenServer Callbacks
  # ===========================================================================

  @impl true
  def init(opts) do
    endpoint = Keyword.fetch!(opts, :endpoint)
    token = Keyword.fetch!(opts, :token)
    workspace_id = Keyword.fetch!(opts, :workspace_id)
    container_id = Keyword.fetch!(opts, :container_id)
    track_id = Keyword.fetch!(opts, :track_id)

    # Set process-level metadata for all subsequent logs
    Logger.metadata(
      track_id: track_id,
      container_id: container_id,
      workspace_id: workspace_id
    )

    state = %{
      endpoint: endpoint,
      token: token,
      console_id: nil,
      status: :starting,
      current_command_id: nil,
      current_command: nil,
      accumulated_output: "",
      current_prompt: "",
      retry_count: 0,
      workspace_id: workspace_id,
      container_id: container_id,
      track_id: track_id
    }

    # Create console asynchronously to avoid blocking
    send(self(), :create_console)

    {:ok, state}
  end

  @impl true
  def handle_call({:send_command, command}, _from, %{status: :ready} = state) do
    command_id = generate_command_id()

    # Write command to console (add newline if not present)
    command_with_newline =
      if String.ends_with?(command, "\n"), do: command, else: command <> "\n"

    case msgrpc_client().console_write(
           state.endpoint,
           state.token,
           state.console_id,
           command_with_newline
         ) do
      {:ok, _wrote} ->
        new_state = %{
          state
          | status: :busy,
            current_command_id: command_id,
            current_command: command,
            accumulated_output: "",
            retry_count: 0
        }

        # Emit initial busy event
        broadcast_busy(new_state, "")

        # Start polling for output
        schedule_poll()

        {:reply, {:ok, command_id}, new_state}

      {:error, reason} ->
        Logger.error("Console write failed, stopping", reason: inspect(reason))
        # Let process crash so Container can restart with fresh token
        {:stop, {:console_write_failed, reason}, {:error, :write_failed}, state}
    end
  end

  def handle_call({:send_command, _command}, _from, %{status: :busy} = state) do
    {:reply, {:error, :busy}, state}
  end

  def handle_call({:send_command, _command}, _from, %{status: :starting} = state) do
    {:reply, {:error, :starting}, state}
  end

  def handle_call(:get_status, _from, state) do
    {:reply, state.status, state}
  end

  def handle_call(:get_prompt, _from, state) do
    {:reply, state.current_prompt, state}
  end

  @impl true
  def handle_cast(:go_offline, state) do
    cleanup_console(state)
    {:stop, :normal, state}
  end

  @impl true
  def handle_info(:create_console, state) do
    case msgrpc_client().console_create(state.endpoint, state.token) do
      {:ok, %{"id" => console_id}} ->
        Logger.info("Created MSGRPC console", console_id: console_id)
        new_state = %{state | console_id: console_id}

        # Start polling for initialization output
        schedule_poll()

        {:noreply, new_state}

      {:error, reason} ->
        Logger.error("Failed to create console", reason: inspect(reason))
        # Let the process crash so Container can handle restart
        {:stop, {:console_create_failed, reason}, state}
    end
  end

  def handle_info(:poll_output, state) do
    handle_poll(state)
  end

  def handle_info(:keepalive, %{status: :ready} = state) do
    # Perform keepalive read to keep token alive
    case msgrpc_client().console_read(state.endpoint, state.token, state.console_id) do
      {:ok, _result} ->
        schedule_keepalive()
        {:noreply, state}

      {:error, reason} ->
        Logger.error("Keepalive read failed, stopping", reason: inspect(reason))
        {:stop, {:keepalive_failed, reason}, state}
    end
  end

  def handle_info(:keepalive, state) do
    # Not in :ready state, ignore keepalive (new one will be scheduled when returning to :ready)
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.debug("Console terminating", reason: inspect(reason))
    cleanup_console(state)
    :ok
  end

  # ===========================================================================
  # Private Functions
  # ===========================================================================

  defp handle_poll(%{console_id: nil} = state) do
    # Console not created yet, shouldn't happen but handle gracefully
    {:noreply, state}
  end

  defp handle_poll(state) do
    case msgrpc_client().console_read(state.endpoint, state.token, state.console_id) do
      {:ok, %{"data" => data, "busy" => busy} = result} ->
        prompt = Map.get(result, "prompt", "")
        handle_poll_success(state, data, busy, prompt)

      {:error, reason} ->
        handle_poll_failure(state, reason)
    end
  end

  defp handle_poll_success(state, data, busy, prompt) do
    new_output = state.accumulated_output <> data
    new_prompt = if prompt != "", do: prompt, else: state.current_prompt

    transition_state(state, data, busy, new_output, new_prompt)
  end

  defp transition_state(%{status: :starting} = state, data, true, new_output, new_prompt) do
    # Still initializing, emit output and continue polling
    if data != "", do: broadcast_starting(state, data)
    schedule_poll()

    {:noreply,
     %{state | accumulated_output: new_output, current_prompt: new_prompt, retry_count: 0}}
  end

  defp transition_state(%{status: :starting} = state, data, false, _new_output, new_prompt) do
    # Initialization complete
    if data != "", do: broadcast_starting(state, data)
    broadcast_ready(state, new_prompt)
    schedule_keepalive()

    {:noreply,
     %{state | status: :ready, accumulated_output: "", current_prompt: new_prompt, retry_count: 0}}
  end

  defp transition_state(%{status: :busy} = state, data, true, new_output, new_prompt) do
    # Command still executing, emit output and continue polling
    if data != "", do: broadcast_busy(state, data)
    schedule_poll()

    {:noreply,
     %{state | accumulated_output: new_output, current_prompt: new_prompt, retry_count: 0}}
  end

  defp transition_state(%{status: :busy} = state, data, false, _new_output, new_prompt) do
    # Command finished
    if data != "", do: broadcast_busy(state, data)
    broadcast_ready(state, new_prompt)
    schedule_keepalive()

    # Trace the completed command with full output
    full_output = state.accumulated_output <> data
    Trace.metasploit(state.current_prompt, state.current_command, full_output)

    {:noreply,
     %{
       state
       | status: :ready,
         current_command_id: nil,
         current_command: nil,
         accumulated_output: "",
         current_prompt: new_prompt,
         retry_count: 0
     }}
  end

  defp transition_state(%{status: :ready} = state, _data, _busy, _new_output, new_prompt) do
    # Shouldn't be polling in ready state, but handle gracefully
    {:noreply, %{state | current_prompt: new_prompt}}
  end

  defp handle_poll_failure(state, reason) do
    new_retry_count = state.retry_count + 1

    if new_retry_count <= max_retries() do
      Logger.warning("Console read failed, retrying",
        attempt: new_retry_count,
        max_retries: max_retries(),
        reason: inspect(reason)
      )

      delays = retry_delays_ms()
      delay = Enum.at(delays, new_retry_count - 1, List.last(delays))
      Process.send_after(self(), :poll_output, delay)
      {:noreply, %{state | retry_count: new_retry_count}}
    else
      Logger.error("Console read failed after max retries, stopping",
        attempts: max_retries(),
        reason: inspect(reason)
      )

      # Let process crash so Container can emit :offline and restart
      {:stop, {:console_read_failed, reason}, state}
    end
  end

  defp schedule_poll do
    Process.send_after(self(), :poll_output, poll_interval_ms())
  end

  defp schedule_keepalive do
    Process.send_after(self(), :keepalive, keepalive_interval_ms())
  end

  defp cleanup_console(%{console_id: nil}), do: :ok

  defp cleanup_console(state) do
    case msgrpc_client().console_destroy(state.endpoint, state.token, state.console_id) do
      :ok ->
        Logger.debug("Destroyed MSGRPC console", console_id: state.console_id)

      {:error, reason} ->
        Logger.warning("Failed to destroy MSGRPC console",
          console_id: state.console_id,
          reason: inspect(reason)
        )
    end
  end

  defp generate_command_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  # ===========================================================================
  # Event Broadcasting
  # ===========================================================================

  defp broadcast_starting(state, output) do
    event =
      ConsoleUpdated.starting(
        state.workspace_id,
        state.container_id,
        state.track_id,
        output
      )

    Events.broadcast(event)
  end

  defp broadcast_ready(state, prompt) do
    event =
      ConsoleUpdated.ready(
        state.workspace_id,
        state.container_id,
        state.track_id,
        prompt
      )

    Events.broadcast(event)
  end

  defp broadcast_busy(state, output) do
    event =
      ConsoleUpdated.busy(
        state.workspace_id,
        state.container_id,
        state.track_id,
        state.current_command_id,
        state.current_command,
        output
      )

    Events.broadcast(event)
  end
end
