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

defmodule Msfailab.Tracks.ChatHistoryTurn do
  @moduledoc """
  Represents one complete agentic loop in the chat conversation.

  ## Conceptual Overview

  A **turn** is the fundamental unit of AI interaction. It begins when something
  triggers the AI (typically a user prompt) and ends when the AI stops responding
  (no more tool calls to process). A single turn may involve multiple LLM API
  calls if tools are involved.

  ```
  Turn 1:
    user_prompt
    → [LLM Response 1] → thinking, response, tool_call
    → tool_result
    → [LLM Response 2] → response, tool_call
    → tool_result
    → [LLM Response 3] → response (no tool_calls → FINISHED)

  Turn 2:
    user_prompt
    → [LLM Response 1] → response (no tool_calls → FINISHED)
  ```

  ## Status State Machine

  The turn status is **cyclical**, not linear. It cycles through states until
  the LLM responds without tool calls:

  ```
          ┌─────────────────────────────────────────────────┐
          │                                                 │
          ▼                                                 │
      pending ───► streaming ───► pending_approval ───► executing_tools
          │             │               │                   │
          │             │               │ (autonomous mode) │
          │             │               └───────────────────┤
          │             │                                   │
          │             ▼                                   │
          │        has tool_calls? ──── No ────► finished   │
          │             │                           │       │
          │            Yes                        error     │
          │             │                      interrupted  │
          └─────────────┴───────────────────────────────────┘
  ```

  ### Status Values

  | Status | Description |
  |--------|-------------|
  | `pending` | Waiting for LLM to start responding |
  | `streaming` | LLM is actively generating response |
  | `pending_approval` | Tool calls awaiting user approval |
  | `executing_tools` | Tools are running |
  | `finished` | Turn complete, agent idle |
  | `error` | Turn failed due to error |
  | `interrupted` | Turn was interrupted (e.g., process crash) |

  ## Triggers

  | Trigger | Description |
  |---------|-------------|
  | `user_prompt` | User initiated this turn with a message |
  | `scheduled_prompt` | (Future) Scheduled/automated prompt |
  | `script_triggered` | (Future) External script triggered the turn |

  ## Model Snapshots

  Each turn captures the model and tool_approval_mode at creation time. This
  allows model changes mid-conversation without affecting in-progress turns,
  and provides an audit trail of which model was used for each interaction.

  ## Relationships

  - **Belongs to** a Track (the conversation owner)
  - **Has many** LLM responses (API calls within this turn)
  - **Has many** entries (timeline slots created during this turn)

  ## Usage Example

  ```elixir
  # Create a new turn when user sends a message
  {:ok, turn} = %ChatHistoryTurn{}
    |> ChatHistoryTurn.changeset(%{
      track_id: track.id,
      position: next_turn_position(track.id),
      trigger: "user_prompt",
      model: track.current_model,
      tool_approval_mode: "ask_first"
    })
    |> Repo.insert()

  # Update status as the turn progresses
  turn
  |> ChatHistoryTurn.status_changeset("streaming")
  |> Repo.update()
  ```
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Msfailab.Tracks.ChatHistoryEntry
  alias Msfailab.Tracks.ChatHistoryLLMResponse
  alias Msfailab.Tracks.Track

  @statuses ~w(pending streaming pending_approval executing_tools finished error interrupted)
  @triggers ~w(user_prompt scheduled_prompt script_triggered)

  @type status ::
          :pending
          | :streaming
          | :pending_approval
          | :executing_tools
          | :finished
          | :error
          | :interrupted

  @type trigger :: :user_prompt | :scheduled_prompt | :script_triggered

  @type t :: %__MODULE__{
          id: integer() | nil,
          track_id: integer() | nil,
          track: Track.t() | Ecto.Association.NotLoaded.t(),
          position: integer() | nil,
          trigger: String.t() | nil,
          status: String.t(),
          model: String.t() | nil,
          tool_approval_mode: String.t() | nil,
          llm_responses: [ChatHistoryLLMResponse.t()] | Ecto.Association.NotLoaded.t(),
          entries: [ChatHistoryEntry.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "msfailab_track_chat_history_turns" do
    field :position, :integer
    field :trigger, :string
    field :status, :string, default: "pending"
    field :model, :string
    field :tool_approval_mode, :string

    belongs_to :track, Track
    has_many :llm_responses, ChatHistoryLLMResponse, foreign_key: :turn_id
    has_many :entries, ChatHistoryEntry, foreign_key: :turn_id

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating or updating a turn.

  ## Required Fields

  - `track_id` - The track this turn belongs to
  - `position` - Monotonic position within the track's turns
  - `trigger` - What started this turn (user_prompt, scheduled_prompt, script_triggered)
  - `model` - The LLM model being used
  - `tool_approval_mode` - How tool calls should be approved
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(turn, attrs) do
    turn
    |> cast(attrs, [:position, :trigger, :status, :model, :tool_approval_mode, :track_id])
    |> validate_required([:position, :trigger, :model, :tool_approval_mode, :track_id])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:trigger, @triggers)
    |> validate_number(:position, greater_than: 0)
    |> foreign_key_constraint(:track_id)
  end

  @doc """
  Changeset for updating only the status field.

  Use this for status transitions during the turn lifecycle.
  """
  @spec status_changeset(t(), String.t()) :: Ecto.Changeset.t()
  def status_changeset(turn, status) do
    turn
    |> cast(%{status: status}, [:status])
    |> validate_inclusion(:status, @statuses)
  end

  @doc "Returns the list of valid status values."
  @spec statuses() :: [String.t()]
  def statuses, do: @statuses

  @doc "Returns the list of valid trigger values."
  @spec triggers() :: [String.t()]
  def triggers, do: @triggers
end
