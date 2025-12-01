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

defmodule Msfailab.Tracks.ChatMessage do
  @moduledoc """
  Content table for message-type chat entries.

  ## Conceptual Overview

  A **message** holds textual content for conversation entries. Messages
  represent three kinds of content:

  1. **User prompts** - Questions or instructions from the human researcher
  2. **AI thinking** - Extended reasoning (may be hidden from UI in some modes)
  3. **AI responses** - The assistant's visible replies

  ## Role and Message Type Combinations

  Not all combinations are valid. The schema enforces these constraints:

  | Role | Message Type | Description |
  |------|--------------|-------------|
  | `user` | `prompt` | User's input message |
  | `assistant` | `thinking` | AI's extended thinking (Claude's thinking blocks) |
  | `assistant` | `response` | AI's visible response |

  Invalid combinations (enforced by changeset validation):
  - `user` + `thinking` (users don't have thinking blocks)
  - `user` + `response` (users don't respond)
  - `assistant` + `prompt` (assistants don't prompt)

  ## Shared Identity with Entry

  Messages use `entry_id` as their primary key, establishing a 1:1 relationship
  with `ChatHistoryEntry`. This design:

  - Ensures exactly one content record per entry
  - Simplifies queries (join on entry_id)
  - Maintains referential integrity via foreign key

  ## Content Streaming

  During LLM streaming, message content is updated incrementally:

  ```elixir
  # Initial creation with empty content
  %ChatMessage{entry_id: entry.id, role: "assistant", message_type: "response", content: ""}

  # Updated as tokens arrive
  message
  |> ChatMessage.update_changeset(%{content: accumulated_content})
  |> Repo.update()
  ```

  The TrackServer typically holds streaming content in memory and persists
  only when the response completes.

  ## LLM Context Building

  When building messages for LLM requests:

  ```elixir
  def entry_to_llm_message(%{entry_type: "message", message: msg}) do
    %{role: msg.role, content: msg.content}
  end
  ```

  For Anthropic's API with thinking blocks:

  ```elixir
  def entry_to_anthropic_content(%{message: %{message_type: "thinking"} = msg}) do
    %{type: "thinking", thinking: msg.content}
  end

  def entry_to_anthropic_content(%{message: %{message_type: "response"} = msg}) do
    %{type: "text", text: msg.content}
  end
  ```

  ## Usage Example

  ```elixir
  # Create a user prompt message
  {:ok, message} = %ChatMessage{}
    |> ChatMessage.changeset(%{
      entry_id: entry.id,
      role: "user",
      message_type: "prompt",
      content: "Scan 192.168.1.0/24 for web servers"
    })
    |> Repo.insert()

  # Create an AI response
  {:ok, response} = %ChatMessage{}
    |> ChatMessage.changeset(%{
      entry_id: response_entry.id,
      role: "assistant",
      message_type: "response",
      content: "I'll run an nmap scan targeting HTTP and HTTPS ports..."
    })
    |> Repo.insert()
  ```
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Msfailab.Tracks.ChatHistoryEntry

  @primary_key {:entry_id, :id, autogenerate: false}

  @roles ~w(user assistant)
  @message_types ~w(prompt thinking response)

  @type role :: :user | :assistant
  @type message_type :: :prompt | :thinking | :response

  @type t :: %__MODULE__{
          entry_id: integer() | nil,
          entry: ChatHistoryEntry.t() | Ecto.Association.NotLoaded.t(),
          role: String.t() | nil,
          message_type: String.t() | nil,
          content: String.t()
        }

  schema "msfailab_track_chat_messages" do
    field :role, :string
    field :message_type, :string
    field :content, :string, default: ""

    belongs_to :entry, ChatHistoryEntry,
      foreign_key: :entry_id,
      references: :id,
      define_field: false
  end

  @doc """
  Changeset for creating a message.

  ## Required Fields

  - `entry_id` - The entry this message belongs to (1:1 relationship)
  - `role` - Either "user" or "assistant"
  - `message_type` - One of: "prompt", "thinking", "response"

  ## Optional Fields

  - `content` - The message text (defaults to empty string for streaming)

  ## Validation

  The changeset validates that role and message_type form a valid combination:
  - user + prompt ✓
  - assistant + thinking ✓
  - assistant + response ✓
  - All other combinations are rejected
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:entry_id, :role, :message_type, :content])
    |> validate_required([:entry_id, :role, :message_type])
    |> validate_inclusion(:role, @roles)
    |> validate_inclusion(:message_type, @message_types)
    |> validate_role_message_type_combination()
    |> foreign_key_constraint(:entry_id)
  end

  @doc """
  Changeset for updating message content (e.g., during streaming).
  """
  @spec update_changeset(t(), map()) :: Ecto.Changeset.t()
  def update_changeset(message, attrs) do
    message
    |> cast(attrs, [:content])
  end

  defp validate_role_message_type_combination(changeset) do
    role = get_field(changeset, :role)
    message_type = get_field(changeset, :message_type)

    case {role, message_type} do
      {"user", "prompt"} ->
        changeset

      {"assistant", type} when type in ~w(thinking response) ->
        changeset

      {nil, _} ->
        changeset

      {_, nil} ->
        changeset

      {role, type} ->
        add_error(
          changeset,
          :message_type,
          "#{type} is invalid for role #{role}; valid: user+prompt, assistant+thinking/response"
        )
    end
  end

  @doc "Returns the list of valid role values."
  @spec roles() :: [String.t()]
  def roles, do: @roles

  @doc "Returns the list of valid message type values."
  @spec message_types() :: [String.t()]
  def message_types, do: @message_types
end
