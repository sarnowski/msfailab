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

defmodule Msfailab.Tools do
  @moduledoc """
  Registry of tools available to AI agents.

  This module provides a static registry of tool definitions that can be passed
  to LLM providers. Each tool defines the interface for a capability that the
  AI can invoke during conversations.

  ## Available Tools

  | Tool | Mutex | Description |
  |------|-------|-------------|
  | `execute_msfconsole_command` | `:msf_console` | Execute Metasploit Framework console commands |
  | `execute_bash_command` | `nil` | Execute bash commands in the research environment |
  | Memory tools | `:memory` | Agent memory operations (read, update, tasks) |
  | MSF data tools | `nil` | Database queries (list_*, retrieve_*, create_*) |

  ## Tool Definition Structure

  Tools are defined using the `Msfailab.Tools.Tool` struct with the following fields:

  ### Required Fields

  | Field | Type | Description |
  |-------|------|-------------|
  | `name` | `String.t()` | Unique identifier for the tool (e.g., `"execute_msfconsole_command"`) |
  | `description` | `String.t()` | Human-readable description explaining what the tool does |
  | `parameters` | `map()` | JSON Schema defining the tool's input parameters |

  ### Optional Fields

  | Field | Type | Default | Description |
  |-------|------|---------|-------------|
  | `strict` | `boolean()` | `false` | OpenAI: Enforce structured output matching schema |
  | `cacheable` | `boolean()` | `true` | Anthropic: Allow caching of tool definition |
  | `approval_required` | `boolean()` | `true` | Require user approval before execution |
  | `timeout` | `pos_integer() \\| nil` | `nil` | Max execution time in milliseconds |
  | `mutex` | `atom() \\| nil` | `nil` | Mutex group for execution ordering |

  ## Mutex-Based Execution

  The `mutex` field controls execution ordering when the LLM requests
  multiple tool calls in a single response:

  - **Mutex groups** (e.g., `mutex: :msf_console`): Tools with the same mutex
    execute sequentially in LLM-specified order. Required for `execute_msfconsole_command`
    because the Metasploit console is single-threaded.

  - **Parallel tools** (`mutex: nil`): Execute truly in parallel. Useful for
    read-only database queries or independent operations.

  See `Msfailab.Tools.Tool` for detailed documentation on mutex groups and
  `Msfailab.Tools.ExecutionManager` for execution orchestration.

  ## Parameters JSON Schema

  The `parameters` field uses standard JSON Schema format:

      %{
        "type" => "object",
        "properties" => %{
          "command" => %{
            "type" => "string",
            "description" => "The command to execute"
          },
          "timeout" => %{
            "type" => "integer",
            "description" => "Timeout in seconds",
            "default" => 30
          }
        },
        "required" => ["command"]
      }

  ### Supported JSON Schema Types

  - `"string"` - Text values (with optional `enum` for fixed choices)
  - `"integer"` - Whole numbers
  - `"number"` - Decimal numbers
  - `"boolean"` - true/false values
  - `"array"` - Lists (with `items` defining element type)
  - `"object"` - Nested structures (with `properties`)

  ## Provider Transformation

  Each LLM provider transforms tool definitions to their native format:

  ### Anthropic
  ```json
  {
    "name": "execute_msfconsole_command",
    "description": "Execute a Metasploit command",
    "input_schema": { ... },
    "cache_control": {"type": "ephemeral"}
  }
  ```

  ### OpenAI / Ollama
  ```json
  {
    "type": "function",
    "function": {
      "name": "execute_msfconsole_command",
      "description": "Execute a Metasploit command",
      "parameters": { ... },
      "strict": true
    }
  }
  ```

  ## Usage

      # Get all available tools
      tools = Msfailab.Tools.list_tools()

      # Pass to LLM chat request
      request = %ChatRequest{
        model: "claude-sonnet-4-5-20250514",
        messages: messages,
        tools: tools
      }

      {:ok, ref} = Msfailab.LLM.chat(request)

  ## Internal Fields

  The `approval_required`, `timeout`, and `mutex` fields are not sent to
  LLM providers. They are used by TrackServer and ExecutionManager to:

  - Prompt users for confirmation before executing dangerous tools
  - Set appropriate timeouts for tool execution
  - Schedule mutex-based sequential vs parallel tool execution
  """

  alias Msfailab.Tools.Tool

  @tools [
    %Tool{
      name: "execute_msfconsole_command",
      short_title: "Executing Metasploit command",
      description:
        "Execute a command in the Metasploit Framework console. " <>
          "Use this to interact with MSF for security research tasks like searching for " <>
          "modules, configuring exploits, running scans, and managing sessions.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "command" => %{
            "type" => "string",
            "description" =>
              "The Metasploit console command to execute (e.g., 'search type:exploit platform:windows', 'use exploit/multi/handler', 'set LHOST 10.0.0.1')"
          }
        },
        "required" => ["command"],
        "additionalProperties" => false
      },
      strict: true,
      cacheable: true,
      approval_required: true,
      timeout: 60_000,
      mutex: :msf_console,
      # Custom rendering - execute_msfconsole_command has its own terminal-style display
      render_collapsed: &MsfailabWeb.WorkspaceComponents.render_msf_command_collapsed/1,
      render_expanded: &MsfailabWeb.WorkspaceComponents.render_msf_command_expanded/1,
      render_approval_subject:
        &MsfailabWeb.WorkspaceComponents.render_msf_command_approval_subject/1
    },
    %Tool{
      name: "execute_bash_command",
      short_title: "Executing Bash command",
      description:
        "Execute a bash command in the research environment. " <>
          "Use this for file operations, network reconnaissance tools (nmap, curl, dig), " <>
          "payload generation (msfvenom), custom scripts, and interacting with captured data.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "command" => %{
            "type" => "string",
            "description" =>
              "The bash command to execute (e.g., 'nmap -sV 10.0.0.1', 'ls -la', 'curl http://target')"
          }
        },
        "required" => ["command"],
        "additionalProperties" => false
      },
      strict: true,
      cacheable: true,
      approval_required: true,
      timeout: 120_000,
      # Custom rendering - execute_bash_command has its own terminal-style display
      render_collapsed: &MsfailabWeb.WorkspaceComponents.render_bash_command_collapsed/1,
      render_expanded: &MsfailabWeb.WorkspaceComponents.render_bash_command_expanded/1,
      render_approval_subject:
        &MsfailabWeb.WorkspaceComponents.render_bash_command_approval_subject/1
    },
    # Database query tools - these don't require approval as they're read-only
    %Tool{
      name: "list_hosts",
      short_title: "Listing hosts",
      description:
        "Query discovered hosts from the Metasploit database. " <>
          "Returns host details including OS, architecture, and finding counts.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "address" => %{
            "type" => "string",
            "description" => "Filter by IP address (exact match)"
          },
          "os" => %{
            "type" => "string",
            "description" => "Filter by OS name (case-insensitive partial match)"
          },
          "state" => %{
            "type" => "string",
            "enum" => ["alive", "down", "unknown"],
            "description" => "Filter by host state"
          },
          "search" => %{
            "type" => "string",
            "description" => "Search in hostname, comments, and info"
          },
          "limit" => %{
            "type" => "integer",
            "description" => "Maximum results (default: 50, max: 200)"
          }
        },
        "required" => [],
        "additionalProperties" => false
      },
      strict: false,
      cacheable: true,
      approval_required: false,
      timeout: 30_000
    },
    %Tool{
      name: "list_services",
      short_title: "Listing services",
      description:
        "Query discovered services from the Metasploit database. " <>
          "Returns service details with host information.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "host" => %{
            "type" => "string",
            "description" => "Filter by host IP address"
          },
          "port" => %{
            "type" => "integer",
            "description" => "Filter by port number"
          },
          "proto" => %{
            "type" => "string",
            "enum" => ["tcp", "udp"],
            "description" => "Filter by protocol"
          },
          "state" => %{
            "type" => "string",
            "enum" => ["open", "closed", "filtered", "unknown"],
            "description" => "Filter by state"
          },
          "name" => %{
            "type" => "string",
            "description" => "Filter by service name (e.g., 'http', 'ssh')"
          },
          "search" => %{
            "type" => "string",
            "description" => "Search in service info/banner"
          },
          "limit" => %{
            "type" => "integer",
            "description" => "Maximum results (default: 50, max: 200)"
          }
        },
        "required" => [],
        "additionalProperties" => false
      },
      strict: false,
      cacheable: true,
      approval_required: false,
      timeout: 30_000
    },
    %Tool{
      name: "list_vulns",
      short_title: "Listing vulnerabilities",
      description:
        "Query discovered vulnerabilities from the Metasploit database. " <>
          "Returns vulnerability details with host, service, and references (CVE, MSB, EDB, etc.) always included.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "host" => %{
            "type" => "string",
            "description" => "Filter by host IP address"
          },
          "service_port" => %{
            "type" => "integer",
            "description" => "Filter by service port"
          },
          "name" => %{
            "type" => "string",
            "description" => "Filter by vulnerability/module name (partial match)"
          },
          "search" => %{
            "type" => "string",
            "description" => "Search in name and info"
          },
          "exploited" => %{
            "type" => "boolean",
            "description" => "Filter by exploitation status"
          },
          "limit" => %{
            "type" => "integer",
            "description" => "Maximum results (default: 50, max: 200)"
          }
        },
        "required" => [],
        "additionalProperties" => false
      },
      strict: false,
      cacheable: true,
      approval_required: false,
      timeout: 30_000
    },
    %Tool{
      name: "list_creds",
      short_title: "Listing credentials",
      description:
        "Query discovered credentials from the Metasploit database. " <>
          "Returns credential details with host and service information.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "host" => %{
            "type" => "string",
            "description" => "Filter by host IP address"
          },
          "service_port" => %{
            "type" => "integer",
            "description" => "Filter by service port"
          },
          "service_name" => %{
            "type" => "string",
            "description" => "Filter by service name (e.g., 'ssh', 'smb')"
          },
          "user" => %{
            "type" => "string",
            "description" => "Filter by username (partial match)"
          },
          "ptype" => %{
            "type" => "string",
            "description" => "Filter by credential type (e.g., 'password', 'hash')"
          },
          "limit" => %{
            "type" => "integer",
            "description" => "Maximum results (default: 50, max: 200)"
          }
        },
        "required" => [],
        "additionalProperties" => false
      },
      strict: false,
      cacheable: true,
      approval_required: false,
      timeout: 30_000
    },
    %Tool{
      name: "list_loots",
      short_title: "Listing loot",
      description:
        "Query captured loot/artifacts from the Metasploit database. " <>
          "Returns loot metadata (use retrieve_loot for contents).",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "host" => %{
            "type" => "string",
            "description" => "Filter by host IP address"
          },
          "ltype" => %{
            "type" => "string",
            "description" => "Filter by loot type (e.g., 'windows.hashes')"
          },
          "search" => %{
            "type" => "string",
            "description" => "Search in loot name and info"
          },
          "limit" => %{
            "type" => "integer",
            "description" => "Maximum results (default: 50, max: 200)"
          }
        },
        "required" => [],
        "additionalProperties" => false
      },
      strict: false,
      cacheable: true,
      approval_required: false,
      timeout: 30_000
    },
    %Tool{
      name: "list_notes",
      short_title: "Listing notes",
      description:
        "Query notes/annotations from the Metasploit database. " <>
          "Returns notes with associated host, service, or vulnerability information.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "host" => %{
            "type" => "string",
            "description" => "Filter by host IP address"
          },
          "ntype" => %{
            "type" => "string",
            "description" => "Filter by note type (e.g., 'agent.observation')"
          },
          "critical" => %{
            "type" => "boolean",
            "description" => "Filter by critical flag"
          },
          "search" => %{
            "type" => "string",
            "description" => "Search in note data content"
          },
          "limit" => %{
            "type" => "integer",
            "description" => "Maximum results (default: 50, max: 200)"
          }
        },
        "required" => [],
        "additionalProperties" => false
      },
      strict: false,
      cacheable: true,
      approval_required: false,
      timeout: 30_000
    },
    %Tool{
      name: "list_sessions",
      short_title: "Listing sessions",
      description:
        "Query session history from the Metasploit database. " <>
          "Returns session details including exploit used and status.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "host" => %{
            "type" => "string",
            "description" => "Filter by host IP address"
          },
          "stype" => %{
            "type" => "string",
            "description" => "Filter by session type (e.g., 'meterpreter', 'shell')"
          },
          "active" => %{
            "type" => "boolean",
            "description" => "Filter by active status (true = currently open)"
          },
          "limit" => %{
            "type" => "integer",
            "description" => "Maximum results (default: 50, max: 200)"
          }
        },
        "required" => [],
        "additionalProperties" => false
      },
      strict: false,
      cacheable: true,
      approval_required: false,
      timeout: 30_000
    },
    %Tool{
      name: "retrieve_loot",
      short_title: "Retrieving loot",
      description:
        "Retrieve the contents of a captured loot file. " <>
          "Use list_loots first to find entries, then retrieve specific contents.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "loot_id" => %{
            "type" => "integer",
            "description" => "The loot ID from list_loots results"
          },
          "max_size" => %{
            "type" => "integer",
            "description" => "Maximum bytes to return (default: 10000, max: 100000)"
          }
        },
        "required" => ["loot_id"],
        "additionalProperties" => false
      },
      strict: false,
      cacheable: true,
      approval_required: false,
      timeout: 10_000
    },
    %Tool{
      name: "read_note",
      short_title: "Reading note",
      description:
        "Read the full details of a specific note from the Metasploit database. " <>
          "Returns complete note data including host/service associations. " <>
          "If the note contains serialized Ruby Marshal data (e.g., host.last_boot), " <>
          "the system will automatically attempt to deserialize it when a container is running.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "note_id" => %{
            "type" => "integer",
            "description" => "The note ID from list_notes results"
          }
        },
        "required" => ["note_id"],
        "additionalProperties" => false
      },
      strict: true,
      cacheable: true,
      approval_required: false,
      timeout: 10_000
    },
    %Tool{
      name: "create_note",
      short_title: "Creating note",
      description:
        "Create a research note in the Metasploit database. Notes can be attached to hosts, services, or stand alone.\n\n" <>
          "Standard note types:\n" <>
          "- agent.observation: General findings and observations\n" <>
          "- agent.hypothesis: Suspected vulnerabilities or attack paths\n" <>
          "- agent.summary: Session or scan summaries\n" <>
          "- agent.failed_attempt: Documentation of failed exploits\n" <>
          "- agent.recommendation: Suggested next steps\n" <>
          "- agent.finding: Confirmed security findings\n\n" <>
          "Custom types allowed if prefixed with 'agent.'",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "ntype" => %{
            "type" => "string",
            "description" => "Note type (must start with 'agent.')"
          },
          "content" => %{
            "type" => "string",
            "description" => "Note content text"
          },
          "host" => %{
            "type" => "string",
            "description" => "Host IP address to attach note to (optional)"
          },
          "service_port" => %{
            "type" => "integer",
            "description" => "Service port to attach note to (requires host)"
          },
          "critical" => %{
            "type" => "boolean",
            "description" => "Mark as critical finding (default: false)"
          }
        },
        "required" => ["ntype", "content"],
        "additionalProperties" => false
      },
      strict: false,
      cacheable: true,
      approval_required: false,
      timeout: 10_000
    },
    # =========================================================================
    # Memory Tools - Agent short-term memory for maintaining context
    # =========================================================================
    %Tool{
      name: "read_memory",
      short_title: "Reading memory",
      description:
        "Read the current track memory state. Returns the agent's stored objective, focus, tasks, and working notes. " <>
          "Use this to recall your current state after context compaction.",
      parameters: %{
        "type" => "object",
        "properties" => %{},
        "required" => [],
        "additionalProperties" => false
      },
      strict: true,
      cacheable: true,
      approval_required: false,
      timeout: 5_000,
      mutex: :memory
    },
    %Tool{
      name: "update_memory",
      short_title: "Updating memory",
      description:
        "Update track memory fields. Only provided fields are updated; others are preserved. " <>
          "Use 'objective' for your ultimate goal (rarely changes), 'focus' for current activity, " <>
          "and 'working_notes' for temporary observations and hypotheses.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "objective" => %{
            "type" => "string",
            "description" =>
              "The ultimate goal you're working toward (e.g., 'Gain domain admin access on ACME-DC01')"
          },
          "focus" => %{
            "type" => "string",
            "description" =>
              "What you're doing right now (e.g., 'Enumerating SMB shares on 10.0.0.5')"
          },
          "working_notes" => %{
            "type" => "string",
            "description" => "Temporary observations, hypotheses, blockers (markdown supported)"
          }
        },
        "required" => [],
        "additionalProperties" => false
      },
      strict: false,
      cacheable: true,
      approval_required: false,
      timeout: 5_000,
      mutex: :memory
    },
    %Tool{
      name: "add_task",
      short_title: "Adding task",
      description:
        "Add a new task to the memory task list. Tasks track planned work items with status. " <>
          "New tasks start with 'pending' status.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "content" => %{
            "type" => "string",
            "description" => "Task description (e.g., 'Port scan 10.0.0.0/24')"
          }
        },
        "required" => ["content"],
        "additionalProperties" => false
      },
      strict: true,
      cacheable: true,
      approval_required: false,
      timeout: 5_000,
      mutex: :memory
    },
    %Tool{
      name: "update_task",
      short_title: "Updating task",
      description:
        "Update an existing task in the memory task list. Use to change status or content.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "id" => %{
            "type" => "string",
            "description" => "Task ID (UUID from add_task or read_memory)"
          },
          "content" => %{
            "type" => "string",
            "description" => "New task description"
          },
          "status" => %{
            "type" => "string",
            "enum" => ["pending", "in_progress", "completed"],
            "description" => "New task status"
          }
        },
        "required" => ["id"],
        "additionalProperties" => false
      },
      strict: false,
      cacheable: true,
      approval_required: false,
      timeout: 5_000,
      mutex: :memory
    },
    %Tool{
      name: "remove_task",
      short_title: "Removing task",
      description:
        "Remove a task from the memory task list. Use when a task is no longer relevant.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "id" => %{
            "type" => "string",
            "description" => "Task ID (UUID from add_task or read_memory)"
          }
        },
        "required" => ["id"],
        "additionalProperties" => false
      },
      strict: true,
      cacheable: true,
      approval_required: false,
      timeout: 5_000,
      mutex: :memory
    }
  ]

  @doc """
  Returns all available tool definitions.

  ## Example

      iex> tools = Msfailab.Tools.list_tools()
      iex> length(tools)
      17
      iex> Enum.map(tools, & &1.name) |> Enum.sort()
      ["add_task", "create_note", "execute_bash_command", "execute_msfconsole_command", "list_creds", "list_hosts", "list_loots", "list_notes", "list_services", "list_sessions", "list_vulns", "read_memory", "read_note", "remove_task", "retrieve_loot", "update_memory", "update_task"]
  """
  @spec list_tools() :: [Tool.t()]
  def list_tools, do: @tools

  @doc """
  Returns a tool by name.

  ## Example

      iex> {:ok, tool} = Msfailab.Tools.get_tool("execute_msfconsole_command")
      iex> tool.name
      "execute_msfconsole_command"
      iex> tool.mutex
      :msf_console

      iex> Msfailab.Tools.get_tool("nonexistent")
      {:error, :not_found}
  """
  @spec get_tool(String.t()) :: {:ok, Tool.t()} | {:error, :not_found}
  def get_tool(name) when is_binary(name) do
    case Enum.find(@tools, &(&1.name == name)) do
      nil -> {:error, :not_found}
      tool -> {:ok, tool}
    end
  end
end
