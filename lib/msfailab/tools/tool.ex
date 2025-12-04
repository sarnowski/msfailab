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

# coveralls-ignore-start
# Reason: Pure struct definition, no executable code
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
  | `name` | `String.t()` | Unique identifier for the tool (e.g., `"execute_msfconsole_command"`) |
  | `description` | `String.t()` | Human-readable description for the LLM |
  | `parameters` | `map()` | JSON Schema defining the tool's input parameters |
  | `short_title` | `String.t()` | Human-readable short title for UI display (e.g., `"Running MSF command"`) |

  ### Optional Fields

  | Field | Type | Default | Description |
  |-------|------|---------|-------------|
  | `strict` | `boolean()` | `false` | OpenAI: Enforce structured output matching schema |
  | `cacheable` | `boolean()` | `true` | Anthropic: Allow caching of tool definition |
  | `approval_required` | `boolean()` | `true` | Require user approval before execution |
  | `timeout` | `pos_integer() \\| nil` | `nil` | Max execution time in milliseconds |
  | `mutex` | `atom() \\| nil` | `nil` | Mutex group - tools with same mutex execute sequentially |

  ### UI Rendering Fields (Optional)

  | Field | Type | Default | Description |
  |-------|------|---------|-------------|
  | `render_collapsed` | `function \\| nil` | `nil` | Custom renderer for collapsed tool box |
  | `render_expanded` | `function \\| nil` | `nil` | Custom renderer for expanded tool box |
  | `render_approval_subject` | `function \\| nil` | `nil` | Custom renderer for approval prompt (REQUIRED if approval_required) |

  ## Mutex-Based Execution Grouping

  The `mutex` field controls how multiple tool invocations are executed:

  ```
  ┌─────────────────────────────────────────────────────────────────────┐
  │                     Tool Execution with Mutex Groups                │
  ├─────────────────────────────────────────────────────────────────────┤
  │                                                                     │
  │  mutex: :msf_console           mutex: nil (true parallel)           │
  │  ────────────────────          ────────────────────────────         │
  │                                                                     │
  │  cmd1 ──────►                  list_hosts ──────►                   │
  │              cmd2 ──────►      list_services ──────►                │
  │                       cmd3     bash_command ──────►                 │
  │                                                                     │
  │  • Sequential within group     • True parallel execution            │
  │  • LLM-specified order         • Independent Tasks                  │
  │  • Shared resource access      • No blocking                        │
  │                                                                     │
  └─────────────────────────────────────────────────────────────────────┘
  ```

  ### Mutex Groups

  Tools with the same `mutex` value execute sequentially in LLM-specified order.
  Tools with `mutex: nil` execute truly in parallel.

  | Mutex | Tools | Rationale |
  |-------|-------|-----------|
  | `:msf_console` | `execute_msfconsole_command` | Metasploit console is single-threaded |
  | `:memory` | `read_memory`, `update_memory`, `add_task`, `update_task`, `remove_task` | Must accumulate changes sequentially |
  | `nil` | `execute_bash_command`, `list_*`, `retrieve_loot`, `create_note` | True parallel execution |

  The ExecutionManager handles the scheduling based on mutex groups.
  See `Msfailab.Tools.ExecutionManager` for execution details.
  """

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          parameters: map(),
          short_title: String.t(),
          strict: boolean(),
          cacheable: boolean(),
          approval_required: boolean(),
          timeout: pos_integer() | nil,
          mutex: atom() | nil,
          render_collapsed: (map() -> Phoenix.LiveView.Rendered.t()) | nil,
          render_expanded: (map() -> Phoenix.LiveView.Rendered.t()) | nil,
          render_approval_subject: (map() -> Phoenix.LiveView.Rendered.t()) | nil
        }

  @enforce_keys [:name, :description, :parameters, :short_title]
  defstruct [
    :name,
    :description,
    :parameters,
    :short_title,
    :timeout,
    :mutex,
    :render_collapsed,
    :render_expanded,
    :render_approval_subject,
    strict: false,
    cacheable: true,
    approval_required: true
  ]
end

# coveralls-ignore-stop
