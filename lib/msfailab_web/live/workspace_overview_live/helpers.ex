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

defmodule MsfailabWeb.WorkspaceOverviewLive.Helpers do
  @moduledoc """
  Pure helper functions for WorkspaceOverviewLive.

  These functions contain conditional logic extracted from the LiveView
  to enable comprehensive unit testing without process setup.
  """

  alias Ecto.Changeset
  alias Msfailab.Workspaces

  @doc """
  Generates the helper text for the slug field showing the full URL.

  Returns the full URL with the actual slug if valid, or a placeholder
  if the slug is empty or has errors.

  ## Examples

      iex> field = %{value: "my-workspace", errors: []}
      iex> Helpers.slug_helper(field, "https://example.com")
      "https://example.com/my-workspace"

      iex> field = %{value: "", errors: []}
      iex> Helpers.slug_helper(field, "https://example.com")
      "https://example.com/your-slug"

      iex> field = %{value: "test", errors: [slug: {"is invalid", []}]}
      iex> Helpers.slug_helper(field, "https://example.com")
      "https://example.com/your-slug"
  """
  @spec slug_helper(map(), String.t()) :: String.t()
  def slug_helper(field, base_url) do
    slug = field.value
    has_errors = field.errors != []

    if slug && slug != "" && !has_errors do
      "#{base_url}/#{slug}"
    else
      "#{base_url}/your-slug"
    end
  end

  @doc """
  Validates that a slug is unique across all workspaces.

  Adds an error to the changeset if the slug already exists.

  ## Examples

      iex> changeset = Ecto.Changeset.change(%Workspace{}, %{slug: "existing-slug"})
      iex> # Assuming "existing-slug" exists in the database
      iex> changeset = Helpers.validate_slug_uniqueness(changeset)
      iex> changeset.errors[:slug]
      {"is already taken", []}
  """
  @spec validate_slug_uniqueness(Changeset.t()) :: Changeset.t()
  def validate_slug_uniqueness(changeset) do
    slug = Changeset.get_field(changeset, :slug)

    if slug && Workspaces.slug_exists?(slug) do
      Changeset.add_error(changeset, :slug, "is already taken")
    else
      changeset
    end
  end
end
