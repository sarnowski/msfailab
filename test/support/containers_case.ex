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

defmodule Msfailab.ContainersCase do
  @moduledoc """
  Test case for container related tests.

  Extends `DataCase` with Mox support for mocking the Docker adapter.
  Tests using this case can set expectations on `DockerAdapterMock`
  to control container behavior.

  Also starts the necessary infrastructure for Container GenServers:
  - Container Registry and DynamicSupervisor

  ## Example

      defmodule Msfailab.Containers.ContainerTest do
        use Msfailab.ContainersCase, async: false

        test "starts container on init" do
          expect(DockerAdapterMock, :start_container, fn _name, _labels, _rpc_port ->
            {:ok, "container123"}
          end)

          # Test code here
        end
      end
  """

  use ExUnit.CaseTemplate

  alias Msfailab.Containers.DockerAdapterMock
  alias Msfailab.Containers.Msgrpc.ClientMock, as: MsgrpcClientMock

  using do
    quote do
      alias Msfailab.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Msfailab.DataCase
      import Mox

      alias Msfailab.Containers.DockerAdapterMock
      alias Msfailab.Containers.Msgrpc.ClientMock, as: MsgrpcClientMock

      # Verify Mox expectations after each test
      setup :verify_on_exit!
    end
  end

  setup tags do
    Msfailab.DataCase.setup_sandbox(tags)

    # Configure fast timing for tests to minimize Process.sleep waits
    # Container timing: use very short delays for MSGRPC auth and backoffs
    Application.put_env(:msfailab, :container_timing,
      health_check_interval_ms: 10_000,
      max_restart_count: 5,
      base_backoff_ms: 5,
      max_backoff_ms: 50,
      success_reset_ms: 100,
      msgrpc_initial_delay_ms: 5,
      msgrpc_max_connect_attempts: 10,
      msgrpc_connect_base_backoff_ms: 5,
      console_restart_base_backoff_ms: 5,
      console_restart_max_backoff_ms: 50,
      console_max_restart_attempts: 10
    )

    # Console timing: use very short poll intervals and retry delays
    Application.put_env(:msfailab, :console_timing,
      poll_interval_ms: 5,
      keepalive_interval_ms: 10_000,
      max_retries: 3,
      retry_delays_ms: [5, 10, 20]
    )

    on_exit(fn ->
      Application.delete_env(:msfailab, :container_timing)
      Application.delete_env(:msfailab, :console_timing)
    end)

    # Start the Container Registry and DynamicSupervisor
    start_supervised!({Registry, keys: :unique, name: Msfailab.Containers.Registry})

    start_supervised!(
      {DynamicSupervisor, name: Msfailab.Containers.ContainerSupervisor, strategy: :one_for_one}
    )

    # Set Mox to global mode so spawned GenServer processes can access expectations.
    # This requires tests to run with async: false.
    Mox.set_mox_global(self())

    # Stub with the CLI adapter so tests don't need to expect every call
    Mox.stub_with(DockerAdapterMock, Msfailab.Containers.DockerAdapter.Cli)

    # Stub MSGRPC client with test stub (never use real HTTP client in tests)
    Mox.stub_with(MsgrpcClientMock, Msfailab.Containers.Msgrpc.ClientStub)

    :ok
  end
end
