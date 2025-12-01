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

defmodule Msfailab.Containers.Msgrpc.ConsoleTest do
  use ExUnit.Case, async: false

  import Mox

  alias Msfailab.Containers.Msgrpc.ClientMock, as: MsgrpcClientMock
  alias Msfailab.Containers.Msgrpc.Console
  alias Msfailab.Events
  alias Msfailab.Events.ConsoleUpdated

  @endpoint %{host: "localhost", port: 55_553}
  @token "test-token-123"
  @console_id "1"

  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    # Configure fast timing for tests to minimize Process.sleep waits
    Application.put_env(:msfailab, :console_timing,
      poll_interval_ms: 5,
      keepalive_interval_ms: 50,
      max_retries: 3,
      retry_delays_ms: [5, 10, 20]
    )

    on_exit(fn ->
      Application.delete_env(:msfailab, :console_timing)
    end)

    # Stub console_destroy since terminate/2 always calls cleanup_console
    stub(MsgrpcClientMock, :console_destroy, fn _, _, _ -> :ok end)
    :ok
  end

  defp default_opts do
    [
      endpoint: @endpoint,
      token: @token,
      workspace_id: 1,
      container_id: 2,
      track_id: 10
    ]
  end

  describe "start_link/1 and init/1" do
    test "starts Console GenServer and creates MSGRPC console" do
      Events.subscribe_to_workspace(1)

      expect(MsgrpcClientMock, :console_create, fn endpoint, token ->
        assert endpoint == @endpoint
        assert token == @token
        {:ok, %{"id" => @console_id}}
      end)

      # Console will poll and transition to ready
      expect(MsgrpcClientMock, :console_read, fn _endpoint, _token, console_id ->
        assert console_id == @console_id
        {:ok, %{"data" => "", "busy" => false, "prompt" => "msf6 > "}}
      end)

      {:ok, pid} = Console.start_link(default_opts())
      assert Process.alive?(pid)

      # Wait for initialization (with fast timing: poll_interval=5ms)
      Process.sleep(20)

      assert Console.get_status(pid) == :ready
      assert Console.get_prompt(pid) == "msf6 > "

      # Should have received ConsoleUpdated event
      assert_receive %ConsoleUpdated{track_id: 10, status: :ready, prompt: "msf6 > "}
    end

    test "broadcasts :starting events during initialization" do
      Events.subscribe_to_workspace(1)

      expect(MsgrpcClientMock, :console_create, fn _, _ ->
        {:ok, %{"id" => @console_id}}
      end)

      # First poll - busy with startup output
      expect(MsgrpcClientMock, :console_read, fn _, _, _ ->
        {:ok, %{"data" => "=[ metasploit v6 ]=\n", "busy" => true, "prompt" => ""}}
      end)

      # Second poll - still busy
      expect(MsgrpcClientMock, :console_read, fn _, _, _ ->
        {:ok, %{"data" => "Loading modules...\n", "busy" => true, "prompt" => ""}}
      end)

      # Third poll - ready
      expect(MsgrpcClientMock, :console_read, fn _, _, _ ->
        {:ok, %{"data" => "", "busy" => false, "prompt" => "msf6 > "}}
      end)

      {:ok, _pid} = Console.start_link(default_opts())

      # Wait for initialization (3 polls with fast timing: ~3*5ms)
      Process.sleep(30)

      # Should receive starting events then ready
      assert_receive %ConsoleUpdated{status: :starting, output: "=[ metasploit v6 ]=\n"}
      assert_receive %ConsoleUpdated{status: :starting, output: "Loading modules...\n"}
      assert_receive %ConsoleUpdated{status: :ready, prompt: "msf6 > "}
    end
  end

  describe "send_command/2" do
    setup do
      expect(MsgrpcClientMock, :console_create, fn _, _ ->
        {:ok, %{"id" => @console_id}}
      end)

      expect(MsgrpcClientMock, :console_read, fn _, _, _ ->
        {:ok, %{"data" => "", "busy" => false, "prompt" => "msf6 > "}}
      end)

      {:ok, pid} = Console.start_link(default_opts())
      Process.sleep(20)

      %{pid: pid}
    end

    test "sends command and transitions to :busy", %{pid: pid} do
      Events.subscribe_to_workspace(1)

      expect(MsgrpcClientMock, :console_write, fn _endpoint, _token, console_id, data ->
        assert console_id == @console_id
        assert data == "db_status\n"
        {:ok, 10}
      end)

      # Poll returns busy with output
      expect(MsgrpcClientMock, :console_read, fn _, _, _ ->
        {:ok, %{"data" => "[*] Connected\n", "busy" => true, "prompt" => ""}}
      end)

      # Poll returns ready
      expect(MsgrpcClientMock, :console_read, fn _, _, _ ->
        {:ok, %{"data" => "", "busy" => false, "prompt" => "msf6 > "}}
      end)

      assert {:ok, command_id} = Console.send_command(pid, "db_status")
      assert is_binary(command_id)
      assert String.length(command_id) == 16

      # Wait for command execution (2 polls with fast timing)
      Process.sleep(25)

      assert Console.get_status(pid) == :ready

      # Should receive busy event with command info
      assert_receive %ConsoleUpdated{
        status: :busy,
        command_id: ^command_id,
        command: "db_status"
      }
    end

    test "returns {:error, :busy} when command in progress", %{pid: pid} do
      expect(MsgrpcClientMock, :console_write, fn _, _, _, _ -> {:ok, 10} end)

      # Make the command hang (busy stays true)
      stub(MsgrpcClientMock, :console_read, fn _, _, _ ->
        {:ok, %{"data" => "", "busy" => true, "prompt" => ""}}
      end)

      {:ok, _cmd_id} = Console.send_command(pid, "exploit")
      Process.sleep(10)

      assert {:error, :busy} = Console.send_command(pid, "another_command")
    end

    test "returns {:error, :starting} when console still initializing" do
      expect(MsgrpcClientMock, :console_create, fn _, _ ->
        {:ok, %{"id" => @console_id}}
      end)

      # Keep polling with busy=true to stay in :starting
      stub(MsgrpcClientMock, :console_read, fn _, _, _ ->
        {:ok, %{"data" => "Loading...\n", "busy" => true, "prompt" => ""}}
      end)

      {:ok, pid} = Console.start_link(default_opts())
      Process.sleep(10)

      assert {:error, :starting} = Console.send_command(pid, "help")
    end
  end

  describe "get_status/1 and get_prompt/1" do
    test "returns current status and prompt" do
      expect(MsgrpcClientMock, :console_create, fn _, _ ->
        {:ok, %{"id" => @console_id}}
      end)

      expect(MsgrpcClientMock, :console_read, fn _, _, _ ->
        {:ok, %{"data" => "", "busy" => false, "prompt" => "msf6 exploit(handler) > "}}
      end)

      {:ok, pid} = Console.start_link(default_opts())
      Process.sleep(20)

      assert Console.get_status(pid) == :ready
      assert Console.get_prompt(pid) == "msf6 exploit(handler) > "
    end
  end

  describe "go_offline/1" do
    test "gracefully stops console and destroys session" do
      expect(MsgrpcClientMock, :console_create, fn _, _ ->
        {:ok, %{"id" => @console_id}}
      end)

      expect(MsgrpcClientMock, :console_read, fn _, _, _ ->
        {:ok, %{"data" => "", "busy" => false, "prompt" => "msf6 > "}}
      end)

      {:ok, pid} = Console.start_link(default_opts())
      Process.sleep(20)

      ref = Process.monitor(pid)
      Console.go_offline(pid)

      # Should stop normally (console_destroy is stubbed globally)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
    end
  end

  describe "error handling" do
    test "stops on console_create failure" do
      # Trap exits to avoid test process crashing
      Process.flag(:trap_exit, true)

      expect(MsgrpcClientMock, :console_create, fn _, _ ->
        {:error, {:console_create_failed, "connection refused"}}
      end)

      {:ok, pid} = Console.start_link(default_opts())

      assert_receive {:EXIT, ^pid, {:console_create_failed, _}}
    end

    test "retries on transient console_read failure then recovers" do
      expect(MsgrpcClientMock, :console_create, fn _, _ ->
        {:ok, %{"id" => @console_id}}
      end)

      # First read fails
      expect(MsgrpcClientMock, :console_read, fn _, _, _ ->
        {:error, {:request_failed, :timeout}}
      end)

      # Retry succeeds
      expect(MsgrpcClientMock, :console_read, fn _, _, _ ->
        {:ok, %{"data" => "", "busy" => false, "prompt" => "msf6 > "}}
      end)

      {:ok, pid} = Console.start_link(default_opts())
      # Wait for retry (5ms delay) + successful poll (5ms) + processing
      Process.sleep(30)

      # Should have recovered
      assert Console.get_status(pid) == :ready
    end

    test "stops after max retries on persistent console_read failure" do
      # Trap exits to avoid test process crashing
      Process.flag(:trap_exit, true)

      expect(MsgrpcClientMock, :console_create, fn _, _ ->
        {:ok, %{"id" => @console_id}}
      end)

      # All reads fail (max_retries = 3)
      expect(MsgrpcClientMock, :console_read, 4, fn _, _, _ ->
        {:error, {:request_failed, :timeout}}
      end)

      {:ok, pid} = Console.start_link(default_opts())

      # Should stop after retries exhausted (5ms + 10ms + 20ms delays + processing)
      assert_receive {:EXIT, ^pid, {:console_read_failed, _}}, 200
    end
  end

  describe "state transitions" do
    test "transitions through startup -> ready -> busy -> ready" do
      Events.subscribe_to_workspace(1)

      expect(MsgrpcClientMock, :console_create, fn _, _ ->
        {:ok, %{"id" => @console_id}}
      end)

      # Startup polling
      expect(MsgrpcClientMock, :console_read, fn _, _, _ ->
        {:ok, %{"data" => "Banner\n", "busy" => true, "prompt" => ""}}
      end)

      expect(MsgrpcClientMock, :console_read, fn _, _, _ ->
        {:ok, %{"data" => "", "busy" => false, "prompt" => "msf6 > "}}
      end)

      {:ok, pid} = Console.start_link(default_opts())
      # Wait for startup polling (2 polls with fast timing)
      Process.sleep(25)

      assert Console.get_status(pid) == :ready

      # Now send a command
      expect(MsgrpcClientMock, :console_write, fn _, _, _, _ -> {:ok, 5} end)

      expect(MsgrpcClientMock, :console_read, fn _, _, _ ->
        {:ok, %{"data" => "Help output\n", "busy" => true, "prompt" => ""}}
      end)

      expect(MsgrpcClientMock, :console_read, fn _, _, _ ->
        {:ok, %{"data" => "", "busy" => false, "prompt" => "msf6 > "}}
      end)

      {:ok, _cmd_id} = Console.send_command(pid, "help")
      # Wait for command execution (2 polls with fast timing)
      Process.sleep(25)

      assert Console.get_status(pid) == :ready

      # Verify we received all expected events
      assert_receive %ConsoleUpdated{status: :starting}
      assert_receive %ConsoleUpdated{status: :ready}
      assert_receive %ConsoleUpdated{status: :busy}
      assert_receive %ConsoleUpdated{status: :busy, output: "Help output\n"}
      assert_receive %ConsoleUpdated{status: :ready}
    end
  end

  describe "output accumulation during command" do
    test "accumulates output chunks during busy state" do
      Events.subscribe_to_workspace(1)

      expect(MsgrpcClientMock, :console_create, fn _, _ ->
        {:ok, %{"id" => @console_id}}
      end)

      expect(MsgrpcClientMock, :console_read, fn _, _, _ ->
        {:ok, %{"data" => "", "busy" => false, "prompt" => "msf6 > "}}
      end)

      {:ok, pid} = Console.start_link(default_opts())
      Process.sleep(20)

      # Command execution with multiple output chunks
      expect(MsgrpcClientMock, :console_write, fn _, _, _, _ -> {:ok, 5} end)

      expect(MsgrpcClientMock, :console_read, fn _, _, _ ->
        {:ok, %{"data" => "Chunk 1\n", "busy" => true, "prompt" => ""}}
      end)

      expect(MsgrpcClientMock, :console_read, fn _, _, _ ->
        {:ok, %{"data" => "Chunk 2\n", "busy" => true, "prompt" => ""}}
      end)

      expect(MsgrpcClientMock, :console_read, fn _, _, _ ->
        {:ok, %{"data" => "", "busy" => false, "prompt" => "msf6 > "}}
      end)

      {:ok, _cmd_id} = Console.send_command(pid, "scan")
      # Wait for command execution (3 polls with fast timing)
      Process.sleep(30)

      # Each chunk should be broadcast separately
      assert_receive %ConsoleUpdated{status: :busy, output: "Chunk 1\n"}
      assert_receive %ConsoleUpdated{status: :busy, output: "Chunk 2\n"}
      assert_receive %ConsoleUpdated{status: :ready}
    end
  end

  describe "keepalive" do
    # Uses fast timing from main setup: keepalive_interval_ms: 50

    test "performs keepalive read when idle in :ready state" do
      expect(MsgrpcClientMock, :console_create, fn _, _ ->
        {:ok, %{"id" => @console_id}}
      end)

      # Initial read to transition to ready
      expect(MsgrpcClientMock, :console_read, fn _, _, _ ->
        {:ok, %{"data" => "", "busy" => false, "prompt" => "msf6 > "}}
      end)

      # Keepalive read
      expect(MsgrpcClientMock, :console_read, fn _, _, _ ->
        {:ok, %{"data" => "", "busy" => false, "prompt" => "msf6 > "}}
      end)

      {:ok, pid} = Console.start_link(default_opts())
      # Wait for initialization (20ms) + keepalive interval (50ms) + processing
      Process.sleep(90)

      # Should still be alive and ready after keepalive
      assert Process.alive?(pid)
      assert Console.get_status(pid) == :ready
    end

    test "stops on keepalive failure" do
      Process.flag(:trap_exit, true)

      expect(MsgrpcClientMock, :console_create, fn _, _ ->
        {:ok, %{"id" => @console_id}}
      end)

      # Initial read to transition to ready
      expect(MsgrpcClientMock, :console_read, fn _, _, _ ->
        {:ok, %{"data" => "", "busy" => false, "prompt" => "msf6 > "}}
      end)

      # Keepalive read fails (e.g., token expired)
      expect(MsgrpcClientMock, :console_read, fn _, _, _ ->
        {:error, {:console_read_failed, "Invalid Authentication Token"}}
      end)

      {:ok, pid} = Console.start_link(default_opts())

      # Should stop after keepalive failure (init 20ms + keepalive 50ms + processing)
      assert_receive {:EXIT, ^pid, {:keepalive_failed, _}}, 200
    end
  end

  describe "console_write failure" do
    test "stops process and returns {:error, :write_failed}" do
      Process.flag(:trap_exit, true)

      expect(MsgrpcClientMock, :console_create, fn _, _ ->
        {:ok, %{"id" => @console_id}}
      end)

      expect(MsgrpcClientMock, :console_read, fn _, _, _ ->
        {:ok, %{"data" => "", "busy" => false, "prompt" => "msf6 > "}}
      end)

      {:ok, pid} = Console.start_link(default_opts())
      Process.sleep(20)

      # Write fails (e.g., token expired)
      expect(MsgrpcClientMock, :console_write, fn _, _, _, _ ->
        {:error, {:console_write_failed, "Invalid Authentication Token"}}
      end)

      assert {:error, :write_failed} = Console.send_command(pid, "help")

      # Process should stop
      assert_receive {:EXIT, ^pid, {:console_write_failed, _}}, 100
    end
  end
end
