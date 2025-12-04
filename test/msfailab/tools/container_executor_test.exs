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

defmodule Msfailab.Tools.ContainerExecutorTest do
  use ExUnit.Case, async: true

  alias Msfailab.Tools.ContainerExecutor

  describe "handles_tool?/1" do
    test "returns true for msf_command" do
      assert ContainerExecutor.handles_tool?("msf_command")
    end

    test "returns true for bash_command" do
      assert ContainerExecutor.handles_tool?("bash_command")
    end

    test "returns false for other tools" do
      refute ContainerExecutor.handles_tool?("list_hosts")
      refute ContainerExecutor.handles_tool?("read_memory")
      refute ContainerExecutor.handles_tool?("unknown_tool")
      refute ContainerExecutor.handles_tool?("create_note")
    end
  end

  describe "execute/3 - msf_command argument validation" do
    test "returns error for missing command parameter" do
      context = %{container_id: 1, track_id: 1}

      assert {:error, "Missing required parameter: command"} =
               ContainerExecutor.execute("msf_command", %{}, context)
    end

    test "returns error when command key has wrong name" do
      context = %{container_id: 1, track_id: 1}

      assert {:error, "Missing required parameter: command"} =
               ContainerExecutor.execute("msf_command", %{"cmd" => "help"}, context)
    end
  end

  describe "execute/3 - bash_command argument validation" do
    test "returns error for missing command parameter" do
      context = %{container_id: 1, track_id: 1}

      assert {:error, "Missing required parameter: command"} =
               ContainerExecutor.execute("bash_command", %{}, context)
    end

    test "returns error when command key has wrong name" do
      context = %{container_id: 1, track_id: 1}

      assert {:error, "Missing required parameter: command"} =
               ContainerExecutor.execute("bash_command", %{"cmd" => "ls"}, context)
    end
  end

  describe "retry_timing/0" do
    test "returns default timing when no config" do
      timing = ContainerExecutor.retry_timing()

      assert timing.initial_delay == 100
      assert timing.max_delay == 2_000
      assert timing.max_wait_time == 60_000
    end

    test "merges custom timing overrides from application config" do
      Application.put_env(:msfailab, :container_executor_timing, %{initial_delay: 50})

      try do
        timing = ContainerExecutor.retry_timing()

        assert timing.initial_delay == 50
        assert timing.max_delay == 2_000
        assert timing.max_wait_time == 60_000
      after
        Application.delete_env(:msfailab, :container_executor_timing)
      end
    end

    test "ignores non-map config values" do
      Application.put_env(:msfailab, :container_executor_timing, "invalid")

      try do
        timing = ContainerExecutor.retry_timing()

        # Falls back to defaults
        assert timing.initial_delay == 100
        assert timing.max_delay == 2_000
        assert timing.max_wait_time == 60_000
      after
        Application.delete_env(:msfailab, :container_executor_timing)
      end
    end
  end

  describe "retry_until_ready/2" do
    test "returns async immediately on success" do
      timing = %{initial_delay: 1, max_delay: 10, max_wait_time: 100}
      try_fn = fn -> {:ok, "cmd-123"} end

      assert {:async, "cmd-123"} = ContainerExecutor.retry_until_ready(try_fn, timing)
    end

    test "returns error immediately on permanent error" do
      timing = %{initial_delay: 1, max_delay: 10, max_wait_time: 100}
      try_fn = fn -> {:error, :container_not_running} end

      assert {:error, :container_not_running} =
               ContainerExecutor.retry_until_ready(try_fn, timing)
    end

    test "retries on console_starting and succeeds" do
      timing = %{initial_delay: 1, max_delay: 10, max_wait_time: 100}

      # Use Agent to track call count
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      try_fn = fn ->
        count = Agent.get_and_update(agent, fn c -> {c, c + 1} end)

        if count < 2 do
          {:error, :console_starting}
        else
          {:ok, "cmd-after-retry"}
        end
      end

      assert {:async, "cmd-after-retry"} = ContainerExecutor.retry_until_ready(try_fn, timing)

      # Verify we retried
      assert Agent.get(agent, & &1) == 3
      Agent.stop(agent)
    end

    test "retries on console_busy and succeeds" do
      timing = %{initial_delay: 1, max_delay: 10, max_wait_time: 100}

      {:ok, agent} = Agent.start_link(fn -> 0 end)

      try_fn = fn ->
        count = Agent.get_and_update(agent, fn c -> {c, c + 1} end)

        if count < 1 do
          {:error, :console_busy}
        else
          {:ok, "cmd-after-busy"}
        end
      end

      assert {:async, "cmd-after-busy"} = ContainerExecutor.retry_until_ready(try_fn, timing)

      assert Agent.get(agent, & &1) == 2
      Agent.stop(agent)
    end

    test "times out when console never becomes ready" do
      # Very short timeout for fast test
      timing = %{initial_delay: 1, max_delay: 5, max_wait_time: 10}
      try_fn = fn -> {:error, :console_starting} end

      assert {:error, :console_wait_timeout} =
               ContainerExecutor.retry_until_ready(try_fn, timing)
    end

    test "uses exponential backoff up to max_delay" do
      timing = %{initial_delay: 1, max_delay: 4, max_wait_time: 100}

      {:ok, agent} = Agent.start_link(fn -> [] end)

      try_fn = fn ->
        now = System.monotonic_time(:millisecond)
        Agent.update(agent, fn times -> times ++ [now] end)
        {:error, :console_busy}
      end

      # This will timeout, but we can check the retry pattern
      ContainerExecutor.retry_until_ready(try_fn, timing)

      times = Agent.get(agent, & &1)
      Agent.stop(agent)

      # Should have multiple calls due to retries
      assert length(times) > 1
    end
  end
end
