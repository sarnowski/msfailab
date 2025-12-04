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

defmodule Msfailab.LLM do
  @moduledoc """
  Public API for LLM integration.

  This module provides a unified interface for interacting with multiple LLM providers
  (Ollama, OpenAI, Anthropic). It handles model discovery, provider selection, and
  streaming chat requests with asynchronous event delivery.

  ## Architecture Overview

  The LLM subsystem is designed for agentic workloads where a TrackServer orchestrates
  AI-assisted security research. Key design principles:

  1. **Normalized Message Format**: TrackServer transforms chat history entries into
     provider-agnostic `Msfailab.LLM.Message` structs before calling `chat/2`.

  2. **Direct Event Delivery**: Events are sent directly to the caller via `send/2`
     rather than PubSub, since there's a 1:1 correlation between TrackServer and
     its LLM request.

  3. **Opaque Cache Context**: Provider-specific caching data is passed through
     without interpretation, enabling optimizations like Ollama's context continuation.

  4. **Async with Reference**: `chat/2` returns immediately with a reference for
     correlating events and potential cancellation.

  ## Message Format

  The `Msfailab.LLM.Message` struct provides a normalized format for conversation messages:

  ```elixir
  # User message
  %Message{role: :user, content: [%{type: :text, text: "Search for exploits"}]}

  # Assistant response with tool call
  %Message{
    role: :assistant,
    content: [
      %{type: :text, text: "I'll search for that."},
      %{type: :tool_call, id: "call_1", name: "execute_msfconsole_command", arguments: %{"command" => "search"}}
    ]
  }

  # Tool result
  %Message{
    role: :tool,
    content: [%{type: :tool_result, tool_call_id: "call_1", content: "Results...", is_error: false}]
  }
  ```

  ## Chat Request Parameters

  The `Msfailab.LLM.ChatRequest` struct encapsulates all request parameters:

  | Field           | Type                | Default | Description                              |
  |-----------------|---------------------|---------|------------------------------------------|
  | `model`         | `String.t()`        | required| Model identifier (determines provider)   |
  | `messages`      | `[Message.t()]`     | required| Conversation history                     |
  | `system_prompt` | `String.t() \| nil` | `nil`   | System instructions                      |
  | `tools`         | `[tool_def] \| nil` | `nil`   | Available tool definitions               |
  | `cache_context` | `term() \| nil`     | `nil`   | Provider-specific cache data             |
  | `max_tokens`    | `pos_integer()`     | 8192    | Maximum tokens to generate               |
  | `temperature`   | `float()`           | 0.1     | Sampling temperature (0.0-2.0)           |

  ### Parameter Details

  **`max_tokens`**: The maximum number of tokens the model can generate. Set to 8192
  by default, which accommodates most responses including code generation. When this
  limit is reached, the response is truncated and `stop_reason` will be `:max_tokens`.

  **`temperature`**: Controls randomness in the model's output:
  - `0.0` - Deterministic, always picks most likely token
  - `0.1` - Very focused, slight variation (default for tool use)
  - `0.7-0.8` - Balanced creativity
  - `1.0+` - Highly creative/random

  For agentic tool use, low temperature (0.0-0.3) is recommended for reliable behavior.

  ## Event Delivery

  All events are sent to the caller as `{:llm, ref, event}` tuples, where `ref` is
  the reference returned by `chat/2` and `event` is one of the `Msfailab.LLM.Events` structs.

  ### Event Types

  | Event               | Description                                        |
  |---------------------|----------------------------------------------------|
  | `StreamStarted`     | Stream has begun                                   |
  | `ContentBlockStart` | New content block (thinking, text, or tool_call)   |
  | `ContentDelta`      | Incremental text chunk for a block                 |
  | `ContentBlockStop`  | Content block is complete                          |
  | `ToolCall`          | Tool call fully parsed with arguments              |
  | `StreamComplete`    | Stream finished with metrics and stop_reason       |
  | `StreamError`       | Error occurred (may have partial content)          |

  ### Event Sequence

  A typical successful stream:

  ```
  StreamStarted
  ContentBlockStart (index: 0, type: :thinking)
  ContentDelta (index: 0, delta: "Let me...")
  ContentDelta (index: 0, delta: " analyze...")
  ContentBlockStop (index: 0)
  ContentBlockStart (index: 1, type: :text)
  ContentDelta (index: 1, delta: "Based on...")
  ContentBlockStop (index: 1)
  StreamComplete
  ```

  With tool calls:

  ```
  StreamStarted
  ContentBlockStart (index: 0, type: :text)
  ContentDelta (index: 0, delta: "I'll search...")
  ContentBlockStop (index: 0)
  ContentBlockStart (index: 1, type: :tool_call)
  ToolCall (index: 1, id: "call_1", name: "execute_msfconsole_command", arguments: %{...})
  ContentBlockStop (index: 1)
  StreamComplete (stop_reason: :tool_use)
  ```

  ### Stop Reasons

  The `StreamComplete` event includes a `stop_reason`:

  | Reason        | Meaning                              | Typical Action                |
  |---------------|--------------------------------------|-------------------------------|
  | `:end_turn`   | Model finished naturally             | Turn complete (if no tools)   |
  | `:tool_use`   | Model wants to execute tools         | Execute tools, then continue  |
  | `:max_tokens` | Hit token limit, response truncated  | Handle truncation or continue |

  ## TrackServer Integration Example

  ```elixir
  defmodule Msfailab.Tracks.TrackServer do
    alias Msfailab.LLM
    alias Msfailab.LLM.{ChatRequest, Message, Events}

    # Starting a new LLM request
    def handle_cast({:start_turn, user_prompt}, state) do
      # 1. Build normalized messages from context
      messages = build_messages_for_llm(state)

      request = %ChatRequest{
        model: state.current_model,
        messages: messages,
        system_prompt: build_system_prompt(state),
        tools: available_tools(),
        cache_context: state.last_cache_context
      }

      # 2. Start streaming request
      {:ok, ref} = LLM.chat(request)

      {:noreply, %{state |
        current_llm_ref: ref,
        llm_streaming: true,
        streaming_blocks: %{}
      }}
    end

    # Handle stream start
    def handle_info({:llm, ref, %Events.StreamStarted{model: model}}, state)
        when ref == state.current_llm_ref do
      # Create LLM response record
      {:noreply, state}
    end

    # Handle content block start
    def handle_info({:llm, ref, %Events.ContentBlockStart{index: idx, type: type}}, state)
        when ref == state.current_llm_ref do
      # Allocate position, create streaming entry
      {position, state} = assign_position(state)

      streaming_block = %{
        id: Ecto.UUID.generate(),
        position: position,
        type: type,
        content: ""
      }

      # Broadcast to UI
      Events.broadcast(%ChatEntryStarted{...})

      streaming_blocks = Map.put(state.streaming_blocks, idx, streaming_block)
      {:noreply, %{state | streaming_blocks: streaming_blocks}}
    end

    # Handle content delta
    def handle_info({:llm, ref, %Events.ContentDelta{index: idx, delta: delta}}, state)
        when ref == state.current_llm_ref do
      block = state.streaming_blocks[idx]
      updated = %{block | content: block.content <> delta}

      # Broadcast accumulated content (self-healing pattern)
      Events.broadcast(%ChatEntryUpdated{content: updated.content, ...})

      {:noreply, put_in(state.streaming_blocks[idx], updated)}
    end

    # Handle tool call
    def handle_info({:llm, ref, %Events.ToolCall{} = tool_call}, state)
        when ref == state.current_llm_ref do
      # Create tool invocation entry
      {:noreply, state}
    end

    # Handle stream complete
    def handle_info({:llm, ref, %Events.StreamComplete{} = complete}, state)
        when ref == state.current_llm_ref do
      # 1. Persist streaming entries
      # 2. Save LLM response with token metrics
      # 3. Flush buffered console contexts
      # 4. Store cache context for next request
      # 5. Determine next action based on stop_reason

      next_action = case complete.stop_reason do
        :tool_use -> :execute_tools
        :end_turn -> :turn_finished
        :max_tokens -> :handle_truncation
      end

      {:noreply, %{state |
        llm_streaming: false,
        current_llm_ref: nil,
        last_cache_context: complete.cache_context,
        streaming_blocks: %{}
      }}
    end

    # Handle stream error
    def handle_info({:llm, ref, %Events.StreamError{reason: reason, recoverable: recoverable}}, state)
        when ref == state.current_llm_ref do
      if recoverable do
        # Maybe retry after backoff
      else
        # Mark turn as error
      end

      {:noreply, %{state | llm_streaming: false, current_llm_ref: nil}}
    end
  end
  ```

  ## Message Building (TrackServer → LLM)

  The TrackServer transforms chat history entries into normalized messages.
  This filtering happens before calling `chat/2`:

  | Entry Type              | Action                                    |
  |-------------------------|-------------------------------------------|
  | Before compaction       | **Filter out** (summarized)               |
  | Compaction summary      | **Include** as user message with marker   |
  | User prompts            | **Include** as user messages              |
  | Assistant thinking      | **Filter out** (not sent back to LLM)     |
  | Assistant responses     | **Include** as assistant messages         |
  | Pending tool invocations| **Filter out** (not yet complete)         |
  | Complete tool invocations| **Include** as call + result pair        |
  | Console contexts        | **Include** as user messages with marker  |

  Example message builder:

  ```elixir
  defmodule Msfailab.Tracks.TrackServer.MessageBuilder do
    alias Msfailab.LLM.Message

    def build_messages(%{compaction: compaction, entries: entries}) do
      compaction_messages(compaction) ++ Enum.flat_map(entries, &entry_to_message/1)
    end

    defp compaction_messages(nil), do: []
    defp compaction_messages(%{content: content}) do
      [Message.user("[CONVERSATION SUMMARY]\\n\#{content}\\n[END SUMMARY]")]
    end

    defp entry_to_message(%{entry_type: "message", message: %{role: "user"} = msg}) do
      [Message.user(msg.content)]
    end

    defp entry_to_message(%{entry_type: "message", message: %{message_type: "thinking"}}) do
      []  # Filter out thinking blocks
    end

    defp entry_to_message(%{entry_type: "message", message: %{role: "assistant"} = msg}) do
      [Message.assistant(msg.content)]
    end

    defp entry_to_message(%{entry_type: "tool_invocation", tool_invocation: ti}) do
      if ti.status in ~w(success error timeout denied) do
        [
          Message.tool_call(ti.tool_call_id, ti.tool_name, ti.arguments),
          Message.tool_result(ti.tool_call_id, result_content(ti), ti.status != "success")
        ]
      else
        []  # Filter out pending/executing invocations
      end
    end

    defp entry_to_message(%{entry_type: "console_context", console_context: cc}) do
      [Message.user("[CONSOLE ACTIVITY]\\n\#{cc.content}\\n[END CONSOLE ACTIVITY]")]
    end
  end
  ```

  ## Cache Context Handling

  Each provider handles caching differently. The `cache_context` field is opaque:

  | Provider  | Cache Mechanism                    | Context Contents               |
  |-----------|------------------------------------|--------------------------------|
  | Ollama    | Token context continuation         | `%{context: [integer()]}`      |
  | Anthropic | Cache control on message structure | `nil` (implicit)               |
  | OpenAI    | Automatic prefix caching           | `nil` (automatic)              |

  Pass the `cache_context` from `StreamComplete` back into the next request's
  `ChatRequest.cache_context` field to enable caching.

  ## Configuration

  At least one provider must be configured via environment variables:

  ### Ollama (local)
      OLLAMA_HOST=http://localhost:11434

  ### OpenAI
      OPENAI_API_KEY=sk-...

  ### Anthropic
      ANTHROPIC_API_KEY=sk-ant-...

  ### Default Model (optional)
      DEFAULT_MODEL=gpt-4o

  If DEFAULT_MODEL is not set:
  - If OpenAI is enabled: defaults to `gpt-4.1`
  - If only Ollama is enabled: defaults to `qwen3:30b`
  """

  alias Msfailab.LLM.ChatRequest
  alias Msfailab.LLM.Model
  alias Msfailab.LLM.Registry

  @providers %{
    ollama: Msfailab.LLM.Providers.Ollama,
    openai: Msfailab.LLM.Providers.OpenAI,
    anthropic: Msfailab.LLM.Providers.Anthropic
  }

  @doc """
  Start a streaming chat request.

  Spawns an async task that sends events to the caller. Returns immediately
  with a reference for correlating events.

  ## Parameters

  - `request` - A `Msfailab.LLM.ChatRequest` struct with model, messages, and options
  - `caller` - PID to receive events (defaults to `self()`)

  ## Returns

  - `{:ok, ref}` - Reference for correlating events with this request
  - `{:error, :model_not_found}` - The specified model is not available
  - `{:error, reason}` - Provider failed to start the request

  ## Events

  All events are sent to the caller as `{:llm, ref, event}` tuples.
  See `Msfailab.LLM.Events` for event type definitions.

  ## Example

      alias Msfailab.LLM
      alias Msfailab.LLM.{ChatRequest, Message}

      request = %ChatRequest{
        model: "claude-sonnet-4-5-20250514",
        messages: [
          Message.user("What exploits target Apache?")
        ],
        system_prompt: "You are a security research assistant.",
        tools: [msf_command_tool()]
      }

      {:ok, ref} = LLM.chat(request)

      # Events arrive as messages:
      receive do
        {:llm, ^ref, %LLM.Events.StreamStarted{}} -> :started
        {:llm, ^ref, %LLM.Events.ContentDelta{delta: text}} -> text
        {:llm, ^ref, %LLM.Events.StreamComplete{}} -> :done
      end
  """
  @spec chat(ChatRequest.t(), pid()) :: {:ok, reference()} | {:error, term()}
  def chat(%ChatRequest{} = request, caller \\ self()) do
    with {:ok, model} <- get_model(request.model),
         provider_module <- Map.fetch!(@providers, model.provider),
         ref <- make_ref(),
         :ok <- provider_module.chat(request, caller, ref) do
      {:ok, ref}
    end
  end

  @doc """
  List all available models across all providers.

  Returns an empty list if the LLM Registry is not running.

  ## Example

      iex> Msfailab.LLM.list_models()
      [%Model{name: "gpt-4o", provider: :openai, context_window: 128000}, ...]
  """
  @spec list_models() :: [Model.t()]
  def list_models do
    Registry.list_models()
  catch
    # coveralls-ignore-next-line
    :exit, _ -> []
  end

  @doc """
  Get a specific model by name.

  ## Example

      iex> Msfailab.LLM.get_model("gpt-4o")
      {:ok, %Model{name: "gpt-4o", provider: :openai, context_window: 128000}}

      iex> Msfailab.LLM.get_model("nonexistent")
      {:error, :not_found}
  """
  @spec get_model(String.t()) :: {:ok, Model.t()} | {:error, :not_found}
  defdelegate get_model(name), to: Registry

  @doc """
  Get the default model name.

  Returns the value of DEFAULT_MODEL env var if set and valid,
  otherwise returns the provider-based default.

  Returns `nil` if the LLM Registry is not running.

  ## Example

      iex> Msfailab.LLM.get_default_model()
      "gpt-4.1"
  """
  @spec get_default_model() :: String.t() | nil
  def get_default_model do
    Registry.get_default_model()
  catch
    # coveralls-ignore-next-line
    :exit, _ -> nil
  end

  @doc """
  Get the system prompt for AI assistants.

  Reads the system prompt from `priv/prompts/system_prompt.md` and returns its content.
  The prompt defines the AI's role, capabilities, and behavioral guidelines for
  security research tasks.

  ## Example

      iex> {:ok, prompt} = Msfailab.LLM.get_system_prompt()
      iex> String.starts_with?(prompt, "# Security Research Assistant")
      true
  """
  @spec get_system_prompt() :: {:ok, String.t()} | {:error, File.posix()}
  # sobelow_skip ["Traversal.FileModule"]
  def get_system_prompt do
    :msfailab
    |> :code.priv_dir()
    |> Path.join("prompts/system_prompt.md")
    |> File.read()
  end
end
