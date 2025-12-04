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

defmodule Msfailab.Tracks.Memory.Task do
  @moduledoc """
  A task within track memory.

  Tasks represent planned work items with status tracking:
  - `:pending` - Not yet started
  - `:in_progress` - Currently being worked on
  - `:completed` - Finished
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type status :: :pending | :in_progress | :completed

  @type t :: %__MODULE__{
          id: String.t(),
          content: String.t(),
          status: status()
        }

  @primary_key false
  embedded_schema do
    field :id, :string
    field :content, :string
    field :status, Ecto.Enum, values: [:pending, :in_progress, :completed]
  end

  @doc """
  Changeset for task creation/updates.
  """
  # coveralls-ignore-start
  # Reason: Ecto boilerplate called internally by cast_embed.
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(task, attrs) do
    task
    |> cast(attrs, [:id, :content, :status])
    |> validate_required([:id, :content, :status])
  end

  # coveralls-ignore-stop

  @doc """
  Converts task to a map with string keys.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = task) do
    %{
      "id" => task.id,
      "content" => task.content,
      "status" => Atom.to_string(task.status)
    }
  end
end
