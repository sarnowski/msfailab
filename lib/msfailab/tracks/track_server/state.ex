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

defmodule Msfailab.Tracks.TrackServer.State do
  @moduledoc """
  Typed state structures for TrackServer.

  This module defines the hierarchical state structure used by TrackServer,
  with clear ownership boundaries for each core module:

  - `Console.State` - owned by TrackServer.Console
  - `Stream.State` - owned by TrackServer.Stream
  - `Turn.State` - owned by TrackServer.Turn

  The main `State` struct holds these sub-states plus shared data like
  `chat_entries` that may be read by multiple cores.
  """

  alias Msfailab.Markdown
  alias Msfailab.Tracks.ChatEntry
  alias Msfailab.Tracks.ConsoleHistoryBlock

  # ============================================================================
  # Console State (owned by TrackServer.Console)
  # ============================================================================

  defmodule Console do
    @moduledoc """
    State for console history management.

    Tracks the console status, current prompt, command history blocks,
    and the current command being executed.
    """

    @type status :: :offline | :starting | :ready | :busy

    @type t :: %__MODULE__{
            status: status(),
            current_prompt: String.t(),
            history: [ConsoleHistoryBlock.t()],
            command_id: String.t() | nil
          }

    @enforce_keys [:status, :current_prompt, :history]
    defstruct [
      :status,
      :current_prompt,
      :command_id,
      history: []
    ]

    @doc """
    Creates a new console state with defaults.
    """
    @spec new() :: t()
    def new do
      %__MODULE__{
        status: :offline,
        current_prompt: "",
        history: [],
        command_id: nil
      }
    end

    @doc """
    Creates console state from persisted history.
    """
    @spec from_history([ConsoleHistoryBlock.t()]) :: t()
    def from_history(history) do
      current_prompt =
        case List.last(history) do
          nil -> ""
          block -> block.prompt || ""
        end

      %__MODULE__{
        status: :offline,
        current_prompt: current_prompt,
        history: history,
        command_id: nil
      }
    end
  end

  # ============================================================================
  # Stream State (owned by TrackServer.Stream)
  # ============================================================================

  defmodule Stream do
    @moduledoc """
    State for LLM streaming content handling.

    Tracks the mapping from LLM content block indices to entry positions,
    the MDEx documents for streaming markdown rendering, and the next
    available entry position.
    """

    @type t :: %__MODULE__{
            blocks: %{non_neg_integer() => pos_integer()},
            documents: %{pos_integer() => Markdown.document()},
            next_position: pos_integer()
          }

    @enforce_keys [:next_position]
    defstruct blocks: %{},
              documents: %{},
              next_position: 1

    @doc """
    Creates a new stream state with the given next position.
    """
    @spec new(pos_integer()) :: t()
    def new(next_position) do
      %__MODULE__{
        blocks: %{},
        documents: %{},
        next_position: next_position
      }
    end

    @doc """
    Resets streaming state while preserving next_position.
    """
    @spec reset(t()) :: t()
    def reset(%__MODULE__{} = state) do
      %__MODULE__{state | blocks: %{}, documents: %{}}
    end
  end

  # ============================================================================
  # Turn State (owned by TrackServer.Turn)
  # ============================================================================

  defmodule Turn do
    @moduledoc """
    State for agentic turn lifecycle management.

    Tracks the current turn status, LLM request reference, tool invocations,
    and the mapping from command IDs to tool entry IDs.
    """

    @type status ::
            :idle
            | :pending
            | :streaming
            | :pending_approval
            | :executing_tools
            | :finished
            | :error
            | :cancelled

    @type tool_state :: %{
            tool_call_id: String.t(),
            tool_name: String.t(),
            arguments: map(),
            status:
              :pending
              | :approved
              | :denied
              | :executing
              | :success
              | :error
              | :timeout
              | :cancelled,
            command_id: String.t() | nil,
            started_at: DateTime.t() | nil
          }

    @type t :: %__MODULE__{
            status: status(),
            turn_id: String.t() | nil,
            model: String.t() | nil,
            llm_ref: reference() | nil,
            tool_invocations: %{integer() => tool_state()},
            command_to_tool: %{String.t() => integer()},
            last_cache_context: term() | nil
          }

    @enforce_keys [:status]
    defstruct status: :idle,
              turn_id: nil,
              model: nil,
              llm_ref: nil,
              tool_invocations: %{},
              command_to_tool: %{},
              last_cache_context: nil

    @doc """
    Creates a new turn state in idle status.
    """
    @spec new() :: t()
    def new do
      %__MODULE__{status: :idle}
    end

    @doc """
    Creates turn state from persisted tool invocations.

    Determines the appropriate status based on whether there are
    pending or approved tools.

    ## Parameters

    - `tool_invocations` - Map of entry_id to tool_state
    - `model` - The model name to use for continuing the turn (from active turn in DB)
    """
    @spec from_tool_invocations(%{integer() => tool_state()}, String.t() | nil) :: t()
    def from_tool_invocations(tool_invocations, model \\ nil)

    def from_tool_invocations(tool_invocations, _model) when map_size(tool_invocations) == 0 do
      %__MODULE__{status: :idle}
    end

    def from_tool_invocations(tool_invocations, model) do
      has_pending = Enum.any?(tool_invocations, fn {_id, ts} -> ts.status == :pending end)

      status = if has_pending, do: :pending_approval, else: :executing_tools

      %__MODULE__{
        status: status,
        model: model,
        tool_invocations: tool_invocations,
        command_to_tool: %{}
      }
    end
  end

  # ============================================================================
  # Main State
  # ============================================================================

  @type t :: %__MODULE__{
          track_id: integer(),
          track_slug: String.t(),
          workspace_id: integer(),
          workspace_slug: String.t(),
          container_id: integer(),
          container_slug: String.t(),
          autonomous: boolean(),
          console: Console.t(),
          stream: Stream.t(),
          turn: Turn.t(),
          chat_entries: [ChatEntry.t()]
        }

  @enforce_keys [
    :track_id,
    :track_slug,
    :workspace_id,
    :workspace_slug,
    :container_id,
    :container_slug
  ]
  defstruct [
    :track_id,
    :track_slug,
    :workspace_id,
    :workspace_slug,
    :container_id,
    :container_slug,
    autonomous: false,
    console: nil,
    stream: nil,
    turn: nil,
    chat_entries: []
  ]

  @doc """
  Creates a new state with the given IDs and defaults.
  """
  @spec new(map(), keyword()) :: t()
  def new(ids, opts \\ []) do
    %__MODULE__{
      track_id: Map.fetch!(ids, :track_id),
      track_slug: Map.fetch!(ids, :track_slug),
      workspace_id: Map.fetch!(ids, :workspace_id),
      workspace_slug: Map.fetch!(ids, :workspace_slug),
      container_id: Map.fetch!(ids, :container_id),
      container_slug: Map.fetch!(ids, :container_slug),
      autonomous: Keyword.get(opts, :autonomous, false),
      console: Console.new(),
      stream: Stream.new(1),
      turn: Turn.new(),
      chat_entries: []
    }
  end

  @doc """
  Creates state from persisted data during init.

  ## Parameters

  - `ids` - Map with `:track_id`, `:track_slug`, `:workspace_id`, `:workspace_slug`,
    `:container_id`, `:container_slug`
  - `opts` - Keyword list with:
    - `:autonomous` - Whether autonomous mode is enabled
    - `:console_history` - Persisted console history blocks
    - `:chat_entries` - Persisted chat entries for UI rendering
    - `:next_position` - Next entry position to use
    - `:tool_invocations` - Pending/approved tool invocations
    - `:model` - Model name from active turn (for resuming after restart)
  """
  @spec from_persisted(map(), keyword()) :: t()
  def from_persisted(ids, opts) do
    track_id = Map.fetch!(ids, :track_id)
    track_slug = Map.fetch!(ids, :track_slug)
    workspace_id = Map.fetch!(ids, :workspace_id)
    workspace_slug = Map.fetch!(ids, :workspace_slug)
    container_id = Map.fetch!(ids, :container_id)
    container_slug = Map.fetch!(ids, :container_slug)

    autonomous = Keyword.get(opts, :autonomous, false)
    console_history = Keyword.get(opts, :console_history, [])
    chat_entries = Keyword.get(opts, :chat_entries, [])
    next_position = Keyword.get(opts, :next_position, 1)
    tool_invocations = Keyword.get(opts, :tool_invocations, %{})
    model = Keyword.get(opts, :model)

    %__MODULE__{
      track_id: track_id,
      track_slug: track_slug,
      workspace_id: workspace_id,
      workspace_slug: workspace_slug,
      container_id: container_id,
      container_slug: container_slug,
      autonomous: autonomous,
      console: Console.from_history(console_history),
      stream: Stream.new(next_position),
      turn: Turn.from_tool_invocations(tool_invocations, model),
      chat_entries: chat_entries
    }
  end
end
