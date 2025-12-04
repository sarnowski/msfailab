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

defmodule Msfailab.ContainersTest do
  use Msfailab.ContainersCase, async: false

  alias Msfailab.Containers
  alias Msfailab.Containers.ContainerRecord
  alias Msfailab.Workspaces

  @valid_workspace_attrs %{name: "Test Workspace", slug: "test-workspace"}
  @valid_container_attrs %{
    name: "Test Container",
    slug: "my-container",
    docker_image: "test:latest"
  }

  defp create_workspace(_context) do
    {:ok, workspace} = Workspaces.create_workspace(@valid_workspace_attrs)
    %{workspace: workspace}
  end

  defp create_workspace_and_container(_context) do
    {:ok, workspace} = Workspaces.create_workspace(@valid_workspace_attrs)
    {:ok, container} = Containers.create_container(workspace, @valid_container_attrs)
    %{workspace: workspace, container: container}
  end

  defp container_with_workspace(context) do
    %{context | container: Repo.preload(context.container, :workspace)}
  end

  # ============================================================================
  # Container Record CRUD Tests
  # ============================================================================

  describe "list_containers/1" do
    setup [:create_workspace_and_container]

    test "returns all containers for a workspace", %{workspace: workspace, container: container} do
      assert Containers.list_containers(workspace) == [container]
    end

    test "returns all containers for a workspace id", %{
      workspace: workspace,
      container: container
    } do
      assert Containers.list_containers(workspace.id) == [container]
    end

    test "returns empty list when no containers exist" do
      {:ok, empty_workspace} =
        Workspaces.create_workspace(%{name: "Empty", slug: "empty-workspace"})

      assert Containers.list_containers(empty_workspace) == []
    end
  end

  describe "list_containers_with_tracks/1" do
    setup [:create_workspace_and_container]

    test "returns containers with preloaded tracks", %{workspace: workspace, container: container} do
      # Create a track for this container
      {:ok, track} =
        Msfailab.Tracks.create_track(container, %{name: "Test Track", slug: "test"})

      [result] = Containers.list_containers_with_tracks(workspace)
      assert result.id == container.id
      assert Ecto.assoc_loaded?(result.tracks)
      assert length(result.tracks) == 1
      assert hd(result.tracks).id == track.id
    end

    test "returns containers with empty tracks list when no tracks", %{
      workspace: workspace,
      container: container
    } do
      [result] = Containers.list_containers_with_tracks(workspace.id)
      assert result.id == container.id
      assert result.tracks == []
    end
  end

  describe "list_active_containers/0" do
    setup [:create_workspace_and_container]

    test "returns containers with active tracks", %{container: container} do
      {:ok, _track} =
        Msfailab.Tracks.create_track(container, %{name: "Active", slug: "active"})

      containers = Containers.list_active_containers()
      assert length(containers) >= 1
      assert Enum.any?(containers, &(&1.id == container.id))
      # Should have workspace preloaded
      assert Ecto.assoc_loaded?(hd(containers).workspace)
    end

    test "excludes containers with only archived tracks", %{container: container} do
      {:ok, track} =
        Msfailab.Tracks.create_track(container, %{name: "Archived", slug: "archived"})

      Msfailab.Tracks.archive_track(track)

      containers = Containers.list_active_containers()
      refute Enum.any?(containers, &(&1.id == container.id))
    end
  end

  describe "get_container/1" do
    setup [:create_workspace_and_container]

    test "returns container by id", %{container: container} do
      assert Containers.get_container(container.id) == container
    end

    test "returns nil for non-existent container" do
      assert Containers.get_container(999) == nil
    end
  end

  describe "get_container!/1" do
    setup [:create_workspace_and_container]

    test "returns container by id", %{container: container} do
      assert Containers.get_container!(container.id) == container
    end

    test "raises for non-existent container" do
      assert_raise Ecto.NoResultsError, fn ->
        Containers.get_container!(999)
      end
    end
  end

  describe "get_container_by_slug/2" do
    setup [:create_workspace_and_container]

    test "returns container by workspace and slug", %{workspace: workspace, container: container} do
      assert Containers.get_container_by_slug(workspace, "my-container") == container
    end

    test "returns container by workspace id and slug", %{
      workspace: workspace,
      container: container
    } do
      assert Containers.get_container_by_slug(workspace.id, "my-container") == container
    end

    test "returns nil for non-existent slug", %{workspace: workspace} do
      assert Containers.get_container_by_slug(workspace, "non-existent") == nil
    end
  end

  describe "slug_exists?/2" do
    setup [:create_workspace_and_container]

    test "returns true for existing slug", %{workspace: workspace} do
      assert Containers.slug_exists?(workspace, "my-container")
    end

    test "returns true for existing slug with workspace id", %{workspace: workspace} do
      assert Containers.slug_exists?(workspace.id, "my-container")
    end

    test "returns false for non-existent slug", %{workspace: workspace} do
      refute Containers.slug_exists?(workspace, "non-existent")
    end

    test "returns false for empty slug", %{workspace: workspace} do
      refute Containers.slug_exists?(workspace, "")
    end

    test "returns false for nil slug", %{workspace: workspace} do
      refute Containers.slug_exists?(workspace.id, nil)
    end

    test "returns false for nil workspace" do
      refute Containers.slug_exists?(nil, "my-container")
    end
  end

  describe "create_container/2" do
    setup [:create_workspace]

    test "creates a container with valid attrs", %{workspace: workspace} do
      assert {:ok, %ContainerRecord{} = container} =
               Containers.create_container(workspace, @valid_container_attrs)

      assert container.slug == "my-container"
      assert container.name == "Test Container"
      assert container.docker_image == "test:latest"
      assert container.workspace_id == workspace.id
    end

    test "creates a container with attrs map containing workspace_id", %{workspace: workspace} do
      attrs = Map.put(@valid_container_attrs, :workspace_id, workspace.id)

      assert {:ok, %ContainerRecord{} = container} = Containers.create_container(attrs)
      assert container.workspace_id == workspace.id
      assert container.slug == "my-container"
    end

    test "returns error changeset with invalid attrs", %{workspace: workspace} do
      assert {:error, %Ecto.Changeset{}} =
               Containers.create_container(workspace, %{slug: nil, name: nil})
    end

    test "enforces unique slug within workspace", %{workspace: workspace} do
      {:ok, _container} = Containers.create_container(workspace, @valid_container_attrs)
      assert {:error, changeset} = Containers.create_container(workspace, @valid_container_attrs)
      errors = errors_on(changeset)

      assert "has already been taken" in Map.get(errors, :workspace_id, []) or
               "has already been taken" in Map.get(errors, :slug, [])
    end
  end

  describe "update_container/2" do
    setup [:create_workspace_and_container]

    test "updates container with valid attrs", %{container: container} do
      assert {:ok, %ContainerRecord{} = updated} =
               Containers.update_container(container, %{name: "Updated Container"})

      assert updated.name == "Updated Container"
      assert updated.slug == "my-container"
    end
  end

  describe "change_container/2" do
    setup [:create_workspace_and_container]

    test "returns a changeset for a container", %{container: container} do
      changeset = Containers.change_container(container)
      assert %Ecto.Changeset{} = changeset
      assert changeset.data == container
    end

    test "returns a changeset with changes", %{container: container} do
      changeset = Containers.change_container(container, %{name: "New Name"})
      assert %Ecto.Changeset{} = changeset
      assert Ecto.Changeset.get_change(changeset, :name) == "New Name"
    end
  end

  # ============================================================================
  # Container GenServer Tests
  # ============================================================================

  describe "start_container/1" do
    setup [:create_workspace_and_container, :container_with_workspace]

    test "starts a container process for a container record", %{container: container} do
      expect(DockerAdapterMock, :start_container, fn name, labels, rpc_port ->
        assert name == "msfailab-test-workspace-my-container"
        assert labels["msfailab.managed"] == "true"
        assert labels["msfailab.workspace_slug"] == "test-workspace"
        assert labels["msfailab.container_slug"] == "my-container"
        assert labels["msfailab.container_id"] == to_string(container.id)
        assert rpc_port >= 50_000 and rpc_port <= 60_000
        {:ok, "container_123"}
      end)

      expect(DockerAdapterMock, :get_rpc_endpoint, fn "container_123" ->
        {:ok, %{host: "localhost", port: 55_553}}
      end)

      # Keep container in :starting state by failing MSGRPC login
      stub(MsgrpcClientMock, :login, fn _endpoint, _password, _username ->
        {:error, {:auth_failed, "not ready"}}
      end)

      assert {:ok, pid} = Containers.start_container(container)
      assert is_pid(pid)

      # Wait for async container start
      Process.sleep(50)

      # Container stays :starting until MSGRPC auth completes
      assert {:ok, {:starting, "container_123"}} = Containers.get_status(container.id)
    end
  end

  describe "stop_container/1" do
    setup [:create_workspace_and_container, :container_with_workspace]

    test "stops a running container process", %{container: container} do
      expect(DockerAdapterMock, :start_container, fn _name, _labels, _rpc_port ->
        {:ok, "stop_test_container"}
      end)

      expect(DockerAdapterMock, :get_rpc_endpoint, fn "stop_test_container" ->
        {:ok, %{host: "localhost", port: 55_553}}
      end)

      expect(DockerAdapterMock, :stop_container, fn "stop_test_container" ->
        :ok
      end)

      {:ok, _pid} = Containers.start_container(container)
      Process.sleep(50)

      assert :ok = Containers.stop_container(container.id)
      assert {:error, :not_found} = Containers.get_status(container.id)
    end

    test "returns error when container not found" do
      assert {:error, :not_found} = Containers.stop_container(99_999)
    end
  end

  describe "get_status/1" do
    setup [:create_workspace_and_container, :container_with_workspace]

    test "returns status for running container", %{container: container} do
      expect(DockerAdapterMock, :start_container, fn _name, _labels, _rpc_port ->
        {:ok, "status_container"}
      end)

      expect(DockerAdapterMock, :get_rpc_endpoint, fn "status_container" ->
        {:ok, %{host: "localhost", port: 55_553}}
      end)

      # Keep container in :starting state by failing MSGRPC login
      stub(MsgrpcClientMock, :login, fn _endpoint, _password, _username ->
        {:error, {:auth_failed, "not ready"}}
      end)

      {:ok, _pid} = Containers.start_container(container)
      Process.sleep(50)

      assert {:ok, {status, container_id}} = Containers.get_status(container.id)
      # Container stays :starting until MSGRPC auth completes
      assert status == :starting
      assert container_id == "status_container"
    end

    test "returns error when container not found" do
      assert {:error, :not_found} = Containers.get_status(99_999)
    end
  end

  describe "send_metasploit_command/3" do
    setup [:create_workspace_and_container, :container_with_workspace]

    test "returns error when container not running", %{container: container} do
      expect(DockerAdapterMock, :start_container, fn _name, _labels, _rpc_port ->
        {:ok, "msf_container"}
      end)

      expect(DockerAdapterMock, :get_rpc_endpoint, fn "msf_container" ->
        {:ok, %{host: "localhost", port: 55_553}}
      end)

      # Keep container in :starting state by failing MSGRPC login
      stub(MsgrpcClientMock, :login, fn _endpoint, _password, _username ->
        {:error, {:auth_failed, "not ready"}}
      end)

      {:ok, _pid} = Containers.start_container(container)
      Process.sleep(50)

      # Container is :starting (not :running) until MSGRPC auth completes
      # Commands are rejected when container is not running
      assert {:error, :container_not_running} =
               Containers.send_metasploit_command(container.id, 999, "help")
    end

    test "returns error when container process not found" do
      assert {:error, :container_not_running} =
               Containers.send_metasploit_command(99_999, 1, "help")
    end
  end

  describe "send_bash_command/3" do
    setup [:create_workspace_and_container, :container_with_workspace]

    test "returns error when container not running", %{container: container} do
      expect(DockerAdapterMock, :start_container, fn _name, _labels, _rpc_port ->
        {:ok, "bash_container"}
      end)

      expect(DockerAdapterMock, :get_rpc_endpoint, fn "bash_container" ->
        {:ok, %{host: "localhost", port: 55_553}}
      end)

      # Keep container in :starting state by failing MSGRPC login
      stub(MsgrpcClientMock, :login, fn _endpoint, _password, _username ->
        {:error, {:auth_failed, "not ready"}}
      end)

      {:ok, _pid} = Containers.start_container(container)
      Process.sleep(50)

      # Container is :starting (not :running) until MSGRPC auth completes
      # Bash commands are rejected when container is not running
      assert {:error, :container_not_running} =
               Containers.send_bash_command(container.id, 5, "ls -la")
    end

    test "returns error when container process not found" do
      assert {:error, :container_not_running} = Containers.send_bash_command(99_999, 1, "ls")
    end
  end

  describe "get_rpc_endpoint/1" do
    setup [:create_workspace_and_container, :container_with_workspace]

    test "returns error when container not fully running", %{container: container} do
      expect(DockerAdapterMock, :start_container, fn _name, _labels, _rpc_port ->
        {:ok, "rpc_container"}
      end)

      expect(DockerAdapterMock, :get_rpc_endpoint, fn "rpc_container" ->
        {:ok, %{host: "localhost", port: 55_553}}
      end)

      # Keep container in :starting state by failing MSGRPC login
      stub(MsgrpcClientMock, :login, fn _endpoint, _password, _username ->
        {:error, {:auth_failed, "not ready"}}
      end)

      {:ok, _pid} = Containers.start_container(container)
      Process.sleep(50)

      # Container is :starting (not :running) until MSGRPC auth completes
      # RPC endpoint is only available when fully running
      assert {:error, :not_available} = Containers.get_rpc_endpoint(container.id)
    end

    test "returns error when container not running" do
      assert {:error, :not_running} = Containers.get_rpc_endpoint(99_999)
    end
  end

  # ============================================================================
  # State Query Functions
  # ============================================================================

  describe "get_containers/1" do
    setup [:create_workspace_and_container, :container_with_workspace]

    test "returns containers with offline status when no GenServer", %{
      workspace: workspace,
      container: container
    } do
      containers = Containers.get_containers(workspace.id)
      assert [info] = containers
      assert info.id == container.id
      assert info.workspace_id == workspace.id
      assert info.slug == container.slug
      assert info.name == container.name
      assert info.docker_image == container.docker_image
      assert info.status == :offline
      assert info.docker_container_id == nil
    end

    test "returns containers with live status when GenServer running", %{
      workspace: workspace,
      container: container
    } do
      expect(DockerAdapterMock, :start_container, fn _name, _labels, _rpc_port ->
        {:ok, "get_containers_test"}
      end)

      expect(DockerAdapterMock, :get_rpc_endpoint, fn "get_containers_test" ->
        {:ok, %{host: "localhost", port: 55_553}}
      end)

      # Keep container in :starting state by failing MSGRPC login
      stub(MsgrpcClientMock, :login, fn _endpoint, _password, _username ->
        {:error, {:auth_failed, "not ready"}}
      end)

      {:ok, _pid} = Containers.start_container(container)
      Process.sleep(50)

      containers = Containers.get_containers(workspace.id)
      assert [info] = containers
      assert info.status == :starting
      assert info.docker_container_id == "get_containers_test"
    end
  end

  describe "get_consoles/2" do
    setup [:create_workspace_and_container]

    test "returns empty list when no GenServer running", %{workspace: workspace} do
      assert Containers.get_consoles(workspace.id) == []
    end

    test "returns empty list when GenServer has no consoles", %{
      workspace: workspace,
      container: container
    } do
      container = Repo.preload(container, :workspace)

      expect(DockerAdapterMock, :start_container, fn _name, _labels, _rpc_port ->
        {:ok, "consoles_test"}
      end)

      expect(DockerAdapterMock, :get_rpc_endpoint, fn "consoles_test" ->
        {:ok, %{host: "localhost", port: 55_553}}
      end)

      {:ok, _pid} = Containers.start_container(container)
      Process.sleep(50)

      assert Containers.get_consoles(workspace.id) == []
    end

    test "filters by container_id when option provided", %{workspace: workspace} do
      assert Containers.get_consoles(workspace.id, container_id: 99_999) == []
    end
  end

  describe "register_console/2" do
    setup [:create_workspace_and_container]

    test "returns :ok when container not running", %{container: container} do
      assert :ok = Containers.register_console(container.id, 42)
    end

    test "registers with running container", %{container: container} do
      container = Repo.preload(container, :workspace)

      expect(DockerAdapterMock, :start_container, fn _name, _labels, _rpc_port ->
        {:ok, "register_test"}
      end)

      expect(DockerAdapterMock, :get_rpc_endpoint, fn "register_test" ->
        {:ok, %{host: "localhost", port: 55_553}}
      end)

      {:ok, _pid} = Containers.start_container(container)
      Process.sleep(50)

      assert :ok = Containers.register_console(container.id, 42)
    end
  end

  describe "unregister_console/2" do
    setup [:create_workspace_and_container]

    test "returns :ok when container not running", %{container: container} do
      assert :ok = Containers.unregister_console(container.id, 42)
    end

    test "unregisters from running container", %{container: container} do
      container = Repo.preload(container, :workspace)

      expect(DockerAdapterMock, :start_container, fn _name, _labels, _rpc_port ->
        {:ok, "unregister_test"}
      end)

      expect(DockerAdapterMock, :get_rpc_endpoint, fn "unregister_test" ->
        {:ok, %{host: "localhost", port: 55_553}}
      end)

      {:ok, _pid} = Containers.start_container(container)
      Process.sleep(50)

      # Register first, then unregister
      Containers.register_console(container.id, 42)
      assert :ok = Containers.unregister_console(container.id, 42)
    end
  end

  describe "get_running_bash_commands/2" do
    setup [:create_workspace_and_container]

    test "returns empty list when container not running", %{container: container} do
      assert Containers.get_running_bash_commands(container.id) == []
    end

    test "returns empty list when no commands running", %{container: container} do
      container = Repo.preload(container, :workspace)

      expect(DockerAdapterMock, :start_container, fn _name, _labels, _rpc_port ->
        {:ok, "bash_commands_test"}
      end)

      expect(DockerAdapterMock, :get_rpc_endpoint, fn "bash_commands_test" ->
        {:ok, %{host: "localhost", port: 55_553}}
      end)

      {:ok, _pid} = Containers.start_container(container)
      Process.sleep(50)

      assert Containers.get_running_bash_commands(container.id) == []
    end

    test "filters by track_id when option provided", %{container: container} do
      assert Containers.get_running_bash_commands(container.id, track_id: 42) == []
    end
  end

  # ============================================================================
  # RPC Context
  # ============================================================================

  describe "get_rpc_context_for_workspace/1" do
    setup [:create_workspace_and_container]

    test "returns error when no containers are running", %{workspace: workspace} do
      # Container exists but is not started
      assert {:error, :no_running_container} =
               Containers.get_rpc_context_for_workspace(workspace.id)
    end

    test "returns error when workspace has no containers" do
      {:ok, empty_workspace} =
        Workspaces.create_workspace(%{name: "Empty", slug: "empty-workspace"})

      assert {:error, :no_running_container} =
               Containers.get_rpc_context_for_workspace(empty_workspace.id)
    end

    test "returns RPC context from running container", %{
      workspace: workspace,
      container: container
    } do
      # Use container_with_workspace to get the preloaded association
      container = Repo.preload(container, :workspace)

      expect(DockerAdapterMock, :start_container, fn _name, _labels, _rpc_port ->
        {:ok, "rpc_ctx_container"}
      end)

      expect(DockerAdapterMock, :get_rpc_endpoint, fn "rpc_ctx_container" ->
        {:ok, %{host: "localhost", port: 55_553}}
      end)

      # Login succeeds - container will reach :running state
      stub(MsgrpcClientMock, :login, fn _endpoint, _pass, _user ->
        {:ok, "test-token-abc"}
      end)

      {:ok, _pid} = Containers.start_container(container)
      # Wait for container to start and MSGRPC to connect
      Process.sleep(100)

      {:ok, rpc_context} = Containers.get_rpc_context_for_workspace(workspace.id)

      assert rpc_context.endpoint == %{host: "localhost", port: 55_553}
      assert rpc_context.token == "test-token-abc"
      assert is_atom(rpc_context.client)
    end
  end

  # ============================================================================
  # Utilities
  # ============================================================================

  describe "container_name/2" do
    test "generates correct container name" do
      assert "msfailab-my-workspace-my-container" =
               Containers.container_name("my-workspace", "my-container")
    end

    test "handles edge cases in slug names" do
      assert "msfailab-a-b" = Containers.container_name("a", "b")

      assert "msfailab-workspace-123-container-456" =
               Containers.container_name("workspace-123", "container-456")
    end
  end

  describe "docker_adapter/0" do
    test "returns the configured adapter" do
      # In test environment, should return the mock
      assert Containers.docker_adapter() == DockerAdapterMock
    end
  end
end
