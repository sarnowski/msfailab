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

defmodule Msfailab.Workspaces do
  @moduledoc """
  Context module for managing workspaces.

  Workspaces are the top-level organizational unit representing distinct
  engagements, projects, or clients with complete data isolation.
  """
  import Ecto.Query

  alias Msfailab.Repo
  alias Msfailab.Workspaces.Workspace

  @doc """
  Returns all active (non-archived) workspaces.
  """
  def list_workspaces do
    Workspace
    |> where([w], is_nil(w.archived_at))
    |> order_by([w], asc: w.name)
    |> Repo.all()
  end

  @doc """
  Returns all workspaces including archived ones.
  """
  def list_all_workspaces do
    Workspace
    |> order_by([w], asc: w.name)
    |> Repo.all()
  end

  @doc """
  Gets a workspace by ID.

  Returns `nil` if the workspace does not exist.
  """
  def get_workspace(id), do: Repo.get(Workspace, id)

  @doc """
  Gets a workspace by ID.

  Raises `Ecto.NoResultsError` if the workspace does not exist.
  """
  def get_workspace!(id), do: Repo.get!(Workspace, id)

  @doc """
  Gets an active workspace by slug.

  Returns `nil` if the workspace does not exist or is archived.
  """
  def get_workspace_by_slug(slug) do
    Workspace
    |> where([w], w.slug == ^slug and is_nil(w.archived_at))
    |> Repo.one()
  end

  @doc """
  Checks if a workspace slug is already taken.

  Returns `true` if the slug exists, `false` otherwise.
  """
  def slug_exists?(slug) when is_binary(slug) and slug != "" do
    Workspace
    |> where([w], w.slug == ^slug)
    |> Repo.exists?()
  end

  def slug_exists?(_), do: false

  @doc """
  Creates a new workspace.
  """
  def create_workspace(attrs) do
    %Workspace{}
    |> Workspace.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an existing workspace.
  """
  def update_workspace(%Workspace{} = workspace, attrs) do
    workspace
    |> Workspace.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Archives a workspace.

  Archived workspaces are not listed by default and cannot be accessed via slug.
  """
  def archive_workspace(%Workspace{} = workspace) do
    workspace
    |> Workspace.archive_changeset()
    |> Repo.update()
  end

  @doc """
  Returns a changeset for tracking workspace changes.
  """
  def change_workspace(%Workspace{} = workspace, attrs \\ %{}) do
    Workspace.create_changeset(workspace, attrs)
  end
end
