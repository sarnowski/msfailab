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

defmodule Msfailab.LLM.Providers.Ollama.Core do
  @moduledoc """
  Pure functions for Ollama stream protocol parsing and message transformation.

  This module contains all business logic for the Ollama provider, separated from
  the HTTP transport layer. Functions here are pure and can be unit tested without
  HTTP mocks.

  ## Stream Processing

  The stream processor handles Ollama's NDJSON format, managing state transitions
  for thinking blocks, text content, and tool calls. The `process_chunk/2` function
  returns a tuple of `{events, new_state}` where events are structs from
  `Msfailab.LLM.Events`.

  ## Message Transformation

  Transforms internal message format to Ollama's expected format, handling:
  - User messages with text content
  - Assistant messages with optional tool calls
  - Tool result messages
  """

  alias Msfailab.LLM.ChatRequest
  alias Msfailab.LLM.Events
  alias Msfailab.LLM.Providers.Shared

  require Logger

  @default_context_window 200_000

  # ============================================================================
  # Stream State
  # ============================================================================

  defmodule State do
    @moduledoc """
    State for tracking Ollama stream processing.

    This struct encapsulates all state needed to process an NDJSON stream,
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
            thinking_block_started: boolean(),
            text_block_started: boolean(),
            tool_calls_processed: boolean(),
            trace_thinking: String.t(),
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
              thinking_block_started: false,
              text_block_started: false,
              tool_calls_processed: false,
              trace_thinking: "",
              trace_content: "",
              trace_tool_calls: [],
              trace_metadata: nil
  end

  # ============================================================================
  # Stream State Management
  # ============================================================================

  @doc """
  Initialize accumulator state for a new stream.

  Returns a State struct containing all state needed to process the NDJSON stream,
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
  Process a chunk of NDJSON data, returning events and new state.

  Handles partial line buffering and parses complete JSON lines into events.
  Returns `{events, new_state}` where events is a list of event structs.
  """
  @spec process_chunk(String.t(), State.t()) :: {[Events.t()], State.t()}
  def process_chunk(data, state) do
    state = %{state | raw_body: state.raw_body <> data}
    buffer = state.buffer <> data
    {lines, remaining} = split_complete_lines(buffer)
    state = %{state | buffer: remaining}

    {events, state} =
      Enum.reduce(lines, {[], state}, fn line, {events_acc, state_acc} ->
        case Jason.decode(line) do
          {:ok, parsed} ->
            {new_events, new_state} = handle_parsed_chunk(parsed, state_acc)
            {events_acc ++ new_events, new_state}

          {:error, _} ->
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
  @spec finalize_stream(State.t()) :: {[Events.t()], State.t()}
  def finalize_stream(%State{buffer: buffer} = state) when is_binary(buffer) and buffer != "" do
    line = String.trim(buffer)

    case Jason.decode(line) do
      {:ok, parsed} -> handle_parsed_chunk(parsed, state)
      {:error, _} -> {[], state}
    end
  end

  def finalize_stream(state), do: {[], state}

  defp split_complete_lines(buffer) do
    case String.split(buffer, "\n") do
      [single] -> {[], single}
      parts -> {Enum.slice(parts, 0..-2//1), List.last(parts)}
    end
  end

  defp handle_parsed_chunk(parsed, state) do
    {started_events, state} = maybe_emit_stream_started(parsed, state)

    message = parsed["message"] || %{}
    thinking = message["thinking"] || ""
    content = message["content"] || ""
    tool_calls = message["tool_calls"]
    done = parsed["done"] == true

    {thinking_events, state} = handle_thinking_content(thinking, state)
    {close_thinking_events, state} = maybe_close_thinking_for_content(content, state)
    {text_events, state} = handle_text_content(content, state)

    # Ollama sends tool_calls in a done=false chunk before the final done=true chunk
    # Close text block before processing tool calls (like we close thinking for content)
    {close_text_events, state} = maybe_close_text_for_tool_calls(tool_calls, state)
    {tool_events, state} = handle_tool_calls(tool_calls, state)

    events =
      started_events ++
        thinking_events ++
        close_thinking_events ++ text_events ++ close_text_events ++ tool_events

    if done do
      {finalize_events, state} = finalize_open_blocks(state)
      {complete_events, state} = emit_stream_complete(parsed, state)

      {events ++ finalize_events ++ complete_events, state}
    else
      {events, state}
    end
  end

  defp maybe_close_text_for_tool_calls(nil, state), do: {[], state}
  defp maybe_close_text_for_tool_calls([], state), do: {[], state}

  defp maybe_close_text_for_tool_calls(_tool_calls, state) do
    if state.text_block_started do
      event = %Events.ContentBlockStop{index: state.block_index}
      {[event], %{state | block_index: state.block_index + 1, text_block_started: false}}
    else
      {[], state}
    end
  end

  defp maybe_emit_stream_started(parsed, state) do
    if state.started do
      {[], state}
    else
      model = parsed["model"]
      {[%Events.StreamStarted{model: model}], %{state | started: true}}
    end
  end

  defp handle_thinking_content("", state), do: {[], state}

  defp handle_thinking_content(thinking, state) do
    {start_events, state} =
      if state.thinking_block_started do
        {[], state}
      else
        event = %Events.ContentBlockStart{index: state.block_index, type: :thinking}
        {[event], %{state | thinking_block_started: true}}
      end

    delta_event = %Events.ContentDelta{index: state.block_index, delta: thinking}
    state = %{state | trace_thinking: state.trace_thinking <> thinking}

    {start_events ++ [delta_event], state}
  end

  defp maybe_close_thinking_for_content("", state), do: {[], state}

  defp maybe_close_thinking_for_content(_content, state) do
    if state.thinking_block_started do
      event = %Events.ContentBlockStop{index: state.block_index}
      {[event], %{state | block_index: state.block_index + 1, thinking_block_started: false}}
    else
      {[], state}
    end
  end

  defp handle_text_content("", state), do: {[], state}

  defp handle_text_content(content, state) do
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

  defp finalize_open_blocks(state) do
    {thinking_events, state} =
      if state.thinking_block_started do
        event = %Events.ContentBlockStop{index: state.block_index}
        {[event], %{state | block_index: state.block_index + 1, thinking_block_started: false}}
      else
        {[], state}
      end

    {text_events, state} =
      if state.text_block_started do
        event = %Events.ContentBlockStop{index: state.block_index}
        {[event], %{state | block_index: state.block_index + 1, text_block_started: false}}
      else
        {[], state}
      end

    {thinking_events ++ text_events, state}
  end

  defp handle_tool_calls(nil, state), do: {[], state}
  defp handle_tool_calls([], state), do: {[], state}

  defp handle_tool_calls(tool_calls, state) do
    {events, state} =
      Enum.reduce(tool_calls, {[], state}, fn tool_call, {events_acc, state_acc} ->
        function = tool_call["function"] || %{}
        name = function["name"]
        arguments = function["arguments"] || %{}
        id = tool_call["id"] || generate_tool_call_id()

        start_event = %Events.ContentBlockStart{index: state_acc.block_index, type: :tool_call}

        tool_event = %Events.ToolCall{
          index: state_acc.block_index,
          id: id,
          name: name,
          arguments: arguments
        }

        stop_event = %Events.ContentBlockStop{index: state_acc.block_index}

        trace_tool_call = %{id: id, name: name, arguments: arguments}

        new_state = %{
          state_acc
          | block_index: state_acc.block_index + 1,
            trace_tool_calls: [trace_tool_call | state_acc.trace_tool_calls],
            tool_calls_processed: true
        }

        {events_acc ++ [start_event, tool_event, stop_event], new_state}
      end)

    {events, state}
  end

  defp emit_stream_complete(parsed, state) do
    input_tokens = parsed["prompt_eval_count"] || 0
    output_tokens = parsed["eval_count"] || 0
    context = parsed["context"]
    done_reason = parsed["done_reason"]

    # Use accumulated state to detect tool_use stop reason since tool_calls
    # may come in an earlier chunk (done=false) before the final chunk (done=true)
    stop_reason = map_stop_reason(done_reason, state)

    event = %Events.StreamComplete{
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      cached_input_tokens: nil,
      cache_creation_tokens: nil,
      cache_context: context,
      stop_reason: stop_reason
    }

    metadata = %{
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      stop_reason: stop_reason
    }

    {[event], %{state | trace_metadata: metadata}}
  end

  @doc """
  Generate a unique tool call ID.

  Used when Ollama doesn't provide an ID for a tool call.
  """
  @spec generate_tool_call_id() :: String.t()
  def generate_tool_call_id do
    "call_" <> (:crypto.strong_rand_bytes(12) |> Base.encode16(case: :lower))
  end

  # ============================================================================
  # Request Building
  # ============================================================================

  @doc """
  Build the Ollama API request body from a ChatRequest.

  Transforms the internal request format to Ollama's expected JSON structure,
  including messages, tools, and options.
  """
  @spec build_request_body(ChatRequest.t(), boolean()) :: map()
  def build_request_body(%ChatRequest{} = request, thinking_enabled) do
    body = %{
      "model" => request.model,
      "messages" => build_messages(request),
      "stream" => true,
      "think" => thinking_enabled,
      "options" => %{
        "temperature" => request.temperature,
        "num_predict" => request.max_tokens
      }
    }

    body =
      if request.tools && request.tools != [] do
        Map.put(body, "tools", transform_tools(request.tools))
      else
        body
      end

    if request.cache_context do
      Map.put(body, "context", request.cache_context)
    else
      body
    end
  end

  defp build_messages(%ChatRequest{messages: messages, system_prompt: system_prompt}) do
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
  Transform an internal message to Ollama's format.

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
      %{type: :tool_result, content: result_content} ->
        [%{"role" => "tool", "content" => result_content}]

      _ ->
        []
    end)
  end

  defp extract_text_content(content) do
    content
    |> Enum.filter(&(&1.type == :text))
    |> Enum.map_join("\n", & &1.text)
  end

  defp extract_tool_calls(content) do
    content
    |> Enum.filter(&(&1.type == :tool_call))
    |> Enum.map(fn block ->
      %{
        "function" => %{
          "name" => block.name,
          "arguments" => block.arguments
        }
      }
    end)
  end

  # ============================================================================
  # Tool Transformation
  # ============================================================================

  @doc """
  Transform tools to Ollama's OpenAI-compatible format.
  """
  @spec transform_tools([map()]) :: [map()]
  def transform_tools(tools) do
    Enum.map(tools, fn tool ->
      %{
        "type" => "function",
        "function" => %{
          "name" => tool.name,
          "description" => tool.description,
          "parameters" => tool.parameters
        }
      }
    end)
  end

  # ============================================================================
  # Context Window Extraction
  # ============================================================================

  @doc """
  Extract context window size from Ollama model info.

  Checks multiple locations in the model info response, falling back to
  the default context window (200k) if not found. Logs at debug level
  when using the default.
  """
  @spec extract_context_window(map(), String.t()) :: pos_integer()
  def extract_context_window(body, model_name) do
    result =
      with nil <- get_in(body, ["model_info", "llama.context_length"]),
           nil <- get_in(body, ["model_info", "qwen2.context_length"]),
           nil <- get_in(body, ["model_info", "gemma2.context_length"]),
           nil <- extract_from_parameters(body) do
        Logger.debug("Using default context window",
          context_window: @default_context_window,
          model: model_name
        )

        @default_context_window
      end

    case result do
      length when is_integer(length) -> length
      _ -> @default_context_window
    end
  end

  defp extract_from_parameters(body) do
    case body["parameters"] do
      nil ->
        nil

      params when is_binary(params) ->
        case Regex.run(~r/num_ctx\s+(\d+)/, params) do
          [_, num] -> String.to_integer(num)
          nil -> nil
        end
    end
  end

  # ============================================================================
  # Stop Reason Mapping
  # ============================================================================

  @doc """
  Map Ollama's done_reason to our internal stop reason.

  Uses accumulated state to detect tool_use since Ollama may send
  tool_calls in earlier chunks (done=false) before the final chunk (done=true).
  """
  @spec map_stop_reason(String.t() | nil, State.t()) :: :end_turn | :tool_use | :max_tokens
  def map_stop_reason(done_reason, state) do
    cond do
      state.tool_calls_processed -> :tool_use
      done_reason == "length" -> :max_tokens
      true -> :end_turn
    end
  end

  # ============================================================================
  # Trace Formatting
  # ============================================================================

  @doc """
  Format accumulated stream state for trace logging.

  Organizes thinking, content, tool calls, and metadata into sections
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
      if state.trace_thinking != "" do
        sections ++ ["--- THINKING ---\n#{state.trace_thinking}"]
      else
        sections
      end

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
