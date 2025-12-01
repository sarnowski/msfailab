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

defmodule Msfailab.Tracks.Track do
  @moduledoc """
  Schema for tracks - active research sessions within containers.

  Each track represents a focused investigation stream (e.g., "initial recon",
  "pivot to internal", "AD exploitation") with its own dedicated Metasploit
  console session and AI assistant.

  ## Relationships

  - Belongs to a Container (which provides the Docker environment)
  - Workspace is accessed via the container association
  - Has many chat history turns, entries, and compactions

  ## Console Session

  Each track gets its own MSGRPC console session within its container's
  Metasploit instance. This allows multiple tracks to share the same
  Metasploit database and sessions while maintaining separate console
  state and command history.

  ## Chat History

  The track owns all chat state - there is no separate conversation entity.
  Chat history is organized into:

  - **Turns**: Agentic loops (user prompt → AI responses → tools → done)
  - **Entries**: The conversation timeline with position-based ordering
  - **Compactions**: Summaries that replace older content for context management

  See `Msfailab.Tracks.ChatHistoryEntry` for detailed documentation of the
  chat history architecture.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Msfailab.Containers.ContainerRecord
  alias Msfailab.Slug
  alias Msfailab.Tracks.ChatCompaction
  alias Msfailab.Tracks.ChatHistoryEntry
  alias Msfailab.Tracks.ChatHistoryLLMResponse
  alias Msfailab.Tracks.ChatHistoryTurn

  @type t :: %__MODULE__{
          id: integer() | nil,
          slug: String.t() | nil,
          name: String.t() | nil,
          current_model: String.t() | nil,
          autonomous: boolean(),
          archived_at: DateTime.t() | nil,
          container_id: integer() | nil,
          container: ContainerRecord.t() | Ecto.Association.NotLoaded.t(),
          chat_turns: [ChatHistoryTurn.t()] | Ecto.Association.NotLoaded.t(),
          chat_entries: [ChatHistoryEntry.t()] | Ecto.Association.NotLoaded.t(),
          chat_llm_responses: [ChatHistoryLLMResponse.t()] | Ecto.Association.NotLoaded.t(),
          chat_compactions: [ChatCompaction.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "msfailab_tracks" do
    field :slug, :string
    field :name, :string
    field :current_model, :string
    field :autonomous, :boolean, default: false
    field :archived_at, :utc_datetime

    belongs_to :container, ContainerRecord

    # Chat history associations
    has_many :chat_turns, ChatHistoryTurn
    has_many :chat_entries, ChatHistoryEntry
    has_many :chat_llm_responses, ChatHistoryLLMResponse
    has_many :chat_compactions, ChatCompaction

    timestamps()
  end

  @doc """
  Changeset for creating a new track.
  """
  @spec create_changeset(t(), map()) :: Ecto.Changeset.t()
  def create_changeset(track, attrs) do
    track
    |> cast(attrs, [:slug, :name, :current_model, :container_id])
    |> validate_required([:container_id])
    |> Slug.validate_slug(:slug)
    |> Slug.validate_name(:name)
    |> assoc_constraint(:container)
    |> unique_constraint([:container_id, :slug])
  end

  @doc """
  Changeset for updating an existing track.
  """
  @spec update_changeset(t(), map()) :: Ecto.Changeset.t()
  def update_changeset(track, attrs) do
    track
    |> cast(attrs, [:name, :current_model, :autonomous])
    |> Slug.validate_name(:name)
  end

  @doc """
  Changeset for archiving a track.
  """
  @spec archive_changeset(t()) :: Ecto.Changeset.t()
  def archive_changeset(track) do
    track
    |> change(archived_at: DateTime.utc_now() |> DateTime.truncate(:second))
  end
end
