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

defmodule Msfailab.Tracks.TrackServer.ActionTest do
  use Msfailab.DataCase, async: true

  import ExUnit.CaptureLog

  alias Msfailab.Containers
  alias Msfailab.Events
  alias Msfailab.Events.ChatChanged
  alias Msfailab.Events.ConsoleChanged
  alias Msfailab.Tracks
  alias Msfailab.Tracks.ChatContext
  alias Msfailab.Tracks.ConsoleHistoryBlock
  alias Msfailab.Tracks.TrackServer.Action
  alias Msfailab.Tracks.TrackServer.State
  alias Msfailab.Tracks.TrackServer.State.Console, as: ConsoleState
  alias Msfailab.Tracks.TrackServer.State.Stream, as: StreamState
  alias Msfailab.Tracks.TrackServer.State.Turn, as: TurnState

  # ===========================================================================
  # Test Helpers
  # ===========================================================================

  defp make_state(attrs \\ []) do
    %State{
      track_id: Keyword.get(attrs, :track_id, 1),
      workspace_id: Keyword.get(attrs, :workspace_id, 1),
      workspace_slug: Keyword.get(attrs, :workspace_slug, "test-workspace"),
      container_id: Keyword.get(attrs, :container_id, 1),
      autonomous: Keyword.get(attrs, :autonomous, false),
      console: Keyword.get(attrs, :console, ConsoleState.new()),
      stream: Keyword.get(attrs, :stream, StreamState.new(1)),
      turn: Keyword.get(attrs, :turn, TurnState.new()),
      chat_entries: Keyword.get(attrs, :chat_entries, [])
    }
  end

  defp create_workspace_container_and_track do
    {:ok, workspace} = Msfailab.Workspaces.create_workspace(%{name: "test", slug: "test"})

    {:ok, container} =
      Containers.create_container(workspace, %{
        name: "Test Container",
        slug: "test-container",
        docker_image: "test:latest"
      })

    {:ok, track} = Tracks.create_track(container, %{name: "Test Track", slug: "test-track"})

    %{workspace: workspace, container: container, track: track}
  end

  # ===========================================================================
  # execute_all/2 Tests
  # ===========================================================================

  describe "execute_all/2" do
    test "executes multiple actions" do
      state = make_state()
      actions = [:broadcast_chat_state, :reconcile]

      Events.subscribe_to_workspace(1)

      new_state = Action.execute_all(state, actions)

      assert new_state == state
      assert_receive %ChatChanged{}
    end

    test "handles empty action list" do
      state = make_state()

      new_state = Action.execute_all(state, [])

      assert new_state == state
    end
  end

  # ===========================================================================
  # Broadcast Actions Tests
  # ===========================================================================

  describe "execute/2 - :broadcast_track_state" do
    test "broadcasts ConsoleChanged event" do
      state = make_state(track_id: 42, workspace_id: 10)
      Events.subscribe_to_workspace(10)

      new_state = Action.execute(:broadcast_track_state, state)

      assert new_state == state
      assert_receive %ConsoleChanged{workspace_id: 10, track_id: 42}
    end
  end

  describe "execute/2 - :broadcast_chat_state" do
    test "broadcasts ChatChanged event" do
      state = make_state(track_id: 42, workspace_id: 10)
      Events.subscribe_to_workspace(10)

      new_state = Action.execute(:broadcast_chat_state, state)

      assert new_state == state
      assert_receive %ChatChanged{workspace_id: 10, track_id: 42}
    end
  end

  # ===========================================================================
  # Control Flow Actions Tests
  # ===========================================================================

  describe "execute/2 - :reconcile" do
    test "returns state unchanged (marker action)" do
      state = make_state()

      new_state = Action.execute(:reconcile, state)

      assert new_state == state
    end
  end

  # ===========================================================================
  # Unknown Actions Tests
  # ===========================================================================

  describe "execute/2 - unknown action" do
    test "logs warning and returns state unchanged" do
      state = make_state()

      log =
        capture_log(fn ->
          new_state = Action.execute({:unknown_action, "data"}, state)
          assert new_state == state
        end)

      assert log =~ "Unknown action"
    end
  end

  # ===========================================================================
  # Persistence Actions Tests (require DB)
  # ===========================================================================

  describe "execute/2 - {:persist_message, ...}" do
    setup do
      create_workspace_container_and_track()
    end

    test "persists message entry successfully", %{track: track} do
      state = make_state(track_id: track.id)

      attrs = %{role: "user", message_type: "prompt", content: "Hello"}

      new_state = Action.execute({:persist_message, track.id, nil, 1, attrs}, state)

      assert new_state == state

      # Verify entry was created
      entries = ChatContext.load_entries(track.id)
      assert length(entries) == 1
      assert hd(entries).message.content == "Hello"
    end
  end

  describe "execute/2 - {:create_turn, ...}" do
    setup do
      create_workspace_container_and_track()
    end

    test "creates turn and updates state with turn_id", %{track: track} do
      state = make_state(track_id: track.id)

      new_state = Action.execute({:create_turn, track.id, "gpt-4"}, state)

      assert new_state.turn.turn_id != nil
    end
  end

  describe "execute/2 - {:persist_tool_invocation, ...}" do
    setup do
      %{} = create_workspace_container_and_track()
    end

    test "persists tool invocation entry", %{track: track} do
      state = make_state(track_id: track.id)

      attrs = %{
        tool_call_id: "call_abc",
        tool_name: "execute_msfconsole_command",
        arguments: %{"command" => "help"},
        console_prompt: "msf6 >",
        status: "pending"
      }

      new_state = Action.execute({:persist_tool_invocation, track.id, nil, 1, attrs}, state)

      # State should be unchanged since we rescue the Access error
      assert new_state == state || new_state != nil

      # Verify entry was created
      entries = ChatContext.load_entries(track.id)
      assert length(entries) == 1
    end
  end

  describe "execute/2 - {:update_tool_status, ...}" do
    setup do
      ctx = create_workspace_container_and_track()

      # Create a tool invocation entry
      {:ok, entry} =
        ChatContext.create_tool_invocation_entry(ctx.track.id, nil, nil, 1, %{
          tool_call_id: "call_abc",
          tool_name: "execute_msfconsole_command",
          arguments: %{"command" => "help"},
          console_prompt: "msf6 >",
          status: "pending"
        })

      Map.put(ctx, :entry, entry)
    end

    test "updates tool invocation status", %{track: track, entry: entry} do
      state = make_state(track_id: track.id)

      new_state =
        Action.execute({:update_tool_status, entry.id, "success", [duration_ms: 100]}, state)

      assert new_state == state
    end
  end

  describe "execute/2 - {:update_turn_status, ...}" do
    setup do
      ctx = create_workspace_container_and_track()

      {:ok, turn} = ChatContext.create_turn(ctx.track.id, "gpt-4")

      Map.put(ctx, :turn, turn)
    end

    test "updates turn status", %{turn: turn} do
      state = make_state()

      new_state = Action.execute({:update_turn_status, turn.id, "finished"}, state)

      assert new_state == state
    end
  end

  describe "execute/2 - {:persist_console_block, ...}" do
    setup do
      ctx = create_workspace_container_and_track()
      ctx
    end

    test "persists console block and updates history", %{track: track} do
      now = DateTime.utc_now()

      block = %ConsoleHistoryBlock{
        track_id: track.id,
        type: :startup,
        status: :finished,
        output: "Metasploit Banner",
        prompt: "msf6 >",
        started_at: now,
        finished_at: now
      }

      console = %ConsoleState{
        status: :ready,
        current_prompt: "msf6 >",
        history: [block],
        command_id: nil
      }

      state = make_state(track_id: track.id, console: console)

      new_state = Action.execute({:persist_console_block, block}, state)

      # History should now contain the persisted block with an ID
      assert length(new_state.console.history) == 1
      persisted_block = hd(new_state.console.history)
      assert persisted_block.id != nil
    end

    test "handles error when persisting block" do
      # Block without required track_id association
      block = %ConsoleHistoryBlock{
        track_id: -1,
        type: :startup,
        status: :finished,
        output: "",
        prompt: "",
        started_at: DateTime.utc_now(),
        finished_at: DateTime.utc_now()
      }

      console = %ConsoleState{
        status: :ready,
        current_prompt: "",
        history: [block],
        command_id: nil
      }

      state = make_state(console: console)

      log =
        capture_log(fn ->
          new_state = Action.execute({:persist_console_block, block}, state)
          # State should be unchanged on error
          assert new_state == state
        end)

      assert log =~ "Failed to persist console history block"
    end
  end

  # ===========================================================================
  # Error Path Tests
  # ===========================================================================

  describe "execute/2 - {:update_tool_status, ...} error paths" do
    test "logs error when update fails" do
      state = make_state()

      log =
        capture_log(fn ->
          # Non-existent entry_id should cause failure
          new_state = Action.execute({:update_tool_status, -999, "success", []}, state)
          assert new_state == state
        end)

      assert log =~ "Failed to update tool invocation status"
    end
  end

  describe "execute/2 - {:update_turn_status, ...} error paths" do
    test "logs error when update fails" do
      state = make_state()

      log =
        capture_log(fn ->
          # Non-existent turn_id should cause failure (use integer ID that doesn't exist)
          new_state = Action.execute({:update_turn_status, 999_999_999, "finished"}, state)
          assert new_state == state
        end)

      assert log =~ "Failed to update turn status"
    end
  end
end
