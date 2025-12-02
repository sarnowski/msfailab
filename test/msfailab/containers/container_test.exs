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

defmodule Msfailab.Containers.ContainerTest do
  use Msfailab.ContainersCase, async: false

  alias Msfailab.Containers.Container
  alias Msfailab.Events
  alias Msfailab.Events.WorkspaceChanged

  # By default, keep containers in :starting state by failing MSGRPC login.
  # Tests that need to test :running state should override this stub.
  setup do
    stub(MsgrpcClientMock, :login, fn _endpoint, _password, _username ->
      {:error, {:auth_failed, "test stub"}}
    end)

    :ok
  end

  describe "start_link/1" do
    test "starts container on init and becomes :starting" do
      expect(DockerAdapterMock, :start_container, fn name, labels ->
        assert name == "msfailab-test-workspace-test-container"
        assert labels["msfailab.managed"] == "true"
        assert labels["msfailab.container_id"] == "123"
        assert labels["msfailab.workspace_slug"] == "test-workspace"
        assert labels["msfailab.container_slug"] == "test-container"
        {:ok, "container_abc123"}
      end)

      expect(DockerAdapterMock, :get_rpc_endpoint, fn "container_abc123" ->
        {:ok, %{host: "localhost", port: 55_553}}
      end)

      pid =
        start_supervised!(
          {Container,
           container_record_id: 123,
           workspace_id: 1,
           workspace_slug: "test-workspace",
           container_slug: "test-container",
           container_name: "Test Container",
           docker_image: "test:latest",
           auto_start: true}
        )

      # Wait for async container start (fast timing: msgrpc_initial_delay=5ms)
      Process.sleep(20)

      assert Process.alive?(pid)
      # Container stays :starting until MSGRPC auth completes
      assert {status, container_id} = Container.get_status(123)
      assert status == :starting
      assert container_id == "container_abc123"
    end

    test "adopts existing container when docker_container_id is provided" do
      expect(DockerAdapterMock, :container_running?, fn "existing_container" ->
        true
      end)

      expect(DockerAdapterMock, :get_rpc_endpoint, fn "existing_container" ->
        {:ok, %{host: "localhost", port: 55_553}}
      end)

      pid =
        start_supervised!(
          {Container,
           container_record_id: 456,
           workspace_id: 1,
           workspace_slug: "test-workspace",
           container_slug: "test-container",
           container_name: "Test Container",
           docker_image: "test:latest",
           docker_container_id: "existing_container"}
        )

      # Wait for async container start (fast timing)
      Process.sleep(20)

      assert Process.alive?(pid)
      # Container stays :starting until MSGRPC auth completes
      assert {status, container_id} = Container.get_status(456)
      assert status == :starting
      assert container_id == "existing_container"
    end

    test "starts new container when adopted container is not running" do
      expect(DockerAdapterMock, :container_running?, fn "dead_container" ->
        false
      end)

      expect(DockerAdapterMock, :start_container, fn _name, _labels ->
        {:ok, "new_container_123"}
      end)

      expect(DockerAdapterMock, :get_rpc_endpoint, fn "new_container_123" ->
        {:ok, %{host: "localhost", port: 55_553}}
      end)

      _pid =
        start_supervised!(
          {Container,
           container_record_id: 789,
           workspace_id: 1,
           workspace_slug: "test-workspace",
           container_slug: "test-container",
           container_name: "Test Container",
           docker_image: "test:latest",
           docker_container_id: "dead_container"}
        )

      # Wait for async container start (fast timing)
      Process.sleep(20)

      # Container stays :starting until MSGRPC auth completes
      assert {status, container_id} = Container.get_status(789)
      assert status == :starting
      assert container_id == "new_container_123"
    end
  end

  describe "get_status/1" do
    test "returns status and container_id" do
      expect(DockerAdapterMock, :start_container, fn _name, _labels ->
        {:ok, "status_test_container"}
      end)

      expect(DockerAdapterMock, :get_rpc_endpoint, fn "status_test_container" ->
        {:ok, %{host: "localhost", port: 55_553}}
      end)

      _pid =
        start_supervised!(
          {Container,
           container_record_id: 100,
           workspace_id: 1,
           workspace_slug: "ws",
           container_slug: "container",
           container_name: "Test Container",
           docker_image: "test:latest",
           auto_start: true}
        )

      Process.sleep(20)

      assert {status, container_id} = Container.get_status(100)
      # Container stays :starting until MSGRPC auth completes
      assert status == :starting
      assert container_id == "status_test_container"
    end
  end

  describe "register_console/2 and unregister_console/2" do
    test "register returns ok and tracks the track_id" do
      expect(DockerAdapterMock, :start_container, fn _name, _labels ->
        {:ok, "reg_container"}
      end)

      expect(DockerAdapterMock, :get_rpc_endpoint, fn "reg_container" ->
        {:ok, %{host: "localhost", port: 55_553}}
      end)

      _pid =
        start_supervised!(
          {Container,
           container_record_id: 500,
           workspace_id: 1,
           workspace_slug: "ws",
           container_slug: "container",
           container_name: "Test Container",
           docker_image: "test:latest",
           auto_start: true}
        )

      Process.sleep(20)

      # Register a console
      assert :ok = Container.register_console(500, 42)

      # Check state snapshot shows registered track
      snapshot = Container.get_state_snapshot(500)
      assert MapSet.member?(snapshot.registered_tracks, 42)
    end

    test "unregister removes track from registered_tracks" do
      expect(DockerAdapterMock, :start_container, fn _name, _labels ->
        {:ok, "unreg_container"}
      end)

      expect(DockerAdapterMock, :get_rpc_endpoint, fn "unreg_container" ->
        {:ok, %{host: "localhost", port: 55_553}}
      end)

      _pid =
        start_supervised!(
          {Container,
           container_record_id: 501,
           workspace_id: 1,
           workspace_slug: "ws",
           container_slug: "container",
           container_name: "Test Container",
           docker_image: "test:latest",
           auto_start: true}
        )

      Process.sleep(20)

      # Register and then unregister
      assert :ok = Container.register_console(501, 42)
      assert :ok = Container.unregister_console(501, 42)

      # Check state snapshot shows track is no longer registered
      snapshot = Container.get_state_snapshot(501)
      refute MapSet.member?(snapshot.registered_tracks, 42)
    end
  end

  describe "send_metasploit_command/3" do
    test "returns error when console not registered" do
      expect(DockerAdapterMock, :start_container, fn _name, _labels ->
        {:ok, "cmd_container"}
      end)

      expect(DockerAdapterMock, :get_rpc_endpoint, fn "cmd_container" ->
        {:ok, %{host: "localhost", port: 55_553}}
      end)

      _pid =
        start_supervised!(
          {Container,
           container_record_id: 200,
           workspace_id: 1,
           workspace_slug: "ws",
           container_slug: "container",
           container_name: "Test Container",
           docker_image: "test:latest",
           auto_start: true}
        )

      Process.sleep(20)

      # Container is :starting (not :running) until MSGRPC auth
      assert {:error, :container_not_running} =
               Container.send_metasploit_command(200, 42, "use exploit/test")
    end
  end

  describe "send_bash_command/3" do
    test "returns error when container not running" do
      expect(DockerAdapterMock, :start_container, fn _name, _labels ->
        {:ok, "bash_container"}
      end)

      expect(DockerAdapterMock, :get_rpc_endpoint, fn "bash_container" ->
        {:ok, %{host: "localhost", port: 55_553}}
      end)

      _pid =
        start_supervised!(
          {Container,
           container_record_id: 300,
           workspace_id: 1,
           workspace_slug: "ws",
           container_slug: "container",
           container_name: "Test Container",
           docker_image: "test:latest",
           auto_start: true}
        )

      Process.sleep(20)

      # Container is :starting (not :running) until MSGRPC auth
      assert {:error, :container_not_running} =
               Container.send_bash_command(300, 42, "whoami")
    end
  end

  describe "terminate/2" do
    test "stops container when process terminates" do
      expect(DockerAdapterMock, :start_container, fn _name, _labels ->
        {:ok, "terminate_container"}
      end)

      expect(DockerAdapterMock, :get_rpc_endpoint, fn "terminate_container" ->
        {:ok, %{host: "localhost", port: 55_553}}
      end)

      expect(DockerAdapterMock, :stop_container, fn "terminate_container" ->
        :ok
      end)

      pid =
        start_supervised!(
          {Container,
           container_record_id: 400,
           workspace_id: 1,
           workspace_slug: "ws",
           container_slug: "container",
           container_name: "Test Container",
           docker_image: "test:latest",
           auto_start: true}
        )

      Process.sleep(20)

      # Stop the process with :normal reason to trigger terminate callback
      GenServer.stop(pid, :normal)

      # Give time for terminate to complete
      Process.sleep(20)

      refute Process.alive?(pid)
    end
  end

  describe "via_tuple/1" do
    test "returns correct Registry tuple" do
      assert {:via, Registry, {Msfailab.Containers.Registry, 42}} = Container.via_tuple(42)
    end
  end

  describe "whereis/1" do
    test "returns pid for registered container" do
      expect(DockerAdapterMock, :start_container, fn _name, _labels ->
        {:ok, "whereis_container"}
      end)

      expect(DockerAdapterMock, :get_rpc_endpoint, fn "whereis_container" ->
        {:ok, %{host: "localhost", port: 55_553}}
      end)

      pid =
        start_supervised!(
          {Container,
           container_record_id: 600,
           workspace_id: 1,
           workspace_slug: "ws",
           container_slug: "container",
           container_name: "Test Container",
           docker_image: "test:latest",
           auto_start: true}
        )

      # Wait for async container start
      Process.sleep(20)

      assert Container.whereis(600) == pid
    end

    test "returns nil for unregistered container" do
      assert Container.whereis(99_999) == nil
    end
  end

  describe "get_state_snapshot/1" do
    test "returns current state" do
      expect(DockerAdapterMock, :start_container, fn _name, _labels ->
        {:ok, "snapshot_container"}
      end)

      expect(DockerAdapterMock, :get_rpc_endpoint, fn "snapshot_container" ->
        {:ok, %{host: "localhost", port: 55_553}}
      end)

      _pid =
        start_supervised!(
          {Container,
           container_record_id: 700,
           workspace_id: 1,
           workspace_slug: "ws",
           container_slug: "container",
           container_name: "Test Container",
           docker_image: "test:latest",
           auto_start: true}
        )

      Process.sleep(20)

      snapshot = Container.get_state_snapshot(700)

      assert snapshot.status == :starting
      assert snapshot.docker_container_id == "snapshot_container"
      assert snapshot.registered_tracks == MapSet.new()
      assert snapshot.consoles == %{}
    end
  end

  describe "MSGRPC login flow" do
    test "transitions to :running after successful MSGRPC login" do
      Events.subscribe_to_workspace(1)

      expect(DockerAdapterMock, :start_container, fn _name, _labels ->
        {:ok, "msgrpc_container"}
      end)

      expect(DockerAdapterMock, :get_rpc_endpoint, fn "msgrpc_container" ->
        {:ok, %{host: "localhost", port: 55_553}}
      end)

      # Successful MSGRPC login (3 args: endpoint, password, username)
      expect(MsgrpcClientMock, :login, fn endpoint, _password, _username ->
        assert endpoint == %{host: "localhost", port: 55_553}
        {:ok, "test-token-xyz"}
      end)

      _pid =
        start_supervised!(
          {Container,
           container_record_id: 800,
           workspace_id: 1,
           workspace_slug: "ws",
           container_slug: "container",
           container_name: "Test Container",
           docker_image: "test:latest",
           auto_start: true}
        )

      # Wait for Docker start and MSGRPC login (test config uses fast timing)
      Process.sleep(30)

      assert {status, _container_id} = Container.get_status(800)
      assert status == :running

      # Should broadcast workspace changed event
      assert_receive %WorkspaceChanged{}, 100
    end

    test "retries MSGRPC login on failure with backoff" do
      expect(DockerAdapterMock, :start_container, fn _name, _labels ->
        {:ok, "retry_container"}
      end)

      expect(DockerAdapterMock, :get_rpc_endpoint, fn "retry_container" ->
        {:ok, %{host: "localhost", port: 55_553}}
      end)

      # First login fails
      expect(MsgrpcClientMock, :login, fn _, _, _ ->
        {:error, {:auth_failed, "not ready"}}
      end)

      # Second login succeeds
      expect(MsgrpcClientMock, :login, fn _, _, _ ->
        {:ok, "test-token-retry"}
      end)

      _pid =
        start_supervised!(
          {Container,
           container_record_id: 801,
           workspace_id: 1,
           workspace_slug: "ws",
           container_slug: "container",
           container_name: "Test Container",
           docker_image: "test:latest",
           auto_start: true}
        )

      # Wait for retries (test config uses fast timing: 5ms initial + 10ms backoff)
      Process.sleep(30)

      assert {status, _} = Container.get_status(801)
      assert status == :running
    end
  end

  describe "get_rpc_endpoint/1" do
    test "returns endpoint when available" do
      expect(DockerAdapterMock, :start_container, fn _name, _labels ->
        {:ok, "rpc_container"}
      end)

      expect(DockerAdapterMock, :get_rpc_endpoint, fn "rpc_container" ->
        {:ok, %{host: "localhost", port: 55_553}}
      end)

      # MSGRPC login must succeed for container to reach :running status
      expect(MsgrpcClientMock, :login, fn _endpoint, _password, _user ->
        {:ok, "test-token"}
      end)

      _pid =
        start_supervised!(
          {Container,
           container_record_id: 900,
           workspace_id: 1,
           workspace_slug: "ws",
           container_slug: "container",
           container_name: "Test Container",
           docker_image: "test:latest",
           auto_start: true}
        )

      # Wait for MSGRPC connection (test config uses fast timing)
      Process.sleep(30)

      # Inspect returns a map directly (not wrapped in :ok tuple)
      result = Container.get_rpc_endpoint(900)
      assert {:ok, %{host: "localhost", port: 55_553}} = result
    end
  end

  describe "get_running_bash_commands/1" do
    test "returns empty list initially" do
      expect(DockerAdapterMock, :start_container, fn _name, _labels ->
        {:ok, "bash_cmds_container"}
      end)

      expect(DockerAdapterMock, :get_rpc_endpoint, fn "bash_cmds_container" ->
        {:ok, %{host: "localhost", port: 55_553}}
      end)

      _pid =
        start_supervised!(
          {Container,
           container_record_id: 950,
           workspace_id: 1,
           workspace_slug: "ws",
           container_slug: "container",
           container_name: "Test Container",
           docker_image: "test:latest",
           auto_start: true}
        )

      Process.sleep(20)

      # Returns list directly (not wrapped in :ok tuple)
      assert [] = Container.get_running_bash_commands(950)
    end
  end

  describe "send_bash_command/3 when running" do
    test "executes bash command and returns result" do
      expect(DockerAdapterMock, :start_container, fn _name, _labels ->
        {:ok, "bash_exec_container"}
      end)

      expect(DockerAdapterMock, :get_rpc_endpoint, fn "bash_exec_container" ->
        {:ok, %{host: "localhost", port: 55_553}}
      end)

      # MSGRPC login succeeds
      expect(MsgrpcClientMock, :login, fn _, _, _ ->
        {:ok, "test-token"}
      end)

      # Bash command execution returns output and exit code
      expect(DockerAdapterMock, :exec, fn "bash_exec_container", "whoami" ->
        {:ok, "root\n", 0}
      end)

      _pid =
        start_supervised!(
          {Container,
           container_record_id: 1000,
           workspace_id: 1,
           workspace_slug: "ws",
           container_slug: "container",
           container_name: "Test Container",
           docker_image: "test:latest",
           auto_start: true}
        )

      # Wait for container to become running (test config uses fast timing)
      Process.sleep(30)

      # Send bash command
      assert {:ok, command_id} = Container.send_bash_command(1000, 42, "whoami")
      assert is_binary(command_id)

      # Wait for command to complete (async)
      Process.sleep(50)
    end

    test "handles bash command with non-zero exit code" do
      expect(DockerAdapterMock, :start_container, fn _name, _labels ->
        {:ok, "bash_exit_container"}
      end)

      expect(DockerAdapterMock, :get_rpc_endpoint, fn "bash_exit_container" ->
        {:ok, %{host: "localhost", port: 55_553}}
      end)

      # MSGRPC login succeeds
      expect(MsgrpcClientMock, :login, fn _, _, _ ->
        {:ok, "test-token"}
      end)

      # Bash command returns non-zero exit code
      expect(DockerAdapterMock, :exec, fn "bash_exit_container", "exit 42" ->
        {:ok, "", 42}
      end)

      _pid =
        start_supervised!(
          {Container,
           container_record_id: 1001,
           workspace_id: 1,
           workspace_slug: "ws",
           container_slug: "container",
           container_name: "Test Container",
           docker_image: "test:latest",
           auto_start: true}
        )

      # Wait for container to become running
      Process.sleep(30)

      # Send bash command that exits with non-zero
      assert {:ok, command_id} = Container.send_bash_command(1001, 42, "exit 42")
      assert is_binary(command_id)

      # Wait for command to complete (async)
      Process.sleep(50)
    end

    test "handles bash command infrastructure error" do
      expect(DockerAdapterMock, :start_container, fn _name, _labels ->
        {:ok, "bash_error_container"}
      end)

      expect(DockerAdapterMock, :get_rpc_endpoint, fn "bash_error_container" ->
        {:ok, %{host: "localhost", port: 55_553}}
      end)

      # MSGRPC login succeeds
      expect(MsgrpcClientMock, :login, fn _, _, _ ->
        {:ok, "test-token"}
      end)

      # Bash command fails due to infrastructure error
      expect(DockerAdapterMock, :exec, fn "bash_error_container", "failing_command" ->
        {:error, :container_not_found}
      end)

      _pid =
        start_supervised!(
          {Container,
           container_record_id: 1002,
           workspace_id: 1,
           workspace_slug: "ws",
           container_slug: "container",
           container_name: "Test Container",
           docker_image: "test:latest",
           auto_start: true}
        )

      # Wait for container to become running
      Process.sleep(30)

      # Send bash command that fails
      assert {:ok, command_id} = Container.send_bash_command(1002, 42, "failing_command")
      assert is_binary(command_id)

      # Wait for command error to propagate (async)
      Process.sleep(50)
    end
  end

  describe "console spawn failure and retry" do
    test "retries console spawn when login fails" do
      # Use stub for Docker to allow multiple calls if needed
      stub(DockerAdapterMock, :start_container, fn _name, _labels ->
        {:ok, "retry_container"}
      end)

      stub(DockerAdapterMock, :get_rpc_endpoint, fn "retry_container" ->
        {:ok, %{host: "localhost", port: 55_553}}
      end)

      # Track login calls to differentiate container login from console login
      login_count = :counters.new(1, [:atomics])

      stub(MsgrpcClientMock, :login, fn _, _, _ ->
        :counters.add(login_count, 1, 1)
        count = :counters.get(login_count, 1)

        if count == 1 do
          # First call: container login succeeds
          {:ok, "container-token"}
        else
          # Subsequent calls: console login fails
          {:error, {:auth_failed, "token expired"}}
        end
      end)

      _pid =
        start_supervised!(
          {Container,
           container_record_id: 2001,
           workspace_id: 1,
           workspace_slug: "ws",
           container_slug: "container",
           container_name: "Test Container",
           docker_image: "test:latest",
           auto_start: true}
        )

      # Wait for container to become running
      Process.sleep(30)
      assert {:running, _} = Container.get_status(2001)

      # Register a console - this triggers spawn_console which will fail
      assert :ok = Container.register_console(2001, 42)

      # Wait for spawn attempt to fail and schedule retry
      Process.sleep(20)

      # Check that restart_attempts is tracked
      snapshot = Container.get_state_snapshot(2001)
      assert MapSet.member?(snapshot.registered_tracks, 42)
      console_info = Map.get(snapshot.consoles, 42)
      assert console_info != nil
      assert console_info.restart_attempts >= 1
      assert console_info.pid == nil
    end

    test "tracks restart attempts when login keeps failing" do
      stub(DockerAdapterMock, :start_container, fn _name, _labels ->
        {:ok, "multi_retry_container"}
      end)

      stub(DockerAdapterMock, :get_rpc_endpoint, fn "multi_retry_container" ->
        {:ok, %{host: "localhost", port: 55_553}}
      end)

      # Container login succeeds, then console logins fail
      login_count = :counters.new(1, [:atomics])

      stub(MsgrpcClientMock, :login, fn _, _, _ ->
        :counters.add(login_count, 1, 1)
        count = :counters.get(login_count, 1)

        if count == 1 do
          {:ok, "container-token"}
        else
          {:error, {:auth_failed, "server unreachable"}}
        end
      end)

      _pid =
        start_supervised!(
          {Container,
           container_record_id: 2002,
           workspace_id: 1,
           workspace_slug: "ws",
           container_slug: "container",
           container_name: "Test Container",
           docker_image: "test:latest",
           auto_start: true}
        )

      Process.sleep(30)
      assert {:running, _} = Container.get_status(2002)

      assert :ok = Container.register_console(2002, 42)

      # Wait for multiple restart attempts with backoff
      # Fast timing: 1ms base, so 1ms -> 2ms -> 4ms
      Process.sleep(50)

      # Check restart_attempts incremented
      snapshot = Container.get_state_snapshot(2002)
      console_info = Map.get(snapshot.consoles, 42)

      # Should have attempted multiple times by now
      assert console_info != nil
      assert console_info.restart_attempts >= 2
    end

    test "gives up after max restart attempts" do
      stub(DockerAdapterMock, :start_container, fn _name, _labels ->
        {:ok, "max_retry_container"}
      end)

      stub(DockerAdapterMock, :get_rpc_endpoint, fn "max_retry_container" ->
        {:ok, %{host: "localhost", port: 55_553}}
      end)

      # Container login succeeds once, then all console logins fail
      login_count = :counters.new(1, [:atomics])

      stub(MsgrpcClientMock, :login, fn _, _, _ ->
        :counters.add(login_count, 1, 1)
        count = :counters.get(login_count, 1)

        if count == 1 do
          {:ok, "container-token"}
        else
          {:error, {:auth_failed, "permanent failure"}}
        end
      end)

      _pid =
        start_supervised!(
          {Container,
           container_record_id: 2003,
           workspace_id: 1,
           workspace_slug: "ws",
           container_slug: "container",
           container_name: "Test Container",
           docker_image: "test:latest",
           auto_start: true}
        )

      Process.sleep(30)
      assert {:running, _} = Container.get_status(2003)

      assert :ok = Container.register_console(2003, 42)

      # Wait for all retries to exhaust (with fast timing: 10 attempts max)
      # Backoff: 1 + 2 + 4 + 8 + 16 + 30 + 30 + 30 + 30 + 30 = ~181ms + processing time
      # Need to wait until attempt 11 is checked and fails the condition
      Process.sleep(400)

      # Console should be removed from state after max attempts
      snapshot = Container.get_state_snapshot(2003)
      refute Map.has_key?(snapshot.consoles, 42)
    end
  end
end
