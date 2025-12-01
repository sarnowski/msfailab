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

defmodule Msfailab.Events.ContainerUpdated do
  @moduledoc """
  Event broadcast when a container's runtime status changes.

  This event is emitted by the Container GenServer when it transitions
  between states. It includes all container entity fields for self-healing
  (subscribers who missed ContainerCreated can reconstruct state).

  ## Runtime Statuses

  - `:offline` - GenServer alive, no Docker container or MSGRPC connection
  - `:starting` - Docker container starting or MSGRPC authenticating
  - `:running` - Fully operational, consoles can be created

  ## Fields

  - `workspace_id` - The workspace containing this container
  - `container_id` - The container's database ID
  - `slug` - URL-safe identifier for the container
  - `name` - Human-readable display name
  - `docker_image` - Docker image used for the container
  - `status` - Runtime status (:offline, :starting, :running)
  - `docker_container_id` - Docker container ID (when running)
  - `timestamp` - When the event occurred

  ## State Machine

  ```
  :offline ──start docker──► :starting ──msgrpc auth──► :running
      ▲                           │                         │
      │                           │ docker/msgrpc failure   │ docker dies
      └───────────────────────────┴─────────────────────────┘
  ```
  """

  alias Msfailab.Containers.ContainerRecord

  @type status :: :offline | :starting | :running

  @type t :: %__MODULE__{
          workspace_id: integer(),
          container_id: integer(),
          slug: String.t(),
          name: String.t(),
          docker_image: String.t(),
          status: status(),
          docker_container_id: String.t() | nil,
          timestamp: DateTime.t()
        }

  @enforce_keys [:workspace_id, :container_id, :slug, :name, :docker_image, :status, :timestamp]
  defstruct [
    :workspace_id,
    :container_id,
    :slug,
    :name,
    :docker_image,
    :status,
    :docker_container_id,
    :timestamp
  ]

  @doc """
  Creates a ContainerUpdated event from a container record with a status change.

  ## Options

  - `:docker_container_id` - The Docker container ID (when status is :running)

  ## Examples

      iex> container = %ContainerRecord{id: 1, slug: "msf", name: "Metasploit", ...}
      iex> ContainerUpdated.new(container, :running, docker_container_id: "abc123")
      %ContainerUpdated{container_id: 1, status: :running, docker_container_id: "abc123", ...}

      iex> ContainerUpdated.new(container, :offline)
      %ContainerUpdated{status: :offline, docker_container_id: nil, ...}
  """
  @spec new(ContainerRecord.t(), status(), keyword()) :: t()
  def new(%ContainerRecord{} = container, status, opts \\ []) do
    %__MODULE__{
      workspace_id: container.workspace_id,
      container_id: container.id,
      slug: container.slug,
      name: container.name,
      docker_image: container.docker_image,
      status: status,
      docker_container_id: Keyword.get(opts, :docker_container_id),
      timestamp: DateTime.utc_now()
    }
  end
end
