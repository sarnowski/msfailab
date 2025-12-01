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

defmodule Msfailab.Tracks.ChatCompaction do
  @moduledoc """
  Summaries that replace older conversation content for context management.

  ## Conceptual Overview

  A **compaction** is a summary that condenses older conversation entries
  into a shorter form. This enables long-running security research sessions
  without hitting LLM context limits. Key properties:

  1. **Cumulative**: Each compaction summarizes everything up to a position,
     including the content of previous compactions
  2. **Only latest matters**: For LLM context, only the most recent compaction
     is included
  3. **Chain for audit**: Previous compactions form an audit trail
  4. **Entries preserved**: Original entries are never deleted, just excluded
     from LLM context

  ## Not Part of the Timeline

  Compactions are **not entries**. They don't have positions in the conversation
  timeline. Instead, they reference positions to define what they summarize.

  ## Compaction Example

  ```
  Initial conversation:
    M1(pos=1) M2(pos=2) M3(pos=3) M4(pos=4) M5(pos=5) M6(pos=6)

  After first compaction:
    [C1 summarizes M1-M3] M4(pos=4) M5(pos=5) M6(pos=6)

    C1: summarized_up_to_position = 3

    LLM sees: [C1.content] [M4] [M5] [M6]

  More conversation:
    ... M7(pos=7) M8(pos=8) M9(pos=9) M10(pos=10)

  After second compaction:
    [C2 summarizes C1+M4-M6] M7(pos=7) M8(pos=8) M9(pos=9) M10(pos=10)

    C2: summarized_up_to_position = 6, previous_compaction_id = C1.id

    LLM sees: [C2.content] [M7] [M8] [M9] [M10]
  ```

  ## When to Compact

  Compaction is triggered when:
  - Token count approaches the model's context limit
  - Explicitly requested by the user
  - Conversation reaches a natural breakpoint

  The system estimates tokens by character count (roughly 4 chars per token)
  and tracks actual counts via the compaction metrics.

  ## Compaction Process

  1. **Estimate current context size** using token metrics from recent LLM responses
  2. **Determine compaction boundary** (which position to summarize up to)
  3. **Generate summary** via LLM call with summarization prompt
  4. **Create compaction record** with metrics
  5. **Future LLM calls** exclude summarized entries, include compaction content

  ## Audit Chain

  The `previous_compaction_id` creates a linked list of compactions:

  ```
  C3 → C2 → C1 → nil
  ```

  This enables:
  - Audit trail of what was summarized when
  - Reconstruction of summarization history
  - Analysis of compaction effectiveness

  ## Token Metrics

  Each compaction records before/after token counts:

  - `input_tokens_before`: Estimated tokens if all entries were included
  - `input_tokens_after`: Actual tokens with compaction summary

  This enables analysis of compaction effectiveness:
  ```elixir
  compression_ratio = compaction.input_tokens_after / compaction.input_tokens_before
  ```

  ## LLM Context Building

  When building context for an LLM request:

  ```elixir
  def get_context(track_id) do
    # 1. Get latest compaction
    latest_compaction = get_latest_compaction(track_id)

    # 2. Determine minimum position
    min_position = if latest_compaction, do: latest_compaction.summarized_up_to_position, else: 0

    # 3. Get entries after compaction range
    entries = get_entries_after_position(track_id, min_position)

    %{compaction: latest_compaction, entries: entries}
  end
  ```

  The compaction content is formatted as a system-level summary:

  ```elixir
  def compaction_to_message(%{content: content}) do
    %{
      role: "user",
      content: \"""
      [CONVERSATION SUMMARY]
      The following is a summary of our previous conversation:

      \#{content}

      [END SUMMARY]
      \"""
    }
  end
  ```

  ## Usage Example

  ```elixir
  # Create a compaction after summarization
  {:ok, compaction} = %ChatCompaction{}
    |> ChatCompaction.changeset(%{
      track_id: track.id,
      content: summary_text,
      summarized_up_to_position: last_position,
      previous_compaction_id: previous_compaction_id,
      entries_summarized_count: entry_count,
      input_tokens_before: tokens_before,
      input_tokens_after: tokens_after,
      compaction_model: "claude-sonnet-4-20250514",
      compaction_duration_ms: duration
    })
    |> Repo.insert()
  ```
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Msfailab.Tracks.Track

  @type t :: %__MODULE__{
          id: integer() | nil,
          track_id: integer() | nil,
          track: Track.t() | Ecto.Association.NotLoaded.t(),
          content: String.t() | nil,
          summarized_up_to_position: integer() | nil,
          previous_compaction_id: integer() | nil,
          previous_compaction: t() | Ecto.Association.NotLoaded.t() | nil,
          entries_summarized_count: integer() | nil,
          input_tokens_before: integer() | nil,
          input_tokens_after: integer() | nil,
          compaction_model: String.t() | nil,
          compaction_duration_ms: integer() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "msfailab_track_chat_compactions" do
    field :content, :string
    field :summarized_up_to_position, :integer
    field :entries_summarized_count, :integer
    field :input_tokens_before, :integer
    field :input_tokens_after, :integer
    field :compaction_model, :string
    field :compaction_duration_ms, :integer

    belongs_to :track, Track
    belongs_to :previous_compaction, __MODULE__

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a compaction.

  ## Required Fields

  - `track_id` - The track this compaction belongs to
  - `content` - The summary text
  - `summarized_up_to_position` - Last entry position included in summary
  - `entries_summarized_count` - Number of entries summarized
  - `input_tokens_before` - Estimated tokens before compaction
  - `input_tokens_after` - Actual tokens after compaction
  - `compaction_model` - Model used to generate the summary

  ## Optional Fields

  - `previous_compaction_id` - Link to previous compaction (audit chain)
  - `compaction_duration_ms` - Time taken to generate summary
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(compaction, attrs) do
    compaction
    |> cast(attrs, [
      :content,
      :summarized_up_to_position,
      :entries_summarized_count,
      :input_tokens_before,
      :input_tokens_after,
      :compaction_model,
      :compaction_duration_ms,
      :track_id,
      :previous_compaction_id
    ])
    |> validate_required([
      :content,
      :summarized_up_to_position,
      :entries_summarized_count,
      :input_tokens_before,
      :input_tokens_after,
      :compaction_model,
      :track_id
    ])
    |> validate_number(:summarized_up_to_position, greater_than: 0)
    |> validate_number(:entries_summarized_count, greater_than: 0)
    |> validate_number(:input_tokens_before, greater_than: 0)
    |> validate_number(:input_tokens_after, greater_than: 0)
    |> foreign_key_constraint(:track_id)
    |> foreign_key_constraint(:previous_compaction_id)
  end

  @doc """
  Calculates the compression ratio achieved by this compaction.

  Returns a float between 0 and 1, where lower is better compression.
  Returns nil if metrics are not available.
  """
  @spec compression_ratio(t()) :: float() | nil
  def compression_ratio(%__MODULE__{input_tokens_before: nil}), do: nil
  def compression_ratio(%__MODULE__{input_tokens_after: nil}), do: nil
  def compression_ratio(%__MODULE__{input_tokens_before: 0}), do: nil

  def compression_ratio(%__MODULE__{
        input_tokens_before: before,
        input_tokens_after: after_tokens
      }) do
    after_tokens / before
  end

  @doc """
  Calculates the token savings from this compaction.
  """
  @spec tokens_saved(t()) :: integer() | nil
  def tokens_saved(%__MODULE__{input_tokens_before: nil}), do: nil
  def tokens_saved(%__MODULE__{input_tokens_after: nil}), do: nil

  def tokens_saved(%__MODULE__{
        input_tokens_before: before,
        input_tokens_after: after_tokens
      }) do
    before - after_tokens
  end
end
