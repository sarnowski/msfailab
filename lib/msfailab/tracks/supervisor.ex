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

# coveralls-ignore-start
# Reason: Pure OTP supervision glue code, no business logic to test
defmodule Msfailab.Tracks.Supervisor do
  @moduledoc """
  Supervisor for the track state management subsystem.

  Manages TrackServer GenServers that maintain track session state including
  command history and (eventually) chat history. Each active track has its
  own TrackServer that accumulates state and broadcasts TrackStateUpdated events.

  ## Architecture

  ```
  Tracks.Supervisor
  ├── DynamicSupervisor (Msfailab.Tracks.TrackSupervisor)
  │   └── TrackServer GenServers (one per active track)
  └── Reconciler
      └── Starts TrackServer GenServers on application boot
  ```

  ## Supervision Strategy

  Uses `:one_for_one` strategy because the children are independent:
  - DynamicSupervisor manages independent TrackServer child processes
  - Reconciler only runs on startup
  """

  use Supervisor

  @doc """
  Starts the Tracks Supervisor linked to the calling process.
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      # DynamicSupervisor for TrackServer GenServers
      {DynamicSupervisor, name: Msfailab.Tracks.TrackSupervisor, strategy: :one_for_one},
      # Reconciler runs after supervisor is ready
      Msfailab.Tracks.Reconciler
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end

# coveralls-ignore-stop
