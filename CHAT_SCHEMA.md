# Chat History Schema

This document describes the database schema, state models, and runtime architecture for the LLM chat feature in msfailab.

## Overview

The chat feature enables AI-assisted security research within tracks. The AI agent can:
- Respond to user prompts with reasoning and answers
- Execute Metasploit and bash commands via tool calls
- See user-initiated MSF console activity for context
- Manage long conversations through compaction

## Key Principles

1. **Track is the conversation**: No separate conversation entity; the track owns all chat state
2. **Turns represent agentic loops**: A turn is one complete user-to-agent cycle, potentially with multiple LLM calls
3. **Entries are the timeline**: Immutable, position-ordered records of conversation content
4. **Content tables provide type safety**: Each entry type has its own table with appropriate columns
5. **Compactions are separate entities**: Not part of the timeline; summaries that replace older content
6. **Position is the only ordering**: Simple monotonic counter, no computed ordering
7. **Runtime handles synchronization**: TrackServer manages buffering and ordering guarantees

## Entity Relationships

```
Track
├── current_model: string
├── tool_approval_mode: string
│
├── has_many :turns
│   └── Turn
│       ├── status: pending → streaming → executing_tools → ... → finished
│       ├── has_many :llm_responses
│       │   └── LLMResponse
│       │       ├── token metrics
│       │       └── has_many :entries (LLM-produced)
│       └── has_many :entries (turn-scoped)
│
├── has_many :entries (the conversation timeline)
│   └── Entry
│       ├── position: integer (chronological order)
│       ├── entry_type: "message" | "tool_invocation" | "console_context"
│       │
│       ├── has_one :message (when entry_type = "message")
│       ├── has_one :tool_invocation (when entry_type = "tool_invocation")
│       └── has_one :console_context (when entry_type = "console_context")
│
└── has_many :compactions (summaries, NOT part of timeline)
    └── Compaction
        ├── content: text (the summary)
        ├── summarized_up_to_position: integer
        └── previous_compaction_id: self-reference (audit chain)
```

## Turns

### Definition

A **turn** represents one complete agentic loop: from user input until the AI stops (no more tool calls). A single turn may contain multiple LLM API calls if tools are involved.

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

### Status State Machine

The turn status is **cyclical**, not linear. It cycles through states until the LLM responds without tool calls.

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
| `pending_approval` | Tool calls awaiting user approval (when not autonomous) |
| `executing_tools` | Tools are running |
| `finished` | Turn complete, agent idle |
| `error` | Turn failed due to error |
| `interrupted` | Turn was interrupted (e.g., process crash) |

### Triggers

| Trigger | Description |
|---------|-------------|
| `user_prompt` | User initiated this turn with a message |
| `scheduled_prompt` | (Future) Scheduled/automated prompt |
| `script_triggered` | (Future) External script triggered the turn |

## LLM Responses

### Definition

An **LLM response** represents one API call to the LLM provider. A turn contains 1..N LLM responses.

### Token Metrics

Different providers return different metrics. We normalize to:

| Column | OpenAI | Anthropic | Ollama |
|--------|--------|-----------|--------|
| `input_tokens` | `prompt_tokens` | `input_tokens` | `prompt_eval_count` |
| `output_tokens` | `completion_tokens` | `output_tokens` | `eval_count` |
| `cached_input_tokens` | `prompt_tokens_details.cached_tokens` | `cache_read_input_tokens` | N/A |
| `cache_creation_tokens` | N/A | `cache_creation_input_tokens` | N/A |

### Cache Context

Provider-specific caching mechanisms:

| Provider | Mechanism | Stored Data |
|----------|-----------|-------------|
| Ollama | Returns `context` array of token IDs | JSON array stored in `cache_context` |
| Anthropic | Cache control via message structure | Nothing stored; caching is implicit |
| OpenAI | Automatic prefix caching | Nothing stored; fully automatic |

## Entries

### Definition

An **entry** is a slot in the conversation timeline. It has a `position` (chronological order) and an `entry_type` that determines which content table holds its payload.

### Entry Types

| Type | Content Table | Turn-Scoped | Description |
|------|---------------|-------------|-------------|
| `message` | `chat_messages` | Yes | User prompts, AI thinking, AI responses |
| `tool_invocation` | `chat_tool_invocations` | Yes | Tool call + result (combined) |
| `console_context` | `chat_console_contexts` | **No** | MSF commands run by user |

### Position

