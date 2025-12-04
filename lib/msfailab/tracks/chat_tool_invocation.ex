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

defmodule Msfailab.Tracks.ChatToolInvocation do
  @moduledoc """
  Content table for tool invocation entries - combined call and result.

  ## Conceptual Overview

  A **tool invocation** represents a single tool call requested by the LLM
  and its execution lifecycle. Unlike some designs that separate tool calls
  and results into different entries, this schema combines them into a single
  record that tracks the entire lifecycle.

  This design simplifies:
  - Querying tool call status
  - Building LLM context (one entry = call + result)
  - UI rendering (show call, status, and result together)

  ## Status State Machine

  Tool invocations progress through a state machine:

  ```
      pending ───► approved ───► executing ───► success
          │                          │
          │                          ├───► error
          │                          │
          │                          └───► timeout
          │
          └───► denied
  ```

  ### Status Descriptions

  | Status | Description |
  |--------|-------------|
  | `pending` | Awaiting user approval (when tool_approval_mode requires it) |
  | `approved` | User approved; waiting to execute |
  | `denied` | User denied the tool call |
  | `executing` | Currently running |
  | `success` | Completed successfully |
  | `error` | Failed with an error |
  | `timeout` | Execution timed out |

  ## Tool Approval Flow

  Depending on the track's `tool_approval_mode`:

  - **"autonomous"**: Status goes directly from creation to `executing`
  - **"ask_first"**: Status starts at `pending`, waits for user approval/denial
  - **"ask_dangerous"**: Depends on tool classification

  ## Available Tools

  | Tool Name | Description |
  |-----------|-------------|
  | `msf_command` | Execute a Metasploit console command |
  | `bash_command` | Execute a shell command in the container |

  ## LLM Context Building

  When building messages for LLM requests, tool invocations produce two
  message components:

  1. **Tool call** (from assistant):
     ```json
     {
       "role": "assistant",
       "tool_calls": [{
         "id": "call_abc123",
         "type": "function",
         "function": {"name": "execute_msfconsole_command", "arguments": "{\"command\": \"nmap -sV 10.0.0.1\"}"}
       }]
     }
     ```

  2. **Tool result** (when execution completes):
     ```json
     {
       "role": "tool",
       "tool_call_id": "call_abc123",
       "content": "Starting Nmap scan..."
     }
     ```

  ## Shared Identity with Entry

  Like `ChatMessage`, tool invocations use `entry_id` as their primary key,
  establishing a 1:1 relationship with `ChatHistoryEntry`.

  ## Usage Example

  ```elixir
  # Create tool invocation when LLM requests a tool call
  {:ok, invocation} = %ChatToolInvocation{}
    |> ChatToolInvocation.changeset(%{
      entry_id: entry.id,
      tool_call_id: "call_abc123",
      tool_name: "execute_msfconsole_command",
      arguments: %{"command" => "nmap -sV 10.0.0.1"}
    })
    |> Repo.insert()

  # User approves
  invocation
  |> ChatToolInvocation.approve()
  |> Repo.update()

  # Start execution
  invocation
  |> ChatToolInvocation.start_execution()
  |> Repo.update()

  # Complete with success
  invocation
  |> ChatToolInvocation.complete_success(output, duration_ms)
  |> Repo.update()
  ```

  ## Duration Tracking

  The `duration_ms` field records execution time in milliseconds, enabling:
  - Performance analysis
  - Timeout detection
  - Resource usage tracking
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Msfailab.Tracks.ChatHistoryEntry

  @primary_key {:entry_id, :id, autogenerate: false}

  @statuses ~w(pending approved denied executing success error timeout cancelled)

  @type status ::
          :pending | :approved | :denied | :executing | :success | :error | :timeout | :cancelled

  @type t :: %__MODULE__{
          entry_id: integer() | nil,
          entry: ChatHistoryEntry.t() | Ecto.Association.NotLoaded.t(),
          tool_call_id: String.t() | nil,
          tool_name: String.t() | nil,
          arguments: map(),
          console_prompt: String.t(),
          status: String.t(),
          result_content: String.t() | nil,
          duration_ms: integer() | nil,
          error_message: String.t() | nil,
          denied_reason: String.t() | nil
        }

  schema "msfailab_track_chat_tool_invocations" do
    field :tool_call_id, :string
    field :tool_name, :string
    field :arguments, :map, default: %{}
    field :console_prompt, :string, default: ""
    field :status, :string, default: "pending"
    field :result_content, :string
    field :duration_ms, :integer
    field :error_message, :string
    field :denied_reason, :string

    belongs_to :entry, ChatHistoryEntry,
      foreign_key: :entry_id,
      references: :id,
      define_field: false
  end

  @doc """
  Changeset for creating a tool invocation.

  ## Required Fields

  - `entry_id` - The entry this invocation belongs to (1:1 relationship)
  - `tool_call_id` - Provider-assigned ID for correlating call and result
  - `tool_name` - The tool being invoked (e.g., "execute_msfconsole_command", "execute_bash_command")

  ## Optional Fields

  - `arguments` - Tool arguments as a map (defaults to empty map)
  - `console_prompt` - Console prompt at time of creation (for UI display)
  - `status` - Lifecycle status (defaults to "pending")
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(invocation, attrs) do
    invocation
    |> cast(attrs, [
      :entry_id,
      :tool_call_id,
      :tool_name,
      :arguments,
      :console_prompt,
      :status,
      :result_content,
      :duration_ms,
      :error_message,
      :denied_reason
    ])
    |> validate_required([:entry_id, :tool_call_id, :tool_name])
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:entry_id)
  end

  # ---------------------------------------------------------------------------
  # Status Transition Helpers
  # ---------------------------------------------------------------------------

  @doc """
  Creates a changeset to approve a pending tool call.

  Transitions: pending → approved
  """
  @spec approve(t()) :: Ecto.Changeset.t()
  def approve(invocation) do
    change(invocation, status: "approved")
  end

  @doc """
  Creates a changeset to deny a pending tool call with a reason.

  Transitions: pending → denied
  """
  @spec deny(t(), String.t()) :: Ecto.Changeset.t()
  def deny(invocation, reason) do
    change(invocation, status: "denied", denied_reason: reason)
  end

  @doc """
  Creates a changeset to start tool execution.

  Transitions: approved → executing (or pending → executing in autonomous mode)
  """
  @spec start_execution(t()) :: Ecto.Changeset.t()
  def start_execution(invocation) do
    change(invocation, status: "executing")
  end

  @doc """
  Creates a changeset to record successful completion.

  Transitions: executing → success
  """
  @spec complete_success(t(), String.t(), integer()) :: Ecto.Changeset.t()
  def complete_success(invocation, result, duration_ms) do
    change(invocation, status: "success", result_content: result, duration_ms: duration_ms)
  end

  @doc """
  Creates a changeset to record an error.

  Transitions: executing → error
  """
  @spec complete_error(t(), String.t(), integer()) :: Ecto.Changeset.t()
  def complete_error(invocation, error, duration_ms) do
    change(invocation, status: "error", error_message: error, duration_ms: duration_ms)
  end

  @doc """
  Creates a changeset to record a timeout.

  Transitions: executing → timeout
  """
  @spec complete_timeout(t(), integer()) :: Ecto.Changeset.t()
  def complete_timeout(invocation, duration_ms) do
    change(invocation, status: "timeout", duration_ms: duration_ms)
  end

  @doc "Returns the list of valid status values."
  @spec statuses() :: [String.t()]
  def statuses, do: @statuses

  @doc "Returns true if the invocation has a terminal status."
  @spec terminal?(t()) :: boolean()
  def terminal?(%__MODULE__{status: status}) do
    status in ~w(denied success error timeout cancelled)
  end

  @doc "Returns true if the invocation is awaiting approval."
  @spec pending?(t()) :: boolean()
  def pending?(%__MODULE__{status: "pending"}), do: true
  def pending?(_), do: false
end
