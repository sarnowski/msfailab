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

defmodule Msfailab.Tracks.ChatContext do
  @moduledoc """
  Database operations for chat history.

  This module provides functions to create and query chat-related entities:
  turns, LLM responses, entries, messages, and tool invocations. It serves as
  the persistence layer for TrackServer's chat state.

  ## Entity Hierarchy

  ```
  Turn (complete agentic loop until no more tool calls)
  └── LLMResponse (single API call to LLM provider)
      └── Entry (timeline slot)
          ├── Message (content: prompt/thinking/response)
          └── ToolInvocation (tool call with lifecycle)
  ```

  ## Entry Types

  Each entry has a type that determines its associated content:

  | Entry Type | Content Table | Description |
  |------------|---------------|-------------|
  | `message` | ChatMessage | User prompt, assistant thinking/response |
  | `tool_invocation` | ChatToolInvocation | LLM tool call with approval workflow |

  ## Usage

  TrackServer calls these functions to:
  1. Create a Turn when starting a new conversation cycle
  2. Create Entries + Messages for user prompts and AI responses
  3. Create Entries + ToolInvocations when LLM requests tool calls
  4. Update tool invocation status through approval/execution workflow
  5. Create LLMResponses when streaming completes
  6. Load entries for building LLM message context and UI rendering

  ## LLM Message Building

  The `entries_to_llm_messages/1` function builds the message list for LLM
  API requests. It handles the conversion of both message entries and tool
  invocation entries:

  ```
  ┌─────────────────────────────────────────────────────────────────────┐
  │                    LLM Message Building                             │
  ├─────────────────────────────────────────────────────────────────────┤
  │                                                                     │
  │  Entry Type          →   LLM Messages                               │
  │  ──────────────────      ────────────────────────────               │
  │                                                                     │
  │  message (prompt)    →   user message                               │
  │  message (response)  →   assistant message                          │
  │  message (thinking)  →   [filtered out]                             │
  │                                                                     │
  │  tool_invocation     →   assistant message (tool_call block)        │
  │  (terminal status)   →   tool message (tool_result block)           │
  │                                                                     │
  │  tool_invocation     →   [filtered out - not ready yet]             │
  │  (non-terminal)                                                     │
  │                                                                     │
  └─────────────────────────────────────────────────────────────────────┘
  ```
  """

  import Ecto.Query

  alias Msfailab.LLM.Message, as: LLMMessage
  alias Msfailab.Markdown
  alias Msfailab.Repo
  alias Msfailab.Tracks.ChatEntry
  alias Msfailab.Tracks.ChatHistoryEntry
  alias Msfailab.Tracks.ChatHistoryLLMResponse
  alias Msfailab.Tracks.ChatHistoryTurn
  alias Msfailab.Tracks.ChatMessage
  alias Msfailab.Tracks.ChatToolInvocation

  # ============================================================================
  # Turn Operations
  # ============================================================================

  @doc """
  Creates a new turn for a track.

  A turn represents one complete agentic loop. It starts when the user sends
  a prompt and ends when the AI finishes responding with no more tool calls.
  A turn may contain multiple LLM requests if tool calls are involved.

  ## Parameters

  - `track_id` - The track this turn belongs to
  - `model` - The model being used for this turn
  - `tool_approval_mode` - Tool approval mode (e.g., "autonomous", "confirm")

  ## Returns

  `{:ok, turn}` on success, `{:error, changeset}` on validation failure.
  """
  @spec create_turn(pos_integer(), String.t(), String.t()) ::
          {:ok, ChatHistoryTurn.t()} | {:error, Ecto.Changeset.t()}
  def create_turn(track_id, model, tool_approval_mode \\ "confirm") do
    position = next_turn_position(track_id)

    %ChatHistoryTurn{}
    |> ChatHistoryTurn.changeset(%{
      track_id: track_id,
      position: position,
      trigger: "user_prompt",
      status: "pending",
      model: model,
      tool_approval_mode: tool_approval_mode
    })
    |> Repo.insert()
  end

  @doc """
  Updates a turn's status.
  """
  @spec update_turn_status(ChatHistoryTurn.t(), String.t()) ::
          {:ok, ChatHistoryTurn.t()} | {:error, Ecto.Changeset.t() | :stale}
  def update_turn_status(%ChatHistoryTurn{} = turn, status) do
    turn
    |> ChatHistoryTurn.status_changeset(status)
    |> Repo.update()
  rescue
    Ecto.StaleEntryError -> {:error, :stale}
  end

  @doc """
  Gets the model from the latest active turn for a track.

  An active turn is one that is not in a terminal status (finished, error, interrupted).
  This is used during TrackServer initialization to restore the model when there are
  pending tool invocations.

  ## Returns

  The model name string if an active turn exists, `nil` otherwise.
  """
  @spec get_active_turn_model(pos_integer()) :: String.t() | nil
  def get_active_turn_model(track_id) do
    terminal_statuses = ["finished", "error", "interrupted"]

    from(t in ChatHistoryTurn,
      where: t.track_id == ^track_id and t.status not in ^terminal_statuses,
      order_by: [desc: t.position],
      limit: 1,
      select: t.model
    )
    |> Repo.one()
  end

  defp next_turn_position(track_id) do
    from(t in ChatHistoryTurn,
      where: t.track_id == ^track_id,
      select: coalesce(max(t.position), 0) + 1
    )
    |> Repo.one()
  end

  # ============================================================================
  # LLM Response Operations
  # ============================================================================

  @doc """
  Creates an LLM response record.

  An LLM response represents one API call to the LLM provider. A turn may
  contain multiple LLM responses if tool calls are involved:

  ```
  Turn (one agentic loop)
  ├── LLM Response 1: Initial response with tool calls
  ├── LLM Response 2: Response after first tool execution
  └── LLM Response 3: Final response (no more tool calls)
  ```

  ## Parameters

  - `track_id` - The track this response belongs to
  - `turn_id` - The turn this response is part of
  - `model` - The model that generated this response
  - `metrics` - Token metrics (input_tokens, output_tokens, etc.)
  """
  @spec create_llm_response(pos_integer(), String.t(), String.t(), map()) ::
          {:ok, ChatHistoryLLMResponse.t()} | {:error, Ecto.Changeset.t()}
  def create_llm_response(track_id, turn_id, model, metrics) do
    %ChatHistoryLLMResponse{}
    |> ChatHistoryLLMResponse.changeset(%{
      track_id: track_id,
      turn_id: turn_id,
      model: model,
      input_tokens: metrics[:input_tokens] || 0,
      output_tokens: metrics[:output_tokens] || 0,
      cached_input_tokens: metrics[:cached_input_tokens],
      cache_creation_tokens: metrics[:cache_creation_tokens],
      cache_context: metrics[:cache_context]
    })
    |> Repo.insert()
  end

  # ============================================================================
  # Entry + Message Operations
  # ============================================================================

  @doc """
  Creates a message entry (user prompt, thinking, or response).

  This creates both the Entry (timeline slot) and the Message (content) in a
  single transaction.

  ## Parameters

  - `track_id` - The track this entry belongs to
  - `turn_id` - The turn this entry is part of (can be nil for context entries)
  - `llm_response_id` - The LLM response that generated this (nil for user prompts)
  - `position` - The chronological position in the timeline
  - `attrs` - Message attributes: role, message_type, content

  ## Returns

  `{:ok, entry}` with the message preloaded.
  """
  @spec create_message_entry(
          pos_integer(),
          String.t() | nil,
          String.t() | nil,
          pos_integer(),
          map()
        ) ::
          {:ok, ChatHistoryEntry.t()} | {:error, term()}
  def create_message_entry(track_id, turn_id, llm_response_id, position, attrs) do
    Repo.transaction(fn ->
      # Create entry
      {:ok, entry} =
        %ChatHistoryEntry{}
        |> ChatHistoryEntry.changeset(%{
          track_id: track_id,
          turn_id: turn_id,
          llm_response_id: llm_response_id,
          position: position,
          entry_type: "message"
        })
        |> Repo.insert()

      # Create message content
      {:ok, message} =
        %ChatMessage{}
        |> ChatMessage.changeset(Map.put(attrs, :entry_id, entry.id))
        |> Repo.insert()

      %{entry | message: message}
    end)
  end

  @doc """
  Updates the content of a message entry.

  Used during streaming to update the accumulated content.
  """
  @spec update_message_content(String.t(), String.t()) ::
          {:ok, ChatMessage.t()} | {:error, term()}
  def update_message_content(entry_id, content) do
    from(m in ChatMessage, where: m.entry_id == ^entry_id)
    |> Repo.update_all(set: [content: content])

    {:ok, Repo.get_by!(ChatMessage, entry_id: entry_id)}
  end

  # ============================================================================
  # Entry + Tool Invocation Operations
  # ============================================================================

  @doc """
  Creates a tool invocation entry.

  Creates both the Entry (timeline slot) and the ToolInvocation (content) in a
  single transaction. Initial status is "pending" for approval flow.

  ## Tool Invocation Lifecycle

  ```
            ┌──────────────────────────────────┐
            │                                  │
            ▼                                  │
        pending ───► approved ───► executing ──┴──► success
            │                          │
            │                          ├───► error
            │                          │
            │                          └───► timeout
            │
            └───► denied
  ```

  ## Parameters

  - `track_id` - The track this entry belongs to
  - `turn_id` - The turn this entry is part of
  - `llm_response_id` - The LLM response that generated this (may be nil during streaming)
  - `position` - The chronological position in the timeline
  - `attrs` - Tool invocation attributes:
    - `:tool_call_id` - LLM-assigned identifier for correlating call and result
    - `:tool_name` - Name of the tool being invoked
    - `:arguments` - Map of arguments passed to the tool

  ## Returns

  `{:ok, entry}` with the tool_invocation preloaded.
  """
  @spec create_tool_invocation_entry(
          pos_integer(),
          String.t(),
          String.t() | nil,
          pos_integer(),
          map()
        ) ::
          {:ok, ChatHistoryEntry.t()} | {:error, term()}
  def create_tool_invocation_entry(track_id, turn_id, llm_response_id, position, attrs) do
    Repo.transaction(fn ->
      # Create entry
      {:ok, entry} =
        %ChatHistoryEntry{}
        |> ChatHistoryEntry.changeset(%{
          track_id: track_id,
          turn_id: turn_id,
          llm_response_id: llm_response_id,
          position: position,
          entry_type: "tool_invocation"
        })
        |> Repo.insert()

      # Create tool invocation content
      {:ok, tool_invocation} =
        %ChatToolInvocation{}
        |> ChatToolInvocation.changeset(
          attrs
          |> Map.put(:entry_id, entry.id)
          |> Map.put(:status, "pending")
        )
        |> Repo.insert()

      %{entry | tool_invocation: tool_invocation}
    end)
  end

  @doc """
  Updates a tool invocation's status and optional fields.

  This function handles all status transitions in the tool invocation lifecycle.
  It validates that the status transition is valid before applying.

  ## Parameters

  - `entry_id` - The entry ID (which is also the tool invocation's primary key)
  - `status` - The new status (must be one of: "approved", "denied", "executing", "success", "error", "timeout")
  - `opts` - Optional fields to update:
    - `:result_content` - Output from successful execution
    - `:error_message` - Error details for failed execution
    - `:denied_reason` - Reason user denied the tool
    - `:duration_ms` - Execution time in milliseconds

  ## Status Transitions

  | From | Valid To |
  |------|----------|
  | pending | approved, denied |
  | approved | executing |
  | executing | success, error, timeout |

  ## Returns

  `{:ok, tool_invocation}` on success, `{:error, reason}` on failure.
  """
  @spec update_tool_invocation(integer(), integer(), String.t(), keyword()) ::
          {:ok, ChatToolInvocation.t()} | {:error, term()}
  def update_tool_invocation(track_id, position, status, opts \\ []) do
    # Look up tool invocation by track_id + position (via ChatHistoryEntry join)
    # since in-memory tracking uses position as the key
    query =
      from ti in ChatToolInvocation,
        join: e in ChatHistoryEntry,
        on: ti.entry_id == e.id,
        where: e.track_id == ^track_id and e.position == ^position,
        select: ti

    case Repo.one(query) do
      nil ->
        {:error, :not_found}

      invocation ->
        updates =
          [status: status]
          |> maybe_add_opt(:result_content, opts)
          |> maybe_add_opt(:error_message, opts)
          |> maybe_add_opt(:denied_reason, opts)
          |> maybe_add_opt(:duration_ms, opts)

        invocation
        |> ChatToolInvocation.changeset(Map.new(updates))
        |> Repo.update()
    end
  end

  defp maybe_add_opt(list, key, opts) do
    case Keyword.get(opts, key) do
      nil -> list
      value -> [{key, value} | list]
    end
  end

  # ============================================================================
  # Query Operations
  # ============================================================================

  @doc """
  Gets the next available entry position for a track.

  Position is monotonically increasing within a track.
  """
  @spec next_entry_position(pos_integer()) :: pos_integer()
  def next_entry_position(track_id) do
    from(e in ChatHistoryEntry,
      where: e.track_id == ^track_id,
      select: coalesce(max(e.position), 0) + 1
    )
    |> Repo.one()
  end

  @doc """
  Loads all entries for a track with appropriate associations preloaded.

  Returns entries in chronological order (by position). Entries are loaded
  with their content associations (message or tool_invocation) based on
  the entry type.

  ## Returns

  List of `ChatHistoryEntry` structs with `:message` or `:tool_invocation`
  association preloaded depending on entry type.
  """
  @spec load_entries(pos_integer()) :: [ChatHistoryEntry.t()]
  def load_entries(track_id) do
    from(e in ChatHistoryEntry,
      where: e.track_id == ^track_id,
      order_by: [asc: e.position],
      preload: [:message, :tool_invocation]
    )
    |> Repo.all()
  end

  @doc """
  Loads all message entries for a track with messages preloaded.

  Returns entries in chronological order (by position). Only loads entries
  of type "message" - tool invocations are filtered out.

  ## Returns

  List of `ChatHistoryEntry` structs with `:message` association preloaded.
  """
  @spec load_message_entries(pos_integer()) :: [ChatHistoryEntry.t()]
  def load_message_entries(track_id) do
    from(e in ChatHistoryEntry,
      where: e.track_id == ^track_id and e.entry_type == "message",
      order_by: [asc: e.position],
      preload: [:message]
    )
    |> Repo.all()
  end

  # ============================================================================
  # Conversion Operations
  # ============================================================================

  @doc """
  Converts persisted entries to ChatEntry structs for UI rendering.

  Handles both message entries and tool invocation entries:

  - **Message entries**: Renders markdown content to HTML for assistant entries.
    User prompts are left with `rendered_html: nil` as they display plain text.

  - **Tool invocation entries**: Converted directly without markdown rendering.

  ## Returns

  List of `ChatEntry` structs ready for UI rendering.
  """
  @spec entries_to_chat_entries([ChatHistoryEntry.t()]) :: [ChatEntry.t()]
  def entries_to_chat_entries(entries) do
    Enum.map(entries, &entry_to_chat_entry/1)
  end

  defp entry_to_chat_entry(%{entry_type: "message"} = entry) do
    chat_entry = ChatEntry.from_ecto(entry, false)

    if chat_entry.role == :assistant do
      render_entry_markdown(chat_entry)
    else
      chat_entry
    end
  end

  defp entry_to_chat_entry(%{entry_type: "tool_invocation"} = entry) do
    ChatEntry.from_tool_invocation_ecto(entry)
  end

  defp render_entry_markdown(chat_entry) do
    case Markdown.render(chat_entry.content) do
      {:ok, html} -> %{chat_entry | rendered_html: html}
      {:error, _reason} -> %{chat_entry | rendered_html: chat_entry.content}
    end
  end

  @doc """
  Builds LLM messages from persisted entries.

  Converts entries to the normalized `Msfailab.LLM.Message` format for making
  LLM API requests.

  ## Message Building Rules

  | Entry Type | Filter | LLM Messages |
  |------------|--------|--------------|
  | message (prompt) | Include | User message with text |
  | message (response) | Include | Assistant message with text |
  | message (thinking) | Exclude | Not sent to LLM |
  | tool_invocation (terminal) | Include | Tool call + tool result messages |
  | tool_invocation (non-terminal) | Exclude | Execution not complete |

  ### Terminal Tool Statuses

  Tool invocations with these statuses are included in LLM context:
  - `success` - Completed successfully
  - `error` - Failed with an error
  - `timeout` - Execution timed out
  - `denied` - User denied the tool call

  ## Tool Invocation Message Format

  Each terminal tool invocation produces **two** messages:

  1. **Tool call message** (role: assistant):
     ```elixir
     %Message{
       role: :assistant,
       content: [%{type: :tool_call, id: "call_1", name: "execute_msfconsole_command", arguments: %{...}}]
     }
     ```

  2. **Tool result message** (role: tool):
     ```elixir
     %Message{
       role: :tool,
       content: [%{type: :tool_result, tool_call_id: "call_1", content: "...", is_error: false}]
     }
     ```

  ## Returns

  List of `LLM.Message` structs ready for `LLM.chat/2`.
  """
  @spec entries_to_llm_messages([ChatHistoryEntry.t()]) :: [LLMMessage.t()]
  def entries_to_llm_messages(entries) do
    entries
    |> Enum.filter(&include_in_llm_context?/1)
    |> Enum.flat_map(&entry_to_llm_messages/1)
  end

  # Filter: Include message entries with prompt or response type
  defp include_in_llm_context?(%{entry_type: "message", message: msg}) do
    msg.message_type in ["prompt", "response"]
  end

  # Filter: Include tool invocations with terminal status
  defp include_in_llm_context?(%{entry_type: "tool_invocation", tool_invocation: ti}) do
    ti.status in ["success", "error", "timeout", "denied", "cancelled"]
  end

  defp include_in_llm_context?(_), do: false

  # Convert message entry to LLM message
  defp entry_to_llm_messages(%{entry_type: "message", message: msg}) do
    llm_message =
      case msg.role do
        "user" -> LLMMessage.user(msg.content || "")
        "assistant" -> LLMMessage.assistant(msg.content || "")
      end

    [llm_message]
  end

  # Convert tool invocation entry to LLM messages (call + result)
  defp entry_to_llm_messages(%{entry_type: "tool_invocation", tool_invocation: ti}) do
    # First message: the tool call from assistant
    call_msg = LLMMessage.tool_call(ti.tool_call_id, ti.tool_name, ti.arguments)

    # Second message: the tool result
    {result_content, is_error} = tool_result_content(ti)
    result_msg = LLMMessage.tool_result(ti.tool_call_id, result_content, is_error)

    [call_msg, result_msg]
  end

  defp tool_result_content(%{status: "success"} = ti),
    do: {ti.result_content || "", false}

  defp tool_result_content(%{status: "error"} = ti),
    do: {"Error: #{ti.error_message || "Unknown error"}", true}

  defp tool_result_content(%{status: "timeout"}),
    do: {"Error: Tool execution timed out", true}

  defp tool_result_content(%{status: "denied"} = ti),
    do: {"Tool call denied by user: #{ti.denied_reason || "No reason given"}", true}

  defp tool_result_content(%{status: "cancelled"} = ti),
    do: {"Error: #{ti.error_message || "User cancelled the execution"}", true}
end