The `position` column is:
- **Monotonically increasing**: Each new entry gets `max(position) + 1`
- **Immutable**: Never changes after creation
- **Track-scoped**: Unique within a track
- **The only ordering**: No computed or secondary ordering fields

```
Entry 1: position=1, type=message (user prompt)
Entry 2: position=2, type=message (AI response)
Entry 3: position=3, type=tool_invocation
Entry 4: position=4, type=message (AI response)
Entry 5: position=5, type=console_context (user ran MSF command)
Entry 6: position=6, type=message (user prompt)
...
```

### Entry Lifecycle

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

## Content Tables

### Messages

Holds content for `user_prompt`, `thinking`, and `response` entries.

| Column | Type | Description |
|--------|------|-------------|
| `entry_id` | binary_id (PK) | Shared identity with Entry |
| `role` | string | `"user"` or `"assistant"` |
| `message_type` | string | `"prompt"`, `"thinking"`, or `"response"` |
| `content` | text | The message text |

**Valid combinations:**

| role | message_type | Description |
|------|--------------|-------------|
| `user` | `prompt` | User's input message |
| `assistant` | `thinking` | AI's extended thinking (may be hidden from user) |
| `assistant` | `response` | AI's visible response |

### Tool Invocations

Holds **combined** call + result for tool executions. One entry, one row, complete lifecycle.

| Column | Type | Description |
|--------|------|-------------|
| `entry_id` | binary_id (PK) | Shared identity with Entry |
| `tool_call_id` | string | Provider-assigned ID |
| `tool_name` | string | `"execute_msfconsole_command"`, `"execute_bash_command"` |
| `arguments` | map | Tool arguments |
| `status` | string | Lifecycle status (see below) |
| `result_content` | text | Tool output (when complete) |
| `duration_ms` | integer | Execution time |
| `error_message` | text | Error details (if failed) |
| `denied_reason` | text | Denial reason (if denied) |

**Status state machine:**

```
    pending ───► approved ───► executing ───► success
        │                          │
        │                          ├───► error
        │                          │
        │                          └───► timeout
        │
        └───► denied
```

| Status | Description |
|--------|-------------|
| `pending` | Awaiting user approval (if required) |
| `approved` | User approved, awaiting execution |
| `denied` | User denied the tool call |
| `executing` | Currently running |
| `success` | Completed successfully |
| `error` | Failed with error |
| `timeout` | Execution timed out |

### Console Contexts

Holds user-initiated MSF console activity injected into conversation.

| Column | Type | Description |
|--------|------|-------------|
| `entry_id` | binary_id (PK) | Shared identity with Entry |
| `content` | text | Command and output |
| `console_history_block_id` | binary_id | Reference to source MSF console block |

## Compactions

### Definition

A **compaction** is a summary that replaces older conversation content. Compactions are **not entries** - they are a separate entity that tracks what portion of the timeline has been summarized.

### Key Properties

1. **Cumulative**: Each compaction summarizes everything up to a position, including previous compactions
2. **Only latest matters**: For LLM context, only the most recent compaction is used
3. **Chain for audit**: Previous compactions are retained and linked for audit trail
4. **Entries are preserved**: Original entries are never deleted, just excluded from LLM context

### Example Timeline

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

### Compaction Columns

| Column | Type | Description |
|--------|------|-------------|
| `id` | binary_id | Primary key |
| `track_id` | FK | Parent track |
| `content` | text | The summary content |
| `summarized_up_to_position` | integer | Last position included in summary |
| `previous_compaction_id` | FK (self) | Previous compaction (audit chain) |
| `entries_summarized_count` | integer | Number of entries summarized |
| `input_tokens_before` | integer | Token count before compaction |
| `input_tokens_after` | integer | Token count after compaction |
| `compaction_model` | string | Model used for summarization |
| `compaction_duration_ms` | integer | How long summarization took |

## Database Schema

### Table: msfailab_track_chat_history_turns

```elixir
create table(:msfailab_track_chat_history_turns, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :track_id, references(:msfailab_tracks, on_delete: :delete_all), null: false

  add :position, :integer, null: false

  add :trigger, :string, null: false
  # Values: "user_prompt", (future: "scheduled_prompt", "script_triggered")

  add :status, :string, null: false, default: "pending"
  # Values: "pending", "streaming", "pending_approval", "executing_tools",
  #         "finished", "error", "interrupted"

  # Snapshot at turn creation
  add :model, :string, null: false
  add :tool_approval_mode, :string, null: false

  timestamps(type: :utc_datetime_usec)
end

create index(:msfailab_track_chat_history_turns, [:track_id])
create index(:msfailab_track_chat_history_turns, [:track_id, :position])
create index(:msfailab_track_chat_history_turns, [:track_id, :status])
```

