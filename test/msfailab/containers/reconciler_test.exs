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

defmodule Msfailab.Containers.ReconcilerTest do
  use Msfailab.ContainersCase, async: false

  alias Msfailab.Containers
  alias Msfailab.Containers.Reconciler
  alias Msfailab.Tracks
  alias Msfailab.Workspaces

  @valid_workspace_attrs %{name: "Test Workspace", slug: "test-workspace"}
  @valid_container_attrs %{
    name: "Test Container",
    slug: "test-container",
    docker_image: "test:latest"
  }
  @valid_track_attrs %{name: "Test Track", slug: "test-track"}

  defp create_workspace_and_container(_context) do
    # Stub container operations for workspace/container/track creation
    stub(DockerAdapterMock, :start_container, fn _name, _labels ->
      {:ok, "stub_container_#{System.unique_integer([:positive])}"}
    end)

    stub(DockerAdapterMock, :get_rpc_endpoint, fn _container_id ->
      {:ok, %{host: "localhost", port: 55_553}}
    end)

    # Keep containers in :starting state by failing MSGRPC login
    stub(MsgrpcClientMock, :login, fn _endpoint, _password, _username ->
      {:error, {:auth_failed, "test stub"}}
    end)

    {:ok, workspace} = Workspaces.create_workspace(@valid_workspace_attrs)
    {:ok, container} = Containers.create_container(workspace, @valid_container_attrs)
    container = Repo.preload(container, :workspace)
    %{workspace: workspace, container: container}
  end

  describe "reconcile on startup" do
    setup [:create_workspace_and_container]

    test "starts Container GenServers for active containers", %{container: container} do
      # Create a track to make the container active
      expect(DockerAdapterMock, :start_container, fn _name, _labels ->
        {:ok, "track_container"}
      end)

      expect(DockerAdapterMock, :get_rpc_endpoint, fn "track_container" ->
        {:ok, %{host: "localhost", port: 55_553}}
      end)

      {:ok, _track} = Tracks.create_track(container, @valid_track_attrs)

      # Wait for the GenServer process to start
      Process.sleep(30)

      # Stop Container GenServer to simulate an app restart
      Containers.stop_container(container.id)

      # Expect list_managed_containers to return no containers
      expect(DockerAdapterMock, :list_managed_containers, fn ->
        {:ok, []}
      end)

      # Expect a new container to be started for reconciliation
      expect(DockerAdapterMock, :start_container, fn name, labels ->
        assert name == "msfailab-test-workspace-test-container"
        assert labels["msfailab.container_id"] == to_string(container.id)
        {:ok, "reconciled_container"}
      end)

      expect(DockerAdapterMock, :get_rpc_endpoint, fn "reconciled_container" ->
        {:ok, %{host: "localhost", port: 55_553}}
      end)

      # Start the reconciler
      _pid = start_supervised!(Reconciler)

      # Wait for reconciliation to complete
      Process.sleep(50)

      # Verify the Container GenServer was started
      # Container stays :starting until MSGRPC auth completes
      assert {:ok, {status, _container_id}} = Containers.get_status(container.id)
      assert status == :starting
    end

    test "stops orphaned Docker containers", %{container: _container} do
      # Expect list_managed_containers to return an orphaned container
      expect(DockerAdapterMock, :list_managed_containers, fn ->
        {:ok,
         [
           %{
             id: "orphan_container",
             name: "msfailab-old-workspace-old-container",
             status: :running,
             labels: %{
               "msfailab.managed" => "true",
               "msfailab.container_id" => "99999"
             }
           }
         ]}
      end)

      # Expect the orphaned container to be stopped
      expect(DockerAdapterMock, :stop_container, fn "orphan_container" ->
        :ok
      end)

      # Start the reconciler
      _pid = start_supervised!(Reconciler)

      # Wait for reconciliation to complete
      Process.sleep(30)
    end

    test "adopts existing Docker containers for active containers", %{container: container} do
      # Create a track to make the container active
      expect(DockerAdapterMock, :start_container, fn _name, _labels ->
        {:ok, "original_container"}
      end)

      expect(DockerAdapterMock, :get_rpc_endpoint, fn "original_container" ->
        {:ok, %{host: "localhost", port: 55_553}}
      end)

      {:ok, _track} = Tracks.create_track(container, @valid_track_attrs)

      # Wait for the GenServer process to start
      Process.sleep(30)

      # Stop Container GenServer to simulate a restart
      Containers.stop_container(container.id)

      # Expect list_managed_containers to return the existing container
      expect(DockerAdapterMock, :list_managed_containers, fn ->
        {:ok,
         [
           %{
             id: "existing_docker_container",
             name: "msfailab-test-workspace-test-container",
             status: :running,
             labels: %{
               "msfailab.managed" => "true",
               "msfailab.container_id" => to_string(container.id)
             }
           }
         ]}
      end)

      # Expect the container to be checked if running (adoption)
      expect(DockerAdapterMock, :container_running?, fn "existing_docker_container" ->
        true
      end)

      expect(DockerAdapterMock, :get_rpc_endpoint, fn "existing_docker_container" ->
        {:ok, %{host: "localhost", port: 55_553}}
      end)

      # Start the reconciler
      _pid = start_supervised!(Reconciler)

      # Wait for reconciliation to complete
      Process.sleep(50)

      # Verify the Container GenServer was started and adopted the existing Docker container
      # Container stays :starting until MSGRPC auth completes
      assert {:ok, {status, docker_id}} = Containers.get_status(container.id)
      assert status == :starting
      assert docker_id == "existing_docker_container"
    end
  end
end
