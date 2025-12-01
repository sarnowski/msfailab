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

defmodule Msfailab.Tracks.TrackServer.Turn do
  @moduledoc """
  Pure functions for agentic turn lifecycle management.

  This module implements the reconciliation engine and tool lifecycle state machine.
  It decides when to execute tools, continue LLM requests, or complete turns.

  ## Turn Status State Machine

  ```
                      ┌────────────────────────────────────────────┐
                      │                                            │
                      ▼                                            │
      idle ──► pending ──► streaming ──► pending_approval ──► executing_tools
                                │               │                  │
                                │               │ (all approved    │
                                │               │  + executed)     │
                                │               └──────────────────┤
                                │                                  │
                                ▼                                  │
                           (no tools)                              │
                                │                                  │
                                ▼                                  ▼
                            finished ◄─────────────────────────────┘
  ```

  ## Tool Invocation Lifecycle

  ```
            ┌──────────────────────────────────┐
            │                                  │
            ▼                                  │
        pending ───► approved ───► executing ──┴──► success
            │                          │
            │                          ├───► error
            │                          │
            │                          └───► timeout
            │
            └───► denied
  ```

  ## Reconciliation Pattern

  The reconciliation engine evaluates the current state and decides what action
  to take next. It's called after every state-changing event.

  ```
  Event arrives → Update immediate state → Reconcile → Execute eligible actions
  ```
  """

  require Logger

  alias Msfailab.LLM
  alias Msfailab.LLM.ChatRequest
  alias Msfailab.LLM.Events, as: LLMEvents
  alias Msfailab.Tools
  alias Msfailab.Tracks.ChatContext
  alias Msfailab.Tracks.ChatEntry
  alias Msfailab.Tracks.TrackServer.State.Console, as: ConsoleState
  alias Msfailab.Tracks.TrackServer.State.Stream, as: StreamState
  alias Msfailab.Tracks.TrackServer.State.Turn, as: TurnState

  @type action ::
          {:create_turn, pos_integer(), String.t()}
          | {:persist_message, pos_integer(), String.t() | nil, pos_integer(), map()}
          | {:persist_tool_invocation, pos_integer(), String.t(), pos_integer(), map()}
          | {:update_tool_status, integer(), String.t(), keyword()}
          | {:update_turn_status, String.t(), String.t()}
          | {:start_llm, ChatRequest.t()}
          | {:send_msf_command, String.t()}
          | {:send_bash_command, integer(), String.t()}
          | :broadcast_chat_state
          | :reconcile

  # ============================================================================
  # Reconciliation Engine
  # ============================================================================

  @doc """
  Evaluates current state and returns the next action to take.

  This is the heart of the event-driven reconciliation pattern. It looks at
  the current state and decides what action to take next.

  ## Parameters

  - `turn` - Current turn state
  - `console` - Current console state (needed for tool execution decisions)
  - `entries` - Current chat entries (needed for position lookup)
  - `context` - Additional context: track_id, model, autonomous

  ## Returns

  `{new_turn, new_entries, actions}` or `:no_action` if nothing to do.
  """
  @spec reconcile(TurnState.t(), ConsoleState.t(), [ChatEntry.t()], map()) ::
          {TurnState.t(), [ChatEntry.t()], [action()]} | :no_action
  def reconcile(%TurnState{} = turn, %ConsoleState{} = console, entries, context) do
    cond do
      turn_inactive?(turn) ->
        :no_action

      has_pending_approvals?(turn) ->
        maybe_transition_to_pending_approval(turn, entries)

      should_transition_to_executing?(turn) ->
        transition_to_executing(turn, console, entries, context)

      should_execute_next_sequential_tool?(turn, console) ->
        execute_next_sequential_tool(turn, console, entries, context)

      should_execute_parallel_tools?(turn) ->
        execute_all_parallel_tools(turn, entries)

      should_start_next_llm_request?(turn) ->
        start_llm_request(turn, entries, context)

      should_complete_turn?(turn) ->
        complete_turn(turn, entries)

      true ->
        :no_action
    end
  end

  defp maybe_transition_to_pending_approval(%TurnState{} = turn, entries) do
    if turn.status != :pending_approval do
      {%TurnState{turn | status: :pending_approval}, entries, [:broadcast_chat_state]}
    else
      :no_action
    end
  end

  defp transition_to_executing(%TurnState{} = turn, console, entries, context) do
    new_turn = %TurnState{turn | status: :executing_tools}

    case reconcile(new_turn, console, entries, context) do
      :no_action -> {new_turn, entries, [:broadcast_chat_state]}
      result -> result
    end
  end

  # ---------------------------------------------------------------------------
  # Predicates
  # ---------------------------------------------------------------------------

  defp turn_inactive?(turn), do: turn.status in [:idle, :finished, :error]

  defp should_transition_to_executing?(turn) do
    turn.status == :streaming and has_approved_tools?(turn)
  end

  defp should_start_next_llm_request?(turn) do
    all_tools_terminal?(turn) and map_size(turn.tool_invocations) > 0
  end

  defp should_complete_turn?(turn) do
    turn.status == :streaming and map_size(turn.tool_invocations) == 0
  end

  defp has_pending_approvals?(turn) do
    Enum.any?(turn.tool_invocations, fn {_id, ts} -> ts.status == :pending end)
  end

  defp has_approved_tools?(turn) do
    Enum.any?(turn.tool_invocations, fn {_id, ts} -> ts.status == :approved end)
  end

  defp should_execute_next_sequential_tool?(turn, console) do
    turn.status in [:pending_approval, :executing_tools] and
      console.status == :ready and
      no_sequential_tool_executing?(turn) and
      has_approved_sequential_tool?(turn)
  end

  defp no_sequential_tool_executing?(turn) do
    not Enum.any?(turn.tool_invocations, fn {_id, ts} ->
      ts.status == :executing and sequential_tool?(ts.tool_name)
    end)
  end

  defp has_approved_sequential_tool?(turn) do
    Enum.any?(turn.tool_invocations, fn {_id, ts} ->
      ts.status == :approved and sequential_tool?(ts.tool_name)
    end)
  end

  defp should_execute_parallel_tools?(turn) do
    turn.status in [:pending_approval, :executing_tools] and
      has_approved_parallel_tool?(turn)
  end

  defp has_approved_parallel_tool?(turn) do
    Enum.any?(turn.tool_invocations, fn {_id, ts} ->
      ts.status == :approved and not sequential_tool?(ts.tool_name)
    end)
  end

  defp sequential_tool?(tool_name) do
    case Tools.get_tool(tool_name) do
      {:ok, tool} -> tool.sequential
      {:error, _} -> true
    end
  end

  defp all_tools_terminal?(turn) do
    map_size(turn.tool_invocations) > 0 and
      Enum.all?(turn.tool_invocations, fn {_id, ts} ->
        ts.status in [:success, :error, :timeout, :denied]
      end)
  end

  # ============================================================================
  # Turn Lifecycle
  # ============================================================================

  @doc """
  Starts a new chat turn.

  Creates the turn in the database, adds the user prompt to entries,
  and starts the LLM request.

  ## Parameters

  - `stream` - Current stream state (for next_position)
  - `entries` - Current chat entries
  - `user_prompt` - The user's message
  - `model` - The model to use
  - `context` - track_id

  ## Returns

  `{:ok, new_turn, new_stream, new_entries, actions}` or `{:error, reason}`
  """
  @spec start_turn(StreamState.t(), [ChatEntry.t()], String.t(), String.t(), map()) ::
          {:ok, TurnState.t(), StreamState.t(), [ChatEntry.t()], [action()]}
  def start_turn(%StreamState{} = stream, entries, user_prompt, model, context) do
    track_id = context.track_id
    position = stream.next_position

    # Create user prompt entry
    user_entry = ChatEntry.user_prompt(Ecto.UUID.generate(), position, user_prompt)
    new_entries = entries ++ [user_entry]

    # Build LLM request
    request = build_llm_request(track_id, model, nil)

    # Build actions
    actions = [
      {:create_turn, track_id, model},
      {:persist_message, track_id, nil, position,
       %{role: "user", message_type: "prompt", content: user_prompt}},
      {:start_llm, request},
      :broadcast_chat_state
    ]

    # Create new turn state (turn_id will be set by action execution)
    new_turn = %TurnState{
      status: :pending,
      model: model,
      tool_invocations: %{},
      command_to_tool: %{}
    }

    # Update stream state
    new_stream = %StreamState{stream | next_position: position + 1}

    {:ok, new_turn, new_stream, new_entries, actions}
  end

  @doc """
  Handles a tool call from the LLM.

  Creates a tool invocation entry and adds it to the turn state.

  ## Parameters

  - `turn` - Current turn state
  - `stream` - Current stream state
  - `entries` - Current chat entries
  - `tool_call` - The LLM tool call event
  - `context` - track_id, autonomous, current_prompt

  ## Returns

  `{new_turn, new_stream, new_entries, actions}`
  """
  @spec handle_tool_call(
          TurnState.t(),
          StreamState.t(),
          [ChatEntry.t()],
          LLMEvents.ToolCall.t(),
          map()
        ) ::
          {TurnState.t(), StreamState.t(), [ChatEntry.t()], [action()]}
  def handle_tool_call(%TurnState{} = turn, %StreamState{} = stream, entries, tc, context) do
    position = stream.next_position
    track_id = context.track_id
    autonomous = context.autonomous
    console_prompt = context.current_prompt

    # Determine initial status based on autonomous mode
    initial_status = if autonomous, do: :approved, else: :pending
    initial_status_str = if autonomous, do: "approved", else: "pending"

    Logger.info("LLM tool call received: #{tc.name}")

    if autonomous do
      Logger.info("Auto-approving tool in autonomous mode: #{tc.name}")
    end

    # Create UI entry (with temporary ID - will be replaced after persist)
    chat_entry =
      ChatEntry.tool_invocation(
        position,
        position,
        tc.id,
        tc.name,
        tc.arguments,
        initial_status,
        console_prompt: console_prompt
      )

    # Tool state for tracking
    tool_state = %{
      tool_call_id: tc.id,
      tool_name: tc.name,
      arguments: tc.arguments,
      status: initial_status,
      command_id: nil,
      started_at: nil
    }

    # Actions
    actions = [
      {:persist_tool_invocation, track_id, turn.turn_id, position,
       %{
         tool_call_id: tc.id,
         tool_name: tc.name,
         arguments: tc.arguments,
         console_prompt: console_prompt,
         status: initial_status_str
       }},
      :broadcast_chat_state
    ]

    # Update states
    new_turn = %TurnState{
      turn
      | tool_invocations: Map.put(turn.tool_invocations, position, tool_state)
    }

    new_stream = %StreamState{stream | next_position: position + 1}
    new_entries = entries ++ [chat_entry]

    {new_turn, new_stream, new_entries, actions}
  end

  @doc """
  Handles LLM stream completion.

  Updates turn state and returns actions based on stop reason.

  ## Parameters

  - `turn` - Current turn state
  - `complete` - The StreamComplete event

  ## Returns

  `{new_turn, actions}`
  """
  @spec handle_stream_complete(TurnState.t(), LLMEvents.StreamComplete.t()) ::
          {TurnState.t(), [action()]}
  def handle_stream_complete(
        %TurnState{} = turn,
        %LLMEvents.StreamComplete{stop_reason: :tool_use} = complete
      ) do
    new_turn = %TurnState{
      turn
      | llm_ref: nil,
        last_cache_context: complete.cache_context
    }

    # Reconciliation will handle next steps
    {new_turn, [:reconcile, :broadcast_chat_state]}
  end

  def handle_stream_complete(%TurnState{} = turn, complete) do
    # Normal completion - turn finished
    actions =
      if turn.turn_id do
        [{:update_turn_status, turn.turn_id, "finished"}, :broadcast_chat_state]
      else
        [:broadcast_chat_state]
      end

    new_turn = %TurnState{
      turn
      | status: :finished,
        turn_id: nil,
        llm_ref: nil,
        last_cache_context: complete.cache_context,
        tool_invocations: %{},
        command_to_tool: %{}
    }

    {new_turn, actions}
  end

  @doc """
  Handles LLM stream error.

  ## Returns

  `{new_turn, actions}`
  """
  @spec handle_stream_error(TurnState.t()) :: {TurnState.t(), [action()]}
  def handle_stream_error(%TurnState{} = turn) do
    actions =
      if turn.turn_id do
        [{:update_turn_status, turn.turn_id, "error"}, :broadcast_chat_state]
      else
        [:broadcast_chat_state]
      end

    new_turn = %TurnState{
      turn
      | status: :error,
        llm_ref: nil,
        tool_invocations: %{},
        command_to_tool: %{}
    }

    {new_turn, actions}
  end

  # ============================================================================
  # Tool Approval
  # ============================================================================

  @doc """
  Approves a pending tool invocation.

  ## Parameters

  - `turn` - Current turn state
  - `entries` - Current chat entries
  - `entry_id` - The entry ID to approve

  ## Returns

  `{:ok, new_turn, new_entries, actions}` or `{:error, reason}`
  """
  @spec approve_tool(TurnState.t(), [ChatEntry.t()], integer()) ::
          {:ok, TurnState.t(), [ChatEntry.t()], [action()]} | {:error, term()}
  def approve_tool(%TurnState{} = turn, entries, entry_id) do
    case Map.get(turn.tool_invocations, entry_id) do
      nil ->
        {:error, :not_found}

      %{status: :pending} = tool_state ->
        Logger.info("Tool approved: #{tool_state.tool_name}")

        new_tool_state = %{tool_state | status: :approved}

        new_turn = %TurnState{
          turn
          | tool_invocations: Map.put(turn.tool_invocations, entry_id, new_tool_state)
        }

        new_entries = update_chat_entry_status(entries, entry_id, :approved)

        actions = [
          {:update_tool_status, entry_id, "approved", []},
          :reconcile,
          :broadcast_chat_state
        ]

        {:ok, new_turn, new_entries, actions}

      _ ->
        {:error, :invalid_status}
    end
  end

  @doc """
  Denies a pending tool invocation.

  ## Parameters

  - `turn` - Current turn state
  - `entries` - Current chat entries
  - `entry_id` - The entry ID to deny
  - `reason` - The denial reason

  ## Returns

  `{:ok, new_turn, new_entries, actions}` or `{:error, reason}`
  """
  @spec deny_tool(TurnState.t(), [ChatEntry.t()], integer(), String.t()) ::
          {:ok, TurnState.t(), [ChatEntry.t()], [action()]} | {:error, term()}
  def deny_tool(%TurnState{} = turn, entries, entry_id, reason) do
    case Map.get(turn.tool_invocations, entry_id) do
      nil ->
        {:error, :not_found}

      %{status: :pending} = tool_state ->
        Logger.info("Tool denied: #{tool_state.tool_name} (#{reason})")

        new_tool_state = %{tool_state | status: :denied}

        new_turn = %TurnState{
          turn
          | tool_invocations: Map.put(turn.tool_invocations, entry_id, new_tool_state)
        }

        new_entries = update_chat_entry_status(entries, entry_id, :denied)

        actions = [
          {:update_tool_status, entry_id, "denied", [denied_reason: reason]},
          :reconcile,
          :broadcast_chat_state
        ]

        {:ok, new_turn, new_entries, actions}

      _ ->
        {:error, :invalid_status}
    end
  end

  # ============================================================================
  # Tool Execution
  # ============================================================================

  @doc """
  Marks a tool as executing and returns a command action.

  ## Parameters

  - `turn` - Current turn state
  - `entries` - Current chat entries
  - `entry_id` - The entry ID of the tool to execute

  ## Returns

  `{new_turn, new_entries, actions}`
  """
  @spec start_tool_execution(TurnState.t(), [ChatEntry.t()], integer()) ::
          {TurnState.t(), [ChatEntry.t()], [action()]}
  def start_tool_execution(%TurnState{} = turn, entries, entry_id) do
    case Map.get(turn.tool_invocations, entry_id) do
      %{tool_name: "msf_command", arguments: args} = tool_state ->
        command = Map.get(args, "command", "")

        new_tool_state = %{
          tool_state
          | status: :executing,
            started_at: DateTime.utc_now()
        }

        new_turn = %TurnState{
          turn
          | status: :executing_tools,
            tool_invocations: Map.put(turn.tool_invocations, entry_id, new_tool_state)
        }

        new_entries = update_chat_entry_status(entries, entry_id, :executing)

        actions = [
          {:update_tool_status, entry_id, "executing", []},
          {:send_msf_command, command},
          :broadcast_chat_state
        ]

        {new_turn, new_entries, actions}

      %{tool_name: "bash_command", arguments: args} = tool_state ->
        command = Map.get(args, "command", "")

        new_tool_state = %{
          tool_state
          | status: :executing,
            started_at: DateTime.utc_now()
        }

        new_turn = %TurnState{
          turn
          | status: :executing_tools,
            tool_invocations: Map.put(turn.tool_invocations, entry_id, new_tool_state)
        }

        new_entries = update_chat_entry_status(entries, entry_id, :executing)

        actions = [
          {:update_tool_status, entry_id, "executing", []},
          {:send_bash_command, entry_id, command},
          :broadcast_chat_state
        ]

        {new_turn, new_entries, actions}

      tool_state when tool_state != nil ->
        # Unknown tool type
        Logger.error("Unknown tool type: #{tool_state.tool_name}")

        new_tool_state = %{tool_state | status: :error}

        new_turn = %TurnState{
          turn
          | tool_invocations: Map.put(turn.tool_invocations, entry_id, new_tool_state)
        }

        new_entries = update_chat_entry_status(entries, entry_id, :error)

        actions = [
          {:update_tool_status, entry_id, "error",
           [error_message: "Unknown tool: #{tool_state.tool_name}", duration_ms: 0]},
          :broadcast_chat_state
        ]

        {new_turn, new_entries, actions}

      nil ->
        {turn, entries, []}
    end
  end

  @doc """
  Completes a tool execution.

  Called when the console becomes ready after a command execution.

  ## Parameters

  - `turn` - Current turn state
  - `entries` - Current chat entries
  - `output` - The command output
  - `command_id` - The command ID that completed

  ## Returns

  `{new_turn, new_entries, actions}` or `:no_executing_tool` if no tool was executing
  """
  @spec complete_tool_execution(TurnState.t(), [ChatEntry.t()], String.t(), String.t() | nil) ::
          {TurnState.t(), [ChatEntry.t()], [action()]} | :no_executing_tool
  def complete_tool_execution(%TurnState{} = turn, entries, output, command_id) do
    # Find the tool that was executing
    case find_executing_tool(turn, command_id) do
      nil ->
        :no_executing_tool

      {entry_id, tool_state} ->
        duration = DateTime.diff(DateTime.utc_now(), tool_state.started_at, :millisecond)

        Logger.info("Tool execution complete (#{duration}ms, #{String.length(output)} bytes)")

        new_tool_state = %{tool_state | status: :success}

        new_turn = %TurnState{
          turn
          | tool_invocations: Map.put(turn.tool_invocations, entry_id, new_tool_state),
            command_to_tool: Map.delete(turn.command_to_tool, tool_state.command_id || "")
        }

        new_entries =
          update_chat_entry_status(entries, entry_id, :success, result_content: output)

        actions = [
          {:update_tool_status, entry_id, "success",
           [result_content: output, duration_ms: duration]},
          :reconcile,
          :broadcast_chat_state
        ]

        {new_turn, new_entries, actions}
    end
  end

  @doc """
  Records a command ID for a tool that started executing.

  Called after the send_command action returns a command_id.
  """
  @spec record_command_id(TurnState.t(), integer(), String.t()) :: TurnState.t()
  def record_command_id(%TurnState{} = turn, entry_id, command_id) do
    case Map.get(turn.tool_invocations, entry_id) do
      nil ->
        turn

      tool_state ->
        new_tool_state = %{tool_state | command_id: command_id}

        %TurnState{
          turn
          | tool_invocations: Map.put(turn.tool_invocations, entry_id, new_tool_state),
            command_to_tool: Map.put(turn.command_to_tool, command_id, entry_id)
        }
    end
  end

  @doc """
  Marks a tool as failed due to command error.
  """
  @spec mark_tool_error(TurnState.t(), [ChatEntry.t()], integer(), term()) ::
          {TurnState.t(), [ChatEntry.t()], [action()]}
  def mark_tool_error(%TurnState{} = turn, entries, entry_id, reason) do
    case Map.get(turn.tool_invocations, entry_id) do
      nil ->
        {turn, entries, []}

      tool_state ->
        new_tool_state = %{tool_state | status: :error}

        new_turn = %TurnState{
          turn
          | tool_invocations: Map.put(turn.tool_invocations, entry_id, new_tool_state)
        }

        new_entries = update_chat_entry_status(entries, entry_id, :error)

        actions = [
          {:update_tool_status, entry_id, "error",
           [error_message: inspect(reason), duration_ms: 0]},
          :broadcast_chat_state
        ]

        {new_turn, new_entries, actions}
    end
  end

  # ============================================================================
  # Bash Tool Completion
  # ============================================================================

  @doc """
  Completes a bash tool execution by command_id.

  Unlike MSF commands which complete on console ready, bash commands complete
  via CommandResult events with explicit command_id matching.

  ## Parameters

  - `turn` - Current turn state
  - `entries` - Current chat entries
  - `command_id` - The command ID that completed
  - `output` - The command output

  ## Returns

  `{new_turn, new_entries, actions}` or `:no_executing_tool` if no tool was executing
  """
  @spec complete_bash_tool(TurnState.t(), [ChatEntry.t()], String.t(), String.t()) ::
          {TurnState.t(), [ChatEntry.t()], [action()]} | :no_executing_tool
  def complete_bash_tool(%TurnState{} = turn, entries, command_id, output) do
    case find_tool_by_command_id(turn, command_id) do
      nil ->
        :no_executing_tool

      {entry_id, tool_state} ->
        duration = DateTime.diff(DateTime.utc_now(), tool_state.started_at, :millisecond)

        Logger.info(
          "Bash tool execution complete (#{duration}ms, #{String.length(output)} bytes)"
        )

        new_tool_state = %{tool_state | status: :success}

        new_turn = %TurnState{
          turn
          | tool_invocations: Map.put(turn.tool_invocations, entry_id, new_tool_state),
            command_to_tool: Map.delete(turn.command_to_tool, command_id)
        }

        new_entries =
          update_chat_entry_status(entries, entry_id, :success, result_content: output)

        actions = [
          {:update_tool_status, entry_id, "success",
           [result_content: output, duration_ms: duration]},
          :reconcile,
          :broadcast_chat_state
        ]

        {new_turn, new_entries, actions}
    end
  end

  @doc """
  Marks a bash tool as failed by command_id.

  ## Parameters

  - `turn` - Current turn state
  - `entries` - Current chat entries
  - `command_id` - The command ID that failed
  - `error_message` - The error message

  ## Returns

  `{new_turn, new_entries, actions}` or `:no_executing_tool` if no tool was executing
  """
  @spec error_bash_tool(TurnState.t(), [ChatEntry.t()], String.t(), String.t()) ::
          {TurnState.t(), [ChatEntry.t()], [action()]} | :no_executing_tool
  def error_bash_tool(%TurnState{} = turn, entries, command_id, error_message) do
    case find_tool_by_command_id(turn, command_id) do
      nil ->
        :no_executing_tool

      {entry_id, tool_state} ->
        duration =
          if tool_state.started_at do
            DateTime.diff(DateTime.utc_now(), tool_state.started_at, :millisecond)
          else
            0
          end

        Logger.warning("Bash tool execution failed: #{error_message}")

        new_tool_state = %{tool_state | status: :error}

        new_turn = %TurnState{
          turn
          | tool_invocations: Map.put(turn.tool_invocations, entry_id, new_tool_state),
            command_to_tool: Map.delete(turn.command_to_tool, command_id)
        }

        new_entries = update_chat_entry_status(entries, entry_id, :error)

        actions = [
          {:update_tool_status, entry_id, "error",
           [error_message: error_message, duration_ms: duration]},
          :reconcile,
          :broadcast_chat_state
        ]

        {new_turn, new_entries, actions}
    end
  end

  defp find_tool_by_command_id(turn, command_id) do
    case Map.get(turn.command_to_tool, command_id) do
      nil -> nil
      entry_id -> {entry_id, Map.get(turn.tool_invocations, entry_id)}
    end
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp execute_next_sequential_tool(%TurnState{} = turn, _console, entries, _context) do
    # Find first approved sequential tool by position
    approved_tools =
      turn.tool_invocations
      |> Enum.filter(fn {_id, ts} ->
        ts.status == :approved and sequential_tool?(ts.tool_name)
      end)
      |> Enum.sort_by(fn {id, _ts} -> get_entry_position(entries, id) end)

    case approved_tools do
      [{entry_id, _tool_state} | _] ->
        start_tool_execution(turn, entries, entry_id)

      [] ->
        :no_action
    end
  end

  defp execute_all_parallel_tools(%TurnState{} = turn, entries) do
    # Find all approved parallel tools, sorted by position
    approved_parallel =
      turn.tool_invocations
      |> Enum.filter(fn {_id, ts} ->
        ts.status == :approved and not sequential_tool?(ts.tool_name)
      end)
      |> Enum.sort_by(fn {id, _ts} -> get_entry_position(entries, id) end)

    case approved_parallel do
      [] ->
        :no_action

      tools ->
        # Execute all parallel tools in one batch
        {final_turn, final_entries, all_actions} =
          Enum.reduce(tools, {turn, entries, []}, fn {entry_id, _},
                                                     {acc_turn, acc_entries, acc_actions} ->
            {new_turn, new_entries, actions} =
              start_tool_execution(acc_turn, acc_entries, entry_id)

            {new_turn, new_entries, acc_actions ++ actions}
          end)

        {final_turn, final_entries, all_actions}
    end
  end

  defp get_entry_position(entries, entry_id) do
    case Enum.find(entries, fn e -> e.id == entry_id or e.position == entry_id end) do
      nil -> 999_999
      entry -> entry.position
    end
  end

  defp start_llm_request(%TurnState{} = turn, entries, context) do
    track_id = context.track_id
    model = turn.model

    Logger.debug("Starting next LLM request")

    request = build_llm_request(track_id, model, turn.last_cache_context)

    new_turn = %TurnState{
      turn
      | status: :pending,
        tool_invocations: %{}
    }

    {new_turn, entries, [{:start_llm, request}, :broadcast_chat_state]}
  end

  defp complete_turn(%TurnState{} = turn, entries) do
    Logger.info("Turn complete")

    actions =
      if turn.turn_id do
        [{:update_turn_status, turn.turn_id, "finished"}, :broadcast_chat_state]
      else
        [:broadcast_chat_state]
      end

    new_turn = %TurnState{
      turn
      | status: :finished,
        turn_id: nil,
        llm_ref: nil,
        tool_invocations: %{},
        command_to_tool: %{}
    }

    {new_turn, entries, actions}
  end

  defp build_llm_request(track_id, model, cache_context) do
    # Load entries from DB for accurate LLM context
    entries = ChatContext.load_entries(track_id)
    messages = ChatContext.entries_to_llm_messages(entries)

    system_prompt =
      case LLM.get_system_prompt() do
        {:ok, prompt} -> prompt
        {:error, _} -> nil
      end

    tools = Tools.list_tools()

    %ChatRequest{
      model: model,
      messages: messages,
      system_prompt: system_prompt,
      tools: tools,
      cache_context: cache_context
    }
  end

  defp update_chat_entry_status(entries, entry_id, new_status, opts \\ []) do
    Enum.map(entries, fn entry ->
      if matches_tool_entry?(entry, entry_id),
        do: apply_tool_update(entry, new_status, opts),
        else: entry
    end)
  end

  defp matches_tool_entry?(entry, entry_id) do
    (entry.id == entry_id or entry.position == entry_id) and ChatEntry.tool_invocation?(entry)
  end

  defp apply_tool_update(entry, new_status, opts) do
    entry = %{entry | tool_status: new_status}

    case Keyword.get(opts, :result_content) do
      nil -> entry
      content -> %{entry | result_content: content}
    end
  end

  defp find_executing_tool(turn, _command_id) do
    # Find any executing tool with a command_id
    Enum.find(turn.tool_invocations, fn {_id, ts} ->
      ts.status == :executing and ts.command_id != nil
    end)
  end
end
