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

defmodule Msfailab.Containers.ContainerRecord do
  @moduledoc """
  Schema for containers - first-class entities representing Docker container configurations.

  Each container defines a Docker container that can host multiple research tracks.
  The container's name and slug are user-defined, with the slug used for Docker
  container naming. Multiple tracks can share a single container, each getting
  their own MSGRPC console session within the shared Metasploit instance.

  ## Relationships

  - Belongs to a Workspace
  - Has many Tracks (each track uses this container's Docker environment)

  ## Docker Naming

  Docker containers are named using the format: `msfailab-{workspace_slug}-{container_slug}`
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Msfailab.Slug
  alias Msfailab.Tracks.Track
  alias Msfailab.Workspaces.Workspace

  @type t :: %__MODULE__{
          id: integer() | nil,
          slug: String.t() | nil,
          name: String.t() | nil,
          docker_image: String.t() | nil,
          workspace_id: integer() | nil,
          workspace: Workspace.t() | Ecto.Association.NotLoaded.t(),
          tracks: [Track.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "msfailab_containers" do
    field :slug, :string
    field :name, :string
    field :docker_image, :string

    belongs_to :workspace, Workspace
    has_many :tracks, Track, foreign_key: :container_id

    timestamps()
  end

  @doc """
  Changeset for creating a new container.
  """
  @spec create_changeset(t(), map()) :: Ecto.Changeset.t()
  def create_changeset(container, attrs) do
    container
    |> cast(attrs, [:slug, :name, :docker_image, :workspace_id])
    |> validate_required([:docker_image, :workspace_id])
    |> Slug.validate_slug(:slug)
    |> Slug.validate_name(:name)
    |> assoc_constraint(:workspace)
    |> unique_constraint([:workspace_id, :slug])
  end

  @doc """
  Changeset for updating an existing container.

  Only name and docker_image can be updated after creation.
  Slug cannot be changed as it's used for Docker container naming.
  """
  @spec update_changeset(t(), map()) :: Ecto.Changeset.t()
  def update_changeset(container, attrs) do
    container
    |> cast(attrs, [:name, :docker_image])
    |> Slug.validate_name(:name)
    |> validate_required([:docker_image])
  end
end
