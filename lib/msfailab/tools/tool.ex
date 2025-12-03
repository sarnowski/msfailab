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

defmodule Msfailab.Tools.Tool do
  @moduledoc """
  Struct representing a tool definition for LLM function calling.

  This struct defines the schema and execution characteristics of tools that
  AI agents can invoke during conversations. Tools are registered in
  `Msfailab.Tools` and passed to LLM providers during chat requests.

  ## Fields

  ### Required Fields

  | Field | Type | Description |
  |-------|------|-------------|
  | `name` | `String.t()` | Unique identifier for the tool (e.g., `"msf_command"`) |
  | `description` | `String.t()` | Human-readable description for the LLM |
  | `parameters` | `map()` | JSON Schema defining the tool's input parameters |

  ### Optional Fields

  | Field | Type | Default | Description |
  |-------|------|---------|-------------|
  | `strict` | `boolean()` | `false` | OpenAI: Enforce structured output matching schema |
  | `cacheable` | `boolean()` | `true` | Anthropic: Allow caching of tool definition |
  | `approval_required` | `boolean()` | `true` | Require user approval before execution |
  | `timeout` | `pos_integer() \\| nil` | `nil` | Max execution time in milliseconds |
  | `sequential` | `boolean()` | `false` | If true, only one instance can execute at a time |

  ## Sequential vs Parallel Execution

  The `sequential` flag controls how multiple tool invocations are executed:

  ```
  ┌─────────────────────────────────────────────────────────────────────┐
  │                     Tool Execution Modes                            │
  ├─────────────────────────────────────────────────────────────────────┤
  │                                                                     │
  │  Sequential (sequential: true)        Parallel (sequential: false)  │
  │  ─────────────────────────────        ────────────────────────────  │
  │                                                                     │
  │  Tool 1 ──────►                       Tool 1 ──────►                │
  │                Tool 2 ──────►         Tool 2 ──────►                │
  │                              Tool 3   Tool 3 ──────►                │
  │                                                                     │
  │  • One at a time                      • All at once                 │
  │  • Position order                     • Immediate execution         │
  │  • Wait for completion                • Parallel completion         │
  │                                                                     │
  └─────────────────────────────────────────────────────────────────────┘
  ```

  ### Sequential Tools

  Sequential tools (`sequential: true`) execute one at a time in position order.
  This is required for tools that:

  - Use a shared resource (e.g., Metasploit console is single-threaded)
  - Have side effects that affect subsequent calls
  - Require exclusive access to a system

  Example: `msf_command` is sequential because the Metasploit console can only
  process one command at a time.

  ### Parallel Tools (Future)

  Parallel tools (`sequential: false`) can execute simultaneously. Useful for:

  - Read-only operations
  - Independent API calls
  - File system queries

  The reconciliation engine in TrackServer handles the scheduling based on
  this flag. See `Msfailab.Tracks.TrackServer` for execution details.
  """

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          parameters: map(),
          strict: boolean(),
          cacheable: boolean(),
          approval_required: boolean(),
          timeout: pos_integer() | nil,
          sequential: boolean()
        }

  @enforce_keys [:name, :description, :parameters]
  defstruct [
    :name,
    :description,
    :parameters,
    :timeout,
    strict: false,
    cacheable: true,
    approval_required: true,
    sequential: false
  ]
end