### Table: msfailab_track_chat_history_llm_responses

```elixir
create table(:msfailab_track_chat_history_llm_responses, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :track_id, references(:msfailab_tracks, on_delete: :delete_all), null: false
  add :turn_id, references(:msfailab_track_chat_history_turns,
                           type: :binary_id, on_delete: :delete_all), null: false

  add :model, :string, null: false

  # Normalized token metrics
  add :input_tokens, :integer, null: false
  add :output_tokens, :integer, null: false
  add :cached_input_tokens, :integer
  add :cache_creation_tokens, :integer

  # Provider-specific cache context
  add :cache_context, :map

  timestamps(type: :utc_datetime_usec, updated_at: false)
end

create index(:msfailab_track_chat_history_llm_responses, [:track_id])
create index(:msfailab_track_chat_history_llm_responses, [:turn_id])
```

### Table: msfailab_track_chat_history_entries

```elixir
create table(:msfailab_track_chat_history_entries, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :track_id, references(:msfailab_tracks, on_delete: :delete_all), null: false

  # Turn-scoped entries have turn_id; console_context doesn't
  add :turn_id, references(:msfailab_track_chat_history_turns,
                           type: :binary_id, on_delete: :delete_all)

  # LLM-generated entries have llm_response_id
  add :llm_response_id, references(:msfailab_track_chat_history_llm_responses,
                                   type: :binary_id, on_delete: :nilify_all)

  # Chronological ordering (the ONLY ordering field)
  add :position, :integer, null: false

  # Type discriminator
  add :entry_type, :string, null: false
  # Values: "message", "tool_invocation", "console_context"

  timestamps(type: :utc_datetime_usec)
end

create unique_index(:msfailab_track_chat_history_entries, [:track_id, :position])
create index(:msfailab_track_chat_history_entries, [:turn_id])
create index(:msfailab_track_chat_history_entries, [:llm_response_id])
create index(:msfailab_track_chat_history_entries, [:entry_type])
```

### Table: msfailab_track_chat_messages

```elixir
create table(:msfailab_track_chat_messages, primary_key: false) do
  # Shared identity with Entry
  add :entry_id, references(:msfailab_track_chat_history_entries,
                            type: :binary_id, on_delete: :delete_all),
      primary_key: true

  add :role, :string, null: false
  # Values: "user", "assistant"

  add :message_type, :string, null: false
  # Values: "prompt", "thinking", "response"

  add :content, :text, null: false, default: ""
end
```

### Table: msfailab_track_chat_tool_invocations

```elixir
create table(:msfailab_track_chat_tool_invocations, primary_key: false) do
  add :entry_id, references(:msfailab_track_chat_history_entries,
                            type: :binary_id, on_delete: :delete_all),
      primary_key: true

  # Call info (from LLM)
  add :tool_call_id, :string, null: false
  add :tool_name, :string, null: false
  add :arguments, :map, null: false, default: %{}

  # Lifecycle status
  add :status, :string, null: false, default: "pending"
  # Values: "pending", "approved", "denied", "executing", "success", "error", "timeout"

  # Result info (filled when execution completes)
  add :result_content, :text
  add :duration_ms, :integer
  add :error_message, :text
  add :denied_reason, :text
end

create index(:msfailab_track_chat_tool_invocations, [:tool_call_id])
create index(:msfailab_track_chat_tool_invocations, [:status])
```

### Table: msfailab_track_chat_console_contexts

```elixir
create table(:msfailab_track_chat_console_contexts, primary_key: false) do
  add :entry_id, references(:msfailab_track_chat_history_entries,
                            type: :binary_id, on_delete: :delete_all),
      primary_key: true

  add :content, :text, null: false

  # Reference to source MSF console activity
  add :console_history_block_id, :binary_id
end
```

### Table: msfailab_track_chat_compactions

