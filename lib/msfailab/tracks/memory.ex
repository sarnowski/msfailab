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

defmodule Msfailab.Tracks.Memory do
  @moduledoc """
  Track Memory provides short-term memory for AI agents working within a track.

  ## Purpose

  When conversation context grows too long, compaction summarizes older messages.
  Without explicit memory, agents lose their high-level objective, current focus,
  task list progress, and temporary observations. Track Memory solves this by
  providing a structured memory that persists across context compactions.

  ## Conceptual Model

  Memory is:
  1. **Stored** in the track as the source of truth (JSONB in database)
  2. **Updated** by the agent via dedicated tools
  3. **Injected** as a ChatEntry snapshot at session start (and after compaction)
  4. **Filtered** from compaction summarization to avoid distortion

  ## Data Structure

  ```
  %Memory{
    objective: string | nil,      # The "red line" - ultimate goal (rarely changes)
    focus: string | nil,          # Current focus - what agent is doing now
    tasks: [Task.t()],            # Structured task list with status
    working_notes: string | nil   # Temporary observations, hypotheses, blockers
  }

  %Task{
    id: string,                   # UUID for identification
    content: string,              # Task description
    status: :pending | :in_progress | :completed
  }
  ```

  ## Injection Mechanism

  Memory injection creates a **snapshot** ChatEntry with `type: :memory`. This entry:
  - Is immutable once created (represents what agent saw at that moment)
  - Is hidden from UI display (filtered in templates)
  - Is excluded from compaction (never summarized/paraphrased)
  - Appears immediately after system prompt in LLM context

  The live `Track.memory` field is the source of truth. Injected snapshots are
  historical records showing what the agent saw at specific points.

  ## Compaction Integration

  When compaction is implemented:
  1. Filter out `type: :memory` ChatEntries from compaction input
  2. Summarize the conversation history normally
  3. Inject fresh `:memory` ChatEntry from current `Track.memory`

  This ensures memory is never paraphrased and agent always has accurate state.

  ## Tool API

  All memory tools return the **full memory state** after execution:
  - `read_memory` - Returns current memory
  - `update_memory` - Partial update of fields (objective, focus, working_notes, tasks)
  - `add_task` - Appends new task with generated UUID
  - `update_task` - Updates task by ID (content, status)
  - `remove_task` - Removes task by ID

  All tools have `require_approval: false` for immediate execution.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Msfailab.Tracks.ChatEntry
  alias Msfailab.Tracks.Memory.Task

  @type t :: %__MODULE__{
          objective: String.t() | nil,
          focus: String.t() | nil,
          tasks: [Task.t()],
          working_notes: String.t() | nil
        }

  @primary_key false
  embedded_schema do
    field :objective, :string
    field :focus, :string
    embeds_many :tasks, Task, on_replace: :delete
    field :working_notes, :string
  end

  @doc """
  Creates a new empty memory.
  """
  @spec new() :: t()
  def new do
    %__MODULE__{
      objective: nil,
      focus: nil,
      tasks: [],
      working_notes: nil
    }
  end

  @doc """
  Updates memory with the provided changes.

  Only provided fields are updated. When `tasks` is provided, it replaces
  the entire task list.

  ## Parameters

  - `memory` - Current memory state
  - `changes` - Map with optional keys: `:objective`, `:focus`, `:working_notes`, `:tasks`

  ## Examples

      iex> memory = Memory.new()
      iex> Memory.update(memory, %{objective: "New goal"})
      %Memory{objective: "New goal", ...}
  """
  @spec update(t(), map()) :: t()
  def update(%__MODULE__{} = memory, changes) when is_map(changes) do
    Enum.reduce(changes, memory, fn
      {:objective, value}, acc -> %{acc | objective: value}
      {:focus, value}, acc -> %{acc | focus: value}
      {:working_notes, value}, acc -> %{acc | working_notes: value}
      {:tasks, value}, acc -> %{acc | tasks: value}
      _, acc -> acc
    end)
  end

  @doc """
  Adds a new task to the memory.

  The task is appended to the list with a generated UUID and `:pending` status.
  """
  @spec add_task(t(), String.t()) :: t()
  def add_task(%__MODULE__{} = memory, content) when is_binary(content) do
    new_task = %Task{
      id: Ecto.UUID.generate(),
      content: content,
      status: :pending
    }

    %{memory | tasks: memory.tasks ++ [new_task]}
  end

  @doc """
  Updates an existing task by ID.

  ## Parameters

  - `memory` - Current memory state
  - `task_id` - UUID of the task to update
  - `changes` - Map with optional keys: `:content`, `:status`

  ## Returns

  - `{:ok, updated_memory}` - Task found and updated
  - `{:error, :task_not_found}` - No task with the given ID
  """
  @spec update_task(t(), String.t(), map()) :: {:ok, t()} | {:error, :task_not_found}
  def update_task(%__MODULE__{} = memory, task_id, changes) when is_binary(task_id) do
    case Enum.find_index(memory.tasks, &(&1.id == task_id)) do
      nil ->
        {:error, :task_not_found}

      index ->
        updated_tasks =
          List.update_at(memory.tasks, index, fn task ->
            task
            |> maybe_update_field(:content, changes)
            |> maybe_update_field(:status, changes)
          end)

        {:ok, %{memory | tasks: updated_tasks}}
    end
  end

  defp maybe_update_field(task, field, changes) do
    case Map.get(changes, field) do
      nil -> task
      value -> Map.put(task, field, value)
    end
  end

  @doc """
  Removes a task by ID.

  If the task ID is not found, returns the memory unchanged.
  """
  @spec remove_task(t(), String.t()) :: t()
  def remove_task(%__MODULE__{} = memory, task_id) when is_binary(task_id) do
    %{memory | tasks: Enum.reject(memory.tasks, &(&1.id == task_id))}
  end

  @doc """
  Serializes memory to markdown format for LLM injection.

  The format is designed to be clear and scannable:

  ```markdown
  ## Track Memory

  **Objective:** Gain domain admin access on ACME-DC01

  **Focus:** Enumerating SMB shares on 10.0.0.5

  ### Tasks
  - [x] Port scan 10.0.0.0/24
  - [ ] Check for null sessions ← in progress
  - [ ] Attempt AS-REP roasting

  ### Working Notes
  DC likely 10.0.0.5 based on reverse DNS lookup.
  ```
  """
  @spec serialize(t()) :: String.t()
  def serialize(%__MODULE__{} = memory) do
    parts = ["## Track Memory"]

    # Check if memory is empty
    if empty?(memory) do
      Enum.join(parts ++ ["\n*No memory set*"], "\n")
    else
      parts =
        if memory.objective, do: parts ++ ["\n**Objective:** #{memory.objective}"], else: parts

      parts = if memory.focus, do: parts ++ ["\n**Focus:** #{memory.focus}"], else: parts

      parts =
        if memory.tasks != [] do
          task_lines = Enum.map(memory.tasks, &format_task/1)
          parts ++ ["\n### Tasks"] ++ task_lines
        else
          parts
        end

      parts =
        if memory.working_notes do
          parts ++ ["\n### Working Notes", memory.working_notes]
        else
          parts
        end

      Enum.join(parts, "\n")
    end
  end

  defp empty?(%__MODULE__{objective: nil, focus: nil, tasks: [], working_notes: nil}), do: true
  defp empty?(%__MODULE__{}), do: false

  defp format_task(%Task{status: :completed, content: content}) do
    "- [x] #{content}"
  end

  defp format_task(%Task{status: :in_progress, content: content}) do
    "- [ ] #{content} ← in progress"
  end

  defp format_task(%Task{status: :pending, content: content}) do
    "- [ ] #{content}"
  end

  @doc """
  Converts memory to a map with string keys for JSON serialization.

  Used for tool responses that return the full memory state.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = memory) do
    %{
      "objective" => memory.objective,
      "focus" => memory.focus,
      "tasks" => Enum.map(memory.tasks, &Task.to_map/1),
      "working_notes" => memory.working_notes
    }
  end

  @doc """
  Changeset for embedding memory in a track.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(memory, attrs) do
    memory
    |> cast(attrs, [:objective, :focus, :working_notes])
    |> cast_embed(:tasks)
  end

  @doc """
  Creates a ChatEntry memory snapshot for injection into the conversation.

  The memory is serialized to markdown and wrapped in a ChatEntry with
  `entry_type: :memory`. This entry:

  - Appears as a user message to the LLM (role: :user)
  - Is hidden from UI display
  - Is excluded from compaction summarization

  ## Parameters

  - `memory` - The memory to serialize
  - `id` - Unique identifier for the entry
  - `position` - Position in the conversation timeline

  ## Returns

  A `ChatEntry` struct with the serialized memory content.
  """
  @spec inject(t(), String.t() | integer(), pos_integer()) :: ChatEntry.t()
  def inject(%__MODULE__{} = memory, id, position) do
    content = serialize(memory)
    ChatEntry.memory_snapshot(id, position, content)
  end
end
