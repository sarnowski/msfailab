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

defmodule Msfailab.LLM.Providers.AnthropicTest do
  use ExUnit.Case, async: true

  alias Msfailab.LLM.ChatRequest
  alias Msfailab.LLM.Events
  alias Msfailab.LLM.Message
  alias Msfailab.LLM.Model
  alias Msfailab.LLM.Providers.Anthropic
  alias Msfailab.Tools.Tool

  describe "configured?/0" do
    test "returns true when MSFAILAB_ANTHROPIC_API_KEY is set" do
      System.put_env("MSFAILAB_ANTHROPIC_API_KEY", "sk-ant-test-key")
      assert Anthropic.configured?()
      System.delete_env("MSFAILAB_ANTHROPIC_API_KEY")
    end

    test "returns false when MSFAILAB_ANTHROPIC_API_KEY is not set" do
      System.delete_env("MSFAILAB_ANTHROPIC_API_KEY")
      refute Anthropic.configured?()
    end

    test "returns false when MSFAILAB_ANTHROPIC_API_KEY is empty string" do
      System.put_env("MSFAILAB_ANTHROPIC_API_KEY", "")
      refute Anthropic.configured?()
      System.delete_env("MSFAILAB_ANTHROPIC_API_KEY")
    end
  end

  describe "list_models/1 with mocked HTTP" do
    setup do
      System.put_env("MSFAILAB_ANTHROPIC_API_KEY", "sk-ant-test-key")
      # Use wildcard filter for tests to pass all models through
      System.put_env("MSFAILAB_ANTHROPIC_MODEL_FILTER", "*")

      on_exit(fn ->
        System.delete_env("MSFAILAB_ANTHROPIC_API_KEY")
        System.delete_env("MSFAILAB_ANTHROPIC_MODEL_FILTER")
      end)

      :ok
    end

    test "returns filtered models with context windows" do
      req_opts = [
        plug: fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(
            200,
            Jason.encode!(%{
              "data" => [
                %{"id" => "claude-3-5-sonnet-20241022", "type" => "model"},
                %{"id" => "claude-3-opus-20240229", "type" => "model"},
                %{"id" => "claude-3-haiku-20240307", "type" => "model"}
              ]
            })
          )
        end
      ]

      assert {:ok, models} = Anthropic.list_models(req_opts)

      assert length(models) == 3

      model_names = Enum.map(models, & &1.name)
      assert "claude-3-5-sonnet-20241022" in model_names
      assert "claude-3-opus-20240229" in model_names
      assert "claude-3-haiku-20240307" in model_names
    end

    test "filters out non-model types" do
      req_opts = [
        plug: fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(
            200,
            Jason.encode!(%{
              "data" => [
                %{"id" => "claude-3-5-sonnet-20241022", "type" => "model"},
                %{"id" => "some-other-thing", "type" => "not-a-model"}
              ]
            })
          )
        end
      ]

      assert {:ok, models} = Anthropic.list_models(req_opts)
      assert length(models) == 1
      assert hd(models).name == "claude-3-5-sonnet-20241022"
    end

    test "filters out non-claude models" do
      req_opts = [
        plug: fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(
            200,
            Jason.encode!(%{
              "data" => [
                %{"id" => "claude-3-5-sonnet-20241022", "type" => "model"},
                %{"id" => "other-model", "type" => "model"}
              ]
            })
          )
        end
      ]

      assert {:ok, models} = Anthropic.list_models(req_opts)
      assert length(models) == 1
      assert hd(models).name == "claude-3-5-sonnet-20241022"
    end

    test "maps known models to correct context windows" do
      req_opts = [
        plug: fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(
            200,
            Jason.encode!(%{
              "data" => [
                %{"id" => "claude-3-5-sonnet-20241022", "type" => "model"},
                %{"id" => "claude-3-opus-20240229", "type" => "model"}
              ]
            })
          )
        end
      ]

      assert {:ok, models} = Anthropic.list_models(req_opts)

      sonnet = Enum.find(models, &(&1.name == "claude-3-5-sonnet-20241022"))
      assert %Model{provider: :anthropic, context_window: 200_000} = sonnet

      opus = Enum.find(models, &(&1.name == "claude-3-opus-20240229"))
      assert %Model{provider: :anthropic, context_window: 200_000} = opus
    end

    test "uses default context window for unknown claude models" do
      req_opts = [
        plug: fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(
            200,
            Jason.encode!(%{
              "data" => [%{"id" => "claude-4-future-model", "type" => "model"}]
            })
          )
        end
      ]

      assert {:ok, [model]} = Anthropic.list_models(req_opts)
      # Should use default 200k context window
      assert model.context_window == 200_000
    end

    test "returns error on invalid API key" do
      req_opts = [
        plug: fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(401, Jason.encode!(%{"error" => "Invalid API key"}))
        end
      ]

      assert {:error, :invalid_api_key} = Anthropic.list_models(req_opts)
    end

    test "returns error on unexpected status" do
      req_opts = [
        plug: fn conn ->
          Plug.Conn.send_resp(conn, 500, "Internal Server Error")
        end
      ]

      assert {:error, {:unexpected_status, 500}} = Anthropic.list_models(req_opts)
    end

    test "returns empty list when no supported models" do
      req_opts = [
        plug: fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(
            200,
            Jason.encode!(%{
              "data" => [
                %{"id" => "some-non-claude-model", "type" => "model"}
              ]
            })
          )
        end
      ]

      assert {:ok, []} = Anthropic.list_models(req_opts)
    end
  end

  describe "run_chat_stream/4 - basic streaming" do
    setup do
      System.put_env("MSFAILAB_ANTHROPIC_API_KEY", "sk-ant-test-key")

      on_exit(fn ->
        System.delete_env("MSFAILAB_ANTHROPIC_API_KEY")
      end)

      :ok
    end

    test "streams text response with proper events" do
      ref = make_ref()
      caller = self()

      stream_response =
        [
          "event: message_start",
          ~s(data: {"type":"message_start","message":{"id":"msg_123","model":"claude-3-5-sonnet","role":"assistant","content":[],"usage":{"input_tokens":10,"output_tokens":1}}}),
          "",
          "event: content_block_start",
          ~s(data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}),
          "",
          "event: content_block_delta",
          ~s(data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}),
          "",
          "event: content_block_delta",
          ~s(data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" world"}}),
          "",
          "event: content_block_stop",
          ~s(data: {"type":"content_block_stop","index":0}),
          "",
          "event: message_delta",
          ~s(data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":5}}),
          "",
          "event: message_stop",
          ~s(data: {"type":"message_stop"})
        ]
        |> Enum.join("\n")

      req_opts = [
        plug: fn conn ->
          assert conn.request_path == "/v1/messages"

          conn
          |> Plug.Conn.put_resp_content_type("text/event-stream")
          |> Plug.Conn.send_resp(200, stream_response)
        end
      ]

      request = %ChatRequest{
        model: "claude-3-5-sonnet",
        messages: [Message.user("Hi")],
        max_tokens: 100,
        temperature: 0.1
      }

      Anthropic.run_chat_stream(request, caller, ref, req_opts)

      assert_receive {:llm, ^ref, %Events.StreamStarted{model: "claude-3-5-sonnet"}}, 1000
      assert_receive {:llm, ^ref, %Events.ContentBlockStart{index: 0, type: :text}}, 1000
      assert_receive {:llm, ^ref, %Events.ContentDelta{index: 0, delta: "Hello"}}, 1000
      assert_receive {:llm, ^ref, %Events.ContentDelta{index: 0, delta: " world"}}, 1000
      assert_receive {:llm, ^ref, %Events.ContentBlockStop{index: 0}}, 1000

      assert_receive {:llm, ^ref,
                      %Events.StreamComplete{
                        input_tokens: 10,
                        output_tokens: 5,
                        stop_reason: :end_turn
                      }},
                     1000
    end

    test "handles tool use response with streamed input" do
      ref = make_ref()
      caller = self()

      stream_response =
        [
          "event: message_start",
          ~s(data: {"type":"message_start","message":{"id":"msg_123","model":"claude-3-5-sonnet","role":"assistant","content":[],"usage":{"input_tokens":15,"output_tokens":1}}}),
          "",
          "event: content_block_start",
          ~s(data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}),
          "",
          "event: content_block_delta",
          ~s(data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Let me search"}}),
          "",
          "event: content_block_stop",
          ~s(data: {"type":"content_block_stop","index":0}),
          "",
          "event: content_block_start",
          ~s(data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_123","name":"msf_command","input":{}}}),
          "",
          "event: content_block_delta",
          ~s(data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\\"com"}}),
          "",
          "event: content_block_delta",
          ~s(data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"mand\\":\\"search\\"}"}}),
          "",
          "event: content_block_stop",
          ~s(data: {"type":"content_block_stop","index":1}),
          "",
          "event: message_delta",
          ~s(data: {"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":20}}),
          "",
          "event: message_stop",
          ~s(data: {"type":"message_stop"}),
          ""
        ]
        |> Enum.join("\n")

      req_opts = [
        plug: fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("text/event-stream")
          |> Plug.Conn.send_resp(200, stream_response)
        end
      ]

      request = %ChatRequest{
        model: "claude-3-5-sonnet",
        messages: [Message.user("Search for apache exploits")],
        tools: [
          %Tool{
            name: "msf_command",
            description: "Execute MSF command",
            parameters: %{"type" => "object", "properties" => %{}}
          }
        ]
      }

      Anthropic.run_chat_stream(request, caller, ref, req_opts)

      assert_receive {:llm, ^ref, %Events.StreamStarted{}}, 1000
      assert_receive {:llm, ^ref, %Events.ContentBlockStart{index: 0, type: :text}}, 1000
      assert_receive {:llm, ^ref, %Events.ContentDelta{index: 0, delta: "Let me search"}}, 1000
      assert_receive {:llm, ^ref, %Events.ContentBlockStop{index: 0}}, 1000
      assert_receive {:llm, ^ref, %Events.ContentBlockStart{index: 1, type: :tool_call}}, 1000

      assert_receive {:llm, ^ref,
                      %Events.ToolCall{
                        index: 1,
                        id: "toolu_123",
                        name: "msf_command",
                        arguments: %{"command" => "search"}
                      }},
                     1000

      assert_receive {:llm, ^ref, %Events.ContentBlockStop{index: 1}}, 1000
      assert_receive {:llm, ^ref, %Events.StreamComplete{stop_reason: :tool_use}}, 1000
    end

    test "handles thinking blocks" do
      ref = make_ref()
      caller = self()

      stream_response =
        [
          "event: message_start",
          ~s(data: {"type":"message_start","message":{"id":"msg_123","model":"claude-3-5-sonnet","role":"assistant","content":[],"usage":{"input_tokens":10,"output_tokens":1}}}),
          "",
          "event: content_block_start",
          ~s(data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","text":""}}),
          "",
          "event: content_block_delta",
          ~s(data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"Let me think..."}}),
          "",
          "event: content_block_stop",
          ~s(data: {"type":"content_block_stop","index":0}),
          "",
          "event: content_block_start",
          ~s(data: {"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}),
          "",
          "event: content_block_delta",
          ~s(data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Here's my answer"}}),
          "",
          "event: content_block_stop",
          ~s(data: {"type":"content_block_stop","index":1}),
          "",
          "event: message_delta",
          ~s(data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":15}}),
          "",
          "event: message_stop",
          ~s(data: {"type":"message_stop"}),
          ""
        ]
        |> Enum.join("\n")

      req_opts = [
        plug: fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("text/event-stream")
          |> Plug.Conn.send_resp(200, stream_response)
        end
      ]

      request = %ChatRequest{
        model: "claude-3-5-sonnet",
        messages: [Message.user("Hi")]
      }

      Anthropic.run_chat_stream(request, caller, ref, req_opts)

      assert_receive {:llm, ^ref, %Events.StreamStarted{}}, 1000
      assert_receive {:llm, ^ref, %Events.ContentBlockStart{index: 0, type: :thinking}}, 1000
      assert_receive {:llm, ^ref, %Events.ContentDelta{index: 0, delta: "Let me think..."}}, 1000
      assert_receive {:llm, ^ref, %Events.ContentBlockStop{index: 0}}, 1000
      assert_receive {:llm, ^ref, %Events.ContentBlockStart{index: 1, type: :text}}, 1000
      assert_receive {:llm, ^ref, %Events.ContentDelta{index: 1, delta: "Here's my answer"}}, 1000
      assert_receive {:llm, ^ref, %Events.ContentBlockStop{index: 1}}, 1000
      assert_receive {:llm, ^ref, %Events.StreamComplete{}}, 1000
    end

    test "sends error event on HTTP error" do
      ref = make_ref()
      caller = self()

      req_opts = [
        plug: fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(
            400,
            Jason.encode!(%{"error" => %{"message" => "Invalid request"}})
          )
        end
      ]

      request = %ChatRequest{
        model: "claude-3-5-sonnet",
        messages: [Message.user("Hi")]
      }

      Anthropic.run_chat_stream(request, caller, ref, req_opts)

      assert_receive {:llm, ^ref,
                      %Events.StreamError{reason: "Invalid request", recoverable: false}},
                     1000
    end

    test "marks rate limit and overloaded errors as recoverable" do
      ref = make_ref()
      caller = self()

      req_opts = [
        plug: fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(
            429,
            Jason.encode!(%{"error" => %{"message" => "Rate limit exceeded"}})
          )
        end
      ]

      request = %ChatRequest{
        model: "claude-3-5-sonnet",
        messages: [Message.user("Hi")]
      }

      Anthropic.run_chat_stream(request, caller, ref, req_opts)

      assert_receive {:llm, ^ref,
                      %Events.StreamError{reason: "Rate limit exceeded", recoverable: true}},
                     1000
    end

    test "includes system prompt as separate field in request" do
      ref = make_ref()
      caller = self()

      req_opts = [
        plug: fn conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          parsed = Jason.decode!(body)

          # Anthropic uses a top-level system field, not a system message
          assert parsed["system"] == "You are a security assistant"
          refute Enum.any?(parsed["messages"], &(&1["role"] == "system"))

          conn
          |> Plug.Conn.put_resp_content_type("text/event-stream")
          |> Plug.Conn.send_resp(
            200,
            "event: message_stop\ndata: {\"type\":\"message_stop\"}"
          )
        end
      ]

      request = %ChatRequest{
        model: "claude-3-5-sonnet",
        messages: [Message.user("Hi")],
        system_prompt: "You are a security assistant"
      }

      Anthropic.run_chat_stream(request, caller, ref, req_opts)
      assert_receive {:llm, ^ref, _}, 1000
    end

    test "returns max_tokens stop reason when truncated" do
      ref = make_ref()
      caller = self()

      stream_response =
        [
          "event: message_start",
          ~s(data: {"type":"message_start","message":{"id":"msg_123","model":"claude-3-5-sonnet","role":"assistant","content":[],"usage":{"input_tokens":10,"output_tokens":1}}}),
          "",
          "event: message_delta",
          ~s(data: {"type":"message_delta","delta":{"stop_reason":"max_tokens"},"usage":{"output_tokens":100}}),
          "",
          "event: message_stop",
          ~s(data: {"type":"message_stop"}),
          ""
        ]
        |> Enum.join("\n")

      req_opts = [
        plug: fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("text/event-stream")
          |> Plug.Conn.send_resp(200, stream_response)
        end
      ]

      request = %ChatRequest{
        model: "claude-3-5-sonnet",
        messages: [Message.user("Hi")],
        max_tokens: 100
      }

      Anthropic.run_chat_stream(request, caller, ref, req_opts)

      assert_receive {:llm, ^ref, %Events.StreamComplete{stop_reason: :max_tokens}}, 1000
    end

    test "includes cache token counts when available" do
      ref = make_ref()
      caller = self()

      stream_response =
        [
          "event: message_start",
          ~s(data: {"type":"message_start","message":{"id":"msg_123","model":"claude-3-5-sonnet","role":"assistant","content":[],"usage":{"input_tokens":100,"output_tokens":1,"cache_read_input_tokens":80,"cache_creation_input_tokens":5}}}),
          "",
          "event: message_delta",
          ~s(data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":10}}),
          "",
          "event: message_stop",
          ~s(data: {"type":"message_stop"}),
          ""
        ]
        |> Enum.join("\n")

      req_opts = [
        plug: fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("text/event-stream")
          |> Plug.Conn.send_resp(200, stream_response)
        end
      ]

      request = %ChatRequest{
        model: "claude-3-5-sonnet",
        messages: [Message.user("Hi")]
      }

      Anthropic.run_chat_stream(request, caller, ref, req_opts)

      assert_receive {:llm, ^ref,
                      %Events.StreamComplete{
                        input_tokens: 100,
                        output_tokens: 10,
                        cached_input_tokens: 80,
                        cache_creation_tokens: 5
                      }},
                     1000
    end
  end

  describe "message transformation" do
    setup do
      System.put_env("MSFAILAB_ANTHROPIC_API_KEY", "sk-ant-test-key")

      on_exit(fn ->
        System.delete_env("MSFAILAB_ANTHROPIC_API_KEY")
      end)

      :ok
    end

    test "transforms user messages to content blocks" do
      ref = make_ref()
      caller = self()

      req_opts = [
        plug: fn conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          parsed = Jason.decode!(body)

          user_msg = Enum.find(parsed["messages"], &(&1["role"] == "user"))
          assert user_msg["content"] == [%{"type" => "text", "text" => "Hello world"}]

          conn
          |> Plug.Conn.put_resp_content_type("text/event-stream")
          |> Plug.Conn.send_resp(
            200,
            "event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n"
          )
        end
      ]

      request = %ChatRequest{
        model: "claude-3-5-sonnet",
        messages: [Message.user("Hello world")]
      }

      Anthropic.run_chat_stream(request, caller, ref, req_opts)
      assert_receive {:llm, ^ref, _}, 1000
    end

    test "transforms assistant messages with tool_use blocks" do
      ref = make_ref()
      caller = self()

      req_opts = [
        plug: fn conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          parsed = Jason.decode!(body)

          assistant_msg = Enum.find(parsed["messages"], &(&1["role"] == "assistant"))
          assert length(assistant_msg["content"]) == 2

          text_block = Enum.find(assistant_msg["content"], &(&1["type"] == "text"))
          assert text_block["text"] == "Let me search"

          tool_block = Enum.find(assistant_msg["content"], &(&1["type"] == "tool_use"))
          assert tool_block["id"] == "call_1"
          assert tool_block["name"] == "msf_command"
          assert tool_block["input"] == %{"command" => "search"}

          conn
          |> Plug.Conn.put_resp_content_type("text/event-stream")
          |> Plug.Conn.send_resp(
            200,
            "event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n"
          )
        end
      ]

      request = %ChatRequest{
        model: "claude-3-5-sonnet",
        messages: [
          Message.user("Search"),
          %Message{
            role: :assistant,
            content: [
              %{type: :text, text: "Let me search"},
              %{
                type: :tool_call,
                id: "call_1",
                name: "msf_command",
                arguments: %{"command" => "search"}
              }
            ]
          },
          Message.tool_result("call_1", "Results here", false)
        ]
      }

      Anthropic.run_chat_stream(request, caller, ref, req_opts)
      assert_receive {:llm, ^ref, _}, 1000
    end

    test "transforms tool results as user messages with tool_result blocks" do
      ref = make_ref()
      caller = self()

      req_opts = [
        plug: fn conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          parsed = Jason.decode!(body)

          # Tool results should be in a user message
          tool_result_msg =
            Enum.find(parsed["messages"], fn msg ->
              msg["role"] == "user" and
                Enum.any?(msg["content"], &(&1["type"] == "tool_result"))
            end)

          assert tool_result_msg

          tool_result_block =
            Enum.find(tool_result_msg["content"], &(&1["type"] == "tool_result"))

          assert tool_result_block["tool_use_id"] == "call_1"
          assert tool_result_block["content"] == "Tool output"

          conn
          |> Plug.Conn.put_resp_content_type("text/event-stream")
          |> Plug.Conn.send_resp(
            200,
            "event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n"
          )
        end
      ]

      request = %ChatRequest{
        model: "claude-3-5-sonnet",
        messages: [
          Message.user("Run tool"),
          Message.tool_call("call_1", "test_tool", %{}),
          Message.tool_result("call_1", "Tool output", false)
        ]
      }

      Anthropic.run_chat_stream(request, caller, ref, req_opts)
      assert_receive {:llm, ^ref, _}, 1000
    end

    test "includes is_error flag in tool results when true" do
      ref = make_ref()
      caller = self()

      req_opts = [
        plug: fn conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          parsed = Jason.decode!(body)

          tool_result_msg =
            Enum.find(parsed["messages"], fn msg ->
              msg["role"] == "user" and
                Enum.any?(msg["content"], &(&1["type"] == "tool_result"))
            end)

          tool_result_block =
            Enum.find(tool_result_msg["content"], &(&1["type"] == "tool_result"))

          assert tool_result_block["is_error"] == true
          assert tool_result_block["content"] == "Command failed"

          conn
          |> Plug.Conn.put_resp_content_type("text/event-stream")
          |> Plug.Conn.send_resp(
            200,
            "event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n"
          )
        end
      ]

      request = %ChatRequest{
        model: "claude-3-5-sonnet",
        messages: [
          Message.user("Run tool"),
          Message.tool_call("call_1", "test_tool", %{}),
          Message.tool_result("call_1", "Command failed", true)
        ]
      }

      Anthropic.run_chat_stream(request, caller, ref, req_opts)
      assert_receive {:llm, ^ref, _}, 1000
    end
  end

  describe "tool transformation" do
    setup do
      System.put_env("MSFAILAB_ANTHROPIC_API_KEY", "sk-ant-test-key")

      on_exit(fn ->
        System.delete_env("MSFAILAB_ANTHROPIC_API_KEY")
      end)

      :ok
    end

    test "transforms tools to Anthropic format with input_schema" do
      ref = make_ref()
      caller = self()

      req_opts = [
        plug: fn conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          parsed = Jason.decode!(body)

          assert length(parsed["tools"]) == 1
          tool = hd(parsed["tools"])
          assert tool["name"] == "msf_command"
          assert tool["description"] == "Execute command"
          assert tool["input_schema"]["type"] == "object"

          conn
          |> Plug.Conn.put_resp_content_type("text/event-stream")
          |> Plug.Conn.send_resp(
            200,
            "event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n"
          )
        end
      ]

      request = %ChatRequest{
        model: "claude-3-5-sonnet",
        messages: [Message.user("Hi")],
        tools: [
          %Tool{
            name: "msf_command",
            description: "Execute command",
            parameters: %{
              "type" => "object",
              "properties" => %{"command" => %{"type" => "string"}}
            }
          }
        ]
      }

      Anthropic.run_chat_stream(request, caller, ref, req_opts)
      assert_receive {:llm, ^ref, _}, 1000
    end

    test "includes cache_control when tool is cacheable" do
      ref = make_ref()
      caller = self()

      req_opts = [
        plug: fn conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          parsed = Jason.decode!(body)

          tool = hd(parsed["tools"])
          assert tool["cache_control"] == %{"type" => "ephemeral"}

          conn
          |> Plug.Conn.put_resp_content_type("text/event-stream")
          |> Plug.Conn.send_resp(
            200,
            "event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n"
          )
        end
      ]

      request = %ChatRequest{
        model: "claude-3-5-sonnet",
        messages: [Message.user("Hi")],
        tools: [
          %Tool{
            name: "msf_command",
            description: "Execute command",
            parameters: %{"type" => "object"},
            cacheable: true
          }
        ]
      }

      Anthropic.run_chat_stream(request, caller, ref, req_opts)
      assert_receive {:llm, ^ref, _}, 1000
    end

    test "omits cache_control when tool is not cacheable" do
      ref = make_ref()
      caller = self()

      req_opts = [
        plug: fn conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          parsed = Jason.decode!(body)

          tool = hd(parsed["tools"])
          refute Map.has_key?(tool, "cache_control")

          conn
          |> Plug.Conn.put_resp_content_type("text/event-stream")
          |> Plug.Conn.send_resp(
            200,
            "event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n"
          )
        end
      ]

      request = %ChatRequest{
        model: "claude-3-5-sonnet",
        messages: [Message.user("Hi")],
        tools: [
          %Tool{
            name: "msf_command",
            description: "Execute command",
            parameters: %{"type" => "object"},
            cacheable: false
          }
        ]
      }

      Anthropic.run_chat_stream(request, caller, ref, req_opts)
      assert_receive {:llm, ^ref, _}, 1000
    end
  end

  describe "error handling" do
    setup do
      System.put_env("MSFAILAB_ANTHROPIC_API_KEY", "sk-ant-test-key")

      on_exit(fn ->
        System.delete_env("MSFAILAB_ANTHROPIC_API_KEY")
      end)

      :ok
    end

    test "handles rate limit errors as recoverable" do
      ref = make_ref()
      caller = self()

      stream_response =
        """
        event: error
        data: {"type":"error","error":{"type":"rate_limit_error","message":"Rate limit exceeded"}}
        """

      req_opts = [
        plug: fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("text/event-stream")
          |> Plug.Conn.send_resp(200, stream_response)
        end
      ]

      request = %ChatRequest{
        model: "claude-3-5-sonnet",
        messages: [Message.user("Hi")]
      }

      Anthropic.run_chat_stream(request, caller, ref, req_opts)

      assert_receive {:llm, ^ref,
                      %Events.StreamError{reason: "Rate limit exceeded", recoverable: true}},
                     1000
    end

    test "handles overloaded errors as recoverable" do
      ref = make_ref()
      caller = self()

      stream_response =
        """
        event: error
        data: {"type":"error","error":{"type":"overloaded_error","message":"Server overloaded"}}
        """

      req_opts = [
        plug: fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("text/event-stream")
          |> Plug.Conn.send_resp(200, stream_response)
        end
      ]

      request = %ChatRequest{
        model: "claude-3-5-sonnet",
        messages: [Message.user("Hi")]
      }

      Anthropic.run_chat_stream(request, caller, ref, req_opts)

      assert_receive {:llm, ^ref,
                      %Events.StreamError{reason: "Server overloaded", recoverable: true}},
                     1000
    end

    test "handles unknown events gracefully" do
      ref = make_ref()
      caller = self()

      stream_response =
        """
        event: unknown_event_type
        data: {"type":"unknown"}

        event: message_start
        data: {"type":"message_start","message":{"id":"msg_1","model":"claude-3-5-sonnet","usage":{"input_tokens":10}}}

        event: message_stop
        data: {"type":"message_stop"}

        """

      req_opts = [
        plug: fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("text/event-stream")
          |> Plug.Conn.send_resp(200, stream_response)
        end
      ]

      request = %ChatRequest{
        model: "claude-3-5-sonnet",
        messages: [Message.user("Hi")]
      }

      Anthropic.run_chat_stream(request, caller, ref, req_opts)

      # Should still process valid events
      assert_receive {:llm, ^ref, %Events.StreamStarted{}}, 1000
      assert_receive {:llm, ^ref, %Events.StreamComplete{}}, 1000
    end

    test "handles HTTP error responses" do
      ref = make_ref()
      caller = self()

      req_opts = [
        plug: fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(
            529,
            Jason.encode!(%{"error" => %{"message" => "Service overloaded"}})
          )
        end
      ]

      request = %ChatRequest{
        model: "claude-3-5-sonnet",
        messages: [Message.user("Hi")]
      }

      Anthropic.run_chat_stream(request, caller, ref, req_opts)

      assert_receive {:llm, ^ref,
                      %Events.StreamError{reason: "Service overloaded", recoverable: true}},
                     1000
    end

    test "handles malformed SSE events gracefully" do
      ref = make_ref()
      caller = self()

      stream_response =
        """
        malformed line without event

        event: message_start
        data: {"type":"message_start","message":{"id":"msg_1","model":"claude-3-5-sonnet","usage":{"input_tokens":10}}}

        event: content_block_start
        data: {"type":"content_block_start","index":0,"content_block":{"type":"text"}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hi"}}

        event: content_block_stop
        data: {"type":"content_block_stop","index":0}

        event: message_delta
        data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":1}}

        event: message_stop
        data: {"type":"message_stop"}

        """

      req_opts = [
        plug: fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("text/event-stream")
          |> Plug.Conn.send_resp(200, stream_response)
        end
      ]

      request = %ChatRequest{
        model: "claude-3-5-sonnet",
        messages: [Message.user("Hi")]
      }

      Anthropic.run_chat_stream(request, caller, ref, req_opts)

      # Should process valid events
      assert_receive {:llm, ^ref, %Events.StreamStarted{}}, 1000
      assert_receive {:llm, ^ref, %Events.ContentBlockStart{}}, 1000
      assert_receive {:llm, ^ref, %Events.ContentDelta{delta: "Hi"}}, 1000
      assert_receive {:llm, ^ref, %Events.ContentBlockStop{}}, 1000
      assert_receive {:llm, ^ref, %Events.StreamComplete{stop_reason: :end_turn}}, 1000
    end

    test "handles content_block_delta with nil block" do
      ref = make_ref()
      caller = self()

      # Delta for an index that doesn't have a started block
      stream_response =
        """
        event: message_start
        data: {"type":"message_start","message":{"id":"msg_1","model":"claude-3-5-sonnet","usage":{"input_tokens":10}}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":99,"delta":{"type":"text_delta","text":"orphan"}}

        event: message_stop
        data: {"type":"message_stop"}

        """

      req_opts = [
        plug: fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("text/event-stream")
          |> Plug.Conn.send_resp(200, stream_response)
        end
      ]

      request = %ChatRequest{
        model: "claude-3-5-sonnet",
        messages: [Message.user("Hi")]
      }

      Anthropic.run_chat_stream(request, caller, ref, req_opts)

      # Should complete without crashing
      assert_receive {:llm, ^ref, %Events.StreamStarted{}}, 1000
      assert_receive {:llm, ^ref, %Events.StreamComplete{}}, 1000
    end
  end

  describe "comprehensive integration - full response with all content block types" do
    setup do
      System.put_env("MSFAILAB_ANTHROPIC_API_KEY", "sk-ant-test-key")

      on_exit(fn ->
        System.delete_env("MSFAILAB_ANTHROPIC_API_KEY")
      end)

      :ok
    end

    @doc """
    This test simulates a complete Anthropic response that includes:
    - thinking block (index 0)
    - text block (index 1)
    - two tool_use blocks (index 2, 3)

    This validates the full event sequence and correct index assignment across all block types.
    """
    test "streams thinking + text + multiple tool calls with correct indices and events" do
      ref = make_ref()
      caller = self()

      # Complete raw HTTP response with all content block types
      stream_response =
        [
          # Message start with initial usage
          "event: message_start",
          ~s(data: {"type":"message_start","message":{"id":"msg_01XFDUDYJgAACzvnptvVoYEL","model":"claude-sonnet-4-5-20250514","role":"assistant","content":[],"stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":1247,"output_tokens":1,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}),
          "",
          # Thinking block start (Anthropic index 0)
          "event: content_block_start",
          ~s(data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}),
          "",
          # Thinking deltas
          "event: content_block_delta",
          ~s(data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"Let me analyze this security"}}),
          "",
          "event: content_block_delta",
          ~s(data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":" research request carefully..."}}),
          "",
          # Thinking block stop
          "event: content_block_stop",
          ~s(data: {"type":"content_block_stop","index":0}),
          "",
          # Text block start (Anthropic index 1)
          "event: content_block_start",
          ~s(data: {"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}),
          "",
          # Text deltas
          "event: content_block_delta",
          ~s(data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"I'll help you search for Apache"}}),
          "",
          "event: content_block_delta",
          ~s(data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":" exploits and check the current hosts."}}),
          "",
          # Text block stop
          "event: content_block_stop",
          ~s(data: {"type":"content_block_stop","index":1}),
          "",
          # First tool_use block start (Anthropic index 2)
          "event: content_block_start",
          ~s(data: {"type":"content_block_start","index":2,"content_block":{"type":"tool_use","id":"toolu_01ABC123DEF456","name":"msf_command","input":{}}}),
          "",
          # Tool use input deltas (streamed JSON)
          "event: content_block_delta",
          ~s(data: {"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":"{\\"command\\""}}),
          "",
          "event: content_block_delta",
          ~s(data: {"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":":\\"search apache\\"}"}}),
          "",
          # First tool_use block stop
          "event: content_block_stop",
          ~s(data: {"type":"content_block_stop","index":2}),
          "",
          # Second tool_use block start (Anthropic index 3)
          "event: content_block_start",
          ~s(data: {"type":"content_block_start","index":3,"content_block":{"type":"tool_use","id":"toolu_02XYZ789GHI012","name":"list_hosts","input":{}}}),
          "",
          # Tool use input deltas
          "event: content_block_delta",
          ~s(data: {"type":"content_block_delta","index":3,"delta":{"type":"input_json_delta","partial_json":"{\\"workspace\\":\\"default\\"}"}}),
          "",
          # Second tool_use block stop
          "event: content_block_stop",
          ~s(data: {"type":"content_block_stop","index":3}),
          "",
          # Message delta with stop reason and final usage
          "event: message_delta",
          ~s(data: {"type":"message_delta","delta":{"stop_reason":"tool_use","stop_sequence":null},"usage":{"output_tokens":87}}),
          "",
          # Message stop
          "event: message_stop",
          ~s(data: {"type":"message_stop"}),
          ""
        ]
        |> Enum.join("\n")

      req_opts = [
        plug: fn conn ->
          assert conn.request_path == "/v1/messages"

          conn
          |> Plug.Conn.put_resp_content_type("text/event-stream")
          |> Plug.Conn.send_resp(200, stream_response)
        end
      ]

      request = %ChatRequest{
        model: "claude-sonnet-4-5-20250514",
        messages: [Message.user("Search for Apache exploits and list hosts")],
        tools: [
          %Tool{
            name: "msf_command",
            description: "Execute MSF command",
            parameters: %{"type" => "object"}
          },
          %Tool{name: "list_hosts", description: "List hosts", parameters: %{"type" => "object"}}
        ]
      }

      Anthropic.run_chat_stream(request, caller, ref, req_opts)

      # 1. Stream started
      assert_receive {:llm, ^ref, %Events.StreamStarted{model: "claude-sonnet-4-5-20250514"}},
                     1000

      # 2. Thinking block (our index 0)
      assert_receive {:llm, ^ref, %Events.ContentBlockStart{index: 0, type: :thinking}}, 1000

      assert_receive {:llm, ^ref,
                      %Events.ContentDelta{index: 0, delta: "Let me analyze this security"}},
                     1000

      assert_receive {:llm, ^ref,
                      %Events.ContentDelta{index: 0, delta: " research request carefully..."}},
                     1000

      assert_receive {:llm, ^ref, %Events.ContentBlockStop{index: 0}}, 1000

      # 3. Text block (our index 1)
      assert_receive {:llm, ^ref, %Events.ContentBlockStart{index: 1, type: :text}}, 1000

      assert_receive {:llm, ^ref,
                      %Events.ContentDelta{index: 1, delta: "I'll help you search for Apache"}},
                     1000

      assert_receive {:llm, ^ref,
                      %Events.ContentDelta{
                        index: 1,
                        delta: " exploits and check the current hosts."
                      }},
                     1000

      assert_receive {:llm, ^ref, %Events.ContentBlockStop{index: 1}}, 1000

      # 4. First tool_use block (our index 2)
      assert_receive {:llm, ^ref, %Events.ContentBlockStart{index: 2, type: :tool_call}}, 1000

      assert_receive {:llm, ^ref,
                      %Events.ToolCall{
                        index: 2,
                        id: "toolu_01ABC123DEF456",
                        name: "msf_command",
                        arguments: %{"command" => "search apache"}
                      }},
                     1000

      assert_receive {:llm, ^ref, %Events.ContentBlockStop{index: 2}}, 1000

      # 5. Second tool_use block (our index 3)
      assert_receive {:llm, ^ref, %Events.ContentBlockStart{index: 3, type: :tool_call}}, 1000

      assert_receive {:llm, ^ref,
                      %Events.ToolCall{
                        index: 3,
                        id: "toolu_02XYZ789GHI012",
                        name: "list_hosts",
                        arguments: %{"workspace" => "default"}
                      }},
                     1000

      assert_receive {:llm, ^ref, %Events.ContentBlockStop{index: 3}}, 1000

      # 6. Stream complete with correct metrics and stop reason
      assert_receive {:llm, ^ref,
                      %Events.StreamComplete{
                        input_tokens: 1247,
                        output_tokens: 87,
                        cached_input_tokens: 0,
                        cache_creation_tokens: 0,
                        stop_reason: :tool_use
                      }},
                     1000

      # Verify no more events
      refute_receive {:llm, ^ref, _}, 100
    end

    test "handles empty thinking block followed by text and tool use" do
      ref = make_ref()
      caller = self()

      # Response with a thinking block that has no content (empty thinking delta)
      stream_response =
        [
          "event: message_start",
          ~s(data: {"type":"message_start","message":{"id":"msg_test","model":"claude-3-5-sonnet","role":"assistant","content":[],"usage":{"input_tokens":50,"output_tokens":1}}}),
          "",
          "event: content_block_start",
          ~s(data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}),
          "",
          "event: content_block_delta",
          ~s(data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Searching now."}}),
          "",
          "event: content_block_stop",
          ~s(data: {"type":"content_block_stop","index":0}),
          "",
          "event: content_block_start",
          ~s(data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_test","name":"search","input":{}}}),
          "",
          "event: content_block_delta",
          ~s(data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\\"query\\":\\"test\\"}"}}),
          "",
          "event: content_block_stop",
          ~s(data: {"type":"content_block_stop","index":1}),
          "",
          "event: message_delta",
          ~s(data: {"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":25}}),
          "",
          "event: message_stop",
          ~s(data: {"type":"message_stop"}),
          ""
        ]
        |> Enum.join("\n")

      req_opts = [
        plug: fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("text/event-stream")
          |> Plug.Conn.send_resp(200, stream_response)
        end
      ]

      request = %ChatRequest{
        model: "claude-3-5-sonnet",
        messages: [Message.user("Search")]
      }

      Anthropic.run_chat_stream(request, caller, ref, req_opts)

      # Text block at index 0
      assert_receive {:llm, ^ref, %Events.StreamStarted{}}, 1000
      assert_receive {:llm, ^ref, %Events.ContentBlockStart{index: 0, type: :text}}, 1000
      assert_receive {:llm, ^ref, %Events.ContentDelta{index: 0, delta: "Searching now."}}, 1000
      assert_receive {:llm, ^ref, %Events.ContentBlockStop{index: 0}}, 1000

      # Tool use at index 1
      assert_receive {:llm, ^ref, %Events.ContentBlockStart{index: 1, type: :tool_call}}, 1000

      assert_receive {:llm, ^ref,
                      %Events.ToolCall{
                        index: 1,
                        id: "toolu_test",
                        name: "search",
                        arguments: %{"query" => "test"}
                      }},
                     1000

      assert_receive {:llm, ^ref, %Events.ContentBlockStop{index: 1}}, 1000

      assert_receive {:llm, ^ref,
                      %Events.StreamComplete{stop_reason: :tool_use, output_tokens: 25}},
                     1000
    end

    test "handles tool use with complex nested JSON arguments" do
      ref = make_ref()
      caller = self()

      # Response with tool use that has complex nested JSON arguments streamed in many small chunks
      stream_response =
        [
          "event: message_start",
          ~s(data: {"type":"message_start","message":{"id":"msg_nested","model":"claude-3-5-sonnet","role":"assistant","content":[],"usage":{"input_tokens":100,"output_tokens":1}}}),
          "",
          "event: content_block_start",
          ~s(data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_nested","name":"complex_tool","input":{}}}),
          "",
          # Stream the complex JSON in small chunks
          "event: content_block_delta",
          ~s(data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{"}}),
          "",
          "event: content_block_delta",
          ~s(data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"\\"options\\":"}}),
          "",
          "event: content_block_delta",
          ~s(data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\\"verbose\\":true,\\"level\\":3}"}}),
          "",
          "event: content_block_delta",
          ~s(data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":",\\"targets\\":[\\"192.168.1.1\\",\\"192.168.1.2\\"]"}}),
          "",
          "event: content_block_delta",
          ~s(data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"}"}}),
          "",
          "event: content_block_stop",
          ~s(data: {"type":"content_block_stop","index":0}),
          "",
          "event: message_delta",
          ~s(data: {"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":40}}),
          "",
          "event: message_stop",
          ~s(data: {"type":"message_stop"}),
          ""
        ]
        |> Enum.join("\n")

      req_opts = [
        plug: fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("text/event-stream")
          |> Plug.Conn.send_resp(200, stream_response)
        end
      ]

      request = %ChatRequest{
        model: "claude-3-5-sonnet",
        messages: [Message.user("Run complex tool")]
      }

      Anthropic.run_chat_stream(request, caller, ref, req_opts)

      assert_receive {:llm, ^ref, %Events.StreamStarted{}}, 1000
      assert_receive {:llm, ^ref, %Events.ContentBlockStart{index: 0, type: :tool_call}}, 1000

      # The arguments should be correctly parsed from all the chunks
      assert_receive {:llm, ^ref,
                      %Events.ToolCall{
                        index: 0,
                        id: "toolu_nested",
                        name: "complex_tool",
                        arguments: %{
                          "options" => %{"verbose" => true, "level" => 3},
                          "targets" => ["192.168.1.1", "192.168.1.2"]
                        }
                      }},
                     1000

      assert_receive {:llm, ^ref, %Events.ContentBlockStop{index: 0}}, 1000
      assert_receive {:llm, ^ref, %Events.StreamComplete{stop_reason: :tool_use}}, 1000
    end
  end

  describe "trace formatting" do
    test "formats successful response with all content block types" do
      acc = %{
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

      result = Anthropic.format_trace_response(acc, 200)

      # Should contain all content blocks with correct formatting
      assert result =~ "--- CONTENT BLOCK 0 (thinking) ---"
      assert result =~ "Let me analyze this request."
      assert result =~ "--- CONTENT BLOCK 1 (text) ---"
      assert result =~ "Here is my response."
      assert result =~ "--- CONTENT BLOCK 2 (tool_use) ---"
      assert result =~ "toolu_123"
      assert result =~ "search"
      assert result =~ "\"query\""

      # Should contain metadata section
      assert result =~ "--- METADATA ---"
      assert result =~ "\"input_tokens\": 100"
      assert result =~ "\"output_tokens\": 50"
      assert result =~ "\"cached_input_tokens\": 25"
      assert result =~ "\"stop_reason\": \"tool_use\""
    end

    test "formats response with only text block" do
      acc = %{
        trace_blocks: [{:text, "Simple response without tools."}],
        trace_metadata: %{
          input_tokens: 50,
          output_tokens: 10,
          stop_reason: :end_turn
        }
      }

      result = Anthropic.format_trace_response(acc, 200)

      assert result =~ "--- CONTENT BLOCK 0 (text) ---"
      assert result =~ "Simple response without tools."
      assert result =~ "--- METADATA ---"
      refute result =~ "(tool_use)"
      refute result =~ "(thinking)"
    end

    test "formats response with only thinking block" do
      acc = %{
        trace_blocks: [{:thinking, "Extended thinking content here."}],
        trace_metadata: %{stop_reason: :end_turn}
      }

      result = Anthropic.format_trace_response(acc, 200)

      assert result =~ "--- CONTENT BLOCK 0 (thinking) ---"
      assert result =~ "Extended thinking content here."
    end

    test "formats empty response" do
      acc = %{
        trace_blocks: [],
        trace_metadata: nil
      }

      result = Anthropic.format_trace_response(acc, 200)

      assert result == "(empty response)"
    end

    test "formats error response with raw body" do
      acc = %{
        raw_body: ~s({"error": {"type": "rate_limit_error", "message": "Too many requests"}})
      }

      result = Anthropic.format_trace_response(acc, 429)

      assert result =~ "--- ERROR RESPONSE ---"
      assert result =~ "rate_limit_error"
      assert result =~ "Too many requests"
    end

    test "formats error response with non-JSON body" do
      acc = %{
        raw_body: "Internal server error"
      }

      result = Anthropic.format_trace_response(acc, 500)

      assert result =~ "--- ERROR RESPONSE ---"
      assert result =~ "Internal server error"
    end

    test "formats error response with empty body" do
      acc = %{
        raw_body: ""
      }

      result = Anthropic.format_trace_response(acc, 500)

      assert result == "(empty error response)"
    end

    test "formats multiple tool_use blocks correctly" do
      acc = %{
        trace_blocks: [
          {:tool_use, %{id: "toolu_1", name: "tool_a", arguments: %{"x" => 1}}},
          {:tool_use, %{id: "toolu_2", name: "tool_b", arguments: %{"y" => 2}}}
        ],
        trace_metadata: %{stop_reason: :tool_use}
      }

      result = Anthropic.format_trace_response(acc, 200)

      assert result =~ "--- CONTENT BLOCK 0 (tool_use) ---"
      assert result =~ "toolu_1"
      assert result =~ "tool_a"
      assert result =~ "--- CONTENT BLOCK 1 (tool_use) ---"
      assert result =~ "toolu_2"
      assert result =~ "tool_b"
    end
  end
end