```elixir
create table(:msfailab_track_chat_compactions, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :track_id, references(:msfailab_tracks, on_delete: :delete_all), null: false

  # The summary content
  add :content, :text, null: false

  # What this compaction covers
  add :summarized_up_to_position, :integer, null: false

  # Audit chain
  add :previous_compaction_id, references(:msfailab_track_chat_compactions,
                                          type: :binary_id, on_delete: :nilify_all)

  # Metrics
  add :entries_summarized_count, :integer, null: false
  add :input_tokens_before, :integer, null: false
  add :input_tokens_after, :integer, null: false
  add :compaction_model, :string, null: false
  add :compaction_duration_ms, :integer

  timestamps(type: :utc_datetime_usec)
end

create index(:msfailab_track_chat_compactions, [:track_id])
create index(:msfailab_track_chat_compactions, [:track_id, :inserted_at])
```

## Ecto Schemas

### Turn Schema

```elixir
defmodule Msfailab.Tracks.ChatHistoryTurn do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(pending streaming pending_approval executing_tools finished error interrupted)
  @triggers ~w(user_prompt scheduled_prompt script_triggered)

  schema "msfailab_track_chat_history_turns" do
    field :position, :integer
    field :trigger, :string
    field :status, :string, default: "pending"
    field :model, :string
    field :tool_approval_mode, :string

    belongs_to :track, Msfailab.Tracks.Track
    has_many :llm_responses, Msfailab.Tracks.ChatHistoryLLMResponse
    has_many :entries, Msfailab.Tracks.ChatHistoryEntry

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(turn, attrs) do
    turn
    |> cast(attrs, [:position, :trigger, :status, :model, :tool_approval_mode, :track_id])
    |> validate_required([:position, :trigger, :model, :tool_approval_mode, :track_id])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:trigger, @triggers)
    |> foreign_key_constraint(:track_id)
  end
end
```

### LLM Response Schema

```elixir
defmodule Msfailab.Tracks.ChatHistoryLLMResponse do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "msfailab_track_chat_history_llm_responses" do
    field :model, :string
    field :input_tokens, :integer
    field :output_tokens, :integer
    field :cached_input_tokens, :integer
    field :cache_creation_tokens, :integer
    field :cache_context, :map

    belongs_to :track, Msfailab.Tracks.Track
    belongs_to :turn, Msfailab.Tracks.ChatHistoryTurn
    has_many :entries, Msfailab.Tracks.ChatHistoryEntry

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(response, attrs) do
    response
    |> cast(attrs, [:model, :input_tokens, :output_tokens, :cached_input_tokens,
                    :cache_creation_tokens, :cache_context, :track_id, :turn_id])
    |> validate_required([:model, :input_tokens, :output_tokens, :track_id, :turn_id])
    |> validate_number(:input_tokens, greater_than_or_equal_to: 0)
    |> validate_number(:output_tokens, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:track_id)
    |> foreign_key_constraint(:turn_id)
  end
end
```

### Entry Schema

```elixir
defmodule Msfailab.Tracks.ChatHistoryEntry do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @entry_types ~w(message tool_invocation console_context)

  schema "msfailab_track_chat_history_entries" do
    field :position, :integer
    field :entry_type, :string

    belongs_to :track, Msfailab.Tracks.Track
    belongs_to :turn, Msfailab.Tracks.ChatHistoryTurn
    belongs_to :llm_response, Msfailab.Tracks.ChatHistoryLLMResponse

    # Content associations (exactly one based on entry_type)
    has_one :message, Msfailab.Tracks.ChatMessage, foreign_key: :entry_id
    has_one :tool_invocation, Msfailab.Tracks.ChatToolInvocation, foreign_key: :entry_id
    has_one :console_context, Msfailab.Tracks.ChatConsoleContext, foreign_key: :entry_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:position, :entry_type, :track_id, :turn_id, :llm_response_id])
    |> validate_required([:position, :entry_type, :track_id])
    |> validate_inclusion(:entry_type, @entry_types)
    |> foreign_key_constraint(:track_id)
    |> foreign_key_constraint(:turn_id)
    |> foreign_key_constraint(:llm_response_id)
  end
end
```

### Message Schema

