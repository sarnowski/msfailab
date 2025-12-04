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

defmodule Msfailab.Tracks.TrackServer do
  @moduledoc """
  GenServer managing the session state for a track.

  This module is the **shell** in the Functional Core, Imperative Shell pattern.
  It holds process state, routes events to core modules, and executes side effects.

  ## Architecture

  ```
  TrackServer (Shell)
  ├── Routes events to cores
  ├── Executes actions returned by cores
  └── Manages process lifecycle

  Core Modules (Pure Functions)
  ├── TrackServer.Console - Console history state machine
  ├── TrackServer.Stream  - LLM streaming content handling
  └── TrackServer.Turn    - Agentic turn lifecycle & reconciliation
  ```

  ## Event Flow

  ```
  Event arrives → Delegate to core → Core returns {new_state, actions} → Execute actions
  ```

  ## State Structure

  State is organized into sub-states owned by each core:
  - `console` - Console status, history blocks (Console core)
  - `stream` - Streaming blocks, documents, positions (Stream core)
  - `turn` - Turn status, tool invocations, LLM ref (Turn core)
  - `chat_entries` - Shared UI entries (read by multiple cores)

  See `TrackServer.State` for full type definitions.

  ## Turn and Request Model

  A **Turn** is a complete agentic loop from user prompt until the LLM stops
  (no more tool calls). A turn may contain multiple **LLM Requests** if tool
  calls are involved.

  ## Turn Status State Machine

  See `TrackServer.Turn` for the full state machine diagram.

  ## Tool Invocation Lifecycle

  See `TrackServer.Turn` for the full lifecycle diagram.
  """

  use GenServer, restart: :transient

  require Logger

  alias Msfailab.Containers
  alias Msfailab.Events
  alias Msfailab.Events.CommandResult
  alias Msfailab.Events.ConsoleUpdated
  alias Msfailab.LLM
  alias Msfailab.LLM.Events, as: LLMEvents
  alias Msfailab.Tracks
  alias Msfailab.Tracks.ChatContext
  alias Msfailab.Tracks.ChatEntry
  alias Msfailab.Tracks.ChatState
  alias Msfailab.Tracks.ConsoleHistoryBlock
  alias Msfailab.Tracks.Memory
  alias Msfailab.Tracks.TrackServer.Action
  alias Msfailab.Tracks.TrackServer.Console
  alias Msfailab.Tracks.TrackServer.State
  alias Msfailab.Tracks.TrackServer.Stream
  alias Msfailab.Tracks.TrackServer.Turn
  alias Msfailab.Workspaces

  @typedoc "Console status"
  @type console_status :: :offline | :starting | :ready | :busy

  @typedoc "Turn status in the agentic loop lifecycle"
  @type turn_status ::
          :idle
          | :pending
          | :streaming
          | :pending_approval
          | :executing_tools
          | :finished
          | :error

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Starts a TrackServer process linked to the calling process.

  ## Options

  - `:track_id` - Required. The database ID of the track.
  - `:workspace_id` - Required. The database ID of the workspace.
  - `:container_id` - Required. The database ID of the container.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    track_id = Keyword.fetch!(opts, :track_id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(track_id))
  end

  @doc """
  Returns the via tuple for Registry lookup by track_id.
  """
  @spec via_tuple(integer()) :: {:via, Registry, {module(), integer()}}
  def via_tuple(track_id) do
    {:via, Registry, {Msfailab.Tracks.Registry, track_id}}
  end

  @doc """
  Looks up the pid of a TrackServer GenServer by track_id.

  Returns the pid if found, nil otherwise.
  """
  @spec whereis(integer()) :: pid() | nil
  def whereis(track_id) do
    case Registry.lookup(Msfailab.Tracks.Registry, track_id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @doc """
  Gets the console history for a track.

  Returns a list of `ConsoleHistoryBlock` structs in chronological order (oldest first).
  """
  @spec get_console_history(integer()) :: [ConsoleHistoryBlock.t()]
  def get_console_history(track_id) do
    GenServer.call(via_tuple(track_id), :get_console_history)
  end

  @doc """
  Gets the current console status for a track.
  """
  @spec get_console_status(integer()) :: console_status()
  def get_console_status(track_id) do
    GenServer.call(via_tuple(track_id), :get_console_status)
  end

  @doc """
  Gets the current console prompt for a track.
  """
  @spec get_prompt(integer()) :: String.t()
  def get_prompt(track_id) do
    GenServer.call(via_tuple(track_id), :get_prompt)
  end

  @doc """
  Gets a full state snapshot for UI rendering.

  Returns a map with `:console_status`, `:current_prompt`, and `:console_history`.
  """
  @spec get_state(integer()) :: %{
          console_status: console_status(),
          current_prompt: String.t(),
          console_history: [ConsoleHistoryBlock.t()]
        }
  def get_state(track_id) do
    GenServer.call(via_tuple(track_id), :get_state)
  end

  # ---------------------------------------------------------------------------
  # Chat API
  # ---------------------------------------------------------------------------

  @doc """
  Starts a new chat turn with the given user prompt.

  Creates a new turn, persists the user prompt as an entry, builds the
  conversation context, and starts streaming from the LLM.

  ## Parameters

  - `track_id` - The track to start the turn in
  - `user_prompt` - The user's message
  - `model` - The model to use for this turn

  ## Returns

  - `{:ok, turn_id}` - The turn was started successfully
  - `{:error, reason}` - Failed to start the turn
  """
  @spec start_chat_turn(integer(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, term()}
  def start_chat_turn(track_id, user_prompt, model) do
    GenServer.call(via_tuple(track_id), {:start_chat_turn, user_prompt, model})
  end

  @doc """
  Gets the current chat state for UI rendering.

  Returns a `ChatState` struct with entries and turn status.
  """
  @spec get_chat_state(integer()) :: ChatState.t()
  def get_chat_state(track_id) do
    GenServer.call(via_tuple(track_id), :get_chat_state)
  end

  # ---------------------------------------------------------------------------
  # Tool Approval API
  # ---------------------------------------------------------------------------

  @doc """
  Approves a pending tool invocation.

  Triggers reconciliation which may start tool execution if the console is ready.
  """
  @spec approve_tool(integer(), String.t()) :: :ok | {:error, term()}
  def approve_tool(track_id, entry_id) do
    GenServer.call(via_tuple(track_id), {:approve_tool, entry_id})
  end

  @doc """
  Denies a pending tool invocation with a reason.

  Triggers reconciliation which may continue the LLM turn with the denial result.
  """
  @spec deny_tool(integer(), String.t(), String.t()) :: :ok | {:error, term()}
  def deny_tool(track_id, entry_id, reason) do
    GenServer.call(via_tuple(track_id), {:deny_tool, entry_id, reason})
  end

  @doc """
  Updates the autonomous mode setting for the track.

  When autonomous mode is enabled, tool invocations are automatically approved
  without waiting for user confirmation.
  """
  @spec set_autonomous(integer(), boolean()) :: :ok
  def set_autonomous(track_id, autonomous) do
    GenServer.cast(via_tuple(track_id), {:set_autonomous, autonomous})
  end

  # ===========================================================================
  # GenServer Callbacks
  # ===========================================================================

  @impl true
  def init(opts) do
    track_id = Keyword.fetch!(opts, :track_id)
    workspace_id = Keyword.fetch!(opts, :workspace_id)
    container_id = Keyword.fetch!(opts, :container_id)

    # Set process-level metadata for all subsequent logs
    Logger.metadata(
      track_id: track_id,
      workspace_id: workspace_id,
      container_id: container_id
    )

    # Load workspace to get slug (needed for MSF data tool scoping)
    workspace = Workspaces.get_workspace!(workspace_id)

    # Load track settings from database
    track = Tracks.get_track(track_id)
    autonomous = if track, do: track.autonomous, else: false

    # Load persisted console history (finished blocks only)
    persisted_history = Tracks.list_console_history_blocks(track_id)

    # Load persisted chat entries (both messages and tool invocations)
    persisted_entries = ChatContext.load_entries(track_id)
    chat_entries_raw = ChatContext.entries_to_chat_entries(persisted_entries)
    next_entry_position = ChatContext.next_entry_position(track_id)

    # Rebuild tool_invocations map from persisted entries with pending/approved status
    tool_invocations = rebuild_tool_invocations(persisted_entries)

    # Update chat_entries with effective statuses from tool_invocations
    # This ensures the UI shows correct statuses even before reconciliation runs
    chat_entries = apply_effective_statuses(chat_entries_raw, tool_invocations)

    # Get model from active turn if there are pending tools
    active_turn_model =
      if map_size(tool_invocations) > 0 do
        ChatContext.get_active_turn_model(track_id)
      else
        nil
      end

    # Create initial state using the State module
    # Note: Memory is not cached in TrackServer state - it's read from DB on demand
    state =
      State.from_persisted(
        %{
          track_id: track_id,
          workspace_id: workspace_id,
          workspace_slug: workspace.slug,
          container_id: container_id
        },
        autonomous: autonomous,
        console_history: persisted_history,
        chat_entries: chat_entries,
        next_position: next_entry_position,
        tool_invocations: tool_invocations,
        model: active_turn_model
      )

    # Subscribe to workspace events to receive ConsoleUpdated
    Events.subscribe_to_workspace(workspace_id)

    # Register console with Container (declare intent)
    register_console(container_id, track_id)

    Logger.debug("TrackServer started",
      history_blocks: length(persisted_history),
      chat_entries: length(chat_entries),
      pending_tools: map_size(tool_invocations)
    )

    # Log available LLM models (verification during bootstrap)
    log_llm_models()

    # If we loaded pending/approved tools, trigger reconciliation after init
    if map_size(tool_invocations) > 0 do
      send(self(), :reconcile)
    end

    {:ok, state}
  end

  @impl true
  def handle_call(:get_console_history, _from, state) do
    {:reply, state.console.history, state}
  end

  def handle_call(:get_console_status, _from, state) do
    {:reply, state.console.status, state}
  end

  def handle_call(:get_prompt, _from, state) do
    {:reply, state.console.current_prompt, state}
  end

  def handle_call(:get_state, _from, state) do
    # Memory is no longer cached in TrackServer state.
    # Load it from DB for the snapshot.
    memory =
      case Tracks.get_track(state.track_id) do
        nil -> Memory.new()
        track -> track.memory || Memory.new()
      end

    snapshot = %{
      console_status: state.console.status,
      current_prompt: state.console.current_prompt,
      console_history: state.console.history,
      memory: memory
    }

    {:reply, snapshot, state}
  end

  def handle_call(:get_chat_state, _from, state) do
    chat_state =
      ChatState.new(
        state.chat_entries,
        state.turn.status,
        state.turn.turn_id
      )

    {:reply, chat_state, state}
  end

  # ---------------------------------------------------------------------------
  # Chat Turn Start
  # ---------------------------------------------------------------------------

  # coveralls-ignore-start
  # Reason: LLM integration requiring mock infrastructure. Core logic tested in Turn module (94.5%).
  def handle_call({:start_chat_turn, user_prompt, model}, _from, %State{} = state) do
    context = %{track_id: state.track_id}

    {:ok, new_turn, new_stream, new_entries, actions} =
      Turn.start_turn(state.stream, state.chat_entries, user_prompt, model, context)

    new_state = %{
      state
      | turn: new_turn,
        stream: new_stream,
        chat_entries: new_entries
    }

    # Execute actions and get final state
    final_state = execute_actions(new_state, actions)

    {:reply, {:ok, final_state.turn.turn_id}, final_state}
  end

  # coveralls-ignore-stop

  # ---------------------------------------------------------------------------
  # Tool Approval Handlers
  # ---------------------------------------------------------------------------

  # coveralls-ignore-start
  # Reason: Tool approval success paths require tools in internal state from LLM streaming.
  # Core approval logic tested in Turn module (94.5%). Error paths tested below.

  def handle_call({:approve_tool, entry_id}, _from, %State{} = state) do
    # Entry IDs from LiveView events are strings, but stored as integers
    entry_id = normalize_entry_id(entry_id)

    case Turn.approve_tool(state.turn, state.chat_entries, entry_id) do
      {:ok, new_turn, new_entries, actions} ->
        new_state = %{state | turn: new_turn, chat_entries: new_entries}
        final_state = execute_actions(new_state, actions)
        {:reply, :ok, final_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:deny_tool, entry_id, reason}, _from, %State{} = state) do
    entry_id = normalize_entry_id(entry_id)

    case Turn.deny_tool(state.turn, state.chat_entries, entry_id, reason) do
      {:ok, new_turn, new_entries, actions} ->
        new_state = %{state | turn: new_turn, chat_entries: new_entries}
        final_state = execute_actions(new_state, actions)
        {:reply, :ok, final_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # coveralls-ignore-stop

  # ---------------------------------------------------------------------------
  # Autonomous Mode
  # ---------------------------------------------------------------------------

  @impl true
  def handle_cast({:set_autonomous, autonomous}, %State{} = state) do
    Logger.info("Autonomous mode #{if autonomous, do: "enabled", else: "disabled"}")
    {:noreply, %{state | autonomous: autonomous}}
  end

  # ---------------------------------------------------------------------------
  # Console Events
  # ---------------------------------------------------------------------------

  # coveralls-ignore-start
  # Reason: Console event integration requiring real container events.
  # Core console logic tested in Console module (88.2%) and Action module (91.8%).
  # These handlers route events to core modules and coordinate state.

  @impl true
  def handle_info(
        %ConsoleUpdated{track_id: track_id, status: :ready} = event,
        %State{track_id: track_id} = state
      ) do
    # Console became ready - may have completed a tool execution
    {new_console, console_actions} =
      Console.apply_event(state.console, track_id, event)

    state = %{state | console: new_console}
    state = execute_actions(state, console_actions)

    # Check if a tool completed
    output = Console.get_latest_command_output(new_console.history)

    state =
      case Turn.complete_tool_execution(state.turn, state.chat_entries, output, nil) do
        :no_executing_tool ->
          state

        {new_turn, new_entries, actions} ->
          new_state = %{state | turn: new_turn, chat_entries: new_entries}
          execute_actions(new_state, actions)
      end

    {:noreply, state}
  end

  def handle_info(%ConsoleUpdated{track_id: track_id} = event, %State{track_id: track_id} = state) do
    {new_console, actions} = Console.apply_event(state.console, track_id, event)
    new_state = %{state | console: new_console}
    final_state = execute_actions(new_state, actions)
    {:noreply, final_state}
  end

  # Ignore ConsoleUpdated for other tracks
  def handle_info(%ConsoleUpdated{}, state), do: {:noreply, state}

  # coveralls-ignore-stop

  # ---------------------------------------------------------------------------
  # Bash Command Result Events
  # ---------------------------------------------------------------------------

  # coveralls-ignore-start
  # Reason: Bash command integration requiring real container process.
  # Core bash tool logic tested in Turn module.

  def handle_info(
        %CommandResult{track_id: track_id, type: :bash, status: :finished} = event,
        %State{track_id: track_id} = state
      ) do
    Logger.debug("Bash command finished",
      command_id: event.command_id,
      output_bytes: String.length(event.output)
    )

    case Turn.complete_bash_tool(state.turn, state.chat_entries, event.command_id, event.output) do
      :no_executing_tool ->
        {:noreply, state}

      {new_turn, new_entries, actions} ->
        new_state = %{state | turn: new_turn, chat_entries: new_entries}
        final_state = execute_actions(new_state, actions)
        {:noreply, final_state}
    end
  end

  def handle_info(
        %CommandResult{track_id: track_id, type: :bash, status: :error} = event,
        %State{track_id: track_id} = state
      ) do
    Logger.warning("Bash command error",
      command_id: event.command_id,
      error: inspect(event.error)
    )

    error_message = inspect(event.error)

    case Turn.error_bash_tool(state.turn, state.chat_entries, event.command_id, error_message) do
      :no_executing_tool ->
        {:noreply, state}

      {new_turn, new_entries, actions} ->
        new_state = %{state | turn: new_turn, chat_entries: new_entries}
        final_state = execute_actions(new_state, actions)
        {:noreply, final_state}
    end
  end

  # Ignore running status updates (could update UI progress later)
  def handle_info(
        %CommandResult{track_id: track_id, type: :bash, status: :running},
        %State{track_id: track_id} = state
      ) do
    {:noreply, state}
  end

  # Ignore CommandResult for other tracks or Metasploit commands
  def handle_info(%CommandResult{}, state), do: {:noreply, state}

  # coveralls-ignore-stop

  # ---------------------------------------------------------------------------
  # Reconciliation Trigger
  # ---------------------------------------------------------------------------

  def handle_info(:reconcile, %State{} = state) do
    Logger.info("Resuming pending tool executions after restart")
    final_state = do_reconcile(state)
    {:noreply, final_state}
  end

  # ---------------------------------------------------------------------------
  # LLM Events
  # ---------------------------------------------------------------------------

  # coveralls-ignore-start
  # Reason: LLM streaming integration requiring complex mock infrastructure.
  # Core streaming logic tested in Stream module (100%) and Turn module (94.5%).
  # These handlers delegate to core modules and coordinate state updates.

  # Stream started - update turn status
  def handle_info({:llm, ref, %LLMEvents.StreamStarted{model: model}}, state)
      when ref == state.turn.llm_ref do
    Logger.debug("LLM stream started", model: model)

    new_turn = %{state.turn | status: :streaming}
    new_state = %{state | turn: new_turn}
    final_state = execute_actions(new_state, [:broadcast_chat_state])
    {:noreply, final_state}
  end

  # Content block start
  def handle_info({:llm, ref, %LLMEvents.ContentBlockStart{index: index, type: type}}, state)
      when ref == state.turn.llm_ref do
    Logger.debug("LLM content block started", index: index, type: type)

    if type in [:thinking, :text] do
      {new_stream, new_entries, actions} =
        Stream.block_start(state.stream, state.chat_entries, index, type)

      new_state = %{state | stream: new_stream, chat_entries: new_entries}
      final_state = execute_actions(new_state, actions)
      {:noreply, final_state}
    else
      {:noreply, state}
    end
  end

  # Content delta
  def handle_info({:llm, ref, %LLMEvents.ContentDelta{index: index, delta: delta}}, state)
      when ref == state.turn.llm_ref do
    {new_stream, new_entries, actions} =
      Stream.apply_delta(state.stream, state.chat_entries, index, delta)

    new_state = %{state | stream: new_stream, chat_entries: new_entries}
    final_state = execute_actions(new_state, actions)
    {:noreply, final_state}
  end

  # Content block stop
  def handle_info({:llm, ref, %LLMEvents.ContentBlockStop{index: index}}, state)
      when ref == state.turn.llm_ref do
    Logger.debug("LLM content block stopped", index: index)

    {new_stream, new_entries, actions} =
      Stream.block_stop(
        state.stream,
        state.chat_entries,
        index,
        state.track_id,
        state.turn.turn_id
      )

    new_state = %{state | stream: new_stream, chat_entries: new_entries}
    final_state = execute_actions(new_state, actions)
    {:noreply, final_state}
  end

  # Tool call
  def handle_info({:llm, ref, %LLMEvents.ToolCall{} = tc}, state)
      when ref == state.turn.llm_ref do
    context = %{
      track_id: state.track_id,
      autonomous: state.autonomous,
      current_prompt: state.console.current_prompt
    }

    {new_turn, new_stream, new_entries, actions} =
      Turn.handle_tool_call(state.turn, state.stream, state.chat_entries, tc, context)

    new_state = %{
      state
      | turn: new_turn,
        stream: new_stream,
        chat_entries: new_entries
    }

    final_state = execute_actions(new_state, actions)
    {:noreply, final_state}
  end

  # Stream complete with tool_use
  def handle_info(
        {:llm, ref, %LLMEvents.StreamComplete{stop_reason: :tool_use} = complete},
        state
      )
      when ref == state.turn.llm_ref do
    Logger.info("LLM stream complete with tool calls",
      input_tokens: complete.input_tokens,
      output_tokens: complete.output_tokens
    )

    # Finalize streaming entries first
    {new_stream, new_entries, stream_actions} =
      Stream.finalize(state.stream, state.chat_entries, state.track_id, state.turn.turn_id)

    # Handle stream complete in Turn
    {new_turn, turn_actions} = Turn.handle_stream_complete(state.turn, complete)

    new_state = %{
      state
      | stream: new_stream,
        turn: new_turn,
        chat_entries: new_entries
    }

    final_state = execute_actions(new_state, stream_actions ++ turn_actions)
    {:noreply, final_state}
  end

  # Stream complete normally
  def handle_info({:llm, ref, %LLMEvents.StreamComplete{} = complete}, state)
      when ref == state.turn.llm_ref do
    Logger.info("LLM stream complete",
      stop_reason: complete.stop_reason,
      input_tokens: complete.input_tokens,
      output_tokens: complete.output_tokens
    )

    # Finalize streaming entries
    {new_stream, new_entries, stream_actions} =
      Stream.finalize(state.stream, state.chat_entries, state.track_id, state.turn.turn_id)

    # Handle stream complete in Turn
    {new_turn, turn_actions} = Turn.handle_stream_complete(state.turn, complete)

    new_state = %{
      state
      | stream: new_stream,
        turn: new_turn,
        chat_entries: new_entries
    }

    final_state = execute_actions(new_state, stream_actions ++ turn_actions)
    {:noreply, final_state}
  end

  # Stream error
  def handle_info(
        {:llm, ref, %LLMEvents.StreamError{reason: reason, recoverable: recoverable}},
        state
      )
      when ref == state.turn.llm_ref do
    Logger.error("LLM stream error", reason: inspect(reason), recoverable: recoverable)

    {new_turn, actions} = Turn.handle_stream_error(state.turn)
    new_stream = State.Stream.reset(state.stream)

    new_state = %{state | turn: new_turn, stream: new_stream}
    final_state = execute_actions(new_state, actions)
    {:noreply, final_state}
  end

  # Ignore LLM events for old refs (stale)
  def handle_info({:llm, _ref, _event}, state), do: {:noreply, state}

  # coveralls-ignore-stop

  # ---------------------------------------------------------------------------
  # ExecutionManager Status Messages
  # ---------------------------------------------------------------------------
  # These handlers receive status updates from ExecutionManager Tasks.
  # All tools (memory, msf_data, container) use the same message format.

  @doc false
  def handle_info({:tool_status, entry_id, :executing}, %State{} = state) do
    Logger.debug("Tool executing", entry_id: entry_id)

    case Map.get(state.turn.tool_invocations, entry_id) do
      nil ->
        {:noreply, state}

      tool_state ->
        new_tool_state = %{tool_state | status: :executing, started_at: DateTime.utc_now()}

        new_turn = %{
          state.turn
          | status: :executing_tools,
            tool_invocations: Map.put(state.turn.tool_invocations, entry_id, new_tool_state)
        }

        new_entries = update_entry_status(state.chat_entries, entry_id, :executing)

        new_state = %{state | turn: new_turn, chat_entries: new_entries}

        # Persist status update and broadcast
        actions = [
          {:update_tool_status, entry_id, "executing", []},
          :broadcast_chat_state
        ]

        final_state = execute_actions(new_state, actions)
        {:noreply, final_state}
    end
  end

  def handle_info({:tool_status, entry_id, :success, result}, %State{} = state) do
    case Map.get(state.turn.tool_invocations, entry_id) do
      nil ->
        {:noreply, state}

      tool_state ->
        duration = calculate_duration(tool_state.started_at)
        result_content = encode_result(result)

        Logger.info("Tool success: #{tool_state.tool_name} (#{duration}ms)")

        new_tool_state = %{tool_state | status: :success}

        new_turn = %{
          state.turn
          | tool_invocations: Map.put(state.turn.tool_invocations, entry_id, new_tool_state)
        }

        new_entries =
          update_entry_status(state.chat_entries, entry_id, :success,
            result_content: result_content
          )

        new_state = %{state | turn: new_turn, chat_entries: new_entries}

        actions = [
          {:update_tool_status, entry_id, "success",
           [result_content: result_content, duration_ms: duration]},
          :reconcile,
          :broadcast_chat_state
        ]

        final_state = execute_actions(new_state, actions)
        {:noreply, final_state}
    end
  end

  def handle_info({:tool_status, entry_id, :error, reason}, %State{} = state) do
    case Map.get(state.turn.tool_invocations, entry_id) do
      nil ->
        {:noreply, state}

      tool_state ->
        duration = calculate_duration(tool_state.started_at)
        error_message = format_error_reason(reason)

        Logger.warning("Tool error: #{tool_state.tool_name} - #{error_message}")

        new_tool_state = %{tool_state | status: :error}

        new_turn = %{
          state.turn
          | tool_invocations: Map.put(state.turn.tool_invocations, entry_id, new_tool_state)
        }

        new_entries = update_entry_status(state.chat_entries, entry_id, :error)

        new_state = %{state | turn: new_turn, chat_entries: new_entries}

        actions = [
          {:update_tool_status, entry_id, "error",
           [error_message: error_message, duration_ms: duration]},
          :reconcile,
          :broadcast_chat_state
        ]

        final_state = execute_actions(new_state, actions)
        {:noreply, final_state}
    end
  end

  def handle_info({:tool_async, entry_id, command_id}, %State{} = state) do
    Logger.debug("Tool async started", entry_id: entry_id, command_id: command_id)

    # Record command_id for matching completion events
    new_turn = Turn.record_command_id(state.turn, entry_id, command_id)
    {:noreply, %{state | turn: new_turn}}
  end

  # Ignore other workspace events (ContainerUpdated, etc.)
  def handle_info(_event, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Terminate
  # ---------------------------------------------------------------------------

  # coveralls-ignore-start
  # Reason: GenServer lifecycle callback with container registry integration.
  @impl true
  def terminate(reason, state) do
    Logger.debug("TrackServer terminating", reason: inspect(reason))
    unregister_console(state.container_id, state.track_id)
    :ok
  end

  # coveralls-ignore-stop

  # ===========================================================================
  # Private Functions - Action Execution
  # ===========================================================================

  defp execute_actions(state, actions) do
    Enum.reduce(actions, state, fn action, acc_state ->
      execute_action(acc_state, action)
    end)
  end

  defp execute_action(state, :reconcile) do
    do_reconcile(state)
  end

  # coveralls-ignore-start
  # Reason: Container command integration requiring real container process.
  # Command execution tested via integration tests with mock container.
  defp execute_action(state, {:send_msf_command, command}) do
    executing_tool = find_executing_msf_tool(state.turn)

    case Containers.send_metasploit_command(state.container_id, state.track_id, command) do
      {:ok, command_id} ->
        Logger.info("MSF tool execution started: #{command}")
        record_msf_command_id(state, executing_tool, command_id)

      {:error, :console_busy} ->
        Logger.debug("Console busy, will retry tool execution")
        state

      {:error, reason} ->
        Logger.error("MSF tool execution failed immediately", reason: inspect(reason))
        handle_msf_tool_error(state, executing_tool, reason)
    end
  end

  defp execute_action(state, {:send_bash_command, entry_id, command}) do
    case Containers.send_bash_command(state.container_id, state.track_id, command) do
      {:ok, command_id} ->
        Logger.info("Bash tool execution started: #{command}")
        new_turn = Turn.record_command_id(state.turn, entry_id, command_id)
        %{state | turn: new_turn}

      {:error, :container_not_running} ->
        Logger.error("Container not running for bash command")

        {new_turn, new_entries, actions} =
          Turn.mark_tool_error(state.turn, state.chat_entries, entry_id, :container_not_running)

        new_state = %{state | turn: new_turn, chat_entries: new_entries}
        execute_actions(new_state, actions)
    end
  end

  # coveralls-ignore-stop

  defp execute_action(state, action) do
    Action.execute(action, state)
  end

  # coveralls-ignore-start
  # Reason: Container command integration helpers - only used from execute_action

  defp find_executing_msf_tool(turn) do
    Enum.find(turn.tool_invocations, fn {_id, ts} ->
      ts.status == :executing and ts.command_id == nil and
        ts.tool_name == "execute_msfconsole_command"
    end)
  end

  defp record_msf_command_id(state, {entry_id, _}, command_id) do
    new_turn = Turn.record_command_id(state.turn, entry_id, command_id)
    %{state | turn: new_turn}
  end

  defp record_msf_command_id(state, nil, _command_id), do: state

  defp handle_msf_tool_error(state, {entry_id, _}, reason) do
    {new_turn, new_entries, actions} =
      Turn.mark_tool_error(state.turn, state.chat_entries, entry_id, reason)

    new_state = %{state | turn: new_turn, chat_entries: new_entries}
    execute_actions(new_state, actions)
  end

  defp handle_msf_tool_error(state, nil, _reason), do: state

  # ---------------------------------------------------------------------------
  # ExecutionManager Helper Functions
  # ---------------------------------------------------------------------------

  defp update_entry_status(entries, entry_id, status, opts \\ []) do
    Enum.map(entries, fn entry ->
      if matches_tool_entry?(entry, entry_id) do
        apply_status_update(entry, status, opts)
      else
        entry
      end
    end)
  end

  defp apply_status_update(entry, status, opts) do
    entry = %{entry | tool_status: status}

    case Keyword.get(opts, :result_content) do
      nil -> entry
      content -> %{entry | result_content: content}
    end
  end

  defp matches_tool_entry?(entry, entry_id) do
    (entry.id == entry_id or entry.position == entry_id) and ChatEntry.tool_invocation?(entry)
  end

  defp calculate_duration(nil), do: 0

  defp calculate_duration(started_at) do
    DateTime.diff(DateTime.utc_now(), started_at, :millisecond)
  end

  defp encode_result(result) when is_binary(result), do: result

  defp encode_result(result) do
    case Jason.encode(result, pretty: true) do
      {:ok, json} -> json
      {:error, _} -> inspect(result)
    end
  end

  defp format_error_reason(reason) when is_binary(reason), do: reason
  defp format_error_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_error_reason({:unknown_tool, name}), do: "Unknown tool: #{name}"
  defp format_error_reason(reason), do: inspect(reason)

  # Reason: Reconciliation requires pending tools in state from LLM streaming.
  # Core reconciliation logic tested in Turn module (94.5%).

  defp do_reconcile(state) do
    context = %{
      track_id: state.track_id,
      model: state.turn.model,
      autonomous: state.autonomous,
      workspace_slug: state.workspace_slug
    }

    case Turn.reconcile(state.turn, state.console, state.chat_entries, context) do
      :no_action ->
        state

      {new_turn, new_entries, actions} ->
        new_state = %{state | turn: new_turn, chat_entries: new_entries}
        execute_actions(new_state, actions)
    end
  end

  # coveralls-ignore-stop

  # ===========================================================================
  # Private Functions - Initialization Helpers
  # ===========================================================================

  # coveralls-ignore-start
  # Reason: Tool reconstruction requires persisted tool invocations with pending/approved status.
  # Tool persistence tested in ChatContext (87.5%) and Turn module (94.5%).

  defp rebuild_tool_invocations(persisted_entries) do
    persisted_entries
    |> Enum.filter(fn entry ->
      entry.entry_type == "tool_invocation" and
        entry.tool_invocation != nil and
        entry.tool_invocation.status in ["pending", "approved"]
    end)
    |> Enum.reduce(%{}, fn entry, acc ->
      ti = entry.tool_invocation

      # Calculate effective status: if tool doesn't require approval and DB has
      # "pending", treat it as :approved so reconciliation will execute it
      effective_status = calculate_effective_status(ti.tool_name, ti.status)

      tool_state = %{
        tool_call_id: ti.tool_call_id,
        tool_name: ti.tool_name,
        arguments: ti.arguments || %{},
        status: effective_status,
        command_id: nil,
        started_at: nil
      }

      # Use position as key for consistency with Turn.handle_tool_call
      # During streaming, tool_invocations is keyed by position
      Map.put(acc, entry.position, tool_state)
    end)
  end

  # Calculates effective in-memory status based on tool's approval requirements
  defp calculate_effective_status(tool_name, "pending"), do: effective_pending_status(tool_name)
  defp calculate_effective_status(_tool_name, status), do: ChatEntry.tool_status_to_atom(status)

  # For pending tools, check if the tool requires approval
  defp effective_pending_status(tool_name) do
    case Msfailab.Tools.get_tool(tool_name) do
      {:ok, %{approval_required: true}} -> :pending
      {:ok, %{approval_required: false}} -> :approved
      {:error, :not_found} -> :pending
    end
  end

  # Updates chat_entries with effective statuses from tool_invocations map
  # This ensures the UI shows correct statuses even before reconciliation runs
  @spec apply_effective_statuses([ChatEntry.t()], map()) :: [ChatEntry.t()]
  defp apply_effective_statuses(chat_entries, tool_invocations) do
    # Build a lookup from position to effective status
    status_by_position =
      Map.new(tool_invocations, fn {position, tool} -> {position, tool.status} end)

    Enum.map(chat_entries, &apply_entry_status(&1, status_by_position))
  end

  defp apply_entry_status(%{entry_type: :tool_invocation, position: position} = entry, status_map) do
    case Map.get(status_map, position) do
      nil -> entry
      effective_status -> %{entry | tool_status: effective_status}
    end
  end

  defp apply_entry_status(entry, _status_map), do: entry

  # Reason: LLM Registry logging during init.
  defp log_llm_models do
    if Process.whereis(Msfailab.LLM.Registry) do
      models = LLM.list_models()
      default = LLM.get_default_model()

      Logger.info("LLM models available for track",
        model_count: length(models),
        model_names: Enum.map(models, & &1.name),
        default_model: default
      )
    end
  end

  # coveralls-ignore-stop

  defp normalize_entry_id(entry_id) when is_binary(entry_id), do: String.to_integer(entry_id)
  defp normalize_entry_id(entry_id), do: entry_id

  # ===========================================================================
  # Private Functions - Container Integration
  # ===========================================================================

  # coveralls-ignore-start
  # Reason: Container registry integration requiring real container process.
  # These functions are thin wrappers around Container GenServer calls.

  defp register_console(container_id, track_id) do
    case Process.whereis(Msfailab.Containers.Registry) do
      nil ->
        :ok

      _registry_pid ->
        try do
          Containers.Container.register_console(container_id, track_id)
        catch
          :exit, {:noproc, _} ->
            Logger.error("Container GenServer not found during console registration",
              container_id: container_id
            )

            :ok
        end
    end
  end

  defp unregister_console(container_id, track_id) do
    case Process.whereis(Msfailab.Containers.Registry) do
      nil ->
        :ok

      _registry_pid ->
        try do
          Containers.Container.unregister_console(container_id, track_id)
        catch
          :exit, _ -> :ok
        end
    end
  end

  # coveralls-ignore-stop
end
