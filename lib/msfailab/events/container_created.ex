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

defmodule Msfailab.Events.ContainerCreated do
  @moduledoc """
  Event broadcast when a new container is created.

  This is the base event in the container event chain. All subsequent container
  events (ContainerUpdated) include these same fields plus additional ones,
  enabling self-healing state reconstruction.

  ## Fields

  - `workspace_id` - The workspace containing this container
  - `container_id` - The newly created container's ID
  - `slug` - URL-safe identifier for the container
  - `name` - Human-readable display name
  - `docker_image` - Docker image used for the container
  - `timestamp` - When the container was created

  ## Self-Healing

  If a subscriber misses this event but receives a ContainerUpdated,
  they can reconstruct the container's existence from ContainerUpdated
  since it includes all fields from ContainerCreated.
  """

  alias Msfailab.Containers.ContainerRecord

  @type t :: %__MODULE__{
          workspace_id: integer(),
          container_id: integer(),
          slug: String.t(),
          name: String.t(),
          docker_image: String.t(),
          timestamp: DateTime.t()
        }

  @enforce_keys [:workspace_id, :container_id, :slug, :name, :docker_image, :timestamp]
  defstruct [:workspace_id, :container_id, :slug, :name, :docker_image, :timestamp]

  @doc """
  Creates a new ContainerCreated event from a container record.

  The container must have its workspace association loaded or workspace_id set.

  ## Examples

      iex> container = %ContainerRecord{id: 1, slug: "msf", name: "Metasploit", ...}
      iex> ContainerCreated.new(container)
      %ContainerCreated{container_id: 1, slug: "msf", name: "Metasploit", ...}
  """
  @spec new(ContainerRecord.t()) :: t()
  def new(%ContainerRecord{} = container) do
    %__MODULE__{
      workspace_id: container.workspace_id,
      container_id: container.id,
      slug: container.slug,
      name: container.name,
      docker_image: container.docker_image,
      timestamp: DateTime.utc_now()
    }
  end
end
