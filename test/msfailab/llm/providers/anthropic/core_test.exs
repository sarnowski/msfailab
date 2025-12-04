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

defmodule Msfailab.LLM.Providers.Anthropic.CoreTest do
  @moduledoc """
  Unit tests for the Anthropic provider Core module.

  These tests cover pure functions for SSE stream processing, message transformation,
  and state management without requiring HTTP mocks.
  """

  use ExUnit.Case, async: true

  alias Msfailab.LLM.ChatRequest
  alias Msfailab.LLM.Events
  alias Msfailab.LLM.Message
  alias Msfailab.LLM.Providers.Anthropic.Core
  alias Msfailab.Tools.Tool

  describe "init_state/2" do
    test "initializes state with required fields" do
      request_body = %{"model" => "claude-3-5-sonnet", "messages" => []}
      url = "https://api.anthropic.com/v1/messages"

      state = Core.init_state(request_body, url)

      assert state.request_body == request_body
      assert state.request_url == url
      assert state.buffer == ""
      assert state.raw_body == ""
      assert state.model == nil
      assert state.started == false
      assert state.input_tokens == 0
      assert state.output_tokens == 0
      assert state.cached_input_tokens == nil
      assert state.cache_creation_tokens == nil
      assert state.stop_reason == nil
      assert state.current_blocks == %{}
      assert state.block_index_map == %{}
      assert state.trace_blocks == []
      assert state.trace_metadata == nil
    end
  end

  describe "process_chunk/2 - message_start event" do
    test "emits stream started event" do
      state = Core.init_state(%{}, "https://api.anthropic.com/v1/messages")

      chunk = """
      event: message_start
      data: {"type":"message_start","message":{"id":"msg_123","model":"claude-3-5-sonnet","role":"assistant","content":[],"usage":{"input_tokens":10,"output_tokens":1}}}

      """

      {events, new_state} = Core.process_chunk(chunk, state)

      assert [%Events.StreamStarted{model: "claude-3-5-sonnet"}] = events
      assert new_state.started == true
      assert new_state.model == "claude-3-5-sonnet"
      assert new_state.input_tokens == 10
    end

    test "captures cache token counts from usage" do
      state = Core.init_state(%{}, "https://api.anthropic.com/v1/messages")

      chunk = """
      event: message_start
      data: {"type":"message_start","message":{"id":"msg_123","model":"claude-3-5-sonnet","role":"assistant","content":[],"usage":{"input_tokens":100,"output_tokens":1,"cache_read_input_tokens":80,"cache_creation_input_tokens":5}}}

      """

      {_events, new_state} = Core.process_chunk(chunk, state)

      assert new_state.cached_input_tokens == 80
      assert new_state.cache_creation_tokens == 5
    end
  end

  describe "process_chunk/2 - text content blocks" do
    test "emits content block start and delta events" do
      state = Core.init_state(%{}, "https://api.anthropic.com/v1/messages")
      state = %{state | started: true}

      chunk = """
      event: content_block_start
      data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

      event: content_block_delta
      data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}

      """

      {events, new_state} = Core.process_chunk(chunk, state)

      assert [
               %Events.ContentBlockStart{index: 0, type: :text},
               %Events.ContentDelta{index: 0, delta: "Hello"}
             ] = events

      assert new_state.current_blocks[0].text == "Hello"
    end

    test "accumulates text across multiple deltas" do
      state = Core.init_state(%{}, "https://api.anthropic.com/v1/messages")
      state = %{state | started: true}

      # First chunk - start block and first delta
      chunk1 = """
      event: content_block_start
      data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

      event: content_block_delta
      data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}

      """

      {_events1, state} = Core.process_chunk(chunk1, state)

      # Second chunk - more deltas
      chunk2 = """
      event: content_block_delta
      data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" world"}}

      """

      {events2, new_state} = Core.process_chunk(chunk2, state)

      assert [%Events.ContentDelta{index: 0, delta: " world"}] = events2
      assert new_state.current_blocks[0].text == "Hello world"
    end

    test "emits content block stop and adds to trace" do
      state = Core.init_state(%{}, "https://api.anthropic.com/v1/messages")
      state = %{state | started: true}

      chunk = """
      event: content_block_start
      data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

      event: content_block_delta
      data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}

      event: content_block_stop
      data: {"type":"content_block_stop","index":0}

      """

      {events, new_state} = Core.process_chunk(chunk, state)

      assert Enum.any?(events, &match?(%Events.ContentBlockStop{index: 0}, &1))
      assert new_state.trace_blocks == [{:text, "Hello"}]
    end
  end

  describe "process_chunk/2 - thinking blocks" do
    test "emits thinking block events with correct type" do
      state = Core.init_state(%{}, "https://api.anthropic.com/v1/messages")
      state = %{state | started: true}

      chunk = """
      event: content_block_start
      data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","text":""}}

      event: content_block_delta
      data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"Let me analyze"}}

      """

      {events, new_state} = Core.process_chunk(chunk, state)

      assert [
               %Events.ContentBlockStart{index: 0, type: :thinking},
               %Events.ContentDelta{index: 0, delta: "Let me analyze"}
             ] = events

      assert new_state.current_blocks[0].text == "Let me analyze"
    end

    test "adds thinking to trace on block stop" do
      state = Core.init_state(%{}, "https://api.anthropic.com/v1/messages")
      state = %{state | started: true}

      chunk = """
      event: content_block_start
      data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","text":""}}

      event: content_block_delta
      data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"Deep thoughts"}}

      event: content_block_stop
      data: {"type":"content_block_stop","index":0}

      """

      {_events, new_state} = Core.process_chunk(chunk, state)

      assert new_state.trace_blocks == [{:thinking, "Deep thoughts"}]
    end
  end

  describe "process_chunk/2 - tool use blocks" do
    test "emits tool call event on block stop" do
      state = Core.init_state(%{}, "https://api.anthropic.com/v1/messages")
      state = %{state | started: true}

      chunk = """
      event: content_block_start
      data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_123","name":"msf_command","input":{}}}

      event: content_block_delta
      data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\\"command\\""}}

      event: content_block_delta
      data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":":\\"search apache\\"}"}}

      event: content_block_stop
      data: {"type":"content_block_stop","index":0}

      """

      {events, new_state} = Core.process_chunk(chunk, state)

      tool_call = Enum.find(events, &match?(%Events.ToolCall{}, &1))
      assert tool_call.id == "toolu_123"
      assert tool_call.name == "msf_command"
      assert tool_call.arguments == %{"command" => "search apache"}

      assert [{:tool_use, %{id: "toolu_123", name: "msf_command"}}] = new_state.trace_blocks
    end

    test "handles complex nested JSON arguments" do
      state = Core.init_state(%{}, "https://api.anthropic.com/v1/messages")
      state = %{state | started: true}

      chunk = """
      event: content_block_start
      data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_nested","name":"complex","input":{}}}

      event: content_block_delta
      data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\\"options\\":{\\"verbose\\":true},\\"targets\\":[\\"192.168.1.1\\"]}"}}

      event: content_block_stop
      data: {"type":"content_block_stop","index":0}

      """

      {events, _state} = Core.process_chunk(chunk, state)

      tool_call = Enum.find(events, &match?(%Events.ToolCall{}, &1))

      assert tool_call.arguments == %{
               "options" => %{"verbose" => true},
               "targets" => ["192.168.1.1"]
             }
    end
  end

  describe "process_chunk/2 - message completion" do
    test "emits stream complete with usage and stop reason" do
      state = Core.init_state(%{}, "https://api.anthropic.com/v1/messages")
      state = %{state | started: true, input_tokens: 100}

      chunk = """
      event: message_delta
      data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":50}}

      event: message_stop
      data: {"type":"message_stop"}

      """

      {events, new_state} = Core.process_chunk(chunk, state)

      complete = Enum.find(events, &match?(%Events.StreamComplete{}, &1))
      assert complete.input_tokens == 100
      assert complete.output_tokens == 50
      assert complete.stop_reason == :end_turn

      assert new_state.trace_metadata.stop_reason == :end_turn
    end

    test "handles tool_use stop reason" do
      state = Core.init_state(%{}, "https://api.anthropic.com/v1/messages")
      state = %{state | started: true}

      chunk = """
      event: message_delta
      data: {"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":20}}

      event: message_stop
      data: {"type":"message_stop"}

      """

      {events, _state} = Core.process_chunk(chunk, state)

      complete = Enum.find(events, &match?(%Events.StreamComplete{}, &1))
      assert complete.stop_reason == :tool_use
    end

    test "handles max_tokens stop reason" do
      state = Core.init_state(%{}, "https://api.anthropic.com/v1/messages")
      state = %{state | started: true}

      chunk = """
      event: message_delta
      data: {"type":"message_delta","delta":{"stop_reason":"max_tokens"},"usage":{"output_tokens":100}}

      event: message_stop
      data: {"type":"message_stop"}

      """

      {events, _state} = Core.process_chunk(chunk, state)

      complete = Enum.find(events, &match?(%Events.StreamComplete{}, &1))
      assert complete.stop_reason == :max_tokens
    end
  end

  describe "process_chunk/2 - error handling" do
    test "emits stream error event for error events" do
      state = Core.init_state(%{}, "https://api.anthropic.com/v1/messages")

      chunk = """
      event: error
      data: {"type":"error","error":{"type":"rate_limit_error","message":"Rate limit exceeded"}}

      """

      {events, _state} = Core.process_chunk(chunk, state)

      assert [%Events.StreamError{reason: "Rate limit exceeded", recoverable: true}] = events
    end

    test "marks overloaded_error as recoverable" do
      state = Core.init_state(%{}, "https://api.anthropic.com/v1/messages")

      chunk = """
      event: error
      data: {"type":"error","error":{"type":"overloaded_error","message":"Server overloaded"}}

      """

      {events, _state} = Core.process_chunk(chunk, state)

      assert [%Events.StreamError{reason: "Server overloaded", recoverable: true}] = events
    end

    test "marks other errors as not recoverable" do
      state = Core.init_state(%{}, "https://api.anthropic.com/v1/messages")

      chunk = """
      event: error
      data: {"type":"error","error":{"type":"invalid_request_error","message":"Bad request"}}

      """

      {events, _state} = Core.process_chunk(chunk, state)

      assert [%Events.StreamError{reason: "Bad request", recoverable: false}] = events
    end

    test "ignores unknown event types" do
      state = Core.init_state(%{}, "https://api.anthropic.com/v1/messages")

      chunk = """
      event: unknown_event_type
      data: {"type":"unknown"}

      """

      {events, _state} = Core.process_chunk(chunk, state)

      assert events == []
    end

    test "handles malformed SSE events gracefully" do
      state = Core.init_state(%{}, "https://api.anthropic.com/v1/messages")

      chunk = """
      malformed line without event

      event: message_start
      data: {"type":"message_start","message":{"id":"msg_1","model":"claude-3-5-sonnet","usage":{"input_tokens":10}}}

      """

      {events, _state} = Core.process_chunk(chunk, state)

      # Should process valid event, skip malformed
      assert [%Events.StreamStarted{}] = events
    end

    test "handles content_block_delta with unknown block index" do
      state = Core.init_state(%{}, "https://api.anthropic.com/v1/messages")
      state = %{state | started: true}

      # Delta for index that doesn't have a started block
      chunk = """
      event: content_block_delta
      data: {"type":"content_block_delta","index":99,"delta":{"type":"text_delta","text":"orphan"}}

      """

      {events, _state} = Core.process_chunk(chunk, state)

      # Should return empty events, not crash
      assert events == []
    end
  end

  describe "process_chunk/2 - buffer handling" do
    test "handles partial SSE events across chunks" do
      state = Core.init_state(%{}, "https://api.anthropic.com/v1/messages")

      # Partial chunk (no double newline to complete event)
      partial = "event: message_start\ndata: {\"type\":\"message_start\",\"message\":"

      {events, state} = Core.process_chunk(partial, state)

      # No events yet, content is buffered
      assert events == []
      assert state.buffer == partial

      # Complete the event
      rest = """
      {"id":"msg_1","model":"claude-3-5-sonnet","usage":{"input_tokens":10}}}

      """

      {events2, _state} = Core.process_chunk(rest, state)

      assert [%Events.StreamStarted{model: "claude-3-5-sonnet"}] = events2
    end
  end

  describe "finalize_stream/1" do
    test "processes remaining buffer content" do
      state = Core.init_state(%{}, "https://api.anthropic.com/v1/messages")

      # Simulate buffered content without trailing double newline
      state = %{
        state
        | buffer:
            "event: message_start\ndata: {\"type\":\"message_start\",\"message\":{\"id\":\"msg_1\",\"model\":\"claude-3-5-sonnet\",\"usage\":{\"input_tokens\":10}}}"
      }

      {events, _new_state} = Core.finalize_stream(state)

      assert [%Events.StreamStarted{model: "claude-3-5-sonnet"}] = events
    end

    test "returns empty events for empty buffer" do
      state = Core.init_state(%{}, "https://api.anthropic.com/v1/messages")

      {events, new_state} = Core.finalize_stream(state)

      assert events == []
      assert new_state == state
    end
  end

  describe "build_request_body/1" do
    test "builds basic request with model and messages" do
      request = %ChatRequest{
        model: "claude-3-5-sonnet",
        messages: [Message.user("Hello")],
        max_tokens: 100,
        temperature: 0.5
      }

      body = Core.build_request_body(request)

      assert body["model"] == "claude-3-5-sonnet"
      assert body["stream"] == true
      assert body["max_tokens"] == 100
      assert body["temperature"] == 0.5
      assert length(body["messages"]) == 1
    end

    test "includes system prompt as separate field" do
      request = %ChatRequest{
        model: "claude-3-5-sonnet",
        messages: [Message.user("Hello")],
        system_prompt: "You are helpful"
      }

      body = Core.build_request_body(request)

      assert body["system"] == "You are helpful"
      # System should NOT be in messages
      refute Enum.any?(body["messages"], &(&1["role"] == "system"))
    end

    test "excludes system field when prompt is empty" do
      request = %ChatRequest{
        model: "claude-3-5-sonnet",
        messages: [Message.user("Hello")],
        system_prompt: ""
      }

      body = Core.build_request_body(request)

      refute Map.has_key?(body, "system")
    end

    test "includes tools when provided" do
      request = %ChatRequest{
        model: "claude-3-5-sonnet",
        messages: [Message.user("Hello")],
        tools: [
          %Tool{
            name: "search",
            short_title: "Searching",
            description: "Search for exploits",
            parameters: %{"type" => "object"}
          }
        ]
      }

      body = Core.build_request_body(request)

      assert length(body["tools"]) == 1
      tool = hd(body["tools"])
      assert tool["name"] == "search"
      assert tool["input_schema"]["type"] == "object"
    end
  end

  describe "transform_message/1" do
    test "transforms user message to content blocks" do
      message = Message.user("Hello world")

      [transformed] = Core.transform_message(message)

      assert transformed["role"] == "user"
      assert [%{"type" => "text", "text" => "Hello world"}] = transformed["content"]
    end

    test "transforms assistant message with tool calls" do
      message = %Message{
        role: :assistant,
        content: [
          %{type: :text, text: "Let me search"},
          %{type: :tool_call, id: "call_1", name: "search", arguments: %{"q" => "test"}}
        ]
      }

      [transformed] = Core.transform_message(message)

      assert transformed["role"] == "assistant"
      assert length(transformed["content"]) == 2

      text_block = Enum.find(transformed["content"], &(&1["type"] == "text"))
      assert text_block["text"] == "Let me search"

      tool_block = Enum.find(transformed["content"], &(&1["type"] == "tool_use"))
      assert tool_block["id"] == "call_1"
      assert tool_block["name"] == "search"
      assert tool_block["input"] == %{"q" => "test"}
    end

    test "transforms tool result as user message with tool_result block" do
      message = Message.tool_result("call_1", "Result data", false)

      [transformed] = Core.transform_message(message)

      assert transformed["role"] == "user"
      [block] = transformed["content"]
      assert block["type"] == "tool_result"
      assert block["tool_use_id"] == "call_1"
      assert block["content"] == "Result data"
      refute Map.has_key?(block, "is_error")
    end

    test "includes is_error flag in tool results when true" do
      message = Message.tool_result("call_1", "Command failed", true)

      [transformed] = Core.transform_message(message)

      [block] = transformed["content"]
      assert block["is_error"] == true
    end

    test "returns empty list for tool message with no tool results" do
      message = %Message{role: :tool, content: [%{type: :text, text: "ignored"}]}

      result = Core.transform_message(message)

      assert result == []
    end
  end

  describe "transform_tools/1" do
    test "transforms tools to Anthropic format with input_schema" do
      tools = [
        %Tool{
          name: "msf_command",
          short_title: "Running MSF command",
          description: "Execute MSF command",
          parameters: %{"type" => "object", "properties" => %{}}
        }
      ]

      [transformed] = Core.transform_tools(tools)

      assert transformed["name"] == "msf_command"
      assert transformed["description"] == "Execute MSF command"
      assert transformed["input_schema"]["type"] == "object"
    end

    test "includes cache_control when tool is cacheable (default)" do
      tools = [
        %Tool{
          name: "search",
          short_title: "Searching",
          description: "Search",
          parameters: %{"type" => "object"}
        }
      ]

      [transformed] = Core.transform_tools(tools)

      assert transformed["cache_control"] == %{"type" => "ephemeral"}
    end

    test "excludes cache_control when tool is not cacheable" do
      tools = [
        %Tool{
          name: "search",
          short_title: "Searching",
          description: "Search",
          parameters: %{"type" => "object"},
          cacheable: false
        }
      ]

      [transformed] = Core.transform_tools(tools)

      refute Map.has_key?(transformed, "cache_control")
    end
  end

  describe "map_anthropic_block_type/1" do
    test "maps text to :text" do
      assert Core.map_anthropic_block_type("text") == :text
    end

    test "maps thinking to :thinking" do
      assert Core.map_anthropic_block_type("thinking") == :thinking
    end

    test "maps tool_use to :tool_call" do
      assert Core.map_anthropic_block_type("tool_use") == :tool_call
    end

    test "defaults unknown types to :text" do
      assert Core.map_anthropic_block_type("unknown") == :text
      assert Core.map_anthropic_block_type("") == :text
    end
  end

  describe "map_stop_reason/1" do
    test "maps end_turn" do
      assert Core.map_stop_reason("end_turn") == :end_turn
    end

    test "maps tool_use" do
      assert Core.map_stop_reason("tool_use") == :tool_use
    end

    test "maps max_tokens" do
      assert Core.map_stop_reason("max_tokens") == :max_tokens
    end

    test "defaults to :end_turn for unknown reasons" do
      assert Core.map_stop_reason("unknown") == :end_turn
      assert Core.map_stop_reason(nil) == :end_turn
    end
  end

  describe "parse_tool_arguments/1" do
    test "parses valid JSON" do
      assert Core.parse_tool_arguments(~s({"key":"value"})) == %{"key" => "value"}
    end

    test "handles nested JSON" do
      input = ~s({"options":{"verbose":true},"targets":["a","b"]})
      expected = %{"options" => %{"verbose" => true}, "targets" => ["a", "b"]}
      assert Core.parse_tool_arguments(input) == expected
    end

    test "returns empty map for invalid JSON" do
      assert Core.parse_tool_arguments("not json") == %{}
    end

    test "returns empty map for empty string" do
      assert Core.parse_tool_arguments("") == %{}
    end

    test "returns empty map for nil" do
      assert Core.parse_tool_arguments(nil) == %{}
    end
  end

  describe "format_trace_response/2" do
    test "formats successful response with all content block types" do
      state = %{
        trace_blocks: [
          {:thinking, "Let me analyze this request."},
          {:text, "Here is my response."},
          {:tool_use, %{id: "toolu_123", name: "search", arguments: %{"query" => "test"}}}
        ],
        trace_metadata: %{
          input_tokens: 100,
          output_tokens: 50,
          cached_input_tokens: 25,
          stop_reason: :tool_use
        }
      }

      result = Core.format_trace_response(state, 200)

      assert result =~ "--- CONTENT BLOCK 0 (thinking) ---"
      assert result =~ "Let me analyze this request."
      assert result =~ "--- CONTENT BLOCK 1 (text) ---"
      assert result =~ "Here is my response."
      assert result =~ "--- CONTENT BLOCK 2 (tool_use) ---"
      assert result =~ "toolu_123"
      assert result =~ "--- METADATA ---"
      assert result =~ "\"input_tokens\": 100"
    end

    test "formats response with only text block" do
      state = %{
        trace_blocks: [{:text, "Simple response."}],
        trace_metadata: %{stop_reason: :end_turn}
      }

      result = Core.format_trace_response(state, 200)

      assert result =~ "--- CONTENT BLOCK 0 (text) ---"
      assert result =~ "Simple response."
      refute result =~ "(tool_use)"
      refute result =~ "(thinking)"
    end

    test "formats empty response" do
      state = %{
        trace_blocks: [],
        trace_metadata: nil
      }

      result = Core.format_trace_response(state, 200)

      assert result == "(empty response)"
    end

    test "formats error response with raw body" do
      state = %{
        raw_body: ~s({"error": {"type": "rate_limit_error", "message": "Too many requests"}})
      }

      result = Core.format_trace_response(state, 429)

      assert result =~ "--- ERROR RESPONSE ---"
      assert result =~ "rate_limit_error"
      assert result =~ "Too many requests"
    end

    test "formats error response with non-JSON body" do
      state = %{raw_body: "Internal server error"}

      result = Core.format_trace_response(state, 500)

      assert result =~ "--- ERROR RESPONSE ---"
      assert result =~ "Internal server error"
    end

    test "formats empty error response" do
      state = %{raw_body: ""}

      result = Core.format_trace_response(state, 500)

      assert result == "(empty error response)"
    end
  end

  describe "extract_error_message/2" do
    test "extracts error from nested map body" do
      body = %{"error" => %{"message" => "Model not found"}}

      assert Core.extract_error_message(body, 404) == "Model not found"
    end

    test "extracts error from JSON string body" do
      body = ~s({"error": {"message": "Rate limited"}})

      assert Core.extract_error_message(body, 429) == "Rate limited"
    end

    test "extracts error from buffer in state" do
      state = %{buffer: ~s({"error": {"message": "Connection closed"}})}

      assert Core.extract_error_message(state, 500) == "Connection closed"
    end

    test "returns HTTP status when no error found" do
      assert Core.extract_error_message(%{}, 503) == "HTTP 503"
      assert Core.extract_error_message("invalid json", 500) == "HTTP 500"
    end
  end

  describe "recoverable_error?/1" do
    test "returns true for transport errors" do
      assert Core.recoverable_error?(%Req.TransportError{reason: :timeout})
      assert Core.recoverable_error?(%Mint.TransportError{reason: :closed})
    end

    test "returns false for other errors" do
      refute Core.recoverable_error?(%RuntimeError{message: "test"})
      refute Core.recoverable_error?("string error")
      refute Core.recoverable_error?(nil)
    end
  end

  describe "comprehensive integration - full response with all content block types" do
    test "processes complete stream with thinking, text, and tool calls" do
      state = Core.init_state(%{}, "https://api.anthropic.com/v1/messages")

      # Full SSE stream
      stream = """
      event: message_start
      data: {"type":"message_start","message":{"id":"msg_01","model":"claude-sonnet-4-5","role":"assistant","content":[],"usage":{"input_tokens":100,"output_tokens":1}}}

      event: content_block_start
      data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}

      event: content_block_delta
      data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"Let me analyze"}}

      event: content_block_stop
      data: {"type":"content_block_stop","index":0}

      event: content_block_start
      data: {"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}

      event: content_block_delta
      data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"I'll search for you."}}

      event: content_block_stop
      data: {"type":"content_block_stop","index":1}

      event: content_block_start
      data: {"type":"content_block_start","index":2,"content_block":{"type":"tool_use","id":"toolu_01","name":"search","input":{}}}

      event: content_block_delta
      data: {"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":"{\\"query\\":\\"apache\\"}"}}

      event: content_block_stop
      data: {"type":"content_block_stop","index":2}

      event: message_delta
      data: {"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":50}}

      event: message_stop
      data: {"type":"message_stop"}

      """

      {events, final_state} = Core.process_chunk(stream, state)

      # Verify event sequence
      assert %Events.StreamStarted{model: "claude-sonnet-4-5"} = Enum.at(events, 0)
      assert %Events.ContentBlockStart{index: 0, type: :thinking} = Enum.at(events, 1)
      assert %Events.ContentDelta{index: 0, delta: "Let me analyze"} = Enum.at(events, 2)
      assert %Events.ContentBlockStop{index: 0} = Enum.at(events, 3)
      assert %Events.ContentBlockStart{index: 1, type: :text} = Enum.at(events, 4)
      assert %Events.ContentDelta{index: 1, delta: "I'll search for you."} = Enum.at(events, 5)
      assert %Events.ContentBlockStop{index: 1} = Enum.at(events, 6)
      assert %Events.ContentBlockStart{index: 2, type: :tool_call} = Enum.at(events, 7)
      assert %Events.ToolCall{index: 2, id: "toolu_01", name: "search"} = Enum.at(events, 8)
      assert %Events.ContentBlockStop{index: 2} = Enum.at(events, 9)

      complete = Enum.find(events, &match?(%Events.StreamComplete{}, &1))
      assert complete.input_tokens == 100
      assert complete.output_tokens == 50
      assert complete.stop_reason == :tool_use

      # Verify trace state
      assert length(final_state.trace_blocks) == 3
      assert {:thinking, "Let me analyze"} = Enum.at(final_state.trace_blocks, 0)
      assert {:text, "I'll search for you."} = Enum.at(final_state.trace_blocks, 1)
      assert {:tool_use, %{id: "toolu_01", name: "search"}} = Enum.at(final_state.trace_blocks, 2)
    end
  end
end
