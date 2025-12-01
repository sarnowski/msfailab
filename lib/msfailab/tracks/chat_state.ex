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

defmodule Msfailab.Tracks.ChatState do
  @moduledoc """
  Complete chat state returned by `Tracks.get_chat_state/1`.

  This struct represents the full chat state that LiveView fetches from
  TrackServer when it receives a `ChatStateUpdated` event. It follows the
  self-healing pattern where the UI always receives complete state rather
  than incremental updates.

  ## Design Rationale

  Following the established pattern for console state (TrackStateUpdated),
  the chat state uses a simple "state changed" notification. When LiveView
  receives the notification, it fetches this complete state struct and
  re-renders. This approach:

  - Keeps LiveView logic simple (no delta accumulation)
  - Ensures UI always has consistent state
  - Handles missed events gracefully

  ## Fields

  - `entries` - Ordered list of `ChatEntry` structs (oldest first)
  - `turn_status` - Current turn status (`:idle`, `:streaming`, or `:error`)
  - `current_turn_id` - ID of the current turn (nil when idle)

  ## Turn Status State Machine

  A turn progresses through these statuses:

  ```
                      ┌────────────────────────────────────────────┐
                      │                                            │
                      ▼                                            │
      idle ──► pending ──► streaming ──► pending_approval ──► executing_tools
                                │               │                  │
                                │               │ (all approved    │
                                │               │  + executed)     │
                                │               └──────────────────┤
                                │                                  │
                                ▼                                  │
                           (no tools)                              │
                                │                                  │
                                ▼                                  ▼
                            finished ◄─────────────────────────────┘
                                │
                            (user prompt)
                                │
                                ▼
                            pending (new turn)
  ```

  | Status | Description | Exit Conditions |
  |--------|-------------|-----------------|
  | `:idle` | No active turn | User sends prompt |
  | `:pending` | LLM request sent, awaiting response | StreamStarted received |
  | `:streaming` | LLM generating response | StreamComplete received |
  | `:pending_approval` | Tools awaiting user approval | All tools approved/denied |
  | `:executing_tools` | Tools running | All tools terminal |
  | `:finished` | Turn complete | User sends new prompt |
  | `:error` | Turn failed with an error | User sends new prompt |

  ## Example

      %ChatState{
        entries: [
          %ChatEntry{role: :user, message_type: :prompt, content: "Hello", ...},
          %ChatEntry{role: :assistant, message_type: :response, content: "Hi!", ...}
        ],
        turn_status: :idle,
        current_turn_id: nil
      }
  """

  alias Msfailab.Tracks.ChatEntry

  @type turn_status ::
          :idle
          | :pending
          | :streaming
          | :pending_approval
          | :executing_tools
          | :finished
          | :error

  @type t :: %__MODULE__{
          entries: [ChatEntry.t()],
          turn_status: turn_status(),
          current_turn_id: String.t() | nil
        }

  @enforce_keys [:entries, :turn_status]
  defstruct entries: [], turn_status: :idle, current_turn_id: nil

  @doc """
  Creates a new ChatState with the given entries and status.

  ## Example

      iex> ChatState.new([entry1, entry2], :idle)
      %ChatState{entries: [entry1, entry2], turn_status: :idle, current_turn_id: nil}
  """
  @spec new([ChatEntry.t()], turn_status(), String.t() | nil) :: t()
  def new(entries, turn_status, current_turn_id \\ nil)
      when is_list(entries) and
             turn_status in [
               :idle,
               :pending,
               :streaming,
               :pending_approval,
               :executing_tools,
               :finished,
               :error
             ] do
    %__MODULE__{
      entries: entries,
      turn_status: turn_status,
      current_turn_id: current_turn_id
    }
  end

  @doc """
  Creates an empty ChatState in idle status.

  ## Example

      iex> ChatState.empty()
      %ChatState{entries: [], turn_status: :idle, current_turn_id: nil}
  """
  @spec empty() :: t()
  def empty do
    %__MODULE__{entries: [], turn_status: :idle, current_turn_id: nil}
  end

  @doc """
  Returns whether the given turn status indicates the chat is busy.

  The chat is busy when it's actively processing a turn and should not
  accept new user prompts. This includes:
  - `:pending` - Waiting for LLM to start responding
  - `:streaming` - LLM is generating a response
  - `:pending_approval` - Tools are awaiting user approval
  - `:executing_tools` - Tools are running

  The chat can accept new prompts when:
  - `:idle` - No active turn
  - `:finished` - Previous turn completed
  - `:error` - Previous turn failed (user can retry)

  ## Examples

      iex> ChatState.busy?(:streaming)
      true

      iex> ChatState.busy?(:idle)
      false

      iex> ChatState.busy?(:finished)
      false
  """
  @spec busy?(turn_status()) :: boolean()
  def busy?(turn_status)
      when turn_status in [:pending, :streaming, :pending_approval, :executing_tools],
      do: true

  def busy?(_turn_status), do: false
end