```elixir
defmodule Msfailab.Tracks.ChatMessage do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:entry_id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  @roles ~w(user assistant)
  @message_types ~w(prompt thinking response)

  schema "msfailab_track_chat_messages" do
    field :role, :string
    field :message_type, :string
    field :content, :string, default: ""

    belongs_to :entry, Msfailab.Tracks.ChatHistoryEntry,
      foreign_key: :entry_id, references: :id, define_field: false
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:entry_id, :role, :message_type, :content])
    |> validate_required([:entry_id, :role, :message_type])
    |> validate_inclusion(:role, @roles)
    |> validate_inclusion(:message_type, @message_types)
    |> validate_role_message_type_combination()
    |> foreign_key_constraint(:entry_id)
  end

  defp validate_role_message_type_combination(changeset) do
    case {get_field(changeset, :role), get_field(changeset, :message_type)} do
      {"user", "prompt"} -> changeset
      {"assistant", type} when type in ~w(thinking response) -> changeset
      {role, type} -> add_error(changeset, :message_type, "#{type} invalid for role #{role}")
    end
  end
end
```

### Tool Invocation Schema

```elixir
defmodule Msfailab.Tracks.ChatToolInvocation do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:entry_id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  @statuses ~w(pending approved denied executing success error timeout)

  schema "msfailab_track_chat_tool_invocations" do
    field :tool_call_id, :string
    field :tool_name, :string
    field :arguments, :map, default: %{}
    field :status, :string, default: "pending"
    field :result_content, :string
    field :duration_ms, :integer
    field :error_message, :string
    field :denied_reason, :string

    belongs_to :entry, Msfailab.Tracks.ChatHistoryEntry,
      foreign_key: :entry_id, references: :id, define_field: false
  end

  def changeset(invocation, attrs) do
    invocation
    |> cast(attrs, [:entry_id, :tool_call_id, :tool_name, :arguments, :status,
                    :result_content, :duration_ms, :error_message, :denied_reason])
    |> validate_required([:entry_id, :tool_call_id, :tool_name])
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:entry_id)
  end

  # Status transition helpers
  def approve(invocation), do: change(invocation, status: "approved")
  def deny(invocation, reason), do: change(invocation, status: "denied", denied_reason: reason)
  def start_execution(invocation), do: change(invocation, status: "executing")

  def complete_success(invocation, result, duration_ms) do
    change(invocation, status: "success", result_content: result, duration_ms: duration_ms)
  end

  def complete_error(invocation, error, duration_ms) do
    change(invocation, status: "error", error_message: error, duration_ms: duration_ms)
  end

  def complete_timeout(invocation, duration_ms) do
    change(invocation, status: "timeout", duration_ms: duration_ms)
  end
end
```

### Console Context Schema

```elixir
defmodule Msfailab.Tracks.ChatConsoleContext do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:entry_id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "msfailab_track_chat_console_contexts" do
    field :content, :string
    field :console_history_block_id, :binary_id

    belongs_to :entry, Msfailab.Tracks.ChatHistoryEntry,
      foreign_key: :entry_id, references: :id, define_field: false
  end

  def changeset(console_context, attrs) do
    console_context
    |> cast(attrs, [:entry_id, :content, :console_history_block_id])
    |> validate_required([:entry_id, :content])
    |> foreign_key_constraint(:entry_id)
  end
end
```

### Compaction Schema

```elixir
defmodule Msfailab.Tracks.ChatCompaction do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "msfailab_track_chat_compactions" do
    field :content, :string
    field :summarized_up_to_position, :integer
    field :entries_summarized_count, :integer
    field :input_tokens_before, :integer
    field :input_tokens_after, :integer
    field :compaction_model, :string
    field :compaction_duration_ms, :integer

    belongs_to :track, Msfailab.Tracks.Track
    belongs_to :previous_compaction, __MODULE__

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(compaction, attrs) do
    compaction
    |> cast(attrs, [:content, :summarized_up_to_position, :entries_summarized_count,
                    :input_tokens_before, :input_tokens_after, :compaction_model,
                    :compaction_duration_ms, :track_id, :previous_compaction_id])
    |> validate_required([:content, :summarized_up_to_position, :entries_summarized_count,
                          :input_tokens_before, :input_tokens_after, :compaction_model,
                          :track_id])
    |> validate_number(:summarized_up_to_position, greater_than: 0)
    |> foreign_key_constraint(:track_id)
    |> foreign_key_constraint(:previous_compaction_id)
  end
end
```

## Query Patterns

### Get LLM Context

The primary query for building LLM requests:

