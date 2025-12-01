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

defmodule Msfailab.Tracks.ConsoleHistoryBlock do
  @moduledoc """
  Represents a block in the Metasploit console history for a track.

  ## Block Types

  - `:startup` - Console initialization output (banner, version info)
  - `:command` - A command with its output

  ## Block Status

  - `:running` - Currently executing (in-memory only, never persisted)
  - `:finished` - Completed successfully (persisted to database)
  - `:interrupted` - Console died during execution (in-memory only)

  Only blocks with status `:finished` are persisted to the database.
  Running and interrupted blocks exist only in TrackServer memory.

  ## Usage

  TrackServer uses this struct for both in-memory state and persistence.
  When a block transitions from `:running` to `:finished`, it is persisted
  to the database. On TrackServer startup, persisted blocks are loaded
  to restore the console history.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Msfailab.Tracks.Track

  @type block_type :: :startup | :command
  @type block_status :: :running | :finished | :interrupted

  @type t :: %__MODULE__{
          id: integer() | nil,
          track_id: integer(),
          track: Track.t() | Ecto.Association.NotLoaded.t(),
          type: block_type(),
          status: block_status(),
          output: String.t(),
          prompt: String.t(),
          command: String.t() | nil,
          started_at: DateTime.t(),
          finished_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil
        }

  schema "msfailab_track_console_history_blocks" do
    field :type, Ecto.Enum, values: [:startup, :command]
    field :status, Ecto.Enum, values: [:running, :finished, :interrupted], virtual: true
    field :output, :string, default: ""
    field :prompt, :string, default: ""
    field :command, :string
    field :started_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec

    belongs_to :track, Track

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc """
  Creates a new in-memory startup block with status `:running`.
  """
  @spec new_startup(integer(), String.t()) :: t()
  def new_startup(track_id, output \\ "") do
    %__MODULE__{
      track_id: track_id,
      type: :startup,
      status: :running,
      output: output,
      prompt: "",
      started_at: DateTime.utc_now(),
      finished_at: nil
    }
  end

  @doc """
  Creates a new in-memory command block with status `:running`.
  """
  @spec new_command(integer(), String.t(), String.t()) :: t()
  def new_command(track_id, command, output \\ "") do
    %__MODULE__{
      track_id: track_id,
      type: :command,
      status: :running,
      command: command,
      output: output,
      prompt: "",
      started_at: DateTime.utc_now(),
      finished_at: nil
    }
  end

  @doc """
  Changeset for persisting a finished block to the database.

  Only accepts blocks with status `:finished`.
  """
  @spec persist_changeset(t()) :: Ecto.Changeset.t()
  def persist_changeset(%__MODULE__{status: :finished} = block) do
    block
    |> change()
    |> validate_required([:track_id, :type, :started_at, :finished_at])
    |> validate_command_presence()
    |> assoc_constraint(:track)
  end

  def persist_changeset(%__MODULE__{status: status}) do
    %__MODULE__{}
    |> change()
    |> add_error(:status, "must be :finished to persist, got #{inspect(status)}")
  end

  defp validate_command_presence(changeset) do
    type = get_field(changeset, :type)
    command = get_field(changeset, :command)

    case {type, command} do
      {:command, nil} ->
        add_error(changeset, :command, "is required for command blocks")

      {:command, ""} ->
        add_error(changeset, :command, "is required for command blocks")

      {:startup, cmd} when cmd != nil ->
        add_error(changeset, :command, "must be nil for startup blocks")

      _ ->
        changeset
    end
  end
end
