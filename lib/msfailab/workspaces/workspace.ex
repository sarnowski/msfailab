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

defmodule Msfailab.Workspaces.Workspace do
  @moduledoc """
  Schema for workspaces - the top-level organizational unit representing a
  distinct engagement, project, or client.

  Workspaces provide complete data isolation and maintain their own knowledge
  store for hosts, services, vulnerabilities, credentials, and notes.

  ## Relationships

  - Has many Containers (each running a Metasploit instance)
  - Tracks are accessed via containers
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Msfailab.Containers.ContainerRecord
  alias Msfailab.Slug

  @type t :: %__MODULE__{
          id: integer() | nil,
          slug: String.t() | nil,
          name: String.t() | nil,
          description: String.t() | nil,
          default_model: String.t() | nil,
          archived_at: DateTime.t() | nil,
          containers: [ContainerRecord.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "msfailab_workspaces" do
    field :slug, :string
    field :name, :string
    field :description, :string
    field :default_model, :string
    field :archived_at, :utc_datetime

    has_many :containers, ContainerRecord

    timestamps()
  end

  @doc """
  Changeset for creating a new workspace.
  """
  @spec create_changeset(t(), map()) :: Ecto.Changeset.t()
  def create_changeset(workspace, attrs) do
    workspace
    |> cast(attrs, [:slug, :name, :description, :default_model])
    |> Slug.validate_slug(:slug)
    |> Slug.validate_name(:name)
    |> unique_constraint(:slug)
  end

  @doc """
  Changeset for updating an existing workspace.
  """
  @spec update_changeset(t(), map()) :: Ecto.Changeset.t()
  def update_changeset(workspace, attrs) do
    workspace
    |> cast(attrs, [:name, :description, :default_model])
    |> Slug.validate_name(:name)
  end

  @doc """
  Changeset for archiving a workspace.
  """
  @spec archive_changeset(t()) :: Ecto.Changeset.t()
  def archive_changeset(workspace) do
    workspace
    |> change(archived_at: DateTime.utc_now() |> DateTime.truncate(:second))
  end
end