```elixir
defmodule Msfailab.Tracks.ChatContext do
  import Ecto.Query
  alias Msfailab.Repo
  alias Msfailab.Tracks.{ChatHistoryEntry, ChatCompaction}

  @doc """
  Returns the context needed for an LLM request:
  - The latest compaction (if any)
  - All entries after the compaction's range

  ## Example

      iex> get_context(track_id)
      %{compaction: %ChatCompaction{...}, entries: [%ChatHistoryEntry{}, ...]}

  """
  def get_context(track_id) do
    # 1. Get latest compaction
    latest_compaction =
      from(c in ChatCompaction,
        where: c.track_id == ^track_id,
        order_by: [desc: c.inserted_at],
        limit: 1
      )
      |> Repo.one()

    # 2. Determine minimum position for entries
    min_position =
      case latest_compaction do
        nil -> 0
        %{summarized_up_to_position: pos} -> pos
      end

    # 3. Get entries after compaction range
    entries =
      from(e in ChatHistoryEntry,
        where: e.track_id == ^track_id,
        where: e.position > ^min_position,
        order_by: e.position,
        preload: [:message, :tool_invocation, :console_context]
      )
      |> Repo.all()

    %{compaction: latest_compaction, entries: entries}
  end
end
```

### Get Turn Entries

```elixir
@doc """
Get all entries for a specific turn, in order.
"""
def get_turn_entries(turn_id) do
  from(e in ChatHistoryEntry,
    where: e.turn_id == ^turn_id,
    order_by: e.position,
    preload: [:message, :tool_invocation]
  )
  |> Repo.all()
end
```

### Get Pending Tool Approvals

```elixir
@doc """
Get tool invocations awaiting user approval.
"""
def get_pending_approvals(track_id) do
  from(e in ChatHistoryEntry,
    join: ti in assoc(e, :tool_invocation),
    where: e.track_id == ^track_id,
    where: ti.status == "pending",
    order_by: e.position,
    preload: [tool_invocation: ti]
  )
  |> Repo.all()
end
```

### Count Tokens for Compaction Decision

```elixir
@doc """
Estimate token count for entries in a range.
Used to decide when compaction is needed.
"""
def estimate_tokens(track_id, from_position, to_position) do
  from(e in ChatHistoryEntry,
    join: m in assoc(e, :message),
    where: e.track_id == ^track_id,
    where: e.position >= ^from_position,
    where: e.position <= ^to_position,
    select: sum(fragment("length(?)", m.content))
  )
  |> Repo.one()
  |> Kernel.||(0)
  |> Kernel./(4)  # Rough tokens estimate: 4 chars per token
  |> round()
end
```

### Create Entry with Content

```elixir
@doc """
Create an entry and its content in a transaction.
"""
def create_message_entry(track_id, turn_id, llm_response_id, attrs) do
  Repo.transaction(fn ->
    # Get next position
    position = next_position(track_id)

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

defp next_position(track_id) do
  from(e in ChatHistoryEntry,
    where: e.track_id == ^track_id,
    select: coalesce(max(e.position), 0) + 1
  )
  |> Repo.one()
end
```

### Create Compaction

```elixir
@doc """
Create a new compaction that summarizes entries up to a position.
"""
def create_compaction(track_id, summary_content, up_to_position, opts) do
  # Get previous compaction for chain
  previous =
    from(c in ChatCompaction,
      where: c.track_id == ^track_id,
      order_by: [desc: c.inserted_at],
      limit: 1
    )
    |> Repo.one()

  # Count entries being summarized
  previous_position = if previous, do: previous.summarized_up_to_position, else: 0

  entries_count =
    from(e in ChatHistoryEntry,
      where: e.track_id == ^track_id,
      where: e.position > ^previous_position,
      where: e.position <= ^up_to_position,
      select: count(e.id)
    )
    |> Repo.one()

  %ChatCompaction{}
  |> ChatCompaction.changeset(%{
    track_id: track_id,
    content: summary_content,
    summarized_up_to_position: up_to_position,
    previous_compaction_id: previous && previous.id,
    entries_summarized_count: entries_count,
    input_tokens_before: opts[:input_tokens_before],
    input_tokens_after: opts[:input_tokens_after],
    compaction_model: opts[:model],
    compaction_duration_ms: opts[:duration_ms]
  })
  |> Repo.insert()
end
```

## Building LLM Messages

Convert context to provider-specific message format:

