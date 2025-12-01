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

defmodule Msfailab.Tracks.ChatHistoryLLMResponse do
  @moduledoc """
  Represents a single LLM API call within a turn.

  ## Conceptual Overview

  An **LLM response** captures the result of one API call to an LLM provider.
  A turn may contain multiple LLM responses when tool calls are involved:

  ```
  Turn:
    [LLM Response 1] → thinking, response, tool_call(scan_network)
    [tool execution...]
    [LLM Response 2] → response, tool_call(check_port)
    [tool execution...]
    [LLM Response 3] → response (done)
  ```

  ## Token Metrics

  Different LLM providers return different metrics. This schema normalizes them:

  | Column | OpenAI | Anthropic | Ollama |
  |--------|--------|-----------|--------|
  | `input_tokens` | `prompt_tokens` | `input_tokens` | `prompt_eval_count` |
  | `output_tokens` | `completion_tokens` | `output_tokens` | `eval_count` |
  | `cached_input_tokens` | `prompt_tokens_details.cached_tokens` | `cache_read_input_tokens` | N/A |
  | `cache_creation_tokens` | N/A | `cache_creation_input_tokens` | N/A |

  ## Cache Context

  Provider-specific caching mechanisms store different data:

  | Provider | Mechanism | Stored Data |
  |----------|-----------|-------------|
  | Ollama | Returns `context` array of token IDs | JSON array in `cache_context` |
  | Anthropic | Cache control via message structure | Nothing; caching is implicit |
  | OpenAI | Automatic prefix caching | Nothing; fully automatic |

  For Ollama, the `cache_context` field stores the token ID array returned
  by the API, which can be passed back to subsequent requests to avoid
  re-tokenizing the conversation prefix.

  ## Relationships

  - **Belongs to** a Track (for denormalized querying)
  - **Belongs to** a Turn (the agentic loop this response is part of)
  - **Has many** entries (timeline slots produced by this response)

  ## Usage Example

  ```elixir
  # Record an LLM response after API call completes
  {:ok, llm_response} = %ChatHistoryLLMResponse{}
    |> ChatHistoryLLMResponse.changeset(%{
      track_id: track.id,
      turn_id: turn.id,
      model: "claude-sonnet-4-20250514",
      input_tokens: usage.input_tokens,
      output_tokens: usage.output_tokens,
      cached_input_tokens: usage.cache_read_input_tokens,
      cache_creation_tokens: usage.cache_creation_input_tokens
    })
    |> Repo.insert()
  ```

  ## Token Cost Tracking

  LLM responses enable cost tracking and optimization:

  ```elixir
  # Calculate total tokens for a turn
  turn
  |> Repo.preload(:llm_responses)
  |> Map.get(:llm_responses)
  |> Enum.reduce(%{input: 0, output: 0}, fn resp, acc ->
    %{input: acc.input + resp.input_tokens, output: acc.output + resp.output_tokens}
  end)
  ```
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Msfailab.Tracks.ChatHistoryEntry
  alias Msfailab.Tracks.ChatHistoryTurn
  alias Msfailab.Tracks.Track

  @type t :: %__MODULE__{
          id: integer() | nil,
          track_id: integer() | nil,
          track: Track.t() | Ecto.Association.NotLoaded.t(),
          turn_id: integer() | nil,
          turn: ChatHistoryTurn.t() | Ecto.Association.NotLoaded.t(),
          model: String.t() | nil,
          input_tokens: integer() | nil,
          output_tokens: integer() | nil,
          cached_input_tokens: integer() | nil,
          cache_creation_tokens: integer() | nil,
          cache_context: map() | nil,
          entries: [ChatHistoryEntry.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil
        }

  # Use default integer primary key

  schema "msfailab_track_chat_history_llm_responses" do
    field :model, :string
    field :input_tokens, :integer
    field :output_tokens, :integer
    field :cached_input_tokens, :integer
    field :cache_creation_tokens, :integer
    field :cache_context, :map

    belongs_to :track, Track
    belongs_to :turn, ChatHistoryTurn
    has_many :entries, ChatHistoryEntry, foreign_key: :llm_response_id

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc """
  Changeset for creating an LLM response record.

  ## Required Fields

  - `track_id` - The track this response belongs to
  - `turn_id` - The turn this response is part of
  - `model` - The model identifier used for this call
  - `input_tokens` - Number of input tokens consumed
  - `output_tokens` - Number of output tokens generated

  ## Optional Fields

  - `cached_input_tokens` - Tokens served from cache (reduces cost)
  - `cache_creation_tokens` - Tokens used to create cache entry
  - `cache_context` - Provider-specific cache data (e.g., Ollama context array)
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(response, attrs) do
    response
    |> cast(attrs, [
      :model,
      :input_tokens,
      :output_tokens,
      :cached_input_tokens,
      :cache_creation_tokens,
      :cache_context,
      :track_id,
      :turn_id
    ])
    |> validate_required([:model, :input_tokens, :output_tokens, :track_id, :turn_id])
    |> validate_number(:input_tokens, greater_than_or_equal_to: 0)
    |> validate_number(:output_tokens, greater_than_or_equal_to: 0)
    |> validate_number(:cached_input_tokens, greater_than_or_equal_to: 0)
    |> validate_number(:cache_creation_tokens, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:track_id)
    |> foreign_key_constraint(:turn_id)
  end
end
