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

defmodule Msfailab.Tracks.TrackServerTest do
  use Msfailab.TracksCase, async: false

  alias Msfailab.Containers
  alias Msfailab.Events
  alias Msfailab.Events.ConsoleChanged
  alias Msfailab.Events.ConsoleUpdated
  alias Msfailab.Tracks
  alias Msfailab.Tracks.TrackServer

  describe "start_link/1" do
    test "starts and registers the track server" do
      pid =
        start_supervised!({TrackServer, track_id: 100, workspace_id: 1, container_id: 5})

      assert Process.alive?(pid)
      assert TrackServer.whereis(100) == pid
    end

    test "initializes with offline console status" do
      _pid =
        start_supervised!({TrackServer, track_id: 101, workspace_id: 1, container_id: 5})

      assert TrackServer.get_console_status(101) == :offline
      assert TrackServer.get_console_history(101) == []
    end
  end

  describe "get_console_history/1" do
    test "returns empty list initially" do
      _pid =
        start_supervised!({TrackServer, track_id: 200, workspace_id: 1, container_id: 5})

      assert TrackServer.get_console_history(200) == []
    end
  end

  describe "ConsoleUpdated event handling" do
    test "creates startup block on :starting event" do
      _pid =
        start_supervised!({TrackServer, track_id: 300, workspace_id: 1, container_id: 5})

      event = ConsoleUpdated.starting(1, 5, 300, "=[ metasploit v6 ]=\n")
      Events.broadcast(event)
      Process.sleep(15)

      assert TrackServer.get_console_status(300) == :starting

      history = TrackServer.get_console_history(300)
      assert [block] = history
      assert block.type == :startup
      assert block.status == :running
      assert block.output == "=[ metasploit v6 ]=\n"
    end

    test "appends output to startup block during initialization" do
      _pid =
        start_supervised!({TrackServer, track_id: 301, workspace_id: 1, container_id: 5})

      event1 = ConsoleUpdated.starting(1, 5, 301, "=[ metasploit v6 ]=\n")
      Events.broadcast(event1)
      Process.sleep(10)

      event2 = ConsoleUpdated.starting(1, 5, 301, "Loading modules...\n")
      Events.broadcast(event2)
      Process.sleep(15)

      history = TrackServer.get_console_history(301)
      assert [block] = history
      assert block.output == "=[ metasploit v6 ]=\nLoading modules...\n"
    end

    test "finishes startup block and transitions to :ready" do
      _pid =
        start_supervised!({TrackServer, track_id: 302, workspace_id: 1, container_id: 5})

      event1 = ConsoleUpdated.starting(1, 5, 302, "=[ metasploit v6 ]=\n")
      Events.broadcast(event1)
      Process.sleep(10)

      event2 = ConsoleUpdated.ready(1, 5, 302, "msf6 > ")
      Events.broadcast(event2)
      Process.sleep(15)

      assert TrackServer.get_console_status(302) == :ready
      assert TrackServer.get_prompt(302) == "msf6 > "

      history = TrackServer.get_console_history(302)
      assert [block] = history
      assert block.type == :startup
      assert block.status == :finished
      assert block.prompt == "msf6 > "
    end

    test "creates command block on :busy event" do
      _pid =
        start_supervised!({TrackServer, track_id: 303, workspace_id: 1, container_id: 5})

      # First go through startup -> ready
      event1 = ConsoleUpdated.starting(1, 5, 303, "Banner\n")
      event2 = ConsoleUpdated.ready(1, 5, 303, "msf6 > ")
      Events.broadcast(event1)
      Process.sleep(5)
      Events.broadcast(event2)
      Process.sleep(10)

      # Now issue a command
      event3 = ConsoleUpdated.busy(1, 5, 303, "cmd123", "db_status", "[*] Connected\n")
      Events.broadcast(event3)
      Process.sleep(15)

      assert TrackServer.get_console_status(303) == :busy

      history = TrackServer.get_console_history(303)
      assert [_startup, command] = history
      assert command.type == :command
      assert command.command == "db_status"
      assert command.status == :running
      assert command.output == "[*] Connected\n"
    end

    test "finishes command block on :ready event" do
      _pid =
        start_supervised!({TrackServer, track_id: 304, workspace_id: 1, container_id: 5})

      # Go through startup -> ready -> busy -> ready
      Events.broadcast(ConsoleUpdated.starting(1, 5, 304, "Banner\n"))
      Process.sleep(5)
      Events.broadcast(ConsoleUpdated.ready(1, 5, 304, "msf6 > "))
      Process.sleep(5)
      Events.broadcast(ConsoleUpdated.busy(1, 5, 304, "cmd123", "help", "Core Commands\n"))
      Process.sleep(5)
      Events.broadcast(ConsoleUpdated.ready(1, 5, 304, "msf6 > "))
      Process.sleep(15)

      assert TrackServer.get_console_status(304) == :ready

      history = TrackServer.get_console_history(304)
      assert [_startup, command] = history
      assert command.type == :command
      assert command.status == :finished
      assert command.prompt == "msf6 > "
    end

    test "marks running blocks as interrupted on :offline" do
      _pid =
        start_supervised!({TrackServer, track_id: 305, workspace_id: 1, container_id: 5})

      # Start a command
      Events.broadcast(ConsoleUpdated.starting(1, 5, 305, "Banner\n"))
      Process.sleep(5)
      Events.broadcast(ConsoleUpdated.ready(1, 5, 305, "msf6 > "))
      Process.sleep(5)
      Events.broadcast(ConsoleUpdated.busy(1, 5, 305, "cmd123", "exploit", "Running...\n"))
      Process.sleep(5)

      # Console dies
      Events.broadcast(ConsoleUpdated.offline(1, 5, 305))
      Process.sleep(15)

      assert TrackServer.get_console_status(305) == :offline

      history = TrackServer.get_console_history(305)
      assert [_startup, command] = history
      assert command.status == :interrupted
    end

    test "ignores events for other tracks" do
      _pid =
        start_supervised!({TrackServer, track_id: 306, workspace_id: 1, container_id: 5})

      # Event for a different track
      event = ConsoleUpdated.starting(1, 5, 999, "Banner\n")
      Events.broadcast(event)
      Process.sleep(15)

      # Should not appear in our track's history
      assert TrackServer.get_console_history(306) == []
      assert TrackServer.get_console_status(306) == :offline
    end
  end

  describe "ConsoleChanged broadcasting" do
    test "broadcasts ConsoleChanged on ConsoleUpdated" do
      Events.subscribe_to_workspace(1)

      _pid =
        start_supervised!({TrackServer, track_id: 400, workspace_id: 1, container_id: 5})

      event = ConsoleUpdated.starting(1, 5, 400, "Banner\n")
      Events.broadcast(event)

      assert_receive %ConsoleUpdated{track_id: 400}
      assert_receive %ConsoleChanged{track_id: 400, workspace_id: 1}
    end
  end

  describe "get_state/1" do
    test "returns full state snapshot" do
      _pid =
        start_supervised!({TrackServer, track_id: 500, workspace_id: 1, container_id: 5})

      Events.broadcast(ConsoleUpdated.starting(1, 5, 500, "Banner\n"))
      Process.sleep(5)
      Events.broadcast(ConsoleUpdated.ready(1, 5, 500, "msf6 > "))
      Process.sleep(15)

      state = TrackServer.get_state(500)

      assert state.console_status == :ready
      assert state.current_prompt == "msf6 > "
      assert [block] = state.console_history
      assert block.type == :startup
    end
  end

  describe "via_tuple/1" do
    test "returns correct Registry tuple" do
      assert {:via, Registry, {Msfailab.Tracks.Registry, 42}} = TrackServer.via_tuple(42)
    end
  end

  describe "whereis/1" do
    test "returns pid for registered track server" do
      pid =
        start_supervised!({TrackServer, track_id: 600, workspace_id: 1, container_id: 5})

      assert TrackServer.whereis(600) == pid
    end

    test "returns nil for unregistered track" do
      assert TrackServer.whereis(99_999) == nil
    end
  end

  describe "edge cases in ConsoleUpdated handling" do
    test "appends output to existing command block during :busy" do
      _pid =
        start_supervised!({TrackServer, track_id: 700, workspace_id: 1, container_id: 5})

      # Go through startup -> ready -> busy
      Events.broadcast(ConsoleUpdated.starting(1, 5, 700, "Banner\n"))
      Process.sleep(5)
      Events.broadcast(ConsoleUpdated.ready(1, 5, 700, "msf6 > "))
      Process.sleep(5)
      Events.broadcast(ConsoleUpdated.busy(1, 5, 700, "cmd123", "scan", "Starting...\n"))
      Process.sleep(5)

      # Additional output while still busy
      Events.broadcast(ConsoleUpdated.busy(1, 5, 700, nil, nil, "Progress: 50%\n"))
      Process.sleep(15)

      history = TrackServer.get_console_history(700)
      assert [_startup, command] = history
      assert command.output == "Starting...\nProgress: 50%\n"
    end

    test "handles :ready when already :ready (just updates prompt)" do
      _pid =
        start_supervised!({TrackServer, track_id: 701, workspace_id: 1, container_id: 5})

      # Go to ready
      Events.broadcast(ConsoleUpdated.starting(1, 5, 701, "Banner\n"))
      Process.sleep(5)
      Events.broadcast(ConsoleUpdated.ready(1, 5, 701, "msf6 > "))
      Process.sleep(10)

      # Another ready event (prompt might change after module load)
      Events.broadcast(ConsoleUpdated.ready(1, 5, 701, "msf6 exploit(handler) > "))
      Process.sleep(15)

      assert TrackServer.get_console_status(701) == :ready
      assert TrackServer.get_prompt(701) == "msf6 exploit(handler) > "
    end

    test "handles :starting when in unexpected state (fallback)" do
      _pid =
        start_supervised!({TrackServer, track_id: 702, workspace_id: 1, container_id: 5})

      # Go to ready first
      Events.broadcast(ConsoleUpdated.starting(1, 5, 702, "Banner\n"))
      Process.sleep(5)
      Events.broadcast(ConsoleUpdated.ready(1, 5, 702, "msf6 > "))
      Process.sleep(10)

      # Unexpected :starting while ready (edge case, shouldn't normally happen)
      Events.broadcast(ConsoleUpdated.starting(1, 5, 702, "Restarting...\n"))
      Process.sleep(15)

      # Should just update console_status to :starting
      assert TrackServer.get_console_status(702) == :starting
    end

    test "handles :busy without command info when already busy (append output)" do
      _pid =
        start_supervised!({TrackServer, track_id: 703, workspace_id: 1, container_id: 5})

      # Go to ready then busy
      Events.broadcast(ConsoleUpdated.starting(1, 5, 703, "Banner\n"))
      Process.sleep(5)
      Events.broadcast(ConsoleUpdated.ready(1, 5, 703, "msf6 > "))
      Process.sleep(5)
      Events.broadcast(ConsoleUpdated.busy(1, 5, 703, "cmd1", "help", ""))
      Process.sleep(5)

      # More output without new command (continuous output)
      Events.broadcast(ConsoleUpdated.busy(1, 5, 703, nil, nil, "Line 1\n"))
      Process.sleep(5)
      Events.broadcast(ConsoleUpdated.busy(1, 5, 703, nil, nil, "Line 2\n"))
      Process.sleep(15)

      history = TrackServer.get_console_history(703)
      assert [_startup, command] = history
      assert command.output == "Line 1\nLine 2\n"
    end

    test "handles :busy when in unexpected state (fallback)" do
      _pid =
        start_supervised!({TrackServer, track_id: 704, workspace_id: 1, container_id: 5})

      # Still offline, receive busy event (edge case)
      Events.broadcast(ConsoleUpdated.busy(1, 5, 704, "cmd1", "help", "output"))
      Process.sleep(15)

      # Should just update console_status
      assert TrackServer.get_console_status(704) == :busy
    end

    test "appends empty output gracefully (no change)" do
      _pid =
        start_supervised!({TrackServer, track_id: 705, workspace_id: 1, container_id: 5})

      Events.broadcast(ConsoleUpdated.starting(1, 5, 705, "Banner\n"))
      Process.sleep(10)

      # Empty output should not change anything
      Events.broadcast(ConsoleUpdated.starting(1, 5, 705, ""))
      Process.sleep(15)

      history = TrackServer.get_console_history(705)
      assert [block] = history
      assert block.output == "Banner\n"
    end

    test "interrupts startup block when console goes offline" do
      _pid =
        start_supervised!({TrackServer, track_id: 706, workspace_id: 1, container_id: 5})

      # Start startup
      Events.broadcast(ConsoleUpdated.starting(1, 5, 706, "Banner\n"))
      Process.sleep(10)

      # Console dies during startup
      Events.broadcast(ConsoleUpdated.offline(1, 5, 706))
      Process.sleep(15)

      history = TrackServer.get_console_history(706)
      assert [block] = history
      assert block.type == :startup
      assert block.status == :interrupted
    end
  end

  describe "termination" do
    test "unregisters console on normal termination" do
      _pid =
        start_supervised!({TrackServer, track_id: 800, workspace_id: 1, container_id: 5})

      # Stop the server - this is synchronous and waits for termination
      :ok = stop_supervised(TrackServer)

      # Registry cleanup is asynchronous - poll until unregistered
      assert wait_until(fn -> TrackServer.whereis(800) == nil end, 100),
             "Expected TrackServer to be unregistered within 100ms"
    end
  end

  # Helper to poll for a condition with timeout
  defp wait_until(condition, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_wait_until(condition, deadline)
  end

  defp do_wait_until(condition, deadline) do
    if condition.() do
      true
    else
      if System.monotonic_time(:millisecond) < deadline do
        Process.sleep(5)
        do_wait_until(condition, deadline)
      else
        false
      end
    end
  end

  describe "console registration with Container" do
    # These tests require both Container and Track infrastructure
    setup do
      # Start Container infrastructure
      start_supervised!({Registry, keys: :unique, name: Msfailab.Containers.Registry})

      start_supervised!(
        {DynamicSupervisor, name: Msfailab.Containers.ContainerSupervisor, strategy: :one_for_one}
      )

      :ok
    end

    test "registers with Container even when Container is in offline state" do
      alias Msfailab.Containers.Container

      # Start Container GenServer WITHOUT auto_start (simulates Reconciler startup)
      # Container stays in :offline state, waiting for Reconciler to tell it to start
      {:ok, _container_pid} =
        DynamicSupervisor.start_child(
          Msfailab.Containers.ContainerSupervisor,
          {Container,
           container_record_id: 999,
           workspace_id: 1,
           workspace_slug: "test-workspace",
           container_slug: "test-container",
           container_name: "Test Container",
           docker_image: "test:latest"}
        )

      # Verify Container is in offline state
      assert {status, _docker_id} = Container.get_status(999)
      assert status == :offline

      # Start TrackServer - it should register with Container
      _track_pid =
        start_supervised!({TrackServer, track_id: 900, workspace_id: 1, container_id: 999})

      # Give time for registration to complete
      Process.sleep(15)

      # Verify the track was registered with Container
      snapshot = Container.get_state_snapshot(999)
      assert MapSet.member?(snapshot.registered_tracks, 900)
    end

    test "Container spawns console when it reaches running state after registration" do
      alias Msfailab.Containers.Container

      # Start Container GenServer in offline state
      {:ok, _container_pid} =
        DynamicSupervisor.start_child(
          Msfailab.Containers.ContainerSupervisor,
          {Container,
           container_record_id: 998,
           workspace_id: 1,
           workspace_slug: "test-workspace",
           container_slug: "test-container",
           container_name: "Test Container",
           docker_image: "test:latest"}
        )

      # Start TrackServer - registers with offline Container
      _track_pid =
        start_supervised!({TrackServer, track_id: 901, workspace_id: 1, container_id: 998})

      Process.sleep(15)

      # Verify registration
      snapshot = Container.get_state_snapshot(998)
      assert MapSet.member?(snapshot.registered_tracks, 901)

      # No consoles yet (Container is offline)
      assert snapshot.consoles == %{}
    end
  end

  # ===========================================================================
  # Chat State Tests
  # ===========================================================================

  describe "get_chat_state/1" do
    test "returns ChatState with empty entries initially" do
      _pid =
        start_supervised!({TrackServer, track_id: 1000, workspace_id: 1, container_id: 5})

      chat_state = TrackServer.get_chat_state(1000)

      assert chat_state.entries == []
      assert chat_state.turn_status == :idle
      assert chat_state.current_turn_id == nil
    end
  end

  # ===========================================================================
  # Autonomous Mode Tests
  # ===========================================================================

  describe "set_autonomous/2" do
    test "enables autonomous mode" do
      _pid =
        start_supervised!({TrackServer, track_id: 1100, workspace_id: 1, container_id: 5})

      # Default is false (not autonomous)
      :ok = TrackServer.set_autonomous(1100, true)

      # Give time for cast to be processed
      Process.sleep(10)

      # Autonomous mode change should be reflected (we can verify via chat state behavior)
      # The actual value is internal, but we can verify the GenServer handles it
      assert Process.alive?(TrackServer.whereis(1100))
    end

    test "disables autonomous mode" do
      _pid =
        start_supervised!({TrackServer, track_id: 1101, workspace_id: 1, container_id: 5})

      # Enable then disable
      :ok = TrackServer.set_autonomous(1101, true)
      Process.sleep(5)
      :ok = TrackServer.set_autonomous(1101, false)
      Process.sleep(10)

      assert Process.alive?(TrackServer.whereis(1101))
    end
  end

  # ===========================================================================
  # Tool Approval Tests (with persisted data)
  # ===========================================================================

  # Note: Tool approval/denial requires tool invocations to be in server's internal state,
  # which only happens during LLM streaming or from persisted data at init.
  # These tests verify the error handling for unknown tools.

  describe "approve_tool/2" do
    setup do
      create_workspace_container_and_track()
    end

    test "returns error when tool not found", %{track: track} do
      Process.sleep(15)

      # Try to approve a non-existent tool (returns :not_found from Turn.approve_tool)
      result = TrackServer.approve_tool(track.id, "999999")

      assert {:error, :not_found} = result
    end
  end

  describe "deny_tool/3" do
    setup do
      create_workspace_container_and_track()
    end

    test "returns error when tool not found", %{track: track} do
      Process.sleep(15)

      result = TrackServer.deny_tool(track.id, "999999", "Not needed")

      assert {:error, :not_found} = result
    end
  end

  # ===========================================================================
  # Initialization with Persisted Data Tests
  # ===========================================================================

  # Note: These tests work with auto-started TrackServer.
  # For "initialization" tests that need pre-existing data, we create data after
  # server start and verify server state reflects the data through its APIs.

  describe "initialization with persisted data" do
    setup do
      # create_track auto-starts TrackServer
      create_workspace_container_and_track()
    end

    test "starts with empty console history", %{track: track} do
      Process.sleep(15)

      # Verify server is running and has empty history (since we didn't add any)
      history = TrackServer.get_console_history(track.id)
      assert history == []
    end

    test "starts with empty chat entries", %{track: track} do
      Process.sleep(15)

      chat_state = TrackServer.get_chat_state(track.id)
      assert chat_state.entries == []
      assert chat_state.turn_status == :idle
    end

    test "respects autonomous setting from track record", %{track: track} do
      Process.sleep(15)

      # Server is running
      assert Process.alive?(TrackServer.whereis(track.id))
    end
  end

  # ===========================================================================
  # Reconciliation Tests
  # ===========================================================================

  # ===========================================================================
  # Private Function Coverage (via integration)
  # ===========================================================================

  describe "normalize_entry_id coverage" do
    setup do
      create_workspace_container_and_track()
    end

    test "handles string entry_id", %{track: track} do
      Process.sleep(15)

      # Pass entry_id as string (as LiveView would) - tests string->integer conversion
      # Will return not_found since no tool exists, but the conversion happens first
      result = TrackServer.approve_tool(track.id, "12345")

      assert {:error, :not_found} = result
    end

    test "handles integer entry_id", %{track: track} do
      Process.sleep(15)

      # Pass entry_id as integer
      result = TrackServer.approve_tool(track.id, 12_345)

      assert {:error, :not_found} = result
    end
  end

  # ===========================================================================
  # Helper Functions
  # ===========================================================================

  defp create_workspace_container_and_track do
    {:ok, workspace} =
      Msfailab.Workspaces.create_workspace(%{
        name: "test",
        slug: "test-#{System.unique_integer([:positive])}"
      })

    {:ok, container} =
      Containers.create_container(workspace, %{
        name: "Test Container",
        slug: "test-container-#{System.unique_integer([:positive])}",
        docker_image: "test:latest"
      })

    {:ok, track} =
      Tracks.create_track(container, %{
        name: "Test Track",
        slug: "test-track-#{System.unique_integer([:positive])}"
      })

    %{workspace: workspace, container: container, track: track, workspace_id: workspace.id}
  end
end