```elixir
defmodule Msfailab.Tracks.ChatContext.MessageBuilder do
  @doc """
  Convert context (compaction + entries) to LLM message format.
  """
  def build_messages(%{compaction: compaction, entries: entries}) do
    compaction_messages = build_compaction_messages(compaction)
    entry_messages = Enum.flat_map(entries, &entry_to_messages/1)

    compaction_messages ++ entry_messages
  end

  defp build_compaction_messages(nil), do: []
  defp build_compaction_messages(%{content: content}) do
    [%{
      role: "user",
      content: """
      [CONVERSATION SUMMARY]
      The following is a summary of our previous conversation:

      #{content}

      [END SUMMARY]
      """
    }]
  end

  defp entry_to_messages(%{entry_type: "message", message: msg}) do
    [%{role: msg.role, content: msg.content}]
  end

  defp entry_to_messages(%{entry_type: "tool_invocation", tool_invocation: ti}) do
    # Tool call from assistant
    call_message = %{
      role: "assistant",
      tool_calls: [%{
        id: ti.tool_call_id,
        type: "function",
        function: %{
          name: ti.tool_name,
          arguments: Jason.encode!(ti.arguments)
        }
      }]
    }

    # Tool result (if execution completed)
    result_messages =
      if ti.status in ~w(success error timeout denied) do
        content = case ti.status do
          "success" -> ti.result_content || ""
          "error" -> "Error: #{ti.error_message}"
          "timeout" -> "Error: Tool execution timed out"
          "denied" -> "Tool call was denied by user: #{ti.denied_reason}"
        end

        [%{role: "tool", tool_call_id: ti.tool_call_id, content: content}]
      else
        []
      end

    [call_message | result_messages]
  end

  defp entry_to_messages(%{entry_type: "console_context", console_context: cc}) do
    [%{
      role: "user",
      content: """
      [CONSOLE ACTIVITY]
      The user executed the following commands in the Metasploit console:

      #{cc.content}

      [END CONSOLE ACTIVITY]
      """
    }]
  end
end
```

## Runtime Requirements

### TrackServer State

The TrackServer GenServer manages runtime state that cannot be represented in the database:

```elixir
defmodule Msfailab.Tracks.TrackServer do
  use GenServer

  defstruct [
    :track_id,
    :current_turn_id,
    :current_llm_response_id,

    # Position counter (could also query DB each time)
    :next_position,

    # Is LLM currently streaming?
    :llm_streaming,

    # Buffered console contexts (inserted after LLM completes)
    :pending_console_contexts,

    # Currently streaming entries (not yet persisted)
    :streaming_entries
  ]
end
```

### Console Context Buffering

**Requirement:** Console context entries must appear AFTER LLM response entries, even if the console command completed during LLM streaming.

**Solution:** Buffer console contexts in TrackServer during LLM streaming:

```elixir
defmodule Msfailab.Tracks.TrackServer do
  # MSF command completed while LLM is streaming
  def handle_cast({:console_command_completed, content, source_id}, state) do
    if state.llm_streaming do
      # Buffer for later insertion
      pending = [{content, source_id} | state.pending_console_contexts]
      {:noreply, %{state | pending_console_contexts: pending}}
    else
      # Insert immediately
      {:ok, _entry} = insert_console_context(state, content, source_id)
      {:noreply, increment_position(state)}
    end
  end

  # LLM streaming completes
  def handle_info({:llm_stream_complete, llm_response}, state) do
    # 1. Persist any streaming entries
    persist_streaming_entries(state)

    # 2. Flush buffered console contexts (now they get positions after LLM entries)
    for {content, source_id} <- Enum.reverse(state.pending_console_contexts) do
      insert_console_context(state, content, source_id)
    end

    {:noreply, %{state |
      llm_streaming: false,
      pending_console_contexts: [],
      streaming_entries: %{}
    }}
  end
end
```

### Position Assignment Serialization

**Requirement:** Positions must be unique and sequential within a track.

**Solution:** All position assignments go through TrackServer (a single GenServer per track):

```elixir
defp assign_position(state) do
  position = state.next_position
  new_state = %{state | next_position: position + 1}
  {position, new_state}
end
```

Alternative: Use database sequence or `SELECT ... FOR UPDATE` if TrackServer restart could cause gaps.

### Streaming Entry Management

**Requirement:** Entries are persisted only when complete, but UI needs to show streaming content.

**Solution:** Hold streaming entries in memory, broadcast updates via events:

