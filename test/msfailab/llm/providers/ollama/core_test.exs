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

defmodule Msfailab.LLM.Providers.Ollama.CoreTest do
  @moduledoc """
  Unit tests for the Ollama provider Core module.

  These tests cover pure functions for stream processing, message transformation,
  and state management without requiring HTTP mocks.
  """

  use ExUnit.Case, async: true

  alias Msfailab.LLM.ChatRequest
  alias Msfailab.LLM.Events
  alias Msfailab.LLM.Message
  alias Msfailab.LLM.Providers.Ollama.Core
  alias Msfailab.Tools.Tool

  describe "init_state/2" do
    test "initializes state with required fields" do
      request_body = %{"model" => "llama3.1", "messages" => []}
      url = "http://localhost:11434/api/chat"

      state = Core.init_state(request_body, url)

      assert state.request_body == request_body
      assert state.request_url == url
      assert state.buffer == ""
      assert state.raw_body == ""
      assert state.started == false
      assert state.block_index == 0
      assert state.thinking_block_started == false
      assert state.text_block_started == false
      assert state.trace_thinking == ""
      assert state.trace_content == ""
      assert state.trace_tool_calls == []
      assert state.trace_metadata == nil
    end
  end

  describe "process_chunk/2 - basic text streaming" do
    test "emits stream started and text content events" do
      state = Core.init_state(%{}, "http://localhost/api/chat")

      chunk =
        ~s({"model":"llama3.1","message":{"role":"assistant","content":"Hello"},"done":false}\n)

      {events, new_state} = Core.process_chunk(chunk, state)

      assert [
               %Events.StreamStarted{model: "llama3.1"},
               %Events.ContentBlockStart{index: 0, type: :text},
               %Events.ContentDelta{index: 0, delta: "Hello"}
             ] = events

      assert new_state.started == true
      assert new_state.text_block_started == true
      assert new_state.trace_content == "Hello"
    end

    test "accumulates text content across chunks" do
      state = Core.init_state(%{}, "http://localhost/api/chat")

      # First chunk
      chunk1 =
        ~s({"model":"llama3.1","message":{"role":"assistant","content":"Hello"},"done":false}\n)

      {_events1, state} = Core.process_chunk(chunk1, state)

      # Second chunk
      chunk2 =
        ~s({"model":"llama3.1","message":{"role":"assistant","content":" world"},"done":false}\n)

      {events2, new_state} = Core.process_chunk(chunk2, state)

      # Should only emit delta, no new block start
      assert [%Events.ContentDelta{index: 0, delta: " world"}] = events2
      assert new_state.trace_content == "Hello world"
    end

    test "emits stream complete on done=true" do
      state = Core.init_state(%{}, "http://localhost/api/chat")

      chunk =
        ~s({"model":"llama3.1","message":{"role":"assistant","content":"Hi"},"done":true,"done_reason":"stop","prompt_eval_count":10,"eval_count":5}\n)

      {events, new_state} = Core.process_chunk(chunk, state)

      assert [
               %Events.StreamStarted{},
               %Events.ContentBlockStart{type: :text},
               %Events.ContentDelta{delta: "Hi"},
               %Events.ContentBlockStop{index: 0},
               %Events.StreamComplete{
                 input_tokens: 10,
                 output_tokens: 5,
                 stop_reason: :end_turn
               }
             ] = events

      assert new_state.trace_metadata.stop_reason == :end_turn
    end
  end

  describe "process_chunk/2 - thinking blocks" do
    test "emits thinking block events" do
      state = Core.init_state(%{}, "http://localhost/api/chat")

      chunk =
        ~s({"model":"qwen3:30b","message":{"role":"assistant","thinking":"Let me think"},"done":false}\n)

      {events, new_state} = Core.process_chunk(chunk, state)

      assert [
               %Events.StreamStarted{model: "qwen3:30b"},
               %Events.ContentBlockStart{index: 0, type: :thinking},
               %Events.ContentDelta{index: 0, delta: "Let me think"}
             ] = events

      assert new_state.thinking_block_started == true
      assert new_state.trace_thinking == "Let me think"
    end

    test "closes thinking block when content arrives" do
      state = Core.init_state(%{}, "http://localhost/api/chat")

      # First: thinking
      chunk1 =
        ~s({"model":"qwen3:30b","message":{"role":"assistant","thinking":"Thinking..."},"done":false}\n)

      {_events1, state} = Core.process_chunk(chunk1, state)

      # Second: content arrives, should close thinking
      chunk2 =
        ~s({"model":"qwen3:30b","message":{"role":"assistant","content":"Answer"},"done":false}\n)

      {events2, new_state} = Core.process_chunk(chunk2, state)

      assert [
               %Events.ContentBlockStop{index: 0},
               %Events.ContentBlockStart{index: 1, type: :text},
               %Events.ContentDelta{index: 1, delta: "Answer"}
             ] = events2

      assert new_state.thinking_block_started == false
      assert new_state.text_block_started == true
      assert new_state.block_index == 1
    end
  end

  describe "process_chunk/2 - tool calls" do
    test "emits tool call events on done=true" do
      state = Core.init_state(%{}, "http://localhost/api/chat")

      chunk =
        ~s({"model":"llama3.1","message":{"role":"assistant","content":"","tool_calls":[{"function":{"name":"msf_command","arguments":{"command":"search apache"}}}]},"done":true,"done_reason":"stop"}\n)

      {events, new_state} = Core.process_chunk(chunk, state)

      # Find the tool call event
      tool_call_event = Enum.find(events, &match?(%Events.ToolCall{}, &1))
      assert tool_call_event.name == "msf_command"
      assert tool_call_event.arguments == %{"command" => "search apache"}

      # Verify stop reason
      complete_event = Enum.find(events, &match?(%Events.StreamComplete{}, &1))
      assert complete_event.stop_reason == :tool_use

      # Verify tracing
      assert length(new_state.trace_tool_calls) == 1
    end

    test "handles multiple tool calls" do
      state = Core.init_state(%{}, "http://localhost/api/chat")

      chunk =
        ~s({"model":"llama3.1","message":{"role":"assistant","content":"","tool_calls":[{"id":"call_1","function":{"name":"tool_a","arguments":{"x":1}}},{"id":"call_2","function":{"name":"tool_b","arguments":{"y":2}}}]},"done":true,"done_reason":"stop"}\n)

      {events, new_state} = Core.process_chunk(chunk, state)

      tool_calls = Enum.filter(events, &match?(%Events.ToolCall{}, &1))
      assert length(tool_calls) == 2
      assert Enum.at(tool_calls, 0).name == "tool_a"
      assert Enum.at(tool_calls, 1).name == "tool_b"

      assert length(new_state.trace_tool_calls) == 2
    end

    test "generates tool call ID when not provided" do
      state = Core.init_state(%{}, "http://localhost/api/chat")

      # Tool call without id
      chunk =
        ~s({"model":"llama3.1","message":{"role":"assistant","content":"","tool_calls":[{"function":{"name":"test","arguments":{}}}]},"done":true,"done_reason":"stop"}\n)

      {events, _state} = Core.process_chunk(chunk, state)

      tool_call_event = Enum.find(events, &match?(%Events.ToolCall{}, &1))
      assert tool_call_event.id =~ ~r/^call_[a-f0-9]+$/
    end
  end

  describe "process_chunk/2 - buffer handling" do
    test "handles partial JSON lines" do
      state = Core.init_state(%{}, "http://localhost/api/chat")

      # Partial chunk (no newline)
      partial = ~s({"model":"llama3.1","message":{"role":"assistant","content":"Hel)

      {events, state} = Core.process_chunk(partial, state)

      # No events yet, content is buffered
      assert events == []
      assert state.buffer == partial

      # Complete the line
      rest = ~s(lo"},"done":false}\n)
      {events2, _state} = Core.process_chunk(rest, state)

      assert [
               %Events.StreamStarted{},
               %Events.ContentBlockStart{type: :text},
               %Events.ContentDelta{delta: "Hello"}
             ] = events2
    end

    test "handles malformed JSON gracefully" do
      state = Core.init_state(%{}, "http://localhost/api/chat")

      chunk =
        "not valid json\n{\"model\":\"llama3.1\",\"message\":{\"role\":\"assistant\",\"content\":\"Hi\"},\"done\":true,\"done_reason\":\"stop\"}\n"

      {events, _state} = Core.process_chunk(chunk, state)

      # Should skip malformed line and process valid one
      assert Enum.any?(events, &match?(%Events.StreamStarted{}, &1))
      assert Enum.any?(events, &match?(%Events.StreamComplete{}, &1))
    end
  end

  describe "finalize_stream/1" do
    test "processes remaining buffer content" do
      state = Core.init_state(%{}, "http://localhost/api/chat")

      # Simulate buffered content without trailing newline
      state = %{
        state
        | buffer:
            ~s({"model":"llama3.1","message":{"role":"assistant","content":"Final"},"done":true,"done_reason":"stop"})
      }

      {events, _new_state} = Core.finalize_stream(state)

      assert Enum.any?(events, &match?(%Events.StreamStarted{}, &1))
      assert Enum.any?(events, &match?(%Events.StreamComplete{}, &1))
    end

    test "returns empty events for empty buffer" do
      state = Core.init_state(%{}, "http://localhost/api/chat")

      {events, new_state} = Core.finalize_stream(state)

      assert events == []
      assert new_state == state
    end
  end

  describe "build_request_body/2" do
    test "builds basic request with model and messages" do
      request = %ChatRequest{
        model: "llama3.1",
        messages: [Message.user("Hello")],
        max_tokens: 100,
        temperature: 0.5
      }

      body = Core.build_request_body(request, true)

      assert body["model"] == "llama3.1"
      assert body["stream"] == true
      assert body["think"] == true
      assert body["options"]["temperature"] == 0.5
      assert body["options"]["num_predict"] == 100
      assert length(body["messages"]) == 1
    end

    test "includes system prompt when provided" do
      request = %ChatRequest{
        model: "llama3.1",
        messages: [Message.user("Hello")],
        system_prompt: "You are helpful"
      }

      body = Core.build_request_body(request, true)

      system_msg = Enum.find(body["messages"], &(&1["role"] == "system"))
      assert system_msg["content"] == "You are helpful"
    end

    test "excludes system message when prompt is empty" do
      request = %ChatRequest{
        model: "llama3.1",
        messages: [Message.user("Hello")],
        system_prompt: ""
      }

      body = Core.build_request_body(request, true)

      refute Enum.any?(body["messages"], &(&1["role"] == "system"))
    end

    test "includes tools when provided" do
      request = %ChatRequest{
        model: "llama3.1",
        messages: [Message.user("Hello")],
        tools: [
          %Tool{
            name: "search",
            description: "Search for exploits",
            parameters: %{"type" => "object"}
          }
        ]
      }

      body = Core.build_request_body(request, true)

      assert length(body["tools"]) == 1
      tool = hd(body["tools"])
      assert tool["type"] == "function"
      assert tool["function"]["name"] == "search"
    end

    test "includes cache context when provided" do
      request = %ChatRequest{
        model: "llama3.1",
        messages: [Message.user("Hello")],
        cache_context: [1, 2, 3, 4, 5]
      }

      body = Core.build_request_body(request, true)

      assert body["context"] == [1, 2, 3, 4, 5]
    end

    test "sets think based on parameter" do
      request = %ChatRequest{
        model: "llama3.1",
        messages: [Message.user("Hello")]
      }

      body_with_thinking = Core.build_request_body(request, true)
      body_without_thinking = Core.build_request_body(request, false)

      assert body_with_thinking["think"] == true
      assert body_without_thinking["think"] == false
    end
  end

  describe "transform_message/1" do
    test "transforms user message" do
      message = Message.user("Hello world")

      [transformed] = Core.transform_message(message)

      assert transformed["role"] == "user"
      assert transformed["content"] == "Hello world"
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
      assert transformed["content"] == "Let me search"
      assert length(transformed["tool_calls"]) == 1
      assert hd(transformed["tool_calls"])["function"]["name"] == "search"
    end

    test "transforms tool result message" do
      message = Message.tool_result("call_1", "Result data", false)

      [transformed] = Core.transform_message(message)

      assert transformed["role"] == "tool"
      assert transformed["content"] == "Result data"
    end
  end

  describe "transform_tools/1" do
    test "transforms tools to OpenAI-compatible format" do
      tools = [
        %Tool{
          name: "msf_command",
          description: "Execute MSF command",
          parameters: %{"type" => "object", "properties" => %{}}
        }
      ]

      [transformed] = Core.transform_tools(tools)

      assert transformed["type"] == "function"
      assert transformed["function"]["name"] == "msf_command"
      assert transformed["function"]["description"] == "Execute MSF command"
      assert transformed["function"]["parameters"]["type"] == "object"
    end
  end

  describe "extract_context_window/2" do
    test "extracts llama context length" do
      body = %{"model_info" => %{"llama.context_length" => 131_072}}

      assert Core.extract_context_window(body, "llama3.1") == 131_072
    end

    test "extracts qwen2 context length" do
      body = %{"model_info" => %{"qwen2.context_length" => 32_768}}

      assert Core.extract_context_window(body, "qwen2:7b") == 32_768
    end

    test "extracts gemma2 context length" do
      body = %{"model_info" => %{"gemma2.context_length" => 8192}}

      assert Core.extract_context_window(body, "gemma2:2b") == 8192
    end

    test "extracts from parameters string" do
      body = %{"parameters" => "num_ctx 4096\ntemperature 0.7"}

      assert Core.extract_context_window(body, "custom") == 4096
    end

    test "returns default when not found" do
      body = %{"model_info" => %{"general.architecture" => "unknown"}}

      assert Core.extract_context_window(body, "unknown-model") == 200_000
    end
  end

  describe "map_stop_reason/2" do
    test "returns :tool_use when tool calls were processed" do
      state = %{tool_calls_processed: true}

      assert Core.map_stop_reason("stop", state) == :tool_use
    end

    test "returns :max_tokens for length done_reason" do
      state = %{tool_calls_processed: false}

      assert Core.map_stop_reason("length", state) == :max_tokens
    end

    test "returns :end_turn for other reasons" do
      state = %{tool_calls_processed: false}

      assert Core.map_stop_reason("stop", state) == :end_turn
      assert Core.map_stop_reason(nil, state) == :end_turn
    end
  end

  describe "format_trace_response/2" do
    test "formats successful response with all sections" do
      state = %{
        trace_thinking: "Let me think...",
        trace_content: "Here is the answer.",
        trace_tool_calls: [
          %{id: "call_2", name: "tool_b", arguments: %{}},
          %{id: "call_1", name: "tool_a", arguments: %{}}
        ],
        trace_metadata: %{input_tokens: 100, output_tokens: 50, stop_reason: :tool_use}
      }

      result = Core.format_trace_response(state, 200)

      assert result =~ "--- THINKING ---"
      assert result =~ "Let me think..."
      assert result =~ "--- CONTENT ---"
      assert result =~ "Here is the answer."
      assert result =~ "--- TOOL_CALLS ---"
      assert result =~ "tool_a"
      assert result =~ "--- METADATA ---"
      assert result =~ "input_tokens"
    end

    test "formats empty response" do
      state = %{
        trace_thinking: "",
        trace_content: "",
        trace_tool_calls: [],
        trace_metadata: nil
      }

      result = Core.format_trace_response(state, 200)

      assert result == "(empty response)"
    end

    test "formats error response" do
      state = %{raw_body: ~s({"error": "model not found"})}

      result = Core.format_trace_response(state, 404)

      assert result =~ "--- ERROR RESPONSE ---"
      assert result =~ "model not found"
    end
  end

  describe "extract_error_message/2" do
    test "extracts error from map body" do
      body = %{"error" => "Model not found"}

      assert Core.extract_error_message(body, 404) == "Model not found"
    end

    test "extracts error from JSON string body" do
      body = ~s({"error": "Rate limited"})

      assert Core.extract_error_message(body, 429) == "Rate limited"
    end

    test "extracts error from buffer in state" do
      state = %{buffer: ~s({"error": "Connection closed"})}

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

  describe "generate_tool_call_id/0" do
    test "generates unique IDs with correct format" do
      id1 = Core.generate_tool_call_id()
      id2 = Core.generate_tool_call_id()

      assert id1 =~ ~r/^call_[a-f0-9]{24}$/
      assert id2 =~ ~r/^call_[a-f0-9]{24}$/
      assert id1 != id2
    end
  end
end
