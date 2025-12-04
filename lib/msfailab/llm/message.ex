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

defmodule Msfailab.LLM.Message do
  @moduledoc """
  Normalized message format for LLM requests.

  This struct represents a single message in a conversation, using a provider-agnostic
  format. Provider modules are responsible for transforming these messages into
  vendor-specific formats before making API calls.

  ## Structure

  Each message has a `role` and a list of `content` blocks. Content blocks allow
  mixed content within a single message (e.g., text followed by tool calls).

  ## Roles

  - `:user` - Messages from the human user (prompts, context injections)
  - `:assistant` - Messages from the AI assistant (responses, tool calls)
  - `:tool` - Tool execution results

  ## Content Block Types

  ### Text Block
  Simple text content:

      %{type: :text, text: "Hello, how can I help?"}

  ### Tool Call Block
  A tool invocation requested by the assistant:

      %{
        type: :tool_call,
        id: "call_abc123",
        name: "execute_msfconsole_command",
        arguments: %{"command" => "search type:exploit platform:windows"}
      }

  ### Tool Result Block
  The result of executing a tool:

      %{
        type: :tool_result,
        tool_call_id: "call_abc123",
        content: "Found 42 matching modules...",
        is_error: false
      }

  ## Examples

  User message:

      %Message{
        role: :user,
        content: [%{type: :text, text: "What exploits are available for Windows?"}]
      }

  Assistant response with tool call:

      %Message{
        role: :assistant,
        content: [
          %{type: :text, text: "Let me search for Windows exploits."},
          %{type: :tool_call, id: "call_1", name: "execute_msfconsole_command", arguments: %{"command" => "search"}}
        ]
      }

  Tool result:

      %Message{
        role: :tool,
        content: [
          %{type: :tool_result, tool_call_id: "call_1", content: "Results...", is_error: false}
        ]
      }
  """

  @type role :: :user | :assistant | :tool

  @type text_block :: %{
          type: :text,
          text: String.t()
        }

  @type tool_call_block :: %{
          type: :tool_call,
          id: String.t(),
          name: String.t(),
          arguments: map()
        }

  @type tool_result_block :: %{
          type: :tool_result,
          tool_call_id: String.t(),
          content: String.t(),
          is_error: boolean()
        }

  @type content_block :: text_block() | tool_call_block() | tool_result_block()

  @type t :: %__MODULE__{
          role: role(),
          content: [content_block()]
        }

  @enforce_keys [:role]
  defstruct [:role, content: []]

  @doc """
  Creates a user message with text content.

  ## Example

      iex> Message.user("Hello!")
      %Message{role: :user, content: [%{type: :text, text: "Hello!"}]}
  """
  @spec user(String.t()) :: t()
  def user(text) when is_binary(text) do
    %__MODULE__{role: :user, content: [%{type: :text, text: text}]}
  end

  @doc """
  Creates an assistant message with text content.

  ## Example

      iex> Message.assistant("I can help with that.")
      %Message{role: :assistant, content: [%{type: :text, text: "I can help with that."}]}
  """
  @spec assistant(String.t()) :: t()
  def assistant(text) when is_binary(text) do
    %__MODULE__{role: :assistant, content: [%{type: :text, text: text}]}
  end

  @doc """
  Creates an assistant message with a tool call.

  ## Example

      iex> Message.tool_call("call_1", "execute_msfconsole_command", %{"command" => "help"})
      %Message{
        role: :assistant,
        content: [%{type: :tool_call, id: "call_1", name: "execute_msfconsole_command", arguments: %{"command" => "help"}}]
      }
  """
  @spec tool_call(String.t(), String.t(), map()) :: t()
  def tool_call(id, name, arguments)
      when is_binary(id) and is_binary(name) and is_map(arguments) do
    %__MODULE__{
      role: :assistant,
      content: [%{type: :tool_call, id: id, name: name, arguments: arguments}]
    }
  end

  @doc """
  Creates a tool result message.

  ## Example

      iex> Message.tool_result("call_1", "Command executed successfully", false)
      %Message{
        role: :tool,
        content: [%{type: :tool_result, tool_call_id: "call_1", content: "Command executed successfully", is_error: false}]
      }
  """
  @spec tool_result(String.t(), String.t(), boolean()) :: t()
  def tool_result(tool_call_id, content, is_error \\ false)
      when is_binary(tool_call_id) and is_binary(content) and is_boolean(is_error) do
    %__MODULE__{
      role: :tool,
      content: [
        %{type: :tool_result, tool_call_id: tool_call_id, content: content, is_error: is_error}
      ]
    }
  end
end
