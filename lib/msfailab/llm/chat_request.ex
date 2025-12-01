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

defmodule Msfailab.LLM.ChatRequest do
  @moduledoc """
  Request parameters for initiating an LLM chat.

  This struct encapsulates all the information needed to make a streaming
  chat request to any supported LLM provider. The provider is determined
  automatically based on the model name.

  ## Required Fields

  - `model` - The model identifier (e.g., "claude-sonnet-4-5-20250514", "gpt-4o")
  - `messages` - List of `Msfailab.LLM.Message` structs representing the conversation

  ## Optional Fields

  - `system_prompt` - System instructions for the model's behavior
  - `tools` - List of tool definitions the model can invoke
  - `cache_context` - Provider-specific cache data from a previous response
  - `max_tokens` - Maximum tokens to generate (default: 8192)
  - `temperature` - Sampling temperature 0.0-2.0 (default: 0.1 for reliable tool use)

  ## Tool Definitions

  Tools are defined using JSON Schema format:

      %{
        name: "msf_command",
        description: "Execute a command in the Metasploit console",
        parameters: %{
          type: "object",
          properties: %{
            command: %{
              type: "string",
              description: "The MSF command to execute"
            }
          },
          required: ["command"]
        }
      }

  ## Cache Context

  The `cache_context` field is opaque and provider-specific:

  | Provider  | Contents                          | Usage                                    |
  |-----------|-----------------------------------|------------------------------------------|
  | Ollama    | `%{context: [integer()]}`         | Token IDs for context continuation       |
  | Anthropic | `nil`                             | Cache control via message structure      |
  | OpenAI    | `nil`                             | Automatic prefix caching                 |

  Pass the `cache_context` from a `StreamComplete` event back into the next
  request to enable provider-specific caching optimizations.

  ## Example

      %ChatRequest{
        model: "claude-sonnet-4-5-20250514",
        messages: [
          Message.user("Search for Windows exploits"),
        ],
        system_prompt: "You are a security research assistant...",
        tools: [msf_command_tool(), bash_command_tool()],
        max_tokens: 8192,
        temperature: 0.1
      }
  """

  alias Msfailab.LLM.Message
  alias Msfailab.Tools.Tool

  @type tool_definition :: %{
          name: String.t(),
          description: String.t(),
          parameters: map()
        }

  @type t :: %__MODULE__{
          model: String.t(),
          messages: [Message.t()],
          system_prompt: String.t() | nil,
          tools: [Tool.t()] | [tool_definition()] | nil,
          cache_context: term() | nil,
          max_tokens: pos_integer(),
          temperature: float()
        }

  @default_max_tokens 8192
  @default_temperature 0.1

  @enforce_keys [:model, :messages]
  defstruct [
    :model,
    :messages,
    :system_prompt,
    :tools,
    :cache_context,
    max_tokens: @default_max_tokens,
    temperature: @default_temperature
  ]

  @doc """
  Creates a new chat request with the given model and messages.

  ## Example

      iex> ChatRequest.new("gpt-4o", [Message.user("Hello")])
      %ChatRequest{model: "gpt-4o", messages: [...], max_tokens: 8192, temperature: 0.1}
  """
  @spec new(String.t(), [Message.t()], keyword()) :: t()
  def new(model, messages, opts \\ []) when is_binary(model) and is_list(messages) do
    %__MODULE__{
      model: model,
      messages: messages,
      system_prompt: Keyword.get(opts, :system_prompt),
      tools: Keyword.get(opts, :tools),
      cache_context: Keyword.get(opts, :cache_context),
      max_tokens: Keyword.get(opts, :max_tokens, @default_max_tokens),
      temperature: Keyword.get(opts, :temperature, @default_temperature)
    }
  end
end
