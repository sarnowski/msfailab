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

defmodule Msfailab.Tracks.TrackServer.Action do
  @moduledoc """
  Action types returned by TrackServer core modules.

  Core modules (Console, Stream, Turn) are pure functions that return
  state transformations and action lists. The TrackServer shell executes
  these actions to perform side effects.

  ## Action Categories

  ### Persistence Actions
  - `{:persist_console_block, block}` - Save console history block to DB
  - `{:persist_message, attrs}` - Create message entry in DB
  - `{:persist_tool_invocation, attrs}` - Create tool invocation entry in DB
  - `{:update_tool_status, entry_id, status, opts}` - Update tool invocation status
  - `{:update_turn_status, turn_id, status}` - Update turn status

  ### Broadcast Actions
  - `:broadcast_track_state` - Broadcast TrackStateUpdated event
  - `:broadcast_chat_state` - Broadcast ChatStateUpdated event

  ### External System Actions
  - `{:start_llm, request}` - Start LLM streaming request
  - `{:send_command, command}` - Send command to Metasploit console

  ### Control Flow Actions
  - `:reconcile` - Trigger reconciliation after action execution
  """

  require Logger

  alias Msfailab.Containers
  alias Msfailab.Events
  alias Msfailab.Events.ChatChanged
  alias Msfailab.Events.ConsoleChanged
  alias Msfailab.LLM
  alias Msfailab.Tracks
  alias Msfailab.Tracks.ChatContext
  alias Msfailab.Tracks.ChatHistoryTurn
  alias Msfailab.Tracks.TrackServer.State

  # Persistence actions
  @type persist_console_block :: {:persist_console_block, Tracks.ConsoleHistoryBlock.t()}
  @type persist_message ::
          {:persist_message, pos_integer(), String.t() | nil, pos_integer(), map()}
  @type persist_tool_invocation ::
          {:persist_tool_invocation, pos_integer(), String.t(), pos_integer(), map()}
  @type update_tool_status :: {:update_tool_status, integer(), String.t(), keyword()}
  @type update_turn_status :: {:update_turn_status, String.t(), String.t()}
  @type create_turn :: {:create_turn, pos_integer(), String.t()}

  # Broadcast actions
  @type broadcast_track_state :: :broadcast_track_state
  @type broadcast_chat_state :: :broadcast_chat_state

  # External system actions
  @type start_llm :: {:start_llm, LLM.ChatRequest.t()}
  @type send_command :: {:send_command, String.t()}

  # Control flow actions
  @type reconcile :: :reconcile

  @type t ::
          persist_console_block()
          | persist_message()
          | persist_tool_invocation()
          | update_tool_status()
          | update_turn_status()
          | create_turn()
          | broadcast_track_state()
          | broadcast_chat_state()
          | start_llm()
          | send_command()
          | reconcile()

  @type result :: :ok | {:ok, term()} | {:error, term()}

  @doc """
  Executes a list of actions against the given state.

  Returns the updated state after all actions have been executed.
  Some actions may update state (e.g., :start_llm sets llm_ref).

  ## Parameters

  - `state` - The current TrackServer state
  - `actions` - List of actions to execute

  ## Returns

  The updated state after action execution.
  """
  @spec execute_all(State.t(), [t()]) :: State.t()
  def execute_all(state, actions) do
    Enum.reduce(actions, state, &execute/2)
  end

  @doc """
  Executes a single action.

  Returns the updated state.
  """
  @spec execute(t(), State.t()) :: State.t()

  # ---------------------------------------------------------------------------
  # Persistence Actions
  # ---------------------------------------------------------------------------

  def execute({:persist_console_block, block}, state) do
    case Tracks.create_console_history_block(block) do
      {:ok, persisted_block} ->
        history = replace_block_in_history(state.console.history, block, persisted_block)
        put_in(state, [Access.key(:console), Access.key(:history)], history)

      {:error, changeset} ->
        Logger.error("Failed to persist console history block",
          error: inspect(changeset.errors)
        )

        state
    end
  end

  def execute({:persist_message, track_id, turn_id, position, attrs}, state) do
    case ChatContext.create_message_entry(track_id, turn_id, nil, position, attrs) do
      {:ok, _entry} ->
        state

      # coveralls-ignore-start
      # Reason: ChatContext.create_message_entry crashes on failure (pattern match in transaction)
      # rather than returning {:error, _}. This defensive error handling is unreachable.
      {:error, reason} ->
        Logger.error("Failed to persist message entry", reason: inspect(reason))
        state
        # coveralls-ignore-stop
    end
  end

  def execute({:persist_tool_invocation, track_id, turn_id, position, attrs}, state) do
    case ChatContext.create_tool_invocation_entry(track_id, turn_id, nil, position, attrs) do
      {:ok, entry} ->
        # Return the entry ID for the caller to use
        # This is a special case - we need to track the entry_id
        put_in(state, [Access.key(:_last_tool_entry_id)], entry.id)

      # coveralls-ignore-start
      # Reason: ChatContext.create_tool_invocation_entry crashes on failure rather than returning {:error, _}.
      {:error, reason} ->
        Logger.error("Failed to persist tool invocation entry", reason: inspect(reason))
        state
        # coveralls-ignore-stop
    end
  rescue
    # The state struct doesn't have _last_tool_entry_id, this is expected
    # We handle this in the Turn module by passing entry_id explicitly
    _ -> state
  end

  def execute({:update_tool_status, position, status, opts}, state) do
    case ChatContext.update_tool_invocation(state.track_id, position, status, opts) do
      {:ok, _} ->
        state

      {:error, reason} ->
        Logger.error(
          "Failed to update tool invocation status for position #{position}: #{inspect(reason)}"
        )

        state
    end
  end

  def execute({:update_turn_status, turn_id, status}, state) do
    case ChatContext.update_turn_status(%ChatHistoryTurn{id: turn_id}, status) do
      {:ok, _} ->
        state

      {:error, reason} ->
        Logger.error("Failed to update turn status for turn #{turn_id}: #{inspect(reason)}")
        state
    end
  end

  def execute({:create_turn, track_id, model}, state) do
    case ChatContext.create_turn(track_id, model) do
      {:ok, turn} ->
        put_in(state, [Access.key(:turn), Access.key(:turn_id)], turn.id)

      # coveralls-ignore-start
      # Reason: ChatContext.create_turn crashes on failure rather than returning {:error, _}.
      {:error, reason} ->
        Logger.error("Failed to create turn", reason: inspect(reason))
        state
        # coveralls-ignore-stop
    end
  end

  # ---------------------------------------------------------------------------
  # Broadcast Actions
  # ---------------------------------------------------------------------------

  def execute(:broadcast_track_state, state) do
    event = ConsoleChanged.new(state.workspace_id, state.track_id)
    Events.broadcast(event)
    state
  end

  def execute(:broadcast_chat_state, state) do
    event = ChatChanged.new(state.workspace_id, state.track_id)
    Events.broadcast(event)
    state
  end

  # ---------------------------------------------------------------------------
  # External System Actions
  # ---------------------------------------------------------------------------

  # coveralls-ignore-start
  # Reason: External system integration requiring LLM mock infrastructure.
  # Logic is straightforward case match on LLM.chat result.
  def execute({:start_llm, request}, state) do
    case LLM.chat(request) do
      {:ok, ref} ->
        state
        |> put_in([Access.key(:turn), Access.key(:llm_ref)], ref)
        |> put_in([Access.key(:turn), Access.key(:status)], :pending)

      {:error, reason} ->
        Logger.error("Failed to start LLM request", reason: inspect(reason))
        put_in(state, [Access.key(:turn), Access.key(:status)], :error)
    end
  end

  # coveralls-ignore-stop

  # coveralls-ignore-start
  # Reason: External system integration requiring Container mock infrastructure.
  # Logic is straightforward case match on send_metasploit_command result.
  def execute({:send_command, command}, state) do
    case Containers.send_metasploit_command(
           state.container_id,
           state.track_id,
           command
         ) do
      {:ok, command_id} ->
        Logger.info("Tool execution started: #{command}")
        # Return command_id through state for the caller
        put_in(state, [Access.key(:_last_command_id)], command_id)

      {:error, :console_busy} ->
        Logger.debug("Console busy, will retry tool execution")
        state

      {:error, reason} ->
        Logger.error("Tool execution failed immediately", reason: inspect(reason))
        put_in(state, [Access.key(:_command_error)], reason)
    end
  rescue
    # The state struct doesn't have these fields, handle gracefully
    _ -> state
  end

  # coveralls-ignore-stop

  # ---------------------------------------------------------------------------
  # Control Flow Actions
  # ---------------------------------------------------------------------------

  def execute(:reconcile, state) do
    # This is a marker action - the shell handles reconciliation
    # by calling Turn.reconcile after executing all actions
    state
  end

  # ---------------------------------------------------------------------------
  # Catch-all
  # ---------------------------------------------------------------------------

  def execute(unknown_action, state) do
    Logger.warning("Unknown action: #{inspect(unknown_action)}")
    state
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp replace_block_in_history(history, original_block, persisted_block) do
    Enum.map(history, fn b ->
      if b.started_at == original_block.started_at and b.type == original_block.type do
        persisted_block
      else
        b
      end
    end)
  end
end
