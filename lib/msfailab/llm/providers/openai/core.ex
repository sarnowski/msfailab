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

defmodule Msfailab.LLM.Providers.OpenAI.Core do
  @moduledoc """
  Pure functions for OpenAI SSE stream parsing and message transformation.

  This module contains all business logic for the OpenAI provider, separated from
  the HTTP transport layer. Functions here are pure and can be unit tested without
  HTTP mocks.

  ## Stream Processing

  The stream processor handles OpenAI's Server-Sent Events (SSE) format with
  `data: {json}` lines. Tool call arguments are streamed incrementally and must
  be accumulated then parsed as JSON when complete.

  The `process_chunk/2` function returns a tuple of `{events, new_state}` where events
  are structs from `Msfailab.LLM.Events`.

  ## Message Transformation

  Transforms internal message format to OpenAI's expected format, handling:
  - User messages with text content
  - Assistant messages with optional tool calls
  - Tool result messages
  """

  alias Msfailab.LLM.ChatRequest
  alias Msfailab.LLM.Events
  alias Msfailab.LLM.Providers.Shared

  # ============================================================================
  # Stream State
  # ============================================================================

  defmodule State do
    @moduledoc """
    State for tracking OpenAI stream processing.

    This struct encapsulates all state needed to process an SSE stream,
    including buffer for partial lines, content block tracking, and trace data.
    """

    @type t :: %__MODULE__{
            request_body: map(),
            request_url: String.t(),
            response_headers: term() | nil,
            req_resp: {Req.Request.t(), Req.Response.t()} | nil,
            buffer: String.t(),
            raw_body: String.t(),
            started: boolean(),
            block_index: non_neg_integer(),
            text_block_started: boolean(),
            tool_calls: map(),
            usage: map() | nil,
            finish_reason: String.t() | nil,
            trace_content: String.t(),
            trace_tool_calls: [map()],
            trace_metadata: map() | nil
          }

    defstruct request_body: %{},
              request_url: "",
              response_headers: nil,
              req_resp: nil,
              buffer: "",
              raw_body: "",
              started: false,
              block_index: 0,
              text_block_started: false,
              tool_calls: %{},
              usage: nil,
              finish_reason: nil,
              trace_content: "",
              trace_tool_calls: [],
              trace_metadata: nil
  end

  # ============================================================================
  # Stream State Management
  # ============================================================================

  @doc """
  Initialize accumulator state for a new stream.

  Returns a State struct containing all state needed to process the SSE stream,
  including buffer for partial lines and tracking for content blocks.
  """
  @spec init_state(map(), String.t()) :: State.t()
  def init_state(request_body, url) do
    %State{
      request_body: request_body,
      request_url: url
    }
  end

  @doc """
  Process a chunk of SSE data, returning events and new state.

  Handles partial line buffering and parses complete SSE lines into events.
  Returns `{events, new_state}` where events is a list of event structs.
  """
  @spec process_chunk(String.t(), State.t()) :: {[Events.t()], State.t()}
  def process_chunk(data, state) do
    state = %{state | raw_body: state.raw_body <> data}
    buffer = state.buffer <> data
    {lines, remaining} = split_sse_lines(buffer)
    state = %{state | buffer: remaining}

    {events, state} =
      Enum.reduce(lines, {[], state}, fn line, {events_acc, state_acc} ->
        case parse_sse_line(line) do
          {:data, "[DONE]"} ->
            {done_events, new_state} = finalize_stream(state_acc)
            {events_acc ++ done_events, new_state}

          {:data, json} ->
            {new_events, new_state} = handle_json_chunk(json, state_acc)
            {events_acc ++ new_events, new_state}

          :skip ->
            {events_acc, state_acc}
        end
      end)

    {events, state}
  end

  @doc """
  Finalize the stream, processing any remaining buffer content.

  Call this when the HTTP stream ends to handle any partial data that
  wasn't terminated with a newline.
  """
  @spec finalize_stream_buffer(State.t()) :: {[Events.t()], State.t()}
  def finalize_stream_buffer(%State{buffer: buffer} = state)
      when is_binary(buffer) and buffer != "" do
    line = String.trim(buffer)

    case parse_sse_line(line) do
      {:data, "[DONE]"} -> finalize_stream(state)
      {:data, json} -> handle_json_chunk(json, state)
      :skip -> {[], state}
    end
  end

  def finalize_stream_buffer(state), do: {[], state}

  defp split_sse_lines(buffer) do
    case String.split(buffer, "\n") do
      [single] -> {[], single}
      parts -> {Enum.slice(parts, 0..-2//1), List.last(parts)}
    end
  end

  defp parse_sse_line("data: " <> json), do: {:data, String.trim(json)}
  defp parse_sse_line(_), do: :skip

  defp handle_json_chunk(json, state) do
    case Jason.decode(json) do
      {:ok, parsed} -> process_parsed_chunk(parsed, state)
      {:error, _} -> {[], state}
    end
  end

  defp process_parsed_chunk(parsed, state) do
    {start_events, state} =
      if state.started do
        {[], state}
      else
        model = parsed["model"]
        {[%Events.StreamStarted{model: model}], %{state | started: true}}
      end

    state =
      if usage = parsed["usage"] do
        %{state | usage: usage}
      else
        state
      end

    choices = parsed["choices"] || []

    {choice_events, state} =
      Enum.reduce(choices, {[], state}, fn choice, {events_acc, state_acc} ->
        {new_events, new_state} = process_choice(choice, state_acc)
        {events_acc ++ new_events, new_state}
      end)

    {start_events ++ choice_events, state}
  end

  defp process_choice(choice, state) do
    delta = choice["delta"] || %{}
    finish_reason = choice["finish_reason"]

    {content_events, state} = process_content_delta(delta, state)
    state = process_tool_call_delta(delta, state)

    if finish_reason do
      {close_events, state} = close_text_block(state)
      {tool_events, state} = emit_tool_calls(state)
      state = %{state | finish_reason: finish_reason}
      {content_events ++ close_events ++ tool_events, state}
    else
      {content_events, state}
    end
  end

  defp process_content_delta(%{"content" => content}, state)
       when is_binary(content) and content != "" do
    {start_events, state} =
      if state.text_block_started do
        {[], state}
      else
        event = %Events.ContentBlockStart{index: state.block_index, type: :text}
        {[event], %{state | text_block_started: true}}
      end

    delta_event = %Events.ContentDelta{index: state.block_index, delta: content}
    state = %{state | trace_content: state.trace_content <> content}

    {start_events ++ [delta_event], state}
  end

  defp process_content_delta(_, state), do: {[], state}

  defp process_tool_call_delta(%{"tool_calls" => tool_calls}, state) when is_list(tool_calls) do
    Enum.reduce(tool_calls, state, fn tc_delta, state ->
      index = tc_delta["index"]
      existing = Map.get(state.tool_calls, index, %{id: nil, name: nil, arguments: ""})

      updated =
        existing
        |> maybe_update(:id, tc_delta["id"])
        |> maybe_update(:name, get_in(tc_delta, ["function", "name"]))
        |> append_arguments(get_in(tc_delta, ["function", "arguments"]))

      %{state | tool_calls: Map.put(state.tool_calls, index, updated)}
    end)
  end

  defp process_tool_call_delta(_, state), do: state

  defp maybe_update(map, _key, nil), do: map
  defp maybe_update(map, key, value), do: Map.put(map, key, value)

  defp append_arguments(map, nil), do: map
  defp append_arguments(map, args), do: Map.update!(map, :arguments, &(&1 <> args))

  defp close_text_block(state) do
    if state.text_block_started do
      event = %Events.ContentBlockStop{index: state.block_index}
      {[event], %{state | block_index: state.block_index + 1, text_block_started: false}}
    else
      {[], state}
    end
  end

  defp emit_tool_calls(state) do
    tool_calls =
      state.tool_calls
      |> Enum.sort_by(fn {index, _} -> index end)
      |> Enum.map(fn {_, tc} -> tc end)

    {events, state} =
      Enum.reduce(tool_calls, {[], state}, fn tc, {events_acc, state_acc} ->
        arguments = parse_tool_arguments(tc.arguments)

        start_event = %Events.ContentBlockStart{index: state_acc.block_index, type: :tool_call}

        tool_event = %Events.ToolCall{
          index: state_acc.block_index,
          id: tc.id,
          name: tc.name,
          arguments: arguments
        }

        stop_event = %Events.ContentBlockStop{index: state_acc.block_index}

        trace_tool_call = %{id: tc.id, name: tc.name, arguments: arguments}

        new_state = %{
          state_acc
          | block_index: state_acc.block_index + 1,
            trace_tool_calls: [trace_tool_call | state_acc.trace_tool_calls]
        }

        {events_acc ++ [start_event, tool_event, stop_event], new_state}
      end)

    {events, state}
  end

  @doc """
  Parse tool call arguments from accumulated JSON string.
  """
  @spec parse_tool_arguments(String.t()) :: map()
  def parse_tool_arguments(args) when is_binary(args) do
    case Jason.decode(args) do
      {:ok, parsed} -> parsed
      {:error, _} -> %{}
    end
  end

  def parse_tool_arguments(_), do: %{}

  defp finalize_stream(state) do
    usage = state.usage || %{}
    finish_reason = state.finish_reason

    stop_reason = map_stop_reason(finish_reason, state)
    input_tokens = usage["prompt_tokens"] || 0
    output_tokens = usage["completion_tokens"] || 0
    cached_input_tokens = get_in(usage, ["prompt_tokens_details", "cached_tokens"])

    event = %Events.StreamComplete{
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      cached_input_tokens: cached_input_tokens,
      cache_creation_tokens: nil,
      cache_context: nil,
      stop_reason: stop_reason
    }

    metadata = %{
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      cached_input_tokens: cached_input_tokens,
      stop_reason: stop_reason
    }

    {[event], %{state | trace_metadata: metadata}}
  end

  # ============================================================================
  # Request Building
  # ============================================================================

  @doc """
  Build the OpenAI API request body from a ChatRequest.

  Transforms the internal request format to OpenAI's expected JSON structure,
  including messages, tools, and streaming options.
  """
  @spec build_request_body(ChatRequest.t()) :: map()
  def build_request_body(%ChatRequest{} = request) do
    body = %{
      "model" => request.model,
      "messages" => build_messages(request),
      "stream" => true,
      "stream_options" => %{"include_usage" => true},
      "max_completion_tokens" => request.max_tokens,
      "temperature" => request.temperature
    }

    if request.tools && request.tools != [] do
      Map.put(body, "tools", transform_tools(request.tools))
    else
      body
    end
  end

  @doc """
  Build the messages array from a ChatRequest.
  """
  @spec build_messages(ChatRequest.t()) :: [map()]
  def build_messages(%ChatRequest{messages: messages, system_prompt: system_prompt}) do
    system_messages =
      if system_prompt && system_prompt != "" do
        [%{"role" => "system", "content" => system_prompt}]
      else
        []
      end

    user_messages = Enum.flat_map(messages, &transform_message/1)
    system_messages ++ user_messages
  end

  # ============================================================================
  # Message Transformation
  # ============================================================================

  @doc """
  Transform an internal message to OpenAI's format.

  Handles user messages, assistant messages (with optional tool calls),
  and tool result messages.
  """
  @spec transform_message(map()) :: [map()]
  def transform_message(%{role: :user, content: content}) do
    text = extract_text_content(content)
    [%{"role" => "user", "content" => text}]
  end

  def transform_message(%{role: :assistant, content: content}) do
    text = extract_text_content(content)
    tool_calls = extract_tool_calls(content)

    msg = %{"role" => "assistant", "content" => text}

    if tool_calls != [] do
      [Map.put(msg, "tool_calls", tool_calls)]
    else
      [msg]
    end
  end

  def transform_message(%{role: :tool, content: content}) do
    Enum.flat_map(content, fn
      %{type: :tool_result, tool_call_id: id, content: result_content} ->
        [%{"role" => "tool", "tool_call_id" => id, "content" => result_content}]

      _ ->
        []
    end)
  end

  @doc """
  Extract text content from a list of content blocks.
  """
  @spec extract_text_content([map()]) :: String.t()
  def extract_text_content(content) do
    content
    |> Enum.filter(&(&1.type == :text))
    |> Enum.map_join("\n", & &1.text)
  end

  @doc """
  Extract tool calls from a list of content blocks.
  """
  @spec extract_tool_calls([map()]) :: [map()]
  def extract_tool_calls(content) do
    content
    |> Enum.filter(&(&1.type == :tool_call))
    |> Enum.map(fn block ->
      %{
        "id" => block.id,
        "type" => "function",
        "function" => %{
          "name" => block.name,
          "arguments" => Jason.encode!(block.arguments)
        }
      }
    end)
  end

  # ============================================================================
  # Tool Transformation
  # ============================================================================

  @doc """
  Transform tools to OpenAI's function calling format.
  """
  @spec transform_tools([map()]) :: [map()]
  def transform_tools(tools) do
    Enum.map(tools, fn tool ->
      function = %{
        "name" => tool.name,
        "description" => tool.description,
        "parameters" => tool.parameters
      }

      function =
        if Map.get(tool, :strict, false) do
          Map.put(function, "strict", true)
        else
          function
        end

      %{"type" => "function", "function" => function}
    end)
  end

  # ============================================================================
  # Stop Reason Mapping
  # ============================================================================

  @doc """
  Map OpenAI's finish_reason to our internal stop reason.
  """
  @spec map_stop_reason(String.t() | nil, State.t()) :: :end_turn | :tool_use | :max_tokens
  def map_stop_reason("tool_calls", _state), do: :tool_use
  def map_stop_reason("length", _state), do: :max_tokens

  def map_stop_reason(_, state) do
    if map_size(state.tool_calls) > 0, do: :tool_use, else: :end_turn
  end

  # ============================================================================
  # Trace Formatting
  # ============================================================================

  @doc """
  Format accumulated stream state for trace logging.

  Organizes content, tool calls, and metadata into sections
  for the trace log file.
  """
  @spec format_trace_response(map(), non_neg_integer()) :: String.t()
  def format_trace_response(state, status)

  def format_trace_response(state, status) when status >= 400 do
    error_body = Shared.extract_raw_error_body(state)

    if error_body do
      "--- ERROR RESPONSE ---\n#{error_body}"
    else
      "(empty error response)"
    end
  end

  def format_trace_response(state, _status) do
    sections = []

    sections =
      if state.trace_content != "" do
        sections ++ ["--- CONTENT ---\n#{state.trace_content}"]
      else
        sections
      end

    sections =
      if state.trace_tool_calls != [] do
        tool_calls = Enum.reverse(state.trace_tool_calls)
        formatted = Shared.format_json(tool_calls)
        sections ++ ["--- TOOL_CALLS ---\n#{formatted}"]
      else
        sections
      end

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
end
