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

defmodule Msfailab.Tracks.ChatEntry do
  @moduledoc """
  A chat entry for UI rendering.

  This struct represents the public contract between TrackServer and LiveView
  for rendering chat content. It provides a typed, well-defined structure
  that ensures compile-time safety when accessing fields in templates.

  ## Entry Types

  ChatEntry supports two distinct entry types:

  ```
  ┌─────────────────────────────────────────────────────────────────────┐
  │                        ChatEntry Types                              │
  ├─────────────────────────────────────────────────────────────────────┤
  │                                                                     │
  │  :message                           :tool_invocation                │
  │  ────────────────                   ─────────────────────           │
  │                                                                     │
  │  ┌─────────────────────┐            ┌─────────────────────┐         │
  │  │ User Prompt         │            │ Tool Request        │         │
  │  │                     │            │                     │         │
  │  │ "What exploits      │            │ msf_command         │         │
  │  │  target Apache?"    │            │ ► search apache     │         │
  │  └─────────────────────┘            │                     │         │
  │                                     │ [Approve] [Deny]    │         │
  │  ┌─────────────────────┐            └─────────────────────┘         │
  │  │ Assistant Response  │                                            │
  │  │                     │                                            │
  │  │ "Here are several   │                                            │
  │  │  Apache exploits.." │                                            │
  │  └─────────────────────┘                                            │
  │                                                                     │
  └─────────────────────────────────────────────────────────────────────┘
  ```

  ### Message Entries (entry_type: :message)

  Used for user prompts and assistant responses/thinking. Fields used:
  - `role` - `:user` or `:assistant`
  - `message_type` - `:prompt`, `:thinking`, or `:response`
  - `content` - Text content (raw markdown for assistant)
  - `rendered_html` - Pre-rendered HTML (nil for user prompts)
  - `streaming` - Whether content is still being streamed

  ### Tool Invocation Entries (entry_type: :tool_invocation)

  Used for LLM tool calls. Fields used:
  - `tool_call_id` - LLM-assigned identifier for the tool call
  - `tool_name` - Name of the tool being invoked (e.g., "msf_command")
  - `tool_arguments` - Map of arguments passed to the tool
  - `tool_status` - Current status in the lifecycle

  ## Tool Invocation Status State Machine

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

  | Status | Description | UI Indicator |
  |--------|-------------|--------------|
  | `:pending` | Awaiting user approval | Approve/Deny buttons |
  | `:approved` | User approved, waiting for execution | "Approved" badge |
  | `:denied` | User denied the tool call | "Denied" badge |
  | `:executing` | Currently running | Spinner animation |
  | `:success` | Completed successfully | Checkmark icon |
  | `:error` | Failed with an error | Error icon |
  | `:timeout` | Execution timed out | Timeout icon |

  ## Design Rationale

  Rather than passing Ecto schemas directly to the UI (which carry database
  concerns like associations, changesets, and extra fields), we use this
  dedicated struct that contains exactly what the UI needs to render.

  This provides:
  - **Type safety**: `@enforce_keys` catches missing fields at struct creation
  - **Dialyzer support**: Invalid field access is caught at compile time
  - **Clear contract**: The struct definition documents the UI requirements
  - **Decoupling**: DB schema changes don't ripple to UI code

  ## Examples

  ### User Prompt

      %ChatEntry{
        id: "550e8400-e29b-41d4-a716-446655440000",
        position: 1,
        entry_type: :message,
        role: :user,
        message_type: :prompt,
        content: "What exploits target Apache?",
        streaming: false,
        timestamp: ~U[2025-01-15 10:30:00Z]
      }

  ### Tool Invocation

      %ChatEntry{
        id: "660e8400-e29b-41d4-a716-446655440001",
        position: 2,
        entry_type: :tool_invocation,
        tool_call_id: "call_abc123",
        tool_name: "msf_command",
        tool_arguments: %{"command" => "search apache"},
        tool_status: :pending,
        streaming: false,
        timestamp: ~U[2025-01-15 10:30:05Z]
      }
  """

  @type entry_type :: :message | :tool_invocation | :memory
  @type role :: :user | :assistant
  @type message_type :: :prompt | :thinking | :response
  @type tool_status :: :pending | :approved | :denied | :executing | :success | :error | :timeout

  @typedoc """
  A chat entry representing either a message or a tool invocation.

  This is a union type where `entry_type` determines which fields are populated:

  ## Common Fields (always present)

  | Field | Description |
  |-------|-------------|
  | `id` | UUID string (streaming) or integer (persisted) |
  | `position` | Monotonic position in chat timeline |
  | `entry_type` | `:message` or `:tool_invocation` |
  | `timestamp` | When the entry was created |
  | `streaming` | Whether the entry is still being streamed |

  ## Message Fields (when `entry_type == :message`)

  | Field | Description |
  |-------|-------------|
  | `role` | `:user` or `:assistant` |
  | `message_type` | `:prompt`, `:thinking`, or `:response` |
  | `content` | The message text content |
  | `rendered_html` | Markdown-rendered HTML for display |

  ## Tool Invocation Fields (when `entry_type == :tool_invocation`)

  | Field | Description |
  |-------|-------------|
  | `tool_call_id` | LLM-assigned ID for correlating call/result |
  | `tool_name` | `"msf_command"` or `"bash_command"` |
  | `tool_arguments` | Map of arguments passed to the tool |
  | `tool_status` | Lifecycle status (pending, approved, executing, etc.) |
  | `console_prompt` | MSF console prompt at time of invocation |
  | `result_content` | Tool execution output (nil until complete) |
  """
  @type t :: %__MODULE__{
          # Common fields (all entry types)
          id: String.t() | integer(),
          position: pos_integer(),
          entry_type: entry_type(),
          timestamp: DateTime.t(),
          streaming: boolean(),

          # Message fields (entry_type: :message) - nil for tool invocations
          role: role() | nil,
          message_type: message_type() | nil,
          content: String.t() | nil,
          rendered_html: String.t() | nil,

          # Tool invocation fields (entry_type: :tool_invocation) - nil for messages
          tool_call_id: String.t() | nil,
          tool_name: String.t() | nil,
          tool_arguments: map() | nil,
          tool_status: tool_status() | nil,
          console_prompt: String.t() | nil,
          result_content: String.t() | nil,
          error_message: String.t() | nil
        }

  @enforce_keys [:id, :position, :entry_type, :streaming, :timestamp]
  defstruct [
    # Common fields (always present)
    :id,
    :position,
    :entry_type,
    :timestamp,
    :streaming,

    # Message fields (nil for :tool_invocation entries)
    :role,
    :message_type,
    :content,
    :rendered_html,

    # Tool invocation fields (nil for :message entries)
    :tool_call_id,
    :tool_name,
    :tool_arguments,
    :tool_status,
    :console_prompt,
    :result_content,
    :error_message
  ]

  # ===========================================================================
  # String to Atom Conversion (Safe Alternatives to String.to_existing_atom)
  # ===========================================================================

  @doc """
  Converts a role string from the database to an atom.

  ## Examples

      iex> ChatEntry.role_to_atom("user")
      :user

      iex> ChatEntry.role_to_atom("assistant")
      :assistant
  """
  @spec role_to_atom(String.t()) :: role()
  def role_to_atom("user"), do: :user
  def role_to_atom("assistant"), do: :assistant

  @doc """
  Converts a message_type string from the database to an atom.

  ## Examples

      iex> ChatEntry.message_type_to_atom("prompt")
      :prompt

      iex> ChatEntry.message_type_to_atom("thinking")
      :thinking

      iex> ChatEntry.message_type_to_atom("response")
      :response
  """
  @spec message_type_to_atom(String.t()) :: message_type()
  def message_type_to_atom("prompt"), do: :prompt
  def message_type_to_atom("thinking"), do: :thinking
  def message_type_to_atom("response"), do: :response

  @doc """
  Converts a tool_status string from the database to an atom.

  ## Examples

      iex> ChatEntry.tool_status_to_atom("pending")
      :pending

      iex> ChatEntry.tool_status_to_atom("success")
      :success
  """
  @spec tool_status_to_atom(String.t()) :: tool_status()
  def tool_status_to_atom("pending"), do: :pending
  def tool_status_to_atom("approved"), do: :approved
  def tool_status_to_atom("denied"), do: :denied
  def tool_status_to_atom("executing"), do: :executing
  def tool_status_to_atom("success"), do: :success
  def tool_status_to_atom("error"), do: :error
  def tool_status_to_atom("timeout"), do: :timeout

  # ===========================================================================
  # Message Entry Factory Functions
  # ===========================================================================

  @doc """
  Creates a new ChatEntry for a user prompt.

  User prompts do not have rendered HTML (displayed as plain text).

  ## Example

      iex> entry = ChatEntry.user_prompt("uuid", 1, "Hello!", ~U[2025-01-15 10:30:00Z])
      iex> entry.entry_type
      :message
      iex> entry.role
      :user
      iex> entry.message_type
      :prompt
  """
  @spec user_prompt(String.t(), pos_integer(), String.t(), DateTime.t()) :: t()
  def user_prompt(id, position, content, timestamp \\ DateTime.utc_now()) do
    %__MODULE__{
      id: id,
      position: position,
      entry_type: :message,
      role: :user,
      message_type: :prompt,
      content: content,
      rendered_html: nil,
      streaming: false,
      timestamp: timestamp
    }
  end

  @doc """
  Creates a new ChatEntry for assistant thinking.

  ## Parameters

  - `id` - Unique identifier
  - `position` - Position in conversation
  - `content` - Raw markdown content
  - `rendered_html` - Pre-rendered HTML for display
  - `streaming` - Whether currently streaming
  - `timestamp` - Creation time

  ## Example

      iex> entry = ChatEntry.assistant_thinking("uuid", 2, "Let me analyze...", "<p>Let me analyze...</p>", true, ~U[2025-01-15 10:30:00Z])
      iex> entry.entry_type
      :message
      iex> entry.message_type
      :thinking
  """
  @spec assistant_thinking(
          String.t(),
          pos_integer(),
          String.t(),
          String.t(),
          boolean(),
          DateTime.t()
        ) :: t()
  def assistant_thinking(
        id,
        position,
        content,
        rendered_html,
        streaming \\ false,
        timestamp \\ DateTime.utc_now()
      ) do
    %__MODULE__{
      id: id,
      position: position,
      entry_type: :message,
      role: :assistant,
      message_type: :thinking,
      content: content,
      rendered_html: rendered_html,
      streaming: streaming,
      timestamp: timestamp
    }
  end

  @doc """
  Creates a new ChatEntry for assistant response.

  ## Parameters

  - `id` - Unique identifier
  - `position` - Position in conversation
  - `content` - Raw markdown content
  - `rendered_html` - Pre-rendered HTML for display
  - `streaming` - Whether currently streaming
  - `timestamp` - Creation time

  ## Example

      iex> entry = ChatEntry.assistant_response("uuid", 3, "Here's my answer", "<p>Here's my answer</p>", false, ~U[2025-01-15 10:30:00Z])
      iex> entry.entry_type
      :message
      iex> entry.message_type
      :response
  """
  @spec assistant_response(
          String.t(),
          pos_integer(),
          String.t(),
          String.t(),
          boolean(),
          DateTime.t()
        ) :: t()
  def assistant_response(
        id,
        position,
        content,
        rendered_html,
        streaming \\ false,
        timestamp \\ DateTime.utc_now()
      ) do
    %__MODULE__{
      id: id,
      position: position,
      entry_type: :message,
      role: :assistant,
      message_type: :response,
      content: content,
      rendered_html: rendered_html,
      streaming: streaming,
      timestamp: timestamp
    }
  end

  # ===========================================================================
  # Tool Invocation Factory Functions
  # ===========================================================================

  @doc """
  Creates a new ChatEntry for a tool invocation.

  Tool invocations represent LLM requests to execute a tool. They go through
  an approval workflow where users can approve or deny the execution.

  ## Parameters

  - `id` - Unique identifier (typically entry_id from the database)
  - `position` - Position in the conversation timeline
  - `tool_call_id` - LLM-assigned identifier for correlating call and result
  - `tool_name` - Name of the tool being invoked (e.g., "msf_command")
  - `arguments` - Map of arguments passed to the tool
  - `status` - Current status in the lifecycle (see module docs)

  ## Options

  - `:console_prompt` - Console prompt at time of creation (e.g., "msf6 > "), defaults to ""
  - `:result_content` - Tool execution result (when completed), defaults to nil
  - `:timestamp` - Creation time, defaults to `DateTime.utc_now()`

  ## Example

      iex> entry = ChatEntry.tool_invocation(
      ...>   "entry-123",
      ...>   5,
      ...>   "call_abc",
      ...>   "msf_command",
      ...>   %{"command" => "search apache"},
      ...>   :pending,
      ...>   console_prompt: "msf6 > ",
      ...>   timestamp: ~U[2025-01-15 10:30:00Z]
      ...> )
      iex> entry.entry_type
      :tool_invocation
      iex> entry.tool_name
      "msf_command"
      iex> entry.tool_status
      :pending
      iex> entry.console_prompt
      "msf6 > "
  """
  @spec tool_invocation(
          String.t() | integer(),
          pos_integer(),
          String.t(),
          String.t(),
          map(),
          tool_status(),
          keyword()
        ) :: t()
  def tool_invocation(id, position, tool_call_id, tool_name, arguments, status, opts \\ []) do
    %__MODULE__{
      id: id,
      position: position,
      entry_type: :tool_invocation,
      tool_call_id: tool_call_id,
      tool_name: tool_name,
      tool_arguments: arguments,
      tool_status: status,
      console_prompt: Keyword.get(opts, :console_prompt, ""),
      result_content: Keyword.get(opts, :result_content),
      streaming: false,
      timestamp: Keyword.get(opts, :timestamp, DateTime.utc_now())
    }
  end

  # ===========================================================================
  # Memory Entry Factory Functions
  # ===========================================================================

  @doc """
  Creates a new ChatEntry for a memory snapshot.

  Memory entries are injected at session start to provide the AI agent with
  its current state (objective, focus, tasks, working notes). They are:

  - Hidden from UI display (filtered in templates)
  - Excluded from compaction summarization
  - Immutable snapshots of memory at that point in time

  ## Parameters

  - `id` - Unique identifier
  - `position` - Position in conversation
  - `content` - Serialized memory content (markdown)
  - `timestamp` - Creation time

  ## Example

      iex> entry = ChatEntry.memory_snapshot("uuid", 1, "## Track Memory\n...", ~U[2025-01-15 10:30:00Z])
      iex> entry.entry_type
      :memory
      iex> entry.role
      :user
  """
  @spec memory_snapshot(String.t() | integer(), pos_integer(), String.t(), DateTime.t()) :: t()
  def memory_snapshot(id, position, content, timestamp \\ DateTime.utc_now()) do
    %__MODULE__{
      id: id,
      position: position,
      entry_type: :memory,
      role: :user,
      message_type: :prompt,
      content: content,
      rendered_html: nil,
      streaming: false,
      timestamp: timestamp
    }
  end

  # ===========================================================================
  # Ecto Conversion Functions
  # ===========================================================================

  @doc """
  Creates a ChatEntry from an Ecto ChatHistoryEntry with preloaded message.

  The entry must have its `:message` association preloaded.

  Note: `rendered_html` is set to nil - call `Msfailab.Markdown.render/1` on the
  content to populate it for assistant entries. This is typically done by
  `ChatContext.entries_to_chat_entries/1`.

  ## Example

      entry = Repo.get!(ChatHistoryEntry, id) |> Repo.preload(:message)
      ChatEntry.from_ecto(entry)
  """
  @spec from_ecto(Msfailab.Tracks.ChatHistoryEntry.t(), boolean()) :: t()
  def from_ecto(%Msfailab.Tracks.ChatHistoryEntry{} = entry, streaming \\ false) do
    %__MODULE__{
      id: entry.id,
      position: entry.position,
      entry_type: :message,
      role: role_to_atom(entry.message.role),
      message_type: message_type_to_atom(entry.message.message_type),
      content: entry.message.content || "",
      rendered_html: nil,
      streaming: streaming,
      timestamp: entry.inserted_at
    }
  end

  @doc """
  Creates a ChatEntry from an Ecto ChatHistoryEntry with preloaded tool_invocation.

  The entry must have its `:tool_invocation` association preloaded.

  ## Example

      entry = Repo.get!(ChatHistoryEntry, id) |> Repo.preload(:tool_invocation)
      ChatEntry.from_tool_invocation_ecto(entry)
  """
  @spec from_tool_invocation_ecto(Msfailab.Tracks.ChatHistoryEntry.t()) :: t()
  def from_tool_invocation_ecto(%Msfailab.Tracks.ChatHistoryEntry{} = entry) do
    ti = entry.tool_invocation

    # Use position as ID for consistency with streaming entries
    # tool_invocations map is keyed by position, and the UI sends
    # entry.id when clicking approve/deny - so these must match
    %__MODULE__{
      id: entry.position,
      position: entry.position,
      entry_type: :tool_invocation,
      tool_call_id: ti.tool_call_id,
      tool_name: ti.tool_name,
      tool_arguments: ti.arguments,
      tool_status: tool_status_to_atom(ti.status),
      console_prompt: ti.console_prompt || "",
      result_content: ti.result_content,
      error_message: ti.error_message,
      streaming: false,
      timestamp: entry.inserted_at
    }
  end

  # ===========================================================================
  # Helper Functions
  # ===========================================================================

  @doc """
  Returns true if this entry is a message entry.

  ## Example

      iex> entry = ChatEntry.user_prompt("uuid", 1, "Hello!", ~U[2025-01-15 10:30:00Z])
      iex> ChatEntry.message?(entry)
      true
  """
  @spec message?(t()) :: boolean()
  def message?(%__MODULE__{entry_type: :message}), do: true
  def message?(%__MODULE__{}), do: false

  @doc """
  Returns true if this entry is a tool invocation entry.

  ## Example

      iex> entry = ChatEntry.tool_invocation("id", 1, "call_1", "msf_command", %{}, :pending, ~U[2025-01-15 10:30:00Z])
      iex> ChatEntry.tool_invocation?(entry)
      true
  """
  @spec tool_invocation?(t()) :: boolean()
  def tool_invocation?(%__MODULE__{entry_type: :tool_invocation}), do: true
  def tool_invocation?(%__MODULE__{}), do: false

  @doc """
  Returns true if this entry is a memory snapshot entry.

  Memory entries are hidden from UI display and excluded from compaction.

  ## Example

      iex> entry = ChatEntry.memory_snapshot("uuid", 1, "## Track Memory\n...")
      iex> ChatEntry.memory?(entry)
      true
  """
  @spec memory?(t()) :: boolean()
  def memory?(%__MODULE__{entry_type: :memory}), do: true
  def memory?(%__MODULE__{}), do: false
end
