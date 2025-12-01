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

defmodule Msfailab.Tracks.ChatConsoleContext do
  @moduledoc """
  Content table for console context entries - user-initiated MSF activity.

  ## Conceptual Overview

  A **console context** captures Metasploit console commands executed directly
  by the user (not via AI tool calls) that should be visible to the AI assistant.
  This enables the AI to:

  - See what the user is doing manually
  - Understand the current state of the engagement
  - Provide relevant suggestions based on recent activity
  - Avoid redundant commands the user already ran

  ## Key Distinction from Tool Invocations

  | Aspect | Console Context | Tool Invocation |
  |--------|-----------------|-----------------|
  | **Initiator** | Human user | AI assistant |
  | **Turn-scoped** | No (no turn_id) | Yes (has turn_id) |
  | **Status tracking** | None (already complete) | Full lifecycle |
  | **Approval flow** | N/A | May require approval |

  ## Not Turn-Scoped

  Console context entries are the **only entry type without a turn_id**. They
  represent user activity that occurs outside of AI turns - either between
  turns or concurrent with them.

  ## Timing and Buffering

  Console commands may complete while the LLM is streaming a response. To
  maintain proper timeline ordering, the TrackServer buffers console contexts
  during LLM streaming and inserts them after the response completes:

  ```
  Time    Event                          Position Assignment
  ─────   ─────                          ──────────────────
  t=0     User sends prompt              (starts turn)
  t=1     LLM starts streaming           entry pos=1 (user prompt)
  t=2     User runs "sessions -l"        [BUFFERED]
  t=3     LLM continues streaming        entry pos=2 (AI response, streaming)
  t=4     LLM finishes                   pos=2 finalized
  t=5     Buffer flushed                 entry pos=3 (console context)
  ```

  This ensures console contexts always appear after the LLM entries they
  were concurrent with, maintaining a clean chronological narrative.

  ## LLM Context Building

  Console contexts are formatted distinctly in LLM messages to clearly
  indicate they are user-initiated activity:

  ```elixir
  def entry_to_llm_message(%{entry_type: "console_context", console_context: cc}) do
    %{
      role: "user",
      content: \"""
      [CONSOLE ACTIVITY]
      The user executed the following commands in the Metasploit console:

      \#{cc.content}

      [END CONSOLE ACTIVITY]
      \"""
    }
  end
  ```

  ## Source Tracking

  The `console_history_block_id` field links back to the original
  `ConsoleHistoryBlock` that generated this context. This enables:

  - Traceability to the original command and output
  - Deduplication (don't create duplicate contexts for same block)
  - UI linking (click to see full console output)

  ## Usage Example

  ```elixir
  # When a user command completes in the MSF console
  def handle_console_block_finished(track_id, block) do
    # Check if we should create a context entry
    if should_include_in_chat?(block) do
      {:ok, entry} = create_console_context_entry(track_id, block)
      broadcast_entry_created(entry)
    end
  end

  defp create_console_context_entry(track_id, block) do
    Repo.transaction(fn ->
      position = next_position(track_id)

      {:ok, entry} = %ChatHistoryEntry{}
        |> ChatHistoryEntry.changeset(%{
          track_id: track_id,
          turn_id: nil,  # NOT turn-scoped
          position: position,
          entry_type: "console_context"
        })
        |> Repo.insert()

      {:ok, _context} = %ChatConsoleContext{}
        |> ChatConsoleContext.changeset(%{
          entry_id: entry.id,
          content: format_block(block),
          console_history_block_id: block.id
        })
        |> Repo.insert()

      entry
    end)
  end
  ```
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Msfailab.Tracks.ChatHistoryEntry

  @primary_key {:entry_id, :id, autogenerate: false}

  @type t :: %__MODULE__{
          entry_id: integer() | nil,
          entry: ChatHistoryEntry.t() | Ecto.Association.NotLoaded.t(),
          content: String.t() | nil,
          console_history_block_id: integer() | nil
        }

  schema "msfailab_track_chat_console_contexts" do
    field :content, :string
    field :console_history_block_id, :integer

    belongs_to :entry, ChatHistoryEntry,
      foreign_key: :entry_id,
      references: :id,
      define_field: false
  end

  @doc """
  Changeset for creating a console context.

  ## Required Fields

  - `entry_id` - The entry this context belongs to (1:1 relationship)
  - `content` - The formatted command and output text

  ## Optional Fields

  - `console_history_block_id` - Reference to the source ConsoleHistoryBlock
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(console_context, attrs) do
    console_context
    |> cast(attrs, [:entry_id, :content, :console_history_block_id])
    |> validate_required([:entry_id, :content])
    |> foreign_key_constraint(:entry_id)
  end
end
