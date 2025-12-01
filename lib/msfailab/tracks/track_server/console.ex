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

defmodule Msfailab.Tracks.TrackServer.Console do
  @moduledoc """
  Pure functions for console history state management.

  This module implements the console history block state machine. It handles
  transitions between console statuses (offline, starting, ready, busy) and
  manages the creation and finalization of history blocks.

  ## Console Status State Machine

  ```
  offline ──► starting ──► ready ◄──► busy
     ▲                       │
     └───────────────────────┘
           (goes offline)
  ```

  ## Block Types

  - **Startup blocks**: Created when console transitions from offline to starting.
    Only persisted when followed by a command (proves the startup was "real").

  - **Command blocks**: Created when console transitions from ready to busy.
    Persisted when the command completes (ready again).

  ## Design

  All functions are pure - they take state and return new state plus actions.
  Side effects (DB persistence, event broadcasting) are handled by the shell.
  """

  alias Msfailab.Events.ConsoleUpdated
  alias Msfailab.Tracks.ConsoleHistoryBlock
  alias Msfailab.Tracks.TrackServer.State.Console, as: ConsoleState

  @type action ::
          {:persist_console_block, ConsoleHistoryBlock.t()}
          | :broadcast_track_state

  @doc """
  Applies a console event to the console state.

  Returns the updated console state and a list of actions to execute.

  ## Parameters

  - `console` - Current console state
  - `track_id` - The track ID (needed for creating new blocks)
  - `event` - The ConsoleUpdated event

  ## Returns

  `{new_console_state, actions}`
  """
  @spec apply_event(ConsoleState.t(), integer(), ConsoleUpdated.t()) ::
          {ConsoleState.t(), [action()]}
  def apply_event(%ConsoleState{} = console, _track_id, %ConsoleUpdated{status: :offline}) do
    # Console went offline - mark any running blocks as interrupted
    new_history = interrupt_running_blocks(console.history)

    new_console = %ConsoleState{
      console
      | status: :offline,
        history: new_history,
        command_id: nil
    }

    {new_console, [:broadcast_track_state]}
  end

  def apply_event(%ConsoleState{} = console, track_id, %ConsoleUpdated{
        status: :starting,
        output: output
      }) do
    case console.status do
      :offline ->
        # Starting fresh - remove any unpersisted startup blocks from previous
        # connections (they were never followed by a command, so not "real")
        cleaned_history = remove_unpersisted_startup_blocks(console.history)
        block = ConsoleHistoryBlock.new_startup(track_id, output)

        new_console = %ConsoleState{
          console
          | status: :starting,
            history: cleaned_history ++ [block]
        }

        {new_console, [:broadcast_track_state]}

      :starting ->
        # Continuing startup - append to current startup block
        new_history = append_to_current_block(console.history, output)
        new_console = %ConsoleState{console | history: new_history}
        {new_console, [:broadcast_track_state]}

      _ ->
        # Shouldn't happen, but handle gracefully
        new_console = %ConsoleState{console | status: :starting}
        {new_console, [:broadcast_track_state]}
    end
  end

  def apply_event(%ConsoleState{} = console, _track_id, %ConsoleUpdated{
        status: :ready,
        prompt: prompt
      }) do
    case console.status do
      :starting ->
        # Startup complete - mark finished but DON'T persist yet
        # Startup blocks are only persisted when followed by a command
        new_history = finish_startup_block(console.history, prompt)

        new_console = %ConsoleState{
          console
          | status: :ready,
            current_prompt: prompt,
            history: new_history
        }

        {new_console, [:broadcast_track_state]}

      :busy ->
        # Command complete - persist any unpersisted startup blocks, then this command
        {history_with_startups, startup_actions} =
          persist_unpersisted_startup_blocks(console.history)

        {final_history, command_actions} =
          finish_and_persist_command_block(history_with_startups, prompt)

        new_console = %ConsoleState{
          console
          | status: :ready,
            current_prompt: prompt,
            history: final_history,
            command_id: nil
        }

        {new_console, startup_actions ++ command_actions ++ [:broadcast_track_state]}

      _ ->
        # Just update prompt
        new_console = %ConsoleState{console | status: :ready, current_prompt: prompt}
        {new_console, [:broadcast_track_state]}
    end
  end

  def apply_event(%ConsoleState{} = console, track_id, %ConsoleUpdated{
        status: :busy,
        command_id: command_id,
        command: command,
        output: output
      }) do
    case console.status do
      :ready when command_id != nil and command != nil ->
        # New command started
        block = ConsoleHistoryBlock.new_command(track_id, command, output)

        new_console = %ConsoleState{
          console
          | status: :busy,
            history: console.history ++ [block],
            command_id: command_id
        }

        {new_console, [:broadcast_track_state]}

      :busy ->
        # Command continuing - append output
        new_history = append_to_current_block(console.history, output)
        new_console = %ConsoleState{console | history: new_history}
        {new_console, [:broadcast_track_state]}

      _ ->
        # Shouldn't happen, but handle gracefully
        new_console = %ConsoleState{console | status: :busy}
        {new_console, [:broadcast_track_state]}
    end
  end

  # ===========================================================================
  # Block Manipulation Helpers
  # ===========================================================================

  @doc """
  Marks all running blocks as interrupted.

  Called when console goes offline.
  """
  @spec interrupt_running_blocks([ConsoleHistoryBlock.t()]) :: [ConsoleHistoryBlock.t()]
  def interrupt_running_blocks(history) do
    Enum.map(history, fn
      %ConsoleHistoryBlock{status: :running} = block ->
        %{block | status: :interrupted, finished_at: DateTime.utc_now()}

      block ->
        block
    end)
  end

  @doc """
  Appends output to the current (last running) block.
  """
  @spec append_to_current_block([ConsoleHistoryBlock.t()], String.t() | nil) ::
          [ConsoleHistoryBlock.t()]
  def append_to_current_block(history, output) when output == "" or output == nil do
    history
  end

  def append_to_current_block(history, output) do
    case List.last(history) do
      nil ->
        history

      %ConsoleHistoryBlock{status: :running} = block ->
        updated = %{block | output: block.output <> output}
        List.replace_at(history, -1, updated)

      _ ->
        history
    end
  end

  @doc """
  Finishes a startup block (marks as finished but doesn't persist).
  """
  @spec finish_startup_block([ConsoleHistoryBlock.t()], String.t()) ::
          [ConsoleHistoryBlock.t()]
  def finish_startup_block(history, prompt) do
    case List.last(history) do
      %ConsoleHistoryBlock{status: :running, type: :startup} = block ->
        finished_block = %{
          block
          | status: :finished,
            prompt: prompt,
            finished_at: DateTime.utc_now()
        }

        List.replace_at(history, -1, finished_block)

      _ ->
        history
    end
  end

  @doc """
  Finishes and returns actions to persist a command block.
  """
  @spec finish_and_persist_command_block([ConsoleHistoryBlock.t()], String.t()) ::
          {[ConsoleHistoryBlock.t()], [action()]}
  def finish_and_persist_command_block(history, prompt) do
    case List.last(history) do
      %ConsoleHistoryBlock{status: :running, type: :command} = block ->
        finished_block = %{
          block
          | status: :finished,
            prompt: prompt,
            finished_at: DateTime.utc_now()
        }

        new_history = List.replace_at(history, -1, finished_block)
        actions = [{:persist_console_block, finished_block}]
        {new_history, actions}

      _ ->
        {history, []}
    end
  end

  @doc """
  Returns actions to persist any unpersisted startup blocks.

  Also updates the history with the blocks marked for persistence.
  """
  @spec persist_unpersisted_startup_blocks([ConsoleHistoryBlock.t()]) ::
          {[ConsoleHistoryBlock.t()], [action()]}
  def persist_unpersisted_startup_blocks(history) do
    {new_history, actions} =
      Enum.map_reduce(history, [], fn
        %ConsoleHistoryBlock{type: :startup, status: :finished, id: nil} = block, acc ->
          {block, [{:persist_console_block, block} | acc]}

        block, acc ->
          {block, acc}
      end)

    {new_history, Enum.reverse(actions)}
  end

  @doc """
  Removes startup blocks that were never followed by a command (id: nil).
  """
  @spec remove_unpersisted_startup_blocks([ConsoleHistoryBlock.t()]) ::
          [ConsoleHistoryBlock.t()]
  def remove_unpersisted_startup_blocks(history) do
    Enum.reject(history, fn
      %ConsoleHistoryBlock{type: :startup, id: nil} -> true
      _ -> false
    end)
  end

  @doc """
  Gets the output from the latest command block.

  Used to get tool execution results.
  """
  @spec get_latest_command_output([ConsoleHistoryBlock.t()]) :: String.t()
  def get_latest_command_output(history) do
    case List.last(history) do
      %ConsoleHistoryBlock{type: :command, output: output} -> output
      _ -> ""
    end
  end
end
