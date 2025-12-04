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

defmodule Msfailab.LLM.Providers.OpenAITest do
  use ExUnit.Case, async: true

  alias Msfailab.LLM.ChatRequest
  alias Msfailab.LLM.Events
  alias Msfailab.LLM.Message
  alias Msfailab.LLM.Model
  alias Msfailab.LLM.Providers.OpenAI
  alias Msfailab.Tools.Tool

  describe "configured?/0" do
    test "returns true when MSFAILAB_OPENAI_API_KEY is set" do
      System.put_env("MSFAILAB_OPENAI_API_KEY", "sk-test-key")
      assert OpenAI.configured?()
      System.delete_env("MSFAILAB_OPENAI_API_KEY")
    end

    test "returns false when MSFAILAB_OPENAI_API_KEY is not set" do
      System.delete_env("MSFAILAB_OPENAI_API_KEY")
      refute OpenAI.configured?()
    end

    test "returns false when MSFAILAB_OPENAI_API_KEY is empty string" do
      System.put_env("MSFAILAB_OPENAI_API_KEY", "")
      refute OpenAI.configured?()
      System.delete_env("MSFAILAB_OPENAI_API_KEY")
    end
  end

  describe "list_models/1 with mocked HTTP" do
    setup do
      System.put_env("MSFAILAB_OPENAI_API_KEY", "sk-test-key")
      # Use wildcard filter for tests to pass all models through
      System.put_env("MSFAILAB_OPENAI_MODEL_FILTER", "*")

      on_exit(fn ->
        System.delete_env("MSFAILAB_OPENAI_API_KEY")
        System.delete_env("MSFAILAB_OPENAI_MODEL_FILTER")
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
                %{"id" => "gpt-4o"},
                %{"id" => "gpt-4o-mini"},
                %{"id" => "gpt-3.5-turbo"},
                %{"id" => "text-embedding-3-small"},
                %{"id" => "whisper-1"}
              ]
            })
          )
        end
      ]

      assert {:ok, models} = OpenAI.list_models(req_opts)

      # Should filter out embeddings and whisper
      assert length(models) == 3

      model_names = Enum.map(models, & &1.name)
      assert "gpt-4o" in model_names
      assert "gpt-4o-mini" in model_names
      assert "gpt-3.5-turbo" in model_names
      refute "text-embedding-3-small" in model_names
      refute "whisper-1" in model_names
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
                %{"id" => "gpt-4o"},
                %{"id" => "gpt-4"},
                %{"id" => "o1"}
              ]
            })
          )
        end
      ]

      assert {:ok, models} = OpenAI.list_models(req_opts)

      gpt4o = Enum.find(models, &(&1.name == "gpt-4o"))
      assert %Model{provider: :openai, context_window: 128_000} = gpt4o

      gpt4 = Enum.find(models, &(&1.name == "gpt-4"))
      assert %Model{provider: :openai, context_window: 8_192} = gpt4

      o1 = Enum.find(models, &(&1.name == "o1"))
      assert %Model{provider: :openai, context_window: 200_000} = o1
    end

    test "uses default context window for unknown models with supported prefix" do
      req_opts = [
        plug: fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(
            200,
            Jason.encode!(%{
              # Uses gpt-4 prefix (supported) but unknown suffix, no exact or prefix match
              "data" => [%{"id" => "gpt-4-unknown-variant-xyz"}]
            })
          )
        end
      ]

      assert {:ok, [model]} = OpenAI.list_models(req_opts)
      # Should match gpt-4 prefix (8192)
      assert model.context_window == 8_192
    end

    test "matches context window by prefix for versioned models" do
      req_opts = [
        plug: fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(
            200,
            Jason.encode!(%{
              "data" => [%{"id" => "gpt-4o-2024-08-06"}]
            })
          )
        end
      ]

      assert {:ok, [model]} = OpenAI.list_models(req_opts)
      # Should match gpt-4o prefix
      assert model.context_window == 128_000
    end

    test "returns error on invalid API key" do
      req_opts = [
        plug: fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(401, Jason.encode!(%{"error" => "Invalid API key"}))
        end
      ]

      assert {:error, :invalid_api_key} = OpenAI.list_models(req_opts)
    end

    test "returns error on unexpected status" do
      req_opts = [
        plug: fn conn ->
          Plug.Conn.send_resp(conn, 500, "Internal Server Error")
        end
      ]

      assert {:error, {:unexpected_status, 500}} = OpenAI.list_models(req_opts)
    end

    test "returns error when no supported models" do
      req_opts = [
        plug: fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(
            200,
            Jason.encode!(%{
              "data" => [
                %{"id" => "text-embedding-3-small"},
                %{"id" => "whisper-1"}
              ]
            })
          )
        end
      ]

      # API returns models but none are supported (embeddings/whisper not chat models)
      assert {:error, {:all_models_filtered, "*"}} = OpenAI.list_models(req_opts)
    end
  end

  describe "run_chat_stream/4 - basic streaming" do
    setup do
      System.put_env("MSFAILAB_OPENAI_API_KEY", "sk-test-key")

      on_exit(fn ->
        System.delete_env("MSFAILAB_OPENAI_API_KEY")
      end)

      :ok
    end

    test "streams text response with proper events" do
      ref = make_ref()
      caller = self()

      stream_response =
        [
          ~s(data: {"id":"chatcmpl-123","model":"gpt-4o","choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":null}]}),
          ~s(data: {"id":"chatcmpl-123","model":"gpt-4o","choices":[{"index":0,"delta":{"content":"Hello"},"finish_reason":null}]}),
          ~s(data: {"id":"chatcmpl-123","model":"gpt-4o","choices":[{"index":0,"delta":{"content":" world"},"finish_reason":null}]}),
          ~s(data: {"id":"chatcmpl-123","model":"gpt-4o","choices":[{"index":0,"delta":{},"finish_reason":"stop"}],"usage":{"prompt_tokens":10,"completion_tokens":5}}),
          "data: [DONE]",
          ""
        ]
        |> Enum.join("\n")

      req_opts = [
        plug: fn conn ->
          assert conn.request_path == "/v1/chat/completions"

          conn
          |> Plug.Conn.put_resp_content_type("text/event-stream")
          |> Plug.Conn.send_resp(200, stream_response)
        end
      ]

      request = %ChatRequest{
        model: "gpt-4o",
        messages: [Message.user("Hi")],
        max_tokens: 100,
        temperature: 0.1
      }

      OpenAI.run_chat_stream(request, caller, ref, req_opts)

      assert_receive {:llm, ^ref, %Events.StreamStarted{model: "gpt-4o"}}, 1000
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

    test "handles tool call response with streamed arguments" do
      ref = make_ref()
      caller = self()

      stream_response =
        [
          ~s(data: {"id":"chatcmpl-123","model":"gpt-4o","choices":[{"index":0,"delta":{"role":"assistant","content":"Let me search"},"finish_reason":null}]}),
          ~s(data: {"id":"chatcmpl-123","model":"gpt-4o","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_abc","type":"function","function":{"name":"execute_msfconsole_command","arguments":""}}]},"finish_reason":null}]}),
          ~s(data: {"id":"chatcmpl-123","model":"gpt-4o","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\\"com"}}]},"finish_reason":null}]}),
          ~s(data: {"id":"chatcmpl-123","model":"gpt-4o","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"mand\\":\\"search\\"}"}}]},"finish_reason":null}]}),
          ~s(data: {"id":"chatcmpl-123","model":"gpt-4o","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":15,"completion_tokens":20}}),
          "data: [DONE]",
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
        model: "gpt-4o",
        messages: [Message.user("Search for apache exploits")],
        tools: [
          %Tool{
            name: "execute_msfconsole_command",
            short_title: "Running MSF command",
            description: "Execute MSF command",
            parameters: %{"type" => "object", "properties" => %{}}
          }
        ]
      }

      OpenAI.run_chat_stream(request, caller, ref, req_opts)

      assert_receive {:llm, ^ref, %Events.StreamStarted{}}, 1000
      assert_receive {:llm, ^ref, %Events.ContentBlockStart{index: 0, type: :text}}, 1000
      assert_receive {:llm, ^ref, %Events.ContentDelta{index: 0, delta: "Let me search"}}, 1000
      assert_receive {:llm, ^ref, %Events.ContentBlockStop{index: 0}}, 1000
      assert_receive {:llm, ^ref, %Events.ContentBlockStart{index: 1, type: :tool_call}}, 1000

      assert_receive {:llm, ^ref,
                      %Events.ToolCall{
                        index: 1,
                        id: "call_abc",
                        name: "execute_msfconsole_command",
                        arguments: %{"command" => "search"}
                      }},
                     1000

      assert_receive {:llm, ^ref, %Events.ContentBlockStop{index: 1}}, 1000
      assert_receive {:llm, ^ref, %Events.StreamComplete{stop_reason: :tool_use}}, 1000
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
        model: "gpt-4o",
        messages: [Message.user("Hi")]
      }

      OpenAI.run_chat_stream(request, caller, ref, req_opts)

      assert_receive {:llm, ^ref,
                      %Events.StreamError{reason: "Invalid request", recoverable: false}},
                     1000
    end

    test "marks rate limit errors as recoverable" do
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
        model: "gpt-4o",
        messages: [Message.user("Hi")]
      }

      OpenAI.run_chat_stream(request, caller, ref, req_opts)

      assert_receive {:llm, ^ref,
                      %Events.StreamError{reason: "Rate limit exceeded", recoverable: true}},
                     1000
    end

    test "includes system prompt in request" do
      ref = make_ref()
      caller = self()

      req_opts = [
        plug: fn conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          parsed = Jason.decode!(body)

          system_msg = Enum.find(parsed["messages"], &(&1["role"] == "system"))
          assert system_msg["content"] == "You are a security assistant"

          conn
          |> Plug.Conn.put_resp_content_type("text/event-stream")
          |> Plug.Conn.send_resp(200, "data: [DONE]\n")
        end
      ]

      request = %ChatRequest{
        model: "gpt-4o",
        messages: [Message.user("Hi")],
        system_prompt: "You are a security assistant"
      }

      OpenAI.run_chat_stream(request, caller, ref, req_opts)

      # Will fail to parse but that's ok for this test
      assert_receive {:llm, ^ref, _}, 1000
    end

    test "returns max_tokens stop reason when truncated" do
      ref = make_ref()
      caller = self()

      stream_response =
        [
          ~s(data: {"id":"chatcmpl-123","model":"gpt-4o","choices":[{"index":0,"delta":{"content":"truncated"},"finish_reason":null}]}),
          ~s(data: {"id":"chatcmpl-123","model":"gpt-4o","choices":[{"index":0,"delta":{},"finish_reason":"length"}],"usage":{"prompt_tokens":10,"completion_tokens":100}}),
          "data: [DONE]",
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
        model: "gpt-4o",
        messages: [Message.user("Hi")],
        max_tokens: 100
      }

      OpenAI.run_chat_stream(request, caller, ref, req_opts)

      assert_receive {:llm, ^ref, %Events.StreamComplete{stop_reason: :max_tokens}}, 1000
    end

    test "includes cached token count when available" do
      ref = make_ref()
      caller = self()

      stream_response =
        [
          ~s(data: {"id":"chatcmpl-123","model":"gpt-4o","choices":[{"index":0,"delta":{},"finish_reason":"stop"}],"usage":{"prompt_tokens":100,"completion_tokens":10,"prompt_tokens_details":{"cached_tokens":80}}}),
          "data: [DONE]",
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
        model: "gpt-4o",
        messages: [Message.user("Hi")]
      }

      OpenAI.run_chat_stream(request, caller, ref, req_opts)

      assert_receive {:llm, ^ref,
                      %Events.StreamComplete{
                        input_tokens: 100,
                        output_tokens: 10,
                        cached_input_tokens: 80
                      }},
                     1000
    end
  end

  describe "message transformation" do
    setup do
      System.put_env("MSFAILAB_OPENAI_API_KEY", "sk-test-key")

      on_exit(fn ->
        System.delete_env("MSFAILAB_OPENAI_API_KEY")
      end)

      :ok
    end

    test "transforms user messages correctly" do
      ref = make_ref()
      caller = self()

      req_opts = [
        plug: fn conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          parsed = Jason.decode!(body)

          user_msg = Enum.find(parsed["messages"], &(&1["role"] == "user"))
          assert user_msg["content"] == "Hello world"

          conn
          |> Plug.Conn.put_resp_content_type("text/event-stream")
          |> Plug.Conn.send_resp(200, "data: [DONE]\n")
        end
      ]

      request = %ChatRequest{
        model: "gpt-4o",
        messages: [Message.user("Hello world")]
      }

      OpenAI.run_chat_stream(request, caller, ref, req_opts)
      assert_receive {:llm, ^ref, _}, 1000
    end

    test "transforms assistant messages with tool calls using JSON string arguments" do
      ref = make_ref()
      caller = self()

      req_opts = [
        plug: fn conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          parsed = Jason.decode!(body)

          assistant_msg = Enum.find(parsed["messages"], &(&1["role"] == "assistant"))
          assert assistant_msg["content"] == "Let me search"
          assert length(assistant_msg["tool_calls"]) == 1

          tool_call = hd(assistant_msg["tool_calls"])
          assert tool_call["id"] == "call_1"
          assert tool_call["type"] == "function"
          assert tool_call["function"]["name"] == "execute_msfconsole_command"
          # OpenAI expects JSON string for arguments
          assert tool_call["function"]["arguments"] == ~s({"command":"search"})

          conn
          |> Plug.Conn.put_resp_content_type("text/event-stream")
          |> Plug.Conn.send_resp(200, "data: [DONE]\n")
        end
      ]

      request = %ChatRequest{
        model: "gpt-4o",
        messages: [
          Message.user("Search"),
          %Message{
            role: :assistant,
            content: [
              %{type: :text, text: "Let me search"},
              %{
                type: :tool_call,
                id: "call_1",
                name: "execute_msfconsole_command",
                arguments: %{"command" => "search"}
              }
            ]
          },
          Message.tool_result("call_1", "Results here", false)
        ]
      }

      OpenAI.run_chat_stream(request, caller, ref, req_opts)
      assert_receive {:llm, ^ref, _}, 1000
    end

    test "transforms tool result messages with tool_call_id" do
      ref = make_ref()
      caller = self()

      req_opts = [
        plug: fn conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          parsed = Jason.decode!(body)

          tool_msg = Enum.find(parsed["messages"], &(&1["role"] == "tool"))
          assert tool_msg["tool_call_id"] == "call_1"
          assert tool_msg["content"] == "Tool output"

          conn
          |> Plug.Conn.put_resp_content_type("text/event-stream")
          |> Plug.Conn.send_resp(200, "data: [DONE]\n")
        end
      ]

      request = %ChatRequest{
        model: "gpt-4o",
        messages: [
          Message.user("Run tool"),
          Message.tool_call("call_1", "test_tool", %{}),
          Message.tool_result("call_1", "Tool output", false)
        ]
      }

      OpenAI.run_chat_stream(request, caller, ref, req_opts)
      assert_receive {:llm, ^ref, _}, 1000
    end

    test "passes error tool results unchanged" do
      ref = make_ref()
      caller = self()

      req_opts = [
        plug: fn conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          parsed = Jason.decode!(body)

          tool_msg = Enum.find(parsed["messages"], &(&1["role"] == "tool"))
          # Error content should be passed unchanged - TrackServer handles error context
          assert tool_msg["content"] == "Command failed"

          conn
          |> Plug.Conn.put_resp_content_type("text/event-stream")
          |> Plug.Conn.send_resp(200, "data: [DONE]\n")
        end
      ]

      request = %ChatRequest{
        model: "gpt-4o",
        messages: [
          Message.user("Run tool"),
          Message.tool_call("call_1", "test_tool", %{}),
          Message.tool_result("call_1", "Command failed", true)
        ]
      }

      OpenAI.run_chat_stream(request, caller, ref, req_opts)
      assert_receive {:llm, ^ref, _}, 1000
    end
  end

  describe "tool transformation" do
    setup do
      System.put_env("MSFAILAB_OPENAI_API_KEY", "sk-test-key")

      on_exit(fn ->
        System.delete_env("MSFAILAB_OPENAI_API_KEY")
      end)

      :ok
    end

    test "transforms tools to OpenAI function format" do
      ref = make_ref()
      caller = self()

      req_opts = [
        plug: fn conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          parsed = Jason.decode!(body)

          assert length(parsed["tools"]) == 1
          tool = hd(parsed["tools"])
          assert tool["type"] == "function"
          assert tool["function"]["name"] == "execute_msfconsole_command"
          assert tool["function"]["description"] == "Execute command"
          assert tool["function"]["parameters"]["type"] == "object"

          conn
          |> Plug.Conn.put_resp_content_type("text/event-stream")
          |> Plug.Conn.send_resp(200, "data: [DONE]\n")
        end
      ]

      request = %ChatRequest{
        model: "gpt-4o",
        messages: [Message.user("Hi")],
        tools: [
          %Tool{
            name: "execute_msfconsole_command",
            short_title: "Running MSF command",
            description: "Execute command",
            parameters: %{
              "type" => "object",
              "properties" => %{"command" => %{"type" => "string"}}
            }
          }
        ]
      }

      OpenAI.run_chat_stream(request, caller, ref, req_opts)
      assert_receive {:llm, ^ref, _}, 1000
    end

    test "includes strict flag when tool has strict: true" do
      ref = make_ref()
      caller = self()

      req_opts = [
        plug: fn conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          parsed = Jason.decode!(body)

          tool = hd(parsed["tools"])
          assert tool["function"]["strict"] == true

          conn
          |> Plug.Conn.put_resp_content_type("text/event-stream")
          |> Plug.Conn.send_resp(200, "data: [DONE]\n")
        end
      ]

      request = %ChatRequest{
        model: "gpt-4o",
        messages: [Message.user("Hi")],
        tools: [
          %Tool{
            name: "execute_msfconsole_command",
            short_title: "Running MSF command",
            description: "Execute command",
            parameters: %{"type" => "object"},
            strict: true
          }
        ]
      }

      OpenAI.run_chat_stream(request, caller, ref, req_opts)
      assert_receive {:llm, ^ref, _}, 1000
    end
  end

  describe "error handling" do
    setup do
      System.put_env("MSFAILAB_OPENAI_API_KEY", "sk-test-key")

      on_exit(fn ->
        System.delete_env("MSFAILAB_OPENAI_API_KEY")
      end)

      :ok
    end

    test "handles rate limit errors as recoverable" do
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
        model: "gpt-4o",
        messages: [Message.user("Hi")]
      }

      OpenAI.run_chat_stream(request, caller, ref, req_opts)

      assert_receive {:llm, ^ref,
                      %Events.StreamError{
                        reason: "Rate limit exceeded",
                        recoverable: true
                      }},
                     1000
    end

    test "handles malformed SSE data gracefully" do
      ref = make_ref()
      caller = self()

      stream_response =
        """
        event: something
        data: not valid json

        data: {"id":"chat-1","choices":[{"delta":{"content":"Hi"},"finish_reason":null}],"model":"gpt-4o"}

        data: [DONE]
        """

      req_opts = [
        plug: fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("text/event-stream")
          |> Plug.Conn.send_resp(200, stream_response)
        end
      ]

      request = %ChatRequest{
        model: "gpt-4o",
        messages: [Message.user("Hi")]
      }

      OpenAI.run_chat_stream(request, caller, ref, req_opts)

      # Should still process valid events
      assert_receive {:llm, ^ref, %Events.StreamStarted{}}, 1000
    end

    test "handles server errors" do
      ref = make_ref()
      caller = self()

      req_opts = [
        plug: fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(
            500,
            Jason.encode!(%{"error" => %{"message" => "Internal error"}})
          )
        end
      ]

      request = %ChatRequest{
        model: "gpt-4o",
        messages: [Message.user("Hi")]
      }

      OpenAI.run_chat_stream(request, caller, ref, req_opts)

      assert_receive {:llm, ^ref,
                      %Events.StreamError{reason: "Internal error", recoverable: true}},
                     1000
    end

    test "handles empty finish_reason with tool calls" do
      ref = make_ref()
      caller = self()

      # Stream where tool calls are present but finish_reason is nil initially
      stream_response =
        """
        data: {"id":"chat-1","model":"gpt-4o","choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":null}]}

        data: {"id":"chat-1","model":"gpt-4o","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"test","arguments":""}}]},"finish_reason":null}]}

        data: {"id":"chat-1","model":"gpt-4o","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{}"}}]},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":10,"completion_tokens":5}}

        data: [DONE]
        """

      req_opts = [
        plug: fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("text/event-stream")
          |> Plug.Conn.send_resp(200, stream_response)
        end
      ]

      request = %ChatRequest{
        model: "gpt-4o",
        messages: [Message.user("Hi")]
      }

      OpenAI.run_chat_stream(request, caller, ref, req_opts)

      assert_receive {:llm, ^ref, %Events.StreamStarted{}}, 1000
      assert_receive {:llm, ^ref, %Events.ContentBlockStart{type: :tool_call}}, 1000
      assert_receive {:llm, ^ref, %Events.ToolCall{name: "test"}}, 1000
      assert_receive {:llm, ^ref, %Events.ContentBlockStop{}}, 1000
      assert_receive {:llm, ^ref, %Events.StreamComplete{stop_reason: :tool_use}}, 1000
    end
  end

  describe "comprehensive integration - full response with all content block types" do
    setup do
      System.put_env("MSFAILAB_OPENAI_API_KEY", "sk-test-key")

      on_exit(fn ->
        System.delete_env("MSFAILAB_OPENAI_API_KEY")
      end)

      :ok
    end

    @doc """
    This test simulates a complete OpenAI response that includes:
    - text content (index 0)
    - two tool_calls (index 1, 2)

    Note: OpenAI doesn't expose thinking blocks in their API (o1/o3 thinking is internal).
    This validates the full event sequence and correct index assignment.
    """
    test "streams text + multiple tool calls with correct indices and events" do
      ref = make_ref()
      caller = self()

      # Complete raw HTTP response mimicking OpenAI's actual streaming format
      stream_response =
        [
          # Initial chunk with role
          ~s(data: {"id":"chatcmpl-AKqLZ123456789","object":"chat.completion.chunk","created":1732678000,"model":"gpt-4o-2024-08-06","choices":[{"index":0,"delta":{"role":"assistant","content":"","refusal":null},"logprobs":null,"finish_reason":null}]}),
          "",
          # Text content chunks
          ~s(data: {"id":"chatcmpl-AKqLZ123456789","object":"chat.completion.chunk","created":1732678000,"model":"gpt-4o-2024-08-06","choices":[{"index":0,"delta":{"content":"I'll help you search for Apache"},"logprobs":null,"finish_reason":null}]}),
          "",
          ~s(data: {"id":"chatcmpl-AKqLZ123456789","object":"chat.completion.chunk","created":1732678000,"model":"gpt-4o-2024-08-06","choices":[{"index":0,"delta":{"content":" exploits and check the current hosts."},"logprobs":null,"finish_reason":null}]}),
          "",
          # First tool call - id and name
          ~s(data: {"id":"chatcmpl-AKqLZ123456789","object":"chat.completion.chunk","created":1732678000,"model":"gpt-4o-2024-08-06","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_abc123def456","type":"function","function":{"name":"execute_msfconsole_command","arguments":""}}]},"logprobs":null,"finish_reason":null}]}),
          "",
          # First tool call - arguments chunk 1
          ~s(data: {"id":"chatcmpl-AKqLZ123456789","object":"chat.completion.chunk","created":1732678000,"model":"gpt-4o-2024-08-06","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\\"com"}}]},"logprobs":null,"finish_reason":null}]}),
          "",
          # First tool call - arguments chunk 2
          ~s(data: {"id":"chatcmpl-AKqLZ123456789","object":"chat.completion.chunk","created":1732678000,"model":"gpt-4o-2024-08-06","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"mand\\":\\"search apache\\"}"}}]},"logprobs":null,"finish_reason":null}]}),
          "",
          # Second tool call - id and name
          ~s(data: {"id":"chatcmpl-AKqLZ123456789","object":"chat.completion.chunk","created":1732678000,"model":"gpt-4o-2024-08-06","choices":[{"index":0,"delta":{"tool_calls":[{"index":1,"id":"call_xyz789ghi012","type":"function","function":{"name":"list_hosts","arguments":""}}]},"logprobs":null,"finish_reason":null}]}),
          "",
          # Second tool call - arguments
          ~s(data: {"id":"chatcmpl-AKqLZ123456789","object":"chat.completion.chunk","created":1732678000,"model":"gpt-4o-2024-08-06","choices":[{"index":0,"delta":{"tool_calls":[{"index":1,"function":{"arguments":"{\\"workspace\\":\\"default\\"}"}}]},"logprobs":null,"finish_reason":null}]}),
          "",
          # Finish with tool_calls and usage
          ~s(data: {"id":"chatcmpl-AKqLZ123456789","object":"chat.completion.chunk","created":1732678000,"model":"gpt-4o-2024-08-06","choices":[{"index":0,"delta":{},"logprobs":null,"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":156,"completion_tokens":87,"total_tokens":243,"prompt_tokens_details":{"cached_tokens":64},"completion_tokens_details":{"reasoning_tokens":0}}}),
          "",
          "data: [DONE]",
          ""
        ]
        |> Enum.join("\n")

      req_opts = [
        plug: fn conn ->
          assert conn.request_path == "/v1/chat/completions"

          conn
          |> Plug.Conn.put_resp_content_type("text/event-stream")
          |> Plug.Conn.send_resp(200, stream_response)
        end
      ]

      request = %ChatRequest{
        model: "gpt-4o-2024-08-06",
        messages: [Message.user("Search for Apache exploits and list hosts")],
        tools: [
          %Tool{
            name: "execute_msfconsole_command",
            short_title: "Running MSF command",
            description: "Execute MSF command",
            parameters: %{"type" => "object"}
          },
          %Tool{
            name: "list_hosts",
            short_title: "Listing hosts",
            description: "List hosts",
            parameters: %{"type" => "object"}
          }
        ]
      }

      OpenAI.run_chat_stream(request, caller, ref, req_opts)

      # 1. Stream started
      assert_receive {:llm, ^ref, %Events.StreamStarted{model: "gpt-4o-2024-08-06"}}, 1000

      # 2. Text block (index 0)
      assert_receive {:llm, ^ref, %Events.ContentBlockStart{index: 0, type: :text}}, 1000

      assert_receive {:llm, ^ref,
                      %Events.ContentDelta{index: 0, delta: "I'll help you search for Apache"}},
                     1000

      assert_receive {:llm, ^ref,
                      %Events.ContentDelta{
                        index: 0,
                        delta: " exploits and check the current hosts."
                      }},
                     1000

      assert_receive {:llm, ^ref, %Events.ContentBlockStop{index: 0}}, 1000

      # 3. First tool_call block (index 1)
      assert_receive {:llm, ^ref, %Events.ContentBlockStart{index: 1, type: :tool_call}}, 1000

      assert_receive {:llm, ^ref,
                      %Events.ToolCall{
                        index: 1,
                        id: "call_abc123def456",
                        name: "execute_msfconsole_command",
                        arguments: %{"command" => "search apache"}
                      }},
                     1000

      assert_receive {:llm, ^ref, %Events.ContentBlockStop{index: 1}}, 1000

      # 4. Second tool_call block (index 2)
      assert_receive {:llm, ^ref, %Events.ContentBlockStart{index: 2, type: :tool_call}}, 1000

      assert_receive {:llm, ^ref,
                      %Events.ToolCall{
                        index: 2,
                        id: "call_xyz789ghi012",
                        name: "list_hosts",
                        arguments: %{"workspace" => "default"}
                      }},
                     1000

      assert_receive {:llm, ^ref, %Events.ContentBlockStop{index: 2}}, 1000

      # 5. Stream complete with correct metrics and stop reason
      assert_receive {:llm, ^ref,
                      %Events.StreamComplete{
                        input_tokens: 156,
                        output_tokens: 87,
                        cached_input_tokens: 64,
                        stop_reason: :tool_use
                      }},
                     1000

      # Verify no more events
      refute_receive {:llm, ^ref, _}, 100
    end

    test "handles tool call with complex nested JSON arguments streamed incrementally" do
      ref = make_ref()
      caller = self()

      # Response with tool call that has complex nested JSON arguments streamed in many small chunks
      stream_response =
        [
          ~s(data: {"id":"chat-nested","model":"gpt-4o","choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":null}]}),
          "",
          ~s(data: {"id":"chat-nested","model":"gpt-4o","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_nested","type":"function","function":{"name":"complex_tool","arguments":""}}]},"finish_reason":null}]}),
          "",
          # Stream the complex JSON in small chunks
          ~s(data: {"id":"chat-nested","model":"gpt-4o","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{"}}]},"finish_reason":null}]}),
          "",
          ~s(data: {"id":"chat-nested","model":"gpt-4o","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\\"options\\":"}}]},"finish_reason":null}]}),
          "",
          ~s(data: {"id":"chat-nested","model":"gpt-4o","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\\"verbose\\":true,\\"level\\":3}"}}]},"finish_reason":null}]}),
          "",
          ~s(data: {"id":"chat-nested","model":"gpt-4o","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":",\\"targets\\":[\\"192.168.1.1\\",\\"192.168.1.2\\"]"}}]},"finish_reason":null}]}),
          "",
          ~s(data: {"id":"chat-nested","model":"gpt-4o","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"}"}}]},"finish_reason":null}]}),
          "",
          ~s(data: {"id":"chat-nested","model":"gpt-4o","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":100,"completion_tokens":40}}),
          "",
          "data: [DONE]",
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
        model: "gpt-4o",
        messages: [Message.user("Run complex tool")]
      }

      OpenAI.run_chat_stream(request, caller, ref, req_opts)

      assert_receive {:llm, ^ref, %Events.StreamStarted{}}, 1000
      assert_receive {:llm, ^ref, %Events.ContentBlockStart{index: 0, type: :tool_call}}, 1000

      # The arguments should be correctly parsed from all the chunks
      assert_receive {:llm, ^ref,
                      %Events.ToolCall{
                        index: 0,
                        id: "call_nested",
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

    test "handles tool calls without preceding text content" do
      ref = make_ref()
      caller = self()

      # Response with only tool calls, no text content
      stream_response =
        [
          ~s(data: {"id":"chat-tools-only","model":"gpt-4o","choices":[{"index":0,"delta":{"role":"assistant","content":null},"finish_reason":null}]}),
          "",
          ~s(data: {"id":"chat-tools-only","model":"gpt-4o","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_direct","type":"function","function":{"name":"direct_action","arguments":"{\\"immediate\\":true}"}}]},"finish_reason":null}]}),
          "",
          ~s(data: {"id":"chat-tools-only","model":"gpt-4o","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":50,"completion_tokens":15}}),
          "",
          "data: [DONE]",
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
        model: "gpt-4o",
        messages: [Message.user("Do it now")]
      }

      OpenAI.run_chat_stream(request, caller, ref, req_opts)

      assert_receive {:llm, ^ref, %Events.StreamStarted{}}, 1000

      # Should go directly to tool call at index 0 (no text block)
      assert_receive {:llm, ^ref, %Events.ContentBlockStart{index: 0, type: :tool_call}}, 1000

      assert_receive {:llm, ^ref,
                      %Events.ToolCall{
                        index: 0,
                        id: "call_direct",
                        name: "direct_action",
                        arguments: %{"immediate" => true}
                      }},
                     1000

      assert_receive {:llm, ^ref, %Events.ContentBlockStop{index: 0}}, 1000

      assert_receive {:llm, ^ref, %Events.StreamComplete{stop_reason: :tool_use}}, 1000

      # Verify no text block was emitted
      refute_receive {:llm, ^ref, %Events.ContentBlockStart{type: :text}}, 100
    end

    test "handles parallel tool calls arriving in interleaved chunks" do
      ref = make_ref()
      caller = self()

      # Simulates the rare case where tool call arguments are interleaved
      stream_response =
        [
          ~s(data: {"id":"chat-interleaved","model":"gpt-4o","choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":null}]}),
          "",
          # Both tool calls start in the same chunk
          ~s(data: {"id":"chat-interleaved","model":"gpt-4o","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_a","type":"function","function":{"name":"tool_a","arguments":""}},{"index":1,"id":"call_b","type":"function","function":{"name":"tool_b","arguments":""}}]},"finish_reason":null}]}),
          "",
          # Arguments come interleaved
          ~s(data: {"id":"chat-interleaved","model":"gpt-4o","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\\"x\\""}},{"index":1,"function":{"arguments":"{\\"y\\""}}]},"finish_reason":null}]}),
          "",
          ~s(data: {"id":"chat-interleaved","model":"gpt-4o","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":":1}"}},{"index":1,"function":{"arguments":":2}"}}]},"finish_reason":null}]}),
          "",
          ~s(data: {"id":"chat-interleaved","model":"gpt-4o","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":30,"completion_tokens":20}}),
          "",
          "data: [DONE]",
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
        model: "gpt-4o",
        messages: [Message.user("Run both")]
      }

      OpenAI.run_chat_stream(request, caller, ref, req_opts)

      assert_receive {:llm, ^ref, %Events.StreamStarted{}}, 1000

      # First tool call
      assert_receive {:llm, ^ref, %Events.ContentBlockStart{index: 0, type: :tool_call}}, 1000

      assert_receive {:llm, ^ref,
                      %Events.ToolCall{
                        index: 0,
                        id: "call_a",
                        name: "tool_a",
                        arguments: %{"x" => 1}
                      }},
                     1000

      assert_receive {:llm, ^ref, %Events.ContentBlockStop{index: 0}}, 1000

      # Second tool call
      assert_receive {:llm, ^ref, %Events.ContentBlockStart{index: 1, type: :tool_call}}, 1000

      assert_receive {:llm, ^ref,
                      %Events.ToolCall{
                        index: 1,
                        id: "call_b",
                        name: "tool_b",
                        arguments: %{"y" => 2}
                      }},
                     1000

      assert_receive {:llm, ^ref, %Events.ContentBlockStop{index: 1}}, 1000

      assert_receive {:llm, ^ref, %Events.StreamComplete{stop_reason: :tool_use}}, 1000
    end
  end

  describe "trace formatting" do
    test "formats successful response with content and tool calls" do
      acc = %{
        trace_content: "I'll help you search for that information.",
        trace_tool_calls: [
          %{id: "call_xyz789", name: "list_hosts", arguments: %{"workspace" => "default"}},
          %{id: "call_abc123", name: "search", arguments: %{"query" => "apache"}}
        ],
        trace_metadata: %{
          input_tokens: 100,
          output_tokens: 50,
          cached_input_tokens: 25,
          stop_reason: :tool_use
        }
      }

      result = OpenAI.format_trace_response(acc, 200)

      # Should contain content section
      assert result =~ "--- CONTENT ---"
      assert result =~ "I'll help you search for that information."

      # Should contain tool calls section (reversed order for display)
      assert result =~ "--- TOOL_CALLS ---"
      assert result =~ "call_abc123"
      assert result =~ "search"
      assert result =~ "call_xyz789"
      assert result =~ "list_hosts"

      # Should contain metadata section
      assert result =~ "--- METADATA ---"
      assert result =~ "\"input_tokens\": 100"
      assert result =~ "\"output_tokens\": 50"
      assert result =~ "\"cached_input_tokens\": 25"
    end

    test "formats response with only content" do
      acc = %{
        trace_content: "Simple response without tools.",
        trace_tool_calls: [],
        trace_metadata: %{
          input_tokens: 50,
          output_tokens: 10,
          stop_reason: :end_turn
        }
      }

      result = OpenAI.format_trace_response(acc, 200)

      assert result =~ "--- CONTENT ---"
      assert result =~ "Simple response without tools."
      assert result =~ "--- METADATA ---"
      refute result =~ "--- TOOL_CALLS ---"
    end

    test "formats response with only tool calls (no content)" do
      acc = %{
        trace_content: "",
        trace_tool_calls: [
          %{id: "call_direct", name: "direct_action", arguments: %{"immediate" => true}}
        ],
        trace_metadata: %{stop_reason: :tool_use}
      }

      result = OpenAI.format_trace_response(acc, 200)

      refute result =~ "--- CONTENT ---"
      assert result =~ "--- TOOL_CALLS ---"
      assert result =~ "direct_action"
      assert result =~ "--- METADATA ---"
    end

    test "formats empty response" do
      acc = %{
        trace_content: "",
        trace_tool_calls: [],
        trace_metadata: nil
      }

      result = OpenAI.format_trace_response(acc, 200)

      assert result == "(empty response)"
    end

    test "formats error response with raw body" do
      acc = %{
        raw_body: ~s({"error": {"type": "rate_limit_exceeded", "message": "Rate limit exceeded"}})
      }

      result = OpenAI.format_trace_response(acc, 429)

      assert result =~ "--- ERROR RESPONSE ---"
      assert result =~ "rate_limit_exceeded"
      assert result =~ "Rate limit exceeded"
    end

    test "formats error response with non-JSON body" do
      acc = %{
        raw_body: "Service temporarily unavailable"
      }

      result = OpenAI.format_trace_response(acc, 503)

      assert result =~ "--- ERROR RESPONSE ---"
      assert result =~ "Service temporarily unavailable"
    end

    test "formats error response with empty body" do
      acc = %{
        raw_body: ""
      }

      result = OpenAI.format_trace_response(acc, 500)

      assert result == "(empty error response)"
    end

    test "formats multiple tool calls in correct order" do
      # Tool calls are stored in reverse order during streaming, so they need to be reversed for display
      acc = %{
        trace_content: "",
        trace_tool_calls: [
          %{id: "call_3", name: "tool_c", arguments: %{"z" => 3}},
          %{id: "call_2", name: "tool_b", arguments: %{"y" => 2}},
          %{id: "call_1", name: "tool_a", arguments: %{"x" => 1}}
        ],
        trace_metadata: %{stop_reason: :tool_use}
      }

      result = OpenAI.format_trace_response(acc, 200)

      # Tool calls should be in original order (call_1, call_2, call_3)
      tool_calls_section = result |> String.split("--- METADATA ---") |> List.first()
      call_1_pos = :binary.match(tool_calls_section, "call_1") |> elem(0)
      call_2_pos = :binary.match(tool_calls_section, "call_2") |> elem(0)
      call_3_pos = :binary.match(tool_calls_section, "call_3") |> elem(0)

      assert call_1_pos < call_2_pos
      assert call_2_pos < call_3_pos
    end
  end
end
