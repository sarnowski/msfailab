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

defmodule Msfailab.LLM.Providers.Anthropic.Core do
  @moduledoc """
  Pure functions for Anthropic SSE stream parsing and message transformation.

  This module contains all business logic for the Anthropic provider, separated from
  the HTTP transport layer. Functions here are pure and can be unit tested without
  HTTP mocks.

  ## Stream Processing

  The stream processor handles Anthropic's Server-Sent Events (SSE) format with typed events:
  - `message_start` - Initial message metadata
  - `content_block_start` - New content block (text, thinking, or tool_use)
  - `content_block_delta` - Incremental content
  - `content_block_stop` - Block complete
  - `message_delta` - Final stop reason and usage
  - `message_stop` - Stream complete

  The `process_chunk/2` function returns a tuple of `{events, new_state}` where events
  are structs from `Msfailab.LLM.Events`.

  ## Message Transformation

  Transforms internal message format to Anthropic's expected format, handling:
  - User messages with content blocks
  - Assistant messages with text and tool_use blocks
  - Tool result messages (sent as user messages with tool_result blocks)
  """

  alias Msfailab.LLM.ChatRequest
  alias Msfailab.LLM.Events
  alias Msfailab.LLM.Providers.Shared

  # ============================================================================
  # Stream State Management
  # ============================================================================

  @doc """
  Initialize accumulator state for a new stream.

  Returns a map containing all state needed to process the SSE stream,
  including buffer for partial events and tracking for content blocks.
  """
  @spec init_state(map(), String.t()) :: map()
  def init_state(request_body, url) do
    %{
      request_body: request_body,
      request_url: url,
      response_headers: nil,
      buffer: "",
      raw_body: "",
      model: nil,
      started: false,
      input_tokens: 0,
      output_tokens: 0,
      cached_input_tokens: nil,
      cache_creation_tokens: nil,
      stop_reason: nil,
      current_blocks: %{},
      block_index_map: %{},
      trace_blocks: [],
      trace_metadata: nil
    }
  end

  @doc """
  Process a chunk of SSE data, returning events and new state.

  Handles partial event buffering and parses complete SSE events into
  `Msfailab.LLM.Events` structs. Returns `{events, new_state}`.
  """
  @spec process_chunk(String.t(), map()) :: {[Events.t()], map()}
  def process_chunk(data, state) do
    state = %{state | raw_body: state.raw_body <> data}
    buffer = state.buffer <> data
    {events, remaining} = split_sse_events(buffer)
    state = %{state | buffer: remaining}

    Enum.reduce(events, {[], state}, fn event_text, {events_acc, state_acc} ->
      {new_events, new_state} = handle_sse_event(event_text, state_acc)
      {events_acc ++ new_events, new_state}
    end)
  end

  @doc """
  Finalize the stream, processing any remaining buffer content.

  Call this when the HTTP stream ends to handle any partial data that
  wasn't terminated with a double newline.
  """
  @spec finalize_stream(map()) :: {[Events.t()], map()}
  def finalize_stream(%{buffer: buffer} = state) when is_binary(buffer) and buffer != "" do
    handle_sse_event(String.trim(buffer), state)
  end

  def finalize_stream(state), do: {[], state}

  defp split_sse_events(buffer) do
    # SSE events are separated by double newlines
    case String.split(buffer, "\n\n") do
      [single] -> {[], single}
      parts -> {Enum.slice(parts, 0..-2//1), List.last(parts)}
    end
  end

  defp handle_sse_event(event_text, state) do
    case parse_sse_event(event_text) do
      {:ok, event_type, data} ->
        process_event(event_type, data, state)

      :skip ->
        {[], state}
    end
  end

  defp parse_sse_event(text) do
    lines = String.split(text, "\n")

    event_type =
      Enum.find_value(lines, fn
        "event: " <> type -> String.trim(type)
        _ -> nil
      end)

    data =
      Enum.find_value(lines, fn
        "data: " <> json -> String.trim(json)
        _ -> nil
      end)

    if event_type && data do
      case Jason.decode(data) do
        {:ok, parsed} -> {:ok, event_type, parsed}
        {:error, _} -> :skip
      end
    else
      :skip
    end
  end

  # ============================================================================
  # Event Processing
  # ============================================================================

  defp process_event("message_start", data, state) do
    message = data["message"] || %{}
    model = message["model"]
    usage = message["usage"] || %{}

    event = %Events.StreamStarted{model: model}

    new_state = %{
      state
      | model: model,
        started: true,
        input_tokens: usage["input_tokens"] || 0,
        cached_input_tokens: usage["cache_read_input_tokens"],
        cache_creation_tokens: usage["cache_creation_input_tokens"]
    }

    {[event], new_state}
  end

  defp process_event("content_block_start", data, state) do
    index = data["index"]
    content_block = data["content_block"] || %{}
    block_type = content_block["type"]

    our_index = map_size(state.block_index_map)
    our_type = map_anthropic_block_type(block_type)

    event = %Events.ContentBlockStart{index: our_index, type: our_type}

    block_data = %{
      type: block_type,
      our_index: our_index,
      id: content_block["id"],
      name: content_block["name"],
      text: content_block["text"] || "",
      input: ""
    }

    state = put_in(state.current_blocks[index], block_data)
    state = put_in(state.block_index_map[index], our_index)

    {[event], state}
  end

  defp process_event("content_block_delta", data, state) do
    index = data["index"]
    delta = data["delta"] || %{}

    case state.current_blocks[index] do
      nil -> {[], state}
      block -> process_delta(delta, index, block, state)
    end
  end

  defp process_event("content_block_stop", data, state) do
    index = data["index"]
    block = state.current_blocks[index]

    if block do
      our_index = state.block_index_map[index]

      # Build trace entry and emit tool call event if applicable
      {extra_events, trace_entry} =
        case block.type do
          "tool_use" ->
            arguments = parse_tool_arguments(block.input)

            tool_event = %Events.ToolCall{
              index: our_index,
              id: block.id,
              name: block.name,
              arguments: arguments
            }

            {[tool_event], {:tool_use, %{id: block.id, name: block.name, arguments: arguments}}}

          "text" ->
            {[], {:text, block.text}}

          "thinking" ->
            {[], {:thinking, block.text}}

          _ ->
            {[], nil}
        end

      stop_event = %Events.ContentBlockStop{index: our_index}

      # Add trace entry if present
      state =
        if trace_entry do
          %{state | trace_blocks: state.trace_blocks ++ [trace_entry]}
        else
          state
        end

      {extra_events ++ [stop_event], state}
    else
      {[], state}
    end
  end

  defp process_event("message_delta", data, state) do
    delta = data["delta"] || %{}
    usage = data["usage"] || %{}

    stop_reason = delta["stop_reason"]
    output_tokens = usage["output_tokens"] || state.output_tokens

    {[], %{state | stop_reason: stop_reason, output_tokens: output_tokens}}
  end

  defp process_event("message_stop", _data, state) do
    stop_reason = map_stop_reason(state.stop_reason)

    event = %Events.StreamComplete{
      input_tokens: state.input_tokens,
      output_tokens: state.output_tokens,
      cached_input_tokens: state.cached_input_tokens,
      cache_creation_tokens: state.cache_creation_tokens,
      cache_context: nil,
      stop_reason: stop_reason
    }

    # Store metadata for tracing
    metadata = %{
      input_tokens: state.input_tokens,
      output_tokens: state.output_tokens,
      cached_input_tokens: state.cached_input_tokens,
      cache_creation_tokens: state.cache_creation_tokens,
      stop_reason: stop_reason
    }

    {[event], %{state | trace_metadata: metadata}}
  end

  defp process_event("error", data, state) do
    error = data["error"] || %{}
    message = error["message"] || "Unknown error"
    error_type = error["type"]

    recoverable = error_type in ["overloaded_error", "rate_limit_error"]
    event = %Events.StreamError{reason: message, recoverable: recoverable}

    {[event], state}
  end

  defp process_event(_event_type, _data, state), do: {[], state}

  # ============================================================================
  # Delta Processing
  # ============================================================================

  defp process_delta(%{"type" => "text_delta", "text" => text}, index, block, state) do
    text = text || ""
    our_index = state.block_index_map[index]
    event = %Events.ContentDelta{index: our_index, delta: text}
    state = put_in(state.current_blocks[index].text, block.text <> text)
    {[event], state}
  end

  defp process_delta(%{"type" => "thinking_delta", "thinking" => text}, index, block, state) do
    text = text || ""
    our_index = state.block_index_map[index]
    event = %Events.ContentDelta{index: our_index, delta: text}
    state = put_in(state.current_blocks[index].text, block.text <> text)
    {[event], state}
  end

  defp process_delta(%{"type" => "input_json_delta", "partial_json" => json}, index, block, state) do
    json = json || ""
    state = put_in(state.current_blocks[index].input, block.input <> json)
    {[], state}
  end

  defp process_delta(_, _index, _block, state), do: {[], state}

  # ============================================================================
  # Request Building
  # ============================================================================

  @doc """
  Build the Anthropic API request body from a ChatRequest.

  Transforms the internal request format to Anthropic's expected JSON structure,
  including messages, system prompt, and tools.
  """
  @spec build_request_body(ChatRequest.t()) :: map()
  def build_request_body(%ChatRequest{} = request) do
    body = %{
      "model" => request.model,
      "messages" => build_messages(request.messages),
      "stream" => true,
      "max_tokens" => request.max_tokens,
      "temperature" => request.temperature
    }

    body =
      if request.system_prompt && request.system_prompt != "" do
        Map.put(body, "system", request.system_prompt)
      else
        body
      end

    if request.tools && request.tools != [] do
      Map.put(body, "tools", transform_tools(request.tools))
    else
      body
    end
  end

  defp build_messages(messages) do
    Enum.flat_map(messages, &transform_message/1)
  end

  # ============================================================================
  # Message Transformation
  # ============================================================================

  @doc """
  Transform an internal message to Anthropic's format.

  Handles user messages, assistant messages (with optional tool calls),
  and tool result messages (which become user messages with tool_result blocks).
  """
  @spec transform_message(map()) :: [map()]
  def transform_message(%{role: :user, content: content}) do
    blocks = Enum.map(content, &transform_content_block/1)
    [%{"role" => "user", "content" => blocks}]
  end

  def transform_message(%{role: :assistant, content: content}) do
    blocks = Enum.map(content, &transform_content_block/1)
    [%{"role" => "assistant", "content" => blocks}]
  end

  def transform_message(%{role: :tool, content: content}) do
    # Tool results go in a user message for Anthropic
    blocks =
      Enum.flat_map(content, fn
        %{type: :tool_result, tool_call_id: id, content: result_content, is_error: is_error} ->
          block = %{
            "type" => "tool_result",
            "tool_use_id" => id,
            "content" => result_content
          }

          block =
            if is_error do
              Map.put(block, "is_error", true)
            else
              block
            end

          [block]

        _ ->
          []
      end)

    if blocks != [] do
      [%{"role" => "user", "content" => blocks}]
    else
      []
    end
  end

  defp transform_content_block(%{type: :text, text: text}) do
    %{"type" => "text", "text" => text}
  end

  defp transform_content_block(%{type: :tool_call, id: id, name: name, arguments: arguments}) do
    %{"type" => "tool_use", "id" => id, "name" => name, "input" => arguments}
  end

  defp transform_content_block(%{type: :tool_result} = block) do
    base = %{
      "type" => "tool_result",
      "tool_use_id" => block.tool_call_id,
      "content" => block.content
    }

    if block.is_error do
      Map.put(base, "is_error", true)
    else
      base
    end
  end

  # ============================================================================
  # Tool Transformation
  # ============================================================================

  @doc """
  Transform tools to Anthropic's format with input_schema.
  """
  @spec transform_tools([map()]) :: [map()]
  def transform_tools(tools) do
    Enum.map(tools, fn tool ->
      base = %{
        "name" => tool.name,
        "description" => tool.description,
        "input_schema" => tool.parameters
      }

      if Map.get(tool, :cacheable, true) do
        Map.put(base, "cache_control", %{"type" => "ephemeral"})
      else
        base
      end
    end)
  end

  # ============================================================================
  # Type Mapping
  # ============================================================================

  @doc """
  Map Anthropic block type to internal block type.
  """
  @spec map_anthropic_block_type(String.t()) :: :text | :thinking | :tool_call
  def map_anthropic_block_type("text"), do: :text
  def map_anthropic_block_type("thinking"), do: :thinking
  def map_anthropic_block_type("tool_use"), do: :tool_call
  def map_anthropic_block_type(_), do: :text

  @doc """
  Map Anthropic stop reason to internal stop reason.
  """
  @spec map_stop_reason(String.t() | nil) :: :end_turn | :tool_use | :max_tokens
  def map_stop_reason("end_turn"), do: :end_turn
  def map_stop_reason("tool_use"), do: :tool_use
  def map_stop_reason("max_tokens"), do: :max_tokens
  def map_stop_reason(_), do: :end_turn

  # ============================================================================
  # Trace Formatting
  # ============================================================================

  @doc """
  Format accumulated stream state for trace logging.

  Organizes content blocks and metadata into sections for the trace log file.
  """
  @spec format_trace_response(map(), non_neg_integer()) :: String.t()
  def format_trace_response(state, status)

  # For error responses, format the raw error body
  def format_trace_response(state, status) when status >= 400 do
    error_body = Shared.extract_raw_error_body(state)

    if error_body do
      "--- ERROR RESPONSE ---\n#{error_body}"
    else
      "(empty error response)"
    end
  end

  def format_trace_response(state, _status) do
    sections =
      if state.trace_blocks == [] do
        []
      else
        blocks =
          state.trace_blocks
          |> Enum.with_index()
          |> Enum.map_join("\n\n", fn {{type, content}, index} ->
            format_trace_block(type, content, index)
          end)

        [blocks]
      end

    # Add metadata section if present
    sections =
      if state.trace_metadata do
        formatted = Shared.format_json(state.trace_metadata)
        sections ++ ["--- METADATA ---\n#{formatted}"]
      else
        sections
      end

    if sections == [] do
      "(empty response)"
    else
      Enum.join(sections, "\n\n")
    end
  end

  defp format_trace_block(:text, content, index) do
    "--- CONTENT BLOCK #{index} (text) ---\n#{content}"
  end

  defp format_trace_block(:thinking, content, index) do
    "--- CONTENT BLOCK #{index} (thinking) ---\n#{content}"
  end

  defp format_trace_block(:tool_use, tool_call, index) do
    formatted = Shared.format_json(tool_call)
    "--- CONTENT BLOCK #{index} (tool_use) ---\n#{formatted}"
  end

  # ============================================================================
  # Error Handling (delegated to Shared)
  # ============================================================================

  @doc """
  Extract error message from response body or buffer.
  """
  @spec extract_error_message(map() | String.t(), non_neg_integer()) :: String.t()
  defdelegate extract_error_message(body, status), to: Shared

  @doc """
  Check if an error is recoverable (transient network issues).
  """
  @spec recoverable_error?(term()) :: boolean()
  defdelegate recoverable_error?(error), to: Shared

  @doc """
  Parse tool call arguments from accumulated JSON string.
  """
  @spec parse_tool_arguments(String.t()) :: map()
  def parse_tool_arguments(input) when is_binary(input) and input != "" do
    case Jason.decode(input) do
      {:ok, parsed} -> parsed
      {:error, _} -> %{}
    end
  end

  def parse_tool_arguments(_), do: %{}
end