```elixir
# Start streaming a new entry
def handle_info({:llm_stream, :content_block_start, block}, state) do
  {position, state} = assign_position(state)

  streaming_entry = %{
    id: Ecto.UUID.generate(),
    position: position,
    entry_type: "message",
    content: "",
    role: "assistant",
    message_type: block.type  # "thinking" or "text"
  }

  # Broadcast to UI
  Events.broadcast(%ChatEntryStarted{
    track_id: state.track_id,
    entry_id: streaming_entry.id,
    ...
  })

  streaming_entries = Map.put(state.streaming_entries, block.index, streaming_entry)
  {:noreply, %{state | streaming_entries: streaming_entries}}
end

# Append streaming content
def handle_info({:llm_stream, :content_delta, %{index: index, delta: delta}}, state) do
  streaming_entry = state.streaming_entries[index]
  updated = %{streaming_entry | content: streaming_entry.content <> delta}

  # Broadcast accumulated content (self-healing)
  Events.broadcast(%ChatEntryUpdated{
    entry_id: updated.id,
    content: updated.content,  # Full content, not delta
    ...
  })

  streaming_entries = Map.put(state.streaming_entries, index, updated)
  {:noreply, %{state | streaming_entries: streaming_entries}}
end
```

## Events

Events follow the self-healing pattern: subsequent events carry all information from previous events.

### Turn Events

```elixir
defmodule Msfailab.Events.ChatTurnStarted do
  defstruct [:workspace_id, :track_id, :turn_id, :position, :trigger,
             :model, :tool_approval_mode, :status]
end

defmodule Msfailab.Events.ChatTurnUpdated do
  defstruct [:workspace_id, :track_id, :turn_id, :position, :trigger,
             :model, :tool_approval_mode, :status]
end

defmodule Msfailab.Events.ChatTurnFinished do
  defstruct [:workspace_id, :track_id, :turn_id, :position, :trigger,
             :model, :tool_approval_mode, :status,
             :total_input_tokens, :total_output_tokens, :llm_response_count]
end
```

### Entry Events

```elixir
defmodule Msfailab.Events.ChatEntryStarted do
  @moduledoc """
  Broadcast when a new entry is created (may still be streaming).
  """
  defstruct [:workspace_id, :track_id, :turn_id, :entry_id, :entry_type,
             :position, :content, :metadata]
end

defmodule Msfailab.Events.ChatEntryUpdated do
  @moduledoc """
  Broadcast during streaming. Contains ACCUMULATED content (not delta).
  """
  defstruct [:workspace_id, :track_id, :turn_id, :entry_id, :entry_type,
             :position, :content, :metadata]
end

defmodule Msfailab.Events.ChatEntryFinished do
  @moduledoc """
  Broadcast when entry is complete and persisted.
  """
  defstruct [:workspace_id, :track_id, :turn_id, :entry_id, :entry_type,
             :position, :content, :metadata]
end
```

### Tool Events

```elixir
defmodule Msfailab.Events.ChatToolPendingApproval do
  defstruct [:workspace_id, :track_id, :turn_id, :entry_id,
             :tool_call_id, :tool_name, :arguments]
end

defmodule Msfailab.Events.ChatToolApproved do
  defstruct [:workspace_id, :track_id, :turn_id, :entry_id,
             :tool_call_id, :tool_name, :arguments]
end

defmodule Msfailab.Events.ChatToolDenied do
  defstruct [:workspace_id, :track_id, :turn_id, :entry_id,
             :tool_call_id, :tool_name, :arguments, :denial_reason]
end

defmodule Msfailab.Events.ChatToolStarted do
  defstruct [:workspace_id, :track_id, :turn_id, :entry_id,
             :tool_call_id, :tool_name, :arguments]
end

defmodule Msfailab.Events.ChatToolFinished do
  defstruct [:workspace_id, :track_id, :turn_id, :entry_id,
             :tool_call_id, :tool_name, :status, :duration_ms]
end
```

### Compaction Event

```elixir
defmodule Msfailab.Events.ChatCompactionCreated do
  defstruct [:workspace_id, :track_id, :compaction_id,
             :summarized_up_to_position, :entries_summarized_count,
             :input_tokens_before, :input_tokens_after]
end
```

## Summary

| Concept | Implementation |
|---------|----------------|
| **Conversation timeline** | `entries` table with `position` ordering |
| **Type safety** | Separate content tables (messages, tool_invocations, console_contexts) |
| **Compaction** | Separate `compactions` table; only latest used for LLM context |
| **Ordering** | Single `position` field; monotonic, immutable |
| **Console context timing** | TrackServer buffers during LLM streaming |
| **Streaming content** | Held in TrackServer memory; persisted on completion |
| **Self-healing events** | Accumulated content, full context in every event |
