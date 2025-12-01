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

defmodule Msfailab.Tracks.ChatHistoryEntry do
  @moduledoc """
  A slot in the conversation timeline with position-based ordering.

  ## Conceptual Overview

  An **entry** is the core building block of the chat timeline. Every piece
  of content in the conversation - user messages, AI responses, tool calls,
  console activity - is represented as an entry with a unique position.

  ```
  Entry 1: position=1, type=message (user prompt)
  Entry 2: position=2, type=message (AI response)
  Entry 3: position=3, type=tool_invocation
  Entry 4: position=4, type=message (AI response)
  Entry 5: position=5, type=console_context (user ran MSF command)
  Entry 6: position=6, type=message (user prompt)
  ...
  ```

  ## Position Semantics

  The `position` field is:

  - **Monotonically increasing**: Each new entry gets `max(position) + 1`
  - **Immutable**: Never changes after creation
  - **Track-scoped**: Unique within a track
  - **The only ordering**: No computed or secondary ordering fields

  Position is assigned by the TrackServer GenServer to guarantee uniqueness
  and proper sequencing, especially during concurrent operations like LLM
  streaming and console command completion.

  ## Entry Types

  Each entry type has a dedicated content table for type safety:

  | Type | Content Table | Turn-Scoped | Description |
  |------|---------------|-------------|-------------|
  | `message` | `ChatMessage` | Yes | User prompts, AI thinking, AI responses |
  | `tool_invocation` | `ChatToolInvocation` | Yes | Tool call + result (combined) |
  | `console_context` | `ChatConsoleContext` | **No** | MSF commands run by user |

  ## Entry Lifecycle

  ```
                      ENTRY LIFECYCLE

       ┌─────────────────────────────────────────────────┐
       │                                                 │
       │  CREATED                                        │
       │  ════════                                       │
       │  position = next_position()                     │
       │  entry_type = "message" | "tool_invocation" |   │
       │               "console_context"                 │
       │  turn_id = current turn (or NULL for            │
       │            console_context)                     │
       │  llm_response_id = current response (or NULL)   │
       │                                                 │
       └──────────────────┬──────────────────────────────┘
                          │
                          │ Entry is immutable after creation.
                          │ Content may be updated (streaming, tool results).
                          │
                          ▼
       ┌─────────────────────────────────────────────────┐
       │                                                 │
       │  INCLUDED IN LLM CONTEXT                        │
       │  ═══════════════════════                        │
       │                                                 │
       │  Entry is included in LLM requests until        │
       │  compaction summarizes it.                      │
       │                                                 │
       └──────────────────┬──────────────────────────────┘
                          │
                          │ (when compaction runs)
                          │
                          ▼
       ┌─────────────────────────────────────────────────┐
       │                                                 │
       │  SUMMARIZED BY COMPACTION                       │
       │  ════════════════════════                       │
       │                                                 │
       │  Entry's position <= compaction's               │
       │  summarized_up_to_position.                     │
       │                                                 │
       │  Entry is excluded from LLM context but         │
       │  retained for audit trail and search.           │
       │                                                 │
       └─────────────────────────────────────────────────┘
  ```

  ## Type Discriminator Pattern

  The `entry_type` field determines which associated content table holds the
  payload. Exactly one of `message`, `tool_invocation`, or `console_context`
  will be populated based on the entry type.

  ## Relationships

  - **Belongs to** a Track (the conversation owner)
  - **Belongs to** a Turn (optional; NULL for console_context entries)
  - **Belongs to** an LLM Response (optional; only for AI-generated entries)
  - **Has one** message, tool_invocation, or console_context (based on entry_type)

  ## Usage Example

  ```elixir
  # Create a message entry with its content
  Repo.transaction(fn ->
    position = next_position(track_id)

    {:ok, entry} = %ChatHistoryEntry{}
      |> ChatHistoryEntry.changeset(%{
        track_id: track_id,
        turn_id: turn_id,
        llm_response_id: llm_response_id,
        position: position,
        entry_type: "message"
      })
      |> Repo.insert()

    {:ok, _message} = %ChatMessage{}
      |> ChatMessage.changeset(%{
        entry_id: entry.id,
        role: "assistant",
        message_type: "response",
        content: "Scanning the target network..."
      })
      |> Repo.insert()

    entry
  end)
  ```

  ## Querying for LLM Context

  To build the message array for an LLM request:

  ```elixir
  # Get entries not yet summarized by compaction
  def get_active_entries(track_id, compaction_position \\\\ 0) do
    from(e in ChatHistoryEntry,
      where: e.track_id == ^track_id,
      where: e.position > ^compaction_position,
      order_by: e.position,
      preload: [:message, :tool_invocation, :console_context]
    )
    |> Repo.all()
  end
  ```
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Msfailab.Tracks.ChatConsoleContext
  alias Msfailab.Tracks.ChatHistoryLLMResponse
  alias Msfailab.Tracks.ChatHistoryTurn
  alias Msfailab.Tracks.ChatMessage
  alias Msfailab.Tracks.ChatToolInvocation
  alias Msfailab.Tracks.Track

  @entry_types ~w(message tool_invocation console_context)

  @type entry_type :: :message | :tool_invocation | :console_context

  @type t :: %__MODULE__{
          id: integer() | nil,
          track_id: integer() | nil,
          track: Track.t() | Ecto.Association.NotLoaded.t(),
          turn_id: integer() | nil,
          turn: ChatHistoryTurn.t() | Ecto.Association.NotLoaded.t() | nil,
          llm_response_id: integer() | nil,
          llm_response: ChatHistoryLLMResponse.t() | Ecto.Association.NotLoaded.t() | nil,
          position: integer() | nil,
          entry_type: String.t() | nil,
          message: ChatMessage.t() | Ecto.Association.NotLoaded.t() | nil,
          tool_invocation: ChatToolInvocation.t() | Ecto.Association.NotLoaded.t() | nil,
          console_context: ChatConsoleContext.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "msfailab_track_chat_history_entries" do
    field :position, :integer
    field :entry_type, :string

    belongs_to :track, Track
    belongs_to :turn, ChatHistoryTurn
    belongs_to :llm_response, ChatHistoryLLMResponse

    # Content associations (exactly one based on entry_type)
    has_one :message, ChatMessage, foreign_key: :entry_id
    has_one :tool_invocation, ChatToolInvocation, foreign_key: :entry_id
    has_one :console_context, ChatConsoleContext, foreign_key: :entry_id

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating or updating an entry.

  ## Required Fields

  - `track_id` - The track this entry belongs to
  - `position` - Unique position in the timeline (monotonically increasing)
  - `entry_type` - One of: "message", "tool_invocation", "console_context"

  ## Optional Fields

  - `turn_id` - The turn this entry is part of (NULL for console_context)
  - `llm_response_id` - The LLM response that generated this entry
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:position, :entry_type, :track_id, :turn_id, :llm_response_id])
    |> validate_required([:position, :entry_type, :track_id])
    |> validate_inclusion(:entry_type, @entry_types)
    |> validate_number(:position, greater_than: 0)
    |> foreign_key_constraint(:track_id)
    |> foreign_key_constraint(:turn_id)
    |> foreign_key_constraint(:llm_response_id)
    |> unique_constraint(:position,
      name: :msfailab_track_chat_history_entries_track_id_position_index
    )
  end

  @doc "Returns the list of valid entry type values."
  @spec entry_types() :: [String.t()]
  def entry_types, do: @entry_types
end
