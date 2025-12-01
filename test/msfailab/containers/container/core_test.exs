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

defmodule Msfailab.Containers.Container.CoreTest do
  use ExUnit.Case, async: true

  alias Msfailab.Containers.Container.Core

  describe "calculate_backoff/3" do
    test "returns base_ms for first attempt" do
      assert Core.calculate_backoff(1, 1000, 60_000) == 1000
    end

    test "doubles for each subsequent attempt" do
      assert Core.calculate_backoff(2, 1000, 60_000) == 2000
      assert Core.calculate_backoff(3, 1000, 60_000) == 4000
      assert Core.calculate_backoff(4, 1000, 60_000) == 8000
    end

    test "caps at max_ms" do
      assert Core.calculate_backoff(10, 1000, 60_000) == 60_000
      assert Core.calculate_backoff(20, 1000, 60_000) == 60_000
    end

    test "handles edge case of attempt 0" do
      # Should still work (2^-1 = 0.5, rounds to 0 or 1)
      result = Core.calculate_backoff(0, 1000, 60_000)
      assert result <= 1000
    end
  end

  describe "find_console_by_ref/2" do
    test "returns {track_id, console_info} when found" do
      ref = make_ref()

      consoles = %{
        42 => %{pid: self(), ref: ref, status: :ready, prompt: "msf6 > "},
        43 => %{pid: self(), ref: make_ref(), status: :starting, prompt: ""}
      }

      assert {42, console_info} = Core.find_console_by_ref(consoles, ref)
      assert console_info.status == :ready
    end

    test "returns nil when not found" do
      ref = make_ref()
      consoles = %{42 => %{pid: self(), ref: make_ref(), status: :ready, prompt: ""}}

      assert Core.find_console_by_ref(consoles, ref) == nil
    end

    test "returns nil for empty consoles map" do
      assert Core.find_console_by_ref(%{}, make_ref()) == nil
    end
  end

  describe "find_bash_command_by_ref/2" do
    test "returns {command_id, bash_info} when found" do
      ref = make_ref()

      bash_commands = %{
        "cmd-123" => %{
          pid: self(),
          ref: ref,
          track_id: 42,
          command: %{},
          started_at: DateTime.utc_now()
        },
        "cmd-456" => %{
          pid: self(),
          ref: make_ref(),
          track_id: 43,
          command: %{},
          started_at: DateTime.utc_now()
        }
      }

      assert {"cmd-123", bash_info} = Core.find_bash_command_by_ref(bash_commands, ref)
      assert bash_info.track_id == 42
    end

    test "returns nil when not found" do
      ref = make_ref()

      bash_commands = %{
        "cmd-123" => %{
          pid: self(),
          ref: make_ref(),
          track_id: 42,
          command: %{},
          started_at: DateTime.utc_now()
        }
      }

      assert Core.find_bash_command_by_ref(bash_commands, ref) == nil
    end

    test "returns nil for empty bash_commands map" do
      assert Core.find_bash_command_by_ref(%{}, make_ref()) == nil
    end
  end

  describe "validate_console_for_command/2" do
    test "returns error when container not running" do
      state = %{
        status: :starting,
        registered_tracks: MapSet.new([42]),
        consoles: %{}
      }

      assert {:error, :container_not_running} = Core.validate_console_for_command(state, 42)
    end

    test "returns error when container offline" do
      state = %{
        status: :offline,
        registered_tracks: MapSet.new([42]),
        consoles: %{}
      }

      assert {:error, :container_not_running} = Core.validate_console_for_command(state, 42)
    end

    test "returns error when console not registered" do
      state = %{
        status: :running,
        registered_tracks: MapSet.new([99]),
        consoles: %{}
      }

      assert {:error, :console_not_registered} = Core.validate_console_for_command(state, 42)
    end

    test "returns error when console offline" do
      state = %{
        status: :running,
        registered_tracks: MapSet.new([42]),
        consoles: %{42 => %{pid: nil, ref: nil, status: :offline, prompt: ""}}
      }

      assert {:error, :console_offline} = Core.validate_console_for_command(state, 42)
    end

    test "returns ok with pid when console process exists" do
      pid = self()

      state = %{
        status: :running,
        registered_tracks: MapSet.new([42]),
        consoles: %{42 => %{pid: pid, ref: make_ref(), restart_attempts: 0, last_restart_at: nil}}
      }

      # Returns pid - caller forwards to Console which returns status-specific errors
      assert {:ok, ^pid} = Core.validate_console_for_command(state, 42)
    end
  end

  describe "get_console_pid/2" do
    test "returns error for nil console" do
      assert {:error, :console_offline} = Core.get_console_pid(%{}, 42)
    end

    test "returns error for console with nil pid" do
      consoles = %{42 => %{pid: nil, ref: nil, restart_attempts: 0, last_restart_at: nil}}
      assert {:error, :console_offline} = Core.get_console_pid(consoles, 42)
    end

    test "returns ok with pid when console process exists" do
      pid = self()
      consoles = %{42 => %{pid: pid, ref: make_ref(), restart_attempts: 0, last_restart_at: nil}}
      assert {:ok, ^pid} = Core.get_console_pid(consoles, 42)
    end
  end

  describe "should_restart?/2" do
    test "returns true when below max" do
      assert Core.should_restart?(0, 5)
      assert Core.should_restart?(4, 5)
    end

    test "returns false when at or above max" do
      refute Core.should_restart?(5, 5)
      refute Core.should_restart?(6, 5)
    end
  end

  describe "should_retry_msgrpc?/2" do
    test "returns true when below max attempts" do
      assert Core.should_retry_msgrpc?(0, 10)
      assert Core.should_retry_msgrpc?(9, 10)
    end

    test "returns false when at or above max attempts" do
      refute Core.should_retry_msgrpc?(10, 10)
      refute Core.should_retry_msgrpc?(15, 10)
    end
  end

  describe "should_restart_console?/4" do
    test "returns true when all conditions met" do
      registered_tracks = MapSet.new([42])
      assert Core.should_restart_console?(registered_tracks, :running, 0, 10)
    end

    test "returns false when no registered tracks" do
      refute Core.should_restart_console?(MapSet.new(), :running, 0, 10)
    end

    test "returns false when container not running" do
      registered_tracks = MapSet.new([42])
      refute Core.should_restart_console?(registered_tracks, :starting, 0, 10)
      refute Core.should_restart_console?(registered_tracks, :offline, 0, 10)
    end

    test "returns false when max attempts exceeded" do
      registered_tracks = MapSet.new([42])
      refute Core.should_restart_console?(registered_tracks, :running, 10, 10)
    end
  end

  describe "build_container_labels/3" do
    test "returns correct labels map" do
      labels = Core.build_container_labels(123, "my-workspace", "my-container")

      assert labels == %{
               "msfailab.managed" => "true",
               "msfailab.container_id" => "123",
               "msfailab.workspace_slug" => "my-workspace",
               "msfailab.container_slug" => "my-container"
             }
    end
  end

  describe "container_name/2" do
    test "generates correct container name" do
      assert Core.container_name("workspace", "container") == "msfailab-workspace-container"
    end

    test "handles special characters in slugs" do
      assert Core.container_name("work-space", "con-tainer") == "msfailab-work-space-con-tainer"
    end
  end

  describe "new_console_info/2" do
    test "creates correct initial console info" do
      pid = self()
      ref = make_ref()

      info = Core.new_console_info(pid, ref)

      assert info.pid == pid
      assert info.ref == ref
      assert info.restart_attempts == 0
      assert info.last_restart_at == nil
    end
  end

  describe "console_info_pending_restart/1" do
    test "creates console info with restart tracking" do
      info = Core.console_info_pending_restart(3)

      assert info.pid == nil
      assert info.ref == nil
      assert info.restart_attempts == 3
      assert %DateTime{} = info.last_restart_at
    end
  end
end
