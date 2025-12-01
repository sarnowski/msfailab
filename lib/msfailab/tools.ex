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

  | Tool | Description | Sequential |
  |------|-------------|------------|
  | `msf_command` | Execute Metasploit Framework console commands | Yes |
  | `bash_command` | Execute bash commands in the research environment | No |

  ## Tool Definition Structure

  Tools are defined using the `Msfailab.Tools.Tool` struct with the following fields:

  ### Required Fields

  | Field | Type | Description |
  |-------|------|-------------|
  | `name` | `String.t()` | Unique identifier for the tool (e.g., `"msf_command"`) |
  | `description` | `String.t()` | Human-readable description explaining what the tool does |
  | `parameters` | `map()` | JSON Schema defining the tool's input parameters |

  ### Optional Fields

  | Field | Type | Default | Description |
  |-------|------|---------|-------------|
  | `strict` | `boolean()` | `false` | OpenAI: Enforce structured output matching schema |
  | `cacheable` | `boolean()` | `true` | Anthropic: Allow caching of tool definition |
  | `approval_required` | `boolean()` | `false` | Require user approval before execution |
  | `timeout` | `pos_integer() \\| nil` | `nil` | Max execution time in milliseconds |
  | `sequential` | `boolean()` | `false` | If true, only one can execute at a time |

  ## Sequential Execution

  The `sequential` flag controls execution ordering when the LLM requests
  multiple tool calls in a single response:

  - **Sequential tools** (`sequential: true`): Execute one at a time in
    position order. Required for `msf_command` because the Metasploit
    console is single-threaded and can only process one command at a time.

  - **Parallel tools** (`sequential: false`): Can execute simultaneously.
    Useful for read-only operations or independent API calls.

  See `Msfailab.Tools.Tool` for detailed documentation on execution modes.

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
    "name": "msf_command",
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
      "name": "msf_command",
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

  The `approval_required`, `timeout`, and `sequential` fields are not sent to
  LLM providers. They are used by TrackServer to:

  - Prompt users for confirmation before executing dangerous tools
  - Set appropriate timeouts for tool execution
  - Schedule sequential vs parallel tool execution
  """

  alias Msfailab.Tools.Tool

  @tools [
    %Tool{
      name: "msf_command",
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
      approval_required: false,
      timeout: 60_000,
      sequential: true
    },
    %Tool{
      name: "bash_command",
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
      approval_required: false,
      timeout: 120_000,
      sequential: false
    }
  ]

  @doc """
  Returns all available tool definitions.

  ## Example

      iex> tools = Msfailab.Tools.list_tools()
      iex> length(tools)
      2
      iex> Enum.map(tools, & &1.name) |> Enum.sort()
      ["bash_command", "msf_command"]
  """
  @spec list_tools() :: [Tool.t()]
  def list_tools, do: @tools

  @doc """
  Returns a tool by name.

  ## Example

      iex> {:ok, tool} = Msfailab.Tools.get_tool("msf_command")
      iex> tool.name
      "msf_command"
      iex> tool.sequential
      true

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
