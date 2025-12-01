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

defmodule Msfailab.Tracks.TrackServer.StateTest do
  use ExUnit.Case, async: true

  alias Msfailab.Tracks.ChatEntry
  alias Msfailab.Tracks.ConsoleHistoryBlock
  alias Msfailab.Tracks.TrackServer.State
  alias Msfailab.Tracks.TrackServer.State.Console
  alias Msfailab.Tracks.TrackServer.State.Stream
  alias Msfailab.Tracks.TrackServer.State.Turn

  describe "Console.new/0" do
    test "creates console state with defaults" do
      console = Console.new()

      assert console.status == :offline
      assert console.current_prompt == ""
      assert console.history == []
      assert console.command_id == nil
    end
  end

  describe "Console.from_history/1" do
    test "creates console state from empty history" do
      console = Console.from_history([])

      assert console.status == :offline
      assert console.current_prompt == ""
      assert console.history == []
      assert console.command_id == nil
    end

    test "creates console state from history with prompt" do
      history = [
        %ConsoleHistoryBlock{
          track_id: 1,
          type: :startup,
          status: :finished,
          output: "Banner",
          prompt: "msf6 >",
          started_at: DateTime.utc_now()
        }
      ]

      console = Console.from_history(history)

      assert console.status == :offline
      assert console.current_prompt == "msf6 >"
      assert console.history == history
      assert console.command_id == nil
    end

    test "uses last block's prompt from multi-block history" do
      now = DateTime.utc_now()

      history = [
        %ConsoleHistoryBlock{
          track_id: 1,
          type: :startup,
          status: :finished,
          output: "Banner",
          prompt: "msf6 >",
          started_at: now
        },
        %ConsoleHistoryBlock{
          track_id: 1,
          type: :command,
          status: :finished,
          command: "use exploit/test",
          output: "Output",
          prompt: "msf6 exploit(test) >",
          started_at: now
        }
      ]

      console = Console.from_history(history)

      assert console.current_prompt == "msf6 exploit(test) >"
    end

    test "handles nil prompt in last block" do
      history = [
        %ConsoleHistoryBlock{
          track_id: 1,
          type: :startup,
          status: :finished,
          output: "Banner",
          prompt: nil,
          started_at: DateTime.utc_now()
        }
      ]

      console = Console.from_history(history)

      assert console.current_prompt == ""
    end
  end

  describe "Stream.new/1" do
    test "creates stream state with given next_position" do
      stream = Stream.new(5)

      assert stream.blocks == %{}
      assert stream.documents == %{}
      assert stream.next_position == 5
    end
  end

  describe "Stream.reset/1" do
    test "clears blocks and documents while preserving next_position" do
      stream = %Stream{
        blocks: %{0 => 1, 1 => 2},
        documents: %{1 => :some_doc, 2 => :another_doc},
        next_position: 10
      }

      reset_stream = Stream.reset(stream)

      assert reset_stream.blocks == %{}
      assert reset_stream.documents == %{}
      assert reset_stream.next_position == 10
    end
  end

  describe "Turn.new/0" do
    test "creates turn state in idle status" do
      turn = Turn.new()

      assert turn.status == :idle
      assert turn.turn_id == nil
      assert turn.model == nil
      assert turn.llm_ref == nil
      assert turn.tool_invocations == %{}
      assert turn.command_to_tool == %{}
      assert turn.last_cache_context == nil
    end
  end

  describe "Turn.from_tool_invocations/1" do
    test "returns idle status for empty tool invocations" do
      turn = Turn.from_tool_invocations(%{})

      assert turn.status == :idle
      assert turn.tool_invocations == %{}
    end

    test "returns pending_approval status when pending tools exist" do
      tool_invocations = %{
        1 => %{
          tool_call_id: "call_1",
          tool_name: "msf_command",
          arguments: %{},
          status: :pending,
          command_id: nil,
          started_at: nil
        }
      }

      turn = Turn.from_tool_invocations(tool_invocations)

      assert turn.status == :pending_approval
      assert turn.tool_invocations == tool_invocations
      assert turn.command_to_tool == %{}
    end

    test "returns executing_tools status when no pending tools" do
      tool_invocations = %{
        1 => %{
          tool_call_id: "call_1",
          tool_name: "msf_command",
          arguments: %{},
          status: :approved,
          command_id: nil,
          started_at: nil
        }
      }

      turn = Turn.from_tool_invocations(tool_invocations)

      assert turn.status == :executing_tools
      assert turn.tool_invocations == tool_invocations
    end

    test "returns pending_approval if any tool is pending among many" do
      tool_invocations = %{
        1 => %{
          tool_call_id: "call_1",
          tool_name: "msf_command",
          arguments: %{},
          status: :success,
          command_id: nil,
          started_at: nil
        },
        2 => %{
          tool_call_id: "call_2",
          tool_name: "msf_command",
          arguments: %{},
          status: :pending,
          command_id: nil,
          started_at: nil
        }
      }

      turn = Turn.from_tool_invocations(tool_invocations)

      assert turn.status == :pending_approval
    end
  end

  describe "State.new/4" do
    test "creates state with required IDs and defaults" do
      state = State.new(1, 2, 3)

      assert state.track_id == 1
      assert state.workspace_id == 2
      assert state.container_id == 3
      assert state.autonomous == false
      assert %Console{} = state.console
      assert %Stream{} = state.stream
      assert %Turn{} = state.turn
      assert state.chat_entries == []
    end

    test "respects autonomous option" do
      state = State.new(1, 2, 3, autonomous: true)

      assert state.autonomous == true
    end
  end

  describe "State.from_persisted/2" do
    test "creates state from persisted data" do
      console_history = [
        %ConsoleHistoryBlock{
          track_id: 1,
          type: :startup,
          status: :finished,
          output: "Banner",
          prompt: "msf6 >",
          started_at: DateTime.utc_now()
        }
      ]

      chat_entries = [
        ChatEntry.user_prompt("entry-1", 1, "Hello!", DateTime.utc_now())
      ]

      tool_invocations = %{
        1 => %{
          tool_call_id: "call_1",
          tool_name: "msf_command",
          arguments: %{},
          status: :pending,
          command_id: nil,
          started_at: nil
        }
      }

      state =
        State.from_persisted(
          %{track_id: 1, workspace_id: 2, container_id: 3},
          autonomous: true,
          console_history: console_history,
          chat_entries: chat_entries,
          next_position: 5,
          tool_invocations: tool_invocations,
          model: "gpt-4o"
        )

      assert state.track_id == 1
      assert state.workspace_id == 2
      assert state.container_id == 3
      assert state.autonomous == true
      assert state.console.history == console_history
      assert state.console.current_prompt == "msf6 >"
      assert state.stream.next_position == 5
      assert state.turn.status == :pending_approval
      assert state.turn.model == "gpt-4o"
      assert state.turn.tool_invocations == tool_invocations
      assert state.chat_entries == chat_entries
    end

    test "handles empty persisted data" do
      state =
        State.from_persisted(
          %{track_id: 1, workspace_id: 2, container_id: 3},
          autonomous: false
        )

      assert state.track_id == 1
      assert state.autonomous == false
      assert state.console.history == []
      assert state.console.current_prompt == ""
      assert state.stream.next_position == 1
      assert state.turn.status == :idle
      assert state.turn.model == nil
      assert state.chat_entries == []
    end
  end
end
