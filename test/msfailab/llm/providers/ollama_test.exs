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

defmodule Msfailab.LLM.Providers.OllamaTest do
  use ExUnit.Case, async: true

  alias Msfailab.LLM.ChatRequest
  alias Msfailab.LLM.Events
  alias Msfailab.LLM.Message
  alias Msfailab.LLM.Model
  alias Msfailab.LLM.Providers.Ollama
  alias Msfailab.Tools.Tool

  describe "configured?/0" do
    test "returns true when MSFAILAB_OLLAMA_HOST is set" do
      System.put_env("MSFAILAB_OLLAMA_HOST", "http://localhost:11434")
      assert Ollama.configured?()
      System.delete_env("MSFAILAB_OLLAMA_HOST")
    end

    test "returns false when MSFAILAB_OLLAMA_HOST is not set" do
      System.delete_env("MSFAILAB_OLLAMA_HOST")
      refute Ollama.configured?()
    end

    test "returns false when MSFAILAB_OLLAMA_HOST is empty string" do
      System.put_env("MSFAILAB_OLLAMA_HOST", "")
      refute Ollama.configured?()
      System.delete_env("MSFAILAB_OLLAMA_HOST")
    end
  end

  describe "URL normalization" do
    test "adds http:// when protocol is missing" do
      System.put_env("MSFAILAB_OLLAMA_HOST", "192.168.1.10:11434")

      req_opts = [
        plug: fn conn ->
          case conn.request_path do
            "/api/tags" ->
              # Verify the request was made to correct URL
              assert conn.host == "192.168.1.10"
              assert conn.port == 11_434

              conn
              |> Plug.Conn.put_resp_content_type("application/json")
              |> Plug.Conn.send_resp(
                200,
                Jason.encode!(%{"models" => [%{"name" => "llama3:latest"}]})
              )

            "/api/show" ->
              conn
              |> Plug.Conn.put_resp_content_type("application/json")
              |> Plug.Conn.send_resp(200, Jason.encode!(%{"model_info" => %{}}))
          end
        end
      ]

      assert {:ok, [_model]} = Ollama.list_models(req_opts)
      System.delete_env("MSFAILAB_OLLAMA_HOST")
    end

    test "preserves http:// when already present" do
      System.put_env("MSFAILAB_OLLAMA_HOST", "http://localhost:11434")

      req_opts = [
        plug: fn conn ->
          case conn.request_path do
            "/api/tags" ->
              assert conn.scheme == :http
              assert conn.host == "localhost"
              assert conn.port == 11_434

              conn
              |> Plug.Conn.put_resp_content_type("application/json")
              |> Plug.Conn.send_resp(
                200,
                Jason.encode!(%{"models" => [%{"name" => "llama3:latest"}]})
              )

            "/api/show" ->
              conn
              |> Plug.Conn.put_resp_content_type("application/json")
              |> Plug.Conn.send_resp(200, Jason.encode!(%{"model_info" => %{}}))
          end
        end
      ]

      assert {:ok, [_model]} = Ollama.list_models(req_opts)
      System.delete_env("MSFAILAB_OLLAMA_HOST")
    end

    test "preserves https:// when present" do
      System.put_env("MSFAILAB_OLLAMA_HOST", "https://ollama.example.com")

      req_opts = [
        plug: fn conn ->
          case conn.request_path do
            "/api/tags" ->
              assert conn.scheme == :https
              assert conn.host == "ollama.example.com"

              conn
              |> Plug.Conn.put_resp_content_type("application/json")
              |> Plug.Conn.send_resp(
                200,
                Jason.encode!(%{"models" => [%{"name" => "llama3:latest"}]})
              )

            "/api/show" ->
              conn
              |> Plug.Conn.put_resp_content_type("application/json")
              |> Plug.Conn.send_resp(200, Jason.encode!(%{"model_info" => %{}}))
          end
        end
      ]

      assert {:ok, [_model]} = Ollama.list_models(req_opts)
      System.delete_env("MSFAILAB_OLLAMA_HOST")
    end

    test "strips trailing slash from URL" do
      System.put_env("MSFAILAB_OLLAMA_HOST", "http://localhost:11434/")

      req_opts = [
        plug: fn conn ->
          case conn.request_path do
            "/api/tags" ->
              # Path should be /api/tags not //api/tags
              conn
              |> Plug.Conn.put_resp_content_type("application/json")
              |> Plug.Conn.send_resp(
                200,
                Jason.encode!(%{"models" => [%{"name" => "llama3:latest"}]})
              )

            "/api/show" ->
              conn
              |> Plug.Conn.put_resp_content_type("application/json")
              |> Plug.Conn.send_resp(200, Jason.encode!(%{"model_info" => %{}}))
          end
        end
      ]

      assert {:ok, [_model]} = Ollama.list_models(req_opts)
      System.delete_env("MSFAILAB_OLLAMA_HOST")
    end
  end

  describe "list_models/1 with mocked HTTP" do
    setup do
      System.put_env("MSFAILAB_OLLAMA_HOST", "http://localhost:11434")

      on_exit(fn ->
        System.delete_env("MSFAILAB_OLLAMA_HOST")
      end)

      :ok
    end

    test "returns models with context windows from API" do
      # Mock HTTP responses using Req's plug option
      req_opts = [
        plug: fn conn ->
          case conn.request_path do
            "/api/tags" ->
              conn
              |> Plug.Conn.put_resp_content_type("application/json")
              |> Plug.Conn.send_resp(
                200,
                Jason.encode!(%{
                  "models" => [
                    %{"name" => "llama3.1:latest"},
                    %{"name" => "qwen2:7b"}
                  ]
                })
              )

            "/api/show" ->
              body = Plug.Conn.read_body(conn) |> elem(1) |> Jason.decode!()

              response =
                case body["name"] do
                  "llama3.1:latest" ->
                    %{"model_info" => %{"llama.context_length" => 131_072}}

                  "qwen2:7b" ->
                    %{"model_info" => %{"qwen2.context_length" => 32_768}}
                end

              conn
              |> Plug.Conn.put_resp_content_type("application/json")
              |> Plug.Conn.send_resp(200, Jason.encode!(response))
          end
        end
      ]

      assert {:ok, models} = Ollama.list_models(req_opts)
      assert length(models) == 2

      llama_model = Enum.find(models, &(&1.name == "llama3.1:latest"))
      assert %Model{provider: :ollama, context_window: 131_072} = llama_model

      qwen_model = Enum.find(models, &(&1.name == "qwen2:7b"))
      assert %Model{provider: :ollama, context_window: 32_768} = qwen_model
    end

    test "uses default context window when not in model_info" do
      req_opts = [
        plug: fn conn ->
          case conn.request_path do
            "/api/tags" ->
              conn
              |> Plug.Conn.put_resp_content_type("application/json")
              |> Plug.Conn.send_resp(
                200,
                Jason.encode!(%{
                  "models" => [%{"name" => "unknown-model:latest"}]
                })
              )

            "/api/show" ->
              # No context_length in response
              conn
              |> Plug.Conn.put_resp_content_type("application/json")
              |> Plug.Conn.send_resp(
                200,
                Jason.encode!(%{
                  "model_info" => %{"general.architecture" => "unknown"}
                })
              )
          end
        end
      ]

      assert {:ok, [model]} = Ollama.list_models(req_opts)
      # Default context window
      assert model.context_window == 200_000
    end

    test "extracts context window from parameters string" do
      req_opts = [
        plug: fn conn ->
          case conn.request_path do
            "/api/tags" ->
              conn
              |> Plug.Conn.put_resp_content_type("application/json")
              |> Plug.Conn.send_resp(
                200,
                Jason.encode!(%{
                  "models" => [%{"name" => "custom-model:latest"}]
                })
              )

            "/api/show" ->
              conn
              |> Plug.Conn.put_resp_content_type("application/json")
              |> Plug.Conn.send_resp(
                200,
                Jason.encode!(%{
                  "parameters" => "num_ctx 8192\ntemperature 0.7"
                })
              )
          end
        end
      ]

      assert {:ok, [model]} = Ollama.list_models(req_opts)
      assert model.context_window == 8192
    end

    test "returns error on connection failure" do
      req_opts = [
        plug: fn conn ->
          Plug.Conn.send_resp(conn, 500, "Internal Server Error")
        end
      ]

      assert {:error, {:unexpected_status, 500}} = Ollama.list_models(req_opts)
    end

    test "returns error when no models pulled" do
      req_opts = [
        plug: fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(200, Jason.encode!(%{"models" => []}))
        end
      ]

      # Empty model list from API is now an error condition
      assert {:error, :no_models_from_api} = Ollama.list_models(req_opts)
    end
  end

  describe "run_chat_stream/4 - basic streaming" do
    setup do
      System.put_env("MSFAILAB_OLLAMA_HOST", "http://localhost:11434")

      on_exit(fn ->
        System.delete_env("MSFAILAB_OLLAMA_HOST")
      end)

      :ok
    end

    test "streams text response with proper events" do
      ref = make_ref()
      caller = self()

      stream_response =
        [
          ~s({"model":"llama3.1","message":{"role":"assistant","content":"Hello"},"done":false}),
          ~s({"model":"llama3.1","message":{"role":"assistant","content":" world"},"done":false}),
          ~s({"model":"llama3.1","message":{"role":"assistant","content":"!"},"done":true,"done_reason":"stop","prompt_eval_count":10,"eval_count":3}),
          ""
        ]
        |> Enum.join("\n")

      req_opts = [
        plug: fn conn ->
          assert conn.request_path == "/api/chat"

          conn
          |> Plug.Conn.put_resp_content_type("application/x-ndjson")
          |> Plug.Conn.send_resp(200, stream_response)
        end
      ]

      request = %ChatRequest{
        model: "llama3.1",
        messages: [Message.user("Hi")],
        max_tokens: 100,
        temperature: 0.1
      }

      Ollama.run_chat_stream(request, caller, ref, req_opts)

      assert_receive {:llm, ^ref, %Events.StreamStarted{model: "llama3.1"}}, 1000
      assert_receive {:llm, ^ref, %Events.ContentBlockStart{index: 0, type: :text}}, 1000
      assert_receive {:llm, ^ref, %Events.ContentDelta{index: 0, delta: "Hello"}}, 1000
      assert_receive {:llm, ^ref, %Events.ContentDelta{index: 0, delta: " world"}}, 1000
      assert_receive {:llm, ^ref, %Events.ContentDelta{index: 0, delta: "!"}}, 1000
      assert_receive {:llm, ^ref, %Events.ContentBlockStop{index: 0}}, 1000

      assert_receive {:llm, ^ref,
                      %Events.StreamComplete{
                        input_tokens: 10,
                        output_tokens: 3,
                        stop_reason: :end_turn
                      }},
                     1000
    end

    test "handles tool call response" do
      ref = make_ref()
      caller = self()

      # Ollama sends tool_calls in a done=false chunk just before the final done=true chunk
      stream_response =
        [
          ~s({"model":"llama3.1","message":{"role":"assistant","content":"Let me search"},"done":false}),
          ~s({"model":"llama3.1","message":{"role":"assistant","content":"","tool_calls":[{"function":{"name":"msf_command","arguments":{"command":"search apache"}}}]},"done":false}),
          ~s({"model":"llama3.1","message":{"role":"assistant","content":""},"done":true,"done_reason":"stop","prompt_eval_count":15,"eval_count":20}),
          ""
        ]
        |> Enum.join("\n")

      req_opts = [
        plug: fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/x-ndjson")
          |> Plug.Conn.send_resp(200, stream_response)
        end
      ]

      request = %ChatRequest{
        model: "llama3.1",
        messages: [Message.user("Search for apache exploits")],
        tools: [
          %Tool{
            name: "msf_command",
            description: "Execute MSF command",
            parameters: %{"type" => "object", "properties" => %{}}
          }
        ]
      }

      Ollama.run_chat_stream(request, caller, ref, req_opts)

      assert_receive {:llm, ^ref, %Events.StreamStarted{}}, 1000
      assert_receive {:llm, ^ref, %Events.ContentBlockStart{index: 0, type: :text}}, 1000
      assert_receive {:llm, ^ref, %Events.ContentDelta{index: 0, delta: "Let me search"}}, 1000
      assert_receive {:llm, ^ref, %Events.ContentBlockStop{index: 0}}, 1000
      assert_receive {:llm, ^ref, %Events.ContentBlockStart{index: 1, type: :tool_call}}, 1000

      assert_receive {:llm, ^ref,
                      %Events.ToolCall{
                        index: 1,
                        name: "msf_command",
                        arguments: %{"command" => "search apache"}
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
          |> Plug.Conn.send_resp(500, Jason.encode!(%{"error" => "Model not found"}))
        end
      ]

      request = %ChatRequest{
        model: "nonexistent",
        messages: [Message.user("Hi")]
      }

      Ollama.run_chat_stream(request, caller, ref, req_opts)

      assert_receive {:llm, ^ref,
                      %Events.StreamError{reason: "Model not found", recoverable: false}},
                     1000
    end

    test "includes system prompt in request" do
      ref = make_ref()
      caller = self()

      req_opts = [
        plug: fn conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          parsed = Jason.decode!(body)

          assert Enum.any?(parsed["messages"], fn msg ->
                   msg["role"] == "system" and msg["content"] == "You are a security assistant"
                 end)

          conn
          |> Plug.Conn.put_resp_content_type("application/x-ndjson")
          |> Plug.Conn.send_resp(
            200,
            ~s({"model":"llama3.1","message":{"role":"assistant","content":""},"done":true,"done_reason":"stop"}\n)
          )
        end
      ]

      request = %ChatRequest{
        model: "llama3.1",
        messages: [Message.user("Hi")],
        system_prompt: "You are a security assistant"
      }

      Ollama.run_chat_stream(request, caller, ref, req_opts)

      assert_receive {:llm, ^ref, %Events.StreamComplete{}}, 1000
    end

    test "includes cache context when provided" do
      ref = make_ref()
      caller = self()
      context = [1, 2, 3, 4, 5]

      req_opts = [
        plug: fn conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          parsed = Jason.decode!(body)

          assert parsed["context"] == context

          conn
          |> Plug.Conn.put_resp_content_type("application/x-ndjson")
          |> Plug.Conn.send_resp(
            200,
            ~s({"model":"llama3.1","message":{"role":"assistant","content":""},"done":true,"done_reason":"stop","context":[1,2,3,4,5,6]}\n)
          )
        end
      ]

      request = %ChatRequest{
        model: "llama3.1",
        messages: [Message.user("Hi")],
        cache_context: context
      }

      Ollama.run_chat_stream(request, caller, ref, req_opts)

      assert_receive {:llm, ^ref, %Events.StreamComplete{cache_context: [1, 2, 3, 4, 5, 6]}}, 1000
    end

    test "returns max_tokens stop reason when truncated" do
      ref = make_ref()
      caller = self()

      stream_response =
        ~s({"model":"llama3.1","message":{"role":"assistant","content":"truncated"},"done":true,"done_reason":"length","prompt_eval_count":10,"eval_count":100}\n)

      req_opts = [
        plug: fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/x-ndjson")
          |> Plug.Conn.send_resp(200, stream_response)
        end
      ]

      request = %ChatRequest{
        model: "llama3.1",
        messages: [Message.user("Hi")],
        max_tokens: 100
      }

      Ollama.run_chat_stream(request, caller, ref, req_opts)

      assert_receive {:llm, ^ref, %Events.StreamComplete{stop_reason: :max_tokens}}, 1000
    end
  end

  describe "message transformation" do
    setup do
      System.put_env("MSFAILAB_OLLAMA_HOST", "http://localhost:11434")

      on_exit(fn ->
        System.delete_env("MSFAILAB_OLLAMA_HOST")
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
          |> Plug.Conn.put_resp_content_type("application/x-ndjson")
          |> Plug.Conn.send_resp(
            200,
            ~s({"model":"llama3.1","message":{"role":"assistant","content":""},"done":true,"done_reason":"stop"}\n)
          )
        end
      ]

      request = %ChatRequest{
        model: "llama3.1",
        messages: [Message.user("Hello world")]
      }

      Ollama.run_chat_stream(request, caller, ref, req_opts)
      assert_receive {:llm, ^ref, %Events.StreamComplete{}}, 1000
    end

    test "transforms assistant messages with tool calls" do
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
          assert tool_call["function"]["name"] == "msf_command"
          assert tool_call["function"]["arguments"] == %{"command" => "search"}

          conn
          |> Plug.Conn.put_resp_content_type("application/x-ndjson")
          |> Plug.Conn.send_resp(
            200,
            ~s({"model":"llama3.1","message":{"role":"assistant","content":""},"done":true,"done_reason":"stop"}\n)
          )
        end
      ]

      request = %ChatRequest{
        model: "llama3.1",
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

      Ollama.run_chat_stream(request, caller, ref, req_opts)
      assert_receive {:llm, ^ref, %Events.StreamComplete{}}, 1000
    end

    test "transforms tool result messages" do
      ref = make_ref()
      caller = self()

      req_opts = [
        plug: fn conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          parsed = Jason.decode!(body)

          tool_msg = Enum.find(parsed["messages"], &(&1["role"] == "tool"))
          assert tool_msg["content"] == "Tool output"

          conn
          |> Plug.Conn.put_resp_content_type("application/x-ndjson")
          |> Plug.Conn.send_resp(
            200,
            ~s({"model":"llama3.1","message":{"role":"assistant","content":""},"done":true,"done_reason":"stop"}\n)
          )
        end
      ]

      request = %ChatRequest{
        model: "llama3.1",
        messages: [
          Message.user("Run tool"),
          Message.tool_call("call_1", "test_tool", %{}),
          Message.tool_result("call_1", "Tool output", false)
        ]
      }

      Ollama.run_chat_stream(request, caller, ref, req_opts)
      assert_receive {:llm, ^ref, %Events.StreamComplete{}}, 1000
    end
  end

  describe "tool transformation" do
    setup do
      System.put_env("MSFAILAB_OLLAMA_HOST", "http://localhost:11434")

      on_exit(fn ->
        System.delete_env("MSFAILAB_OLLAMA_HOST")
      end)

      :ok
    end

    test "transforms tools to OpenAI-compatible format" do
      ref = make_ref()
      caller = self()

      req_opts = [
        plug: fn conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          parsed = Jason.decode!(body)

          assert length(parsed["tools"]) == 1
          tool = hd(parsed["tools"])
          assert tool["type"] == "function"
          assert tool["function"]["name"] == "msf_command"
          assert tool["function"]["description"] == "Execute command"
          assert tool["function"]["parameters"]["type"] == "object"

          conn
          |> Plug.Conn.put_resp_content_type("application/x-ndjson")
          |> Plug.Conn.send_resp(
            200,
            ~s({"model":"llama3.1","message":{"role":"assistant","content":""},"done":true,"done_reason":"stop"}\n)
          )
        end
      ]

      request = %ChatRequest{
        model: "llama3.1",
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

      Ollama.run_chat_stream(request, caller, ref, req_opts)
      assert_receive {:llm, ^ref, %Events.StreamComplete{}}, 1000
    end
  end

  describe "thinking blocks" do
    setup do
      System.put_env("MSFAILAB_OLLAMA_HOST", "http://localhost:11434")

      on_exit(fn ->
        System.delete_env("MSFAILAB_OLLAMA_HOST")
        Application.delete_env(:msfailab, :ollama_thinking)
      end)

      :ok
    end

    test "streams thinking blocks followed by text response" do
      Application.put_env(:msfailab, :ollama_thinking, true)
      ref = make_ref()
      caller = self()

      stream_response =
        [
          ~s({"model":"qwen3:30b","message":{"role":"assistant","thinking":"Let me think"},"done":false}),
          ~s({"model":"qwen3:30b","message":{"role":"assistant","thinking":" about this..."},"done":false}),
          ~s({"model":"qwen3:30b","message":{"role":"assistant","content":"The answer"},"done":false}),
          ~s({"model":"qwen3:30b","message":{"role":"assistant","content":" is 42."},"done":true,"done_reason":"stop","prompt_eval_count":10,"eval_count":8}),
          ""
        ]
        |> Enum.join("\n")

      req_opts = [
        plug: fn conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          parsed = Jason.decode!(body)

          # Verify think parameter is included
          assert parsed["think"] == true

          conn
          |> Plug.Conn.put_resp_content_type("application/x-ndjson")
          |> Plug.Conn.send_resp(200, stream_response)
        end
      ]

      request = %ChatRequest{
        model: "qwen3:30b",
        messages: [Message.user("What is the meaning of life?")],
        max_tokens: 100,
        temperature: 0.1
      }

      Ollama.run_chat_stream(request, caller, ref, req_opts)

      # Thinking block
      assert_receive {:llm, ^ref, %Events.StreamStarted{model: "qwen3:30b"}}, 1000
      assert_receive {:llm, ^ref, %Events.ContentBlockStart{index: 0, type: :thinking}}, 1000
      assert_receive {:llm, ^ref, %Events.ContentDelta{index: 0, delta: "Let me think"}}, 1000
      assert_receive {:llm, ^ref, %Events.ContentDelta{index: 0, delta: " about this..."}}, 1000
      assert_receive {:llm, ^ref, %Events.ContentBlockStop{index: 0}}, 1000

      # Text block
      assert_receive {:llm, ^ref, %Events.ContentBlockStart{index: 1, type: :text}}, 1000
      assert_receive {:llm, ^ref, %Events.ContentDelta{index: 1, delta: "The answer"}}, 1000
      assert_receive {:llm, ^ref, %Events.ContentDelta{index: 1, delta: " is 42."}}, 1000
      assert_receive {:llm, ^ref, %Events.ContentBlockStop{index: 1}}, 1000

      assert_receive {:llm, ^ref,
                      %Events.StreamComplete{
                        input_tokens: 10,
                        output_tokens: 8,
                        stop_reason: :end_turn
                      }},
                     1000
    end

    test "handles thinking only response (no content)" do
      Application.put_env(:msfailab, :ollama_thinking, true)
      ref = make_ref()
      caller = self()

      stream_response =
        [
          ~s({"model":"qwen3:30b","message":{"role":"assistant","thinking":"Thinking..."},"done":false}),
          ~s({"model":"qwen3:30b","message":{"role":"assistant","thinking":""},"done":true,"done_reason":"stop","prompt_eval_count":5,"eval_count":3}),
          ""
        ]
        |> Enum.join("\n")

      req_opts = [
        plug: fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/x-ndjson")
          |> Plug.Conn.send_resp(200, stream_response)
        end
      ]

      request = %ChatRequest{
        model: "qwen3:30b",
        messages: [Message.user("Think")]
      }

      Ollama.run_chat_stream(request, caller, ref, req_opts)

      assert_receive {:llm, ^ref, %Events.StreamStarted{}}, 1000
      assert_receive {:llm, ^ref, %Events.ContentBlockStart{index: 0, type: :thinking}}, 1000
      assert_receive {:llm, ^ref, %Events.ContentDelta{index: 0, delta: "Thinking..."}}, 1000
      assert_receive {:llm, ^ref, %Events.ContentBlockStop{index: 0}}, 1000
      assert_receive {:llm, ^ref, %Events.StreamComplete{}}, 1000
    end

    test "sends think=false when thinking is disabled" do
      Application.put_env(:msfailab, :ollama_thinking, false)
      ref = make_ref()
      caller = self()

      req_opts = [
        plug: fn conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          parsed = Jason.decode!(body)

          # Verify think parameter is false
          assert parsed["think"] == false

          conn
          |> Plug.Conn.put_resp_content_type("application/x-ndjson")
          |> Plug.Conn.send_resp(
            200,
            ~s({"model":"qwen3:30b","message":{"role":"assistant","content":"Hi"},"done":true,"done_reason":"stop"}\n)
          )
        end
      ]

      request = %ChatRequest{
        model: "qwen3:30b",
        messages: [Message.user("Hi")]
      }

      Ollama.run_chat_stream(request, caller, ref, req_opts)

      assert_receive {:llm, ^ref, %Events.StreamComplete{}}, 1000
    end

    test "defaults to thinking enabled" do
      # Clear any existing config
      Application.delete_env(:msfailab, :ollama_thinking)
      ref = make_ref()
      caller = self()

      req_opts = [
        plug: fn conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          parsed = Jason.decode!(body)

          # Verify think parameter defaults to true
          assert parsed["think"] == true

          conn
          |> Plug.Conn.put_resp_content_type("application/x-ndjson")
          |> Plug.Conn.send_resp(
            200,
            ~s({"model":"qwen3:30b","message":{"role":"assistant","content":"Hi"},"done":true,"done_reason":"stop"}\n)
          )
        end
      ]

      request = %ChatRequest{
        model: "qwen3:30b",
        messages: [Message.user("Hi")]
      }

      Ollama.run_chat_stream(request, caller, ref, req_opts)

      assert_receive {:llm, ^ref, %Events.StreamComplete{}}, 1000
    end
  end

  describe "error handling" do
    setup do
      System.put_env("MSFAILAB_OLLAMA_HOST", "http://localhost:11434")

      on_exit(fn ->
        System.delete_env("MSFAILAB_OLLAMA_HOST")
      end)

      :ok
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
          |> Plug.Conn.put_resp_content_type("application/x-ndjson")
          |> Plug.Conn.send_resp(
            200,
            ~s({"model":"llama3.1","message":{"role":"assistant","content":""},"done":true,"done_reason":"stop"}\n)
          )
        end
      ]

      request = %ChatRequest{
        model: "llama3.1",
        messages: [
          Message.user("Run tool"),
          Message.tool_call("call_1", "test_tool", %{}),
          Message.tool_result("call_1", "Command failed", true)
        ]
      }

      Ollama.run_chat_stream(request, caller, ref, req_opts)
      assert_receive {:llm, ^ref, %Events.StreamComplete{}}, 1000
    end

    test "handles HTTP status with no error body" do
      ref = make_ref()
      caller = self()

      req_opts = [
        plug: fn conn ->
          Plug.Conn.send_resp(conn, 503, "")
        end
      ]

      request = %ChatRequest{
        model: "llama3.1",
        messages: [Message.user("Hi")]
      }

      Ollama.run_chat_stream(request, caller, ref, req_opts)

      assert_receive {:llm, ^ref, %Events.StreamError{reason: "HTTP 503", recoverable: false}},
                     1000
    end

    test "handles response without text content" do
      ref = make_ref()
      caller = self()

      # Ollama sends tool_calls in a done=false chunk just before the final done=true chunk
      stream_response =
        [
          ~s({"model":"llama3.1","message":{"role":"assistant","content":"","tool_calls":[{"function":{"name":"test","arguments":{}}}]},"done":false}),
          ~s({"model":"llama3.1","message":{"role":"assistant","content":""},"done":true,"done_reason":"stop"})
        ]
        |> Enum.join("\n")

      req_opts = [
        plug: fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/x-ndjson")
          |> Plug.Conn.send_resp(200, stream_response)
        end
      ]

      request = %ChatRequest{
        model: "llama3.1",
        messages: [Message.user("Hi")]
      }

      Ollama.run_chat_stream(request, caller, ref, req_opts)

      # Should still emit tool call events
      assert_receive {:llm, ^ref, %Events.StreamStarted{}}, 1000
      assert_receive {:llm, ^ref, %Events.ContentBlockStart{type: :tool_call}}, 1000
      assert_receive {:llm, ^ref, %Events.ToolCall{name: "test"}}, 1000
      assert_receive {:llm, ^ref, %Events.ContentBlockStop{}}, 1000
      assert_receive {:llm, ^ref, %Events.StreamComplete{stop_reason: :tool_use}}, 1000
    end

    test "handles malformed JSON in stream" do
      ref = make_ref()
      caller = self()

      stream_response =
        "not valid json\n{\"model\":\"llama3.1\",\"message\":{\"role\":\"assistant\",\"content\":\"Hi\"},\"done\":true,\"done_reason\":\"stop\"}"

      req_opts = [
        plug: fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/x-ndjson")
          |> Plug.Conn.send_resp(200, stream_response)
        end
      ]

      request = %ChatRequest{
        model: "llama3.1",
        messages: [Message.user("Hi")]
      }

      Ollama.run_chat_stream(request, caller, ref, req_opts)

      # Should recover and process valid JSON
      assert_receive {:llm, ^ref, %Events.StreamStarted{}}, 1000
      assert_receive {:llm, ^ref, %Events.StreamComplete{}}, 1000
    end
  end

  describe "comprehensive integration - full response with all content block types" do
    setup do
      System.put_env("MSFAILAB_OLLAMA_HOST", "http://localhost:11434")
      Application.put_env(:msfailab, :ollama_thinking, true)

      on_exit(fn ->
        System.delete_env("MSFAILAB_OLLAMA_HOST")
        Application.delete_env(:msfailab, :ollama_thinking)
      end)

      :ok
    end

    @doc """
    This test simulates a complete Ollama response that includes:
    - thinking block (index 0)
    - text block (index 1)
    - two tool_calls (index 2, 3)

    Ollama streams thinking and content in separate messages, then sends
    tool_calls in a done=false chunk just before the final done=true chunk.
    This validates the full event sequence and correct index assignment.
    """
    test "streams thinking + text + multiple tool calls with correct indices and events" do
      ref = make_ref()
      caller = self()

      # Complete raw HTTP response mimicking Ollama's NDJSON streaming format
      # Note: Ollama sends tool_calls in a done=false chunk just before the final done=true chunk
      stream_response =
        [
          # Thinking chunks
          ~s({"model":"qwen3:30b","created_at":"2024-01-15T10:00:00Z","message":{"role":"assistant","thinking":"Let me analyze this security research request."},"done":false}),
          ~s({"model":"qwen3:30b","created_at":"2024-01-15T10:00:01Z","message":{"role":"assistant","thinking":" I should search for Apache exploits and list hosts."},"done":false}),
          # Text content chunks (these trigger thinking block close)
          ~s({"model":"qwen3:30b","created_at":"2024-01-15T10:00:02Z","message":{"role":"assistant","content":"I'll help you search for Apache"},"done":false}),
          ~s({"model":"qwen3:30b","created_at":"2024-01-15T10:00:03Z","message":{"role":"assistant","content":" exploits and check the current hosts."},"done":false}),
          # Tool calls in done=false chunk (Ollama sends these before the final chunk)
          ~s({"model":"qwen3:30b","created_at":"2024-01-15T10:00:04Z","message":{"role":"assistant","content":"","tool_calls":[{"function":{"name":"msf_command","arguments":{"command":"search apache"}}},{"function":{"name":"list_hosts","arguments":{"workspace":"default"}}}]},"done":false}),
          # Final done=true chunk with metadata
          ~s({"model":"qwen3:30b","created_at":"2024-01-15T10:00:05Z","message":{"role":"assistant","content":""},"done":true,"done_reason":"stop","prompt_eval_count":156,"eval_count":87,"context":[1,2,3,4,5]}),
          ""
        ]
        |> Enum.join("\n")

      req_opts = [
        plug: fn conn ->
          assert conn.request_path == "/api/chat"

          conn
          |> Plug.Conn.put_resp_content_type("application/x-ndjson")
          |> Plug.Conn.send_resp(200, stream_response)
        end
      ]

      request = %ChatRequest{
        model: "qwen3:30b",
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

      Ollama.run_chat_stream(request, caller, ref, req_opts)

      # 1. Stream started
      assert_receive {:llm, ^ref, %Events.StreamStarted{model: "qwen3:30b"}}, 1000

      # 2. Thinking block (index 0)
      assert_receive {:llm, ^ref, %Events.ContentBlockStart{index: 0, type: :thinking}}, 1000

      assert_receive {:llm, ^ref,
                      %Events.ContentDelta{
                        index: 0,
                        delta: "Let me analyze this security research request."
                      }},
                     1000

      assert_receive {:llm, ^ref,
                      %Events.ContentDelta{
                        index: 0,
                        delta: " I should search for Apache exploits and list hosts."
                      }},
                     1000

      assert_receive {:llm, ^ref, %Events.ContentBlockStop{index: 0}}, 1000

      # 3. Text block (index 1)
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

      # 4. First tool_call block (index 2)
      assert_receive {:llm, ^ref, %Events.ContentBlockStart{index: 2, type: :tool_call}}, 1000

      assert_receive {:llm, ^ref,
                      %Events.ToolCall{
                        index: 2,
                        name: "msf_command",
                        arguments: %{"command" => "search apache"}
                      }},
                     1000

      assert_receive {:llm, ^ref, %Events.ContentBlockStop{index: 2}}, 1000

      # 5. Second tool_call block (index 3)
      assert_receive {:llm, ^ref, %Events.ContentBlockStart{index: 3, type: :tool_call}}, 1000

      assert_receive {:llm, ^ref,
                      %Events.ToolCall{
                        index: 3,
                        name: "list_hosts",
                        arguments: %{"workspace" => "default"}
                      }},
                     1000

      assert_receive {:llm, ^ref, %Events.ContentBlockStop{index: 3}}, 1000

      # 6. Stream complete with correct metrics and stop reason
      assert_receive {:llm, ^ref,
                      %Events.StreamComplete{
                        input_tokens: 156,
                        output_tokens: 87,
                        cache_context: [1, 2, 3, 4, 5],
                        stop_reason: :tool_use
                      }},
                     1000

      # Verify no more events
      refute_receive {:llm, ^ref, _}, 100
    end

    test "handles response with only tool calls (no text)" do
      ref = make_ref()
      caller = self()

      # Response with only tool_calls, no thinking or text content
      # Ollama sends tool_calls in a done=false chunk just before the final done=true chunk
      stream_response =
        [
          ~s({"model":"llama3.1","created_at":"2024-01-15T10:00:00Z","message":{"role":"assistant","content":"","tool_calls":[{"function":{"name":"direct_action","arguments":{"immediate":true}}}]},"done":false}),
          ~s({"model":"llama3.1","created_at":"2024-01-15T10:00:01Z","message":{"role":"assistant","content":""},"done":true,"done_reason":"stop","prompt_eval_count":50,"eval_count":15}),
          ""
        ]
        |> Enum.join("\n")

      req_opts = [
        plug: fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/x-ndjson")
          |> Plug.Conn.send_resp(200, stream_response)
        end
      ]

      request = %ChatRequest{
        model: "llama3.1",
        messages: [Message.user("Do it now")]
      }

      Ollama.run_chat_stream(request, caller, ref, req_opts)

      assert_receive {:llm, ^ref, %Events.StreamStarted{}}, 1000

      # Should go directly to tool call at index 0 (no thinking or text block)
      assert_receive {:llm, ^ref, %Events.ContentBlockStart{index: 0, type: :tool_call}}, 1000

      assert_receive {:llm, ^ref,
                      %Events.ToolCall{
                        index: 0,
                        name: "direct_action",
                        arguments: %{"immediate" => true}
                      }},
                     1000

      assert_receive {:llm, ^ref, %Events.ContentBlockStop{index: 0}}, 1000

      assert_receive {:llm, ^ref, %Events.StreamComplete{stop_reason: :tool_use}}, 1000

      # Verify no thinking or text blocks were emitted
      refute_receive {:llm, ^ref, %Events.ContentBlockStart{type: :thinking}}, 100
      refute_receive {:llm, ^ref, %Events.ContentBlockStart{type: :text}}, 100
    end

    test "handles tool calls with complex nested arguments" do
      ref = make_ref()
      caller = self()

      # Response with tool_call that has complex nested arguments
      # Ollama sends tool_calls in a done=false chunk just before the final done=true chunk
      stream_response =
        [
          ~s({"model":"llama3.1","message":{"role":"assistant","content":"Running scan."},"done":false}),
          ~s({"model":"llama3.1","message":{"role":"assistant","content":"","tool_calls":[{"function":{"name":"complex_tool","arguments":{"options":{"verbose":true,"level":3},"targets":["192.168.1.1","192.168.1.2"]}}}]},"done":false}),
          ~s({"model":"llama3.1","message":{"role":"assistant","content":""},"done":true,"done_reason":"stop","prompt_eval_count":100,"eval_count":40}),
          ""
        ]
        |> Enum.join("\n")

      req_opts = [
        plug: fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/x-ndjson")
          |> Plug.Conn.send_resp(200, stream_response)
        end
      ]

      request = %ChatRequest{
        model: "llama3.1",
        messages: [Message.user("Run complex tool")]
      }

      Ollama.run_chat_stream(request, caller, ref, req_opts)

      assert_receive {:llm, ^ref, %Events.StreamStarted{}}, 1000

      # Text block first
      assert_receive {:llm, ^ref, %Events.ContentBlockStart{index: 0, type: :text}}, 1000
      assert_receive {:llm, ^ref, %Events.ContentDelta{index: 0, delta: "Running scan."}}, 1000
      assert_receive {:llm, ^ref, %Events.ContentBlockStop{index: 0}}, 1000

      # Then tool call
      assert_receive {:llm, ^ref, %Events.ContentBlockStart{index: 1, type: :tool_call}}, 1000

      assert_receive {:llm, ^ref,
                      %Events.ToolCall{
                        index: 1,
                        name: "complex_tool",
                        arguments: %{
                          "options" => %{"verbose" => true, "level" => 3},
                          "targets" => ["192.168.1.1", "192.168.1.2"]
                        }
                      }},
                     1000

      assert_receive {:llm, ^ref, %Events.ContentBlockStop{index: 1}}, 1000
      assert_receive {:llm, ^ref, %Events.StreamComplete{stop_reason: :tool_use}}, 1000
    end

    test "handles thinking-only response transitioning to text" do
      ref = make_ref()
      caller = self()

      # Response that starts with thinking, then transitions to text
      stream_response =
        [
          ~s({"model":"qwen3:30b","message":{"role":"assistant","thinking":"Processing request..."},"done":false}),
          ~s({"model":"qwen3:30b","message":{"role":"assistant","thinking":" Analyzing options."},"done":false}),
          ~s({"model":"qwen3:30b","message":{"role":"assistant","content":"Based on my analysis,"},"done":false}),
          ~s({"model":"qwen3:30b","message":{"role":"assistant","content":" here's my recommendation."},"done":true,"done_reason":"stop","prompt_eval_count":30,"eval_count":20}),
          ""
        ]
        |> Enum.join("\n")

      req_opts = [
        plug: fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/x-ndjson")
          |> Plug.Conn.send_resp(200, stream_response)
        end
      ]

      request = %ChatRequest{
        model: "qwen3:30b",
        messages: [Message.user("Analyze this")]
      }

      Ollama.run_chat_stream(request, caller, ref, req_opts)

      assert_receive {:llm, ^ref, %Events.StreamStarted{}}, 1000

      # Thinking block
      assert_receive {:llm, ^ref, %Events.ContentBlockStart{index: 0, type: :thinking}}, 1000

      assert_receive {:llm, ^ref, %Events.ContentDelta{index: 0, delta: "Processing request..."}},
                     1000

      assert_receive {:llm, ^ref, %Events.ContentDelta{index: 0, delta: " Analyzing options."}},
                     1000

      assert_receive {:llm, ^ref, %Events.ContentBlockStop{index: 0}}, 1000

      # Text block
      assert_receive {:llm, ^ref, %Events.ContentBlockStart{index: 1, type: :text}}, 1000

      assert_receive {:llm, ^ref, %Events.ContentDelta{index: 1, delta: "Based on my analysis,"}},
                     1000

      assert_receive {:llm, ^ref,
                      %Events.ContentDelta{index: 1, delta: " here's my recommendation."}},
                     1000

      assert_receive {:llm, ^ref, %Events.ContentBlockStop{index: 1}}, 1000

      assert_receive {:llm, ^ref, %Events.StreamComplete{stop_reason: :end_turn}}, 1000
    end

    test "handles multiple tool calls in same response message" do
      ref = make_ref()
      caller = self()

      # Response with multiple tool_calls returned together
      # Ollama sends tool_calls in a done=false chunk just before the final done=true chunk
      stream_response =
        [
          ~s({"model":"llama3.1","message":{"role":"assistant","content":"Executing multiple commands."},"done":false}),
          ~s({"model":"llama3.1","message":{"role":"assistant","content":"","tool_calls":[{"id":"call_1","function":{"name":"tool_a","arguments":{"x":1}}},{"id":"call_2","function":{"name":"tool_b","arguments":{"y":2}}},{"id":"call_3","function":{"name":"tool_c","arguments":{"z":3}}}]},"done":false}),
          ~s({"model":"llama3.1","message":{"role":"assistant","content":""},"done":true,"done_reason":"stop","prompt_eval_count":80,"eval_count":50}),
          ""
        ]
        |> Enum.join("\n")

      req_opts = [
        plug: fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/x-ndjson")
          |> Plug.Conn.send_resp(200, stream_response)
        end
      ]

      request = %ChatRequest{
        model: "llama3.1",
        messages: [Message.user("Run all three")]
      }

      Ollama.run_chat_stream(request, caller, ref, req_opts)

      assert_receive {:llm, ^ref, %Events.StreamStarted{}}, 1000

      # Text block
      assert_receive {:llm, ^ref, %Events.ContentBlockStart{index: 0, type: :text}}, 1000

      assert_receive {:llm, ^ref,
                      %Events.ContentDelta{index: 0, delta: "Executing multiple commands."}},
                     1000

      assert_receive {:llm, ^ref, %Events.ContentBlockStop{index: 0}}, 1000

      # Tool call 1
      assert_receive {:llm, ^ref, %Events.ContentBlockStart{index: 1, type: :tool_call}}, 1000

      assert_receive {:llm, ^ref,
                      %Events.ToolCall{
                        index: 1,
                        id: "call_1",
                        name: "tool_a",
                        arguments: %{"x" => 1}
                      }},
                     1000

      assert_receive {:llm, ^ref, %Events.ContentBlockStop{index: 1}}, 1000

      # Tool call 2
      assert_receive {:llm, ^ref, %Events.ContentBlockStart{index: 2, type: :tool_call}}, 1000

      assert_receive {:llm, ^ref,
                      %Events.ToolCall{
                        index: 2,
                        id: "call_2",
                        name: "tool_b",
                        arguments: %{"y" => 2}
                      }},
                     1000

      assert_receive {:llm, ^ref, %Events.ContentBlockStop{index: 2}}, 1000

      # Tool call 3
      assert_receive {:llm, ^ref, %Events.ContentBlockStart{index: 3, type: :tool_call}}, 1000

      assert_receive {:llm, ^ref,
                      %Events.ToolCall{
                        index: 3,
                        id: "call_3",
                        name: "tool_c",
                        arguments: %{"z" => 3}
                      }},
                     1000

      assert_receive {:llm, ^ref, %Events.ContentBlockStop{index: 3}}, 1000

      assert_receive {:llm, ^ref, %Events.StreamComplete{stop_reason: :tool_use}}, 1000
    end
  end

  describe "trace formatting" do
    test "formats successful response with thinking, content, and tool calls" do
      acc = %{
        trace_thinking: "Let me analyze this request carefully.",
        trace_content: "I'll help you search for that information.",
        trace_tool_calls: [
          %{id: "call_xyz789", name: "list_hosts", arguments: %{"workspace" => "default"}},
          %{id: "call_abc123", name: "search", arguments: %{"query" => "apache"}}
        ],
        trace_metadata: %{
          input_tokens: 100,
          output_tokens: 50,
          context_length: 4096,
          stop_reason: :tool_use
        }
      }

      result = Ollama.format_trace_response(acc, 200)

      # Should contain thinking section
      assert result =~ "--- THINKING ---"
      assert result =~ "Let me analyze this request carefully."

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
    end

    test "formats response with only thinking and content (no tool calls)" do
      acc = %{
        trace_thinking: "Processing the request...",
        trace_content: "Here is my analysis.",
        trace_tool_calls: [],
        trace_metadata: %{
          input_tokens: 50,
          output_tokens: 20,
          stop_reason: :end_turn
        }
      }

      result = Ollama.format_trace_response(acc, 200)

      assert result =~ "--- THINKING ---"
      assert result =~ "Processing the request..."
      assert result =~ "--- CONTENT ---"
      assert result =~ "Here is my analysis."
      assert result =~ "--- METADATA ---"
      refute result =~ "--- TOOL_CALLS ---"
    end

    test "formats response with only content (no thinking)" do
      acc = %{
        trace_thinking: "",
        trace_content: "Simple response without thinking.",
        trace_tool_calls: [],
        trace_metadata: %{
          input_tokens: 30,
          output_tokens: 10,
          stop_reason: :end_turn
        }
      }

      result = Ollama.format_trace_response(acc, 200)

      refute result =~ "--- THINKING ---"
      assert result =~ "--- CONTENT ---"
      assert result =~ "Simple response without thinking."
      assert result =~ "--- METADATA ---"
    end

    test "formats response with only tool calls (no content)" do
      acc = %{
        trace_thinking: "",
        trace_content: "",
        trace_tool_calls: [
          %{id: "call_direct", name: "direct_action", arguments: %{"immediate" => true}}
        ],
        trace_metadata: %{stop_reason: :tool_use}
      }

      result = Ollama.format_trace_response(acc, 200)

      refute result =~ "--- THINKING ---"
      refute result =~ "--- CONTENT ---"
      assert result =~ "--- TOOL_CALLS ---"
      assert result =~ "direct_action"
      assert result =~ "--- METADATA ---"
    end

    test "formats empty response" do
      acc = %{
        trace_thinking: "",
        trace_content: "",
        trace_tool_calls: [],
        trace_metadata: nil
      }

      result = Ollama.format_trace_response(acc, 200)

      assert result == "(empty response)"
    end

    test "formats error response with raw body" do
      acc = %{
        raw_body: ~s({"error": "model not found"})
      }

      result = Ollama.format_trace_response(acc, 404)

      assert result =~ "--- ERROR RESPONSE ---"
      assert result =~ "model not found"
    end

    test "formats error response with non-JSON body" do
      acc = %{
        raw_body: "Connection refused"
      }

      result = Ollama.format_trace_response(acc, 500)

      assert result =~ "--- ERROR RESPONSE ---"
      assert result =~ "Connection refused"
    end

    test "formats error response with empty body" do
      acc = %{
        raw_body: ""
      }

      result = Ollama.format_trace_response(acc, 500)

      assert result == "(empty error response)"
    end

    test "formats multiple tool calls in correct order" do
      # Tool calls are stored in reverse order during streaming, so they need to be reversed for display
      acc = %{
        trace_thinking: "",
        trace_content: "",
        trace_tool_calls: [
          %{id: "call_3", name: "tool_c", arguments: %{"z" => 3}},
          %{id: "call_2", name: "tool_b", arguments: %{"y" => 2}},
          %{id: "call_1", name: "tool_a", arguments: %{"x" => 1}}
        ],
        trace_metadata: %{stop_reason: :tool_use}
      }

      result = Ollama.format_trace_response(acc, 200)

      # Tool calls should be in original order (call_1, call_2, call_3)
      tool_calls_section = result |> String.split("--- METADATA ---") |> List.first()
      call_1_pos = :binary.match(tool_calls_section, "call_1") |> elem(0)
      call_2_pos = :binary.match(tool_calls_section, "call_2") |> elem(0)
      call_3_pos = :binary.match(tool_calls_section, "call_3") |> elem(0)

      assert call_1_pos < call_2_pos
      assert call_2_pos < call_3_pos
    end

    test "formats response with thinking but no output content" do
      # This can happen when thinking is enabled but the model only outputs thinking
      acc = %{
        trace_thinking: "Extended internal reasoning here...",
        trace_content: "",
        trace_tool_calls: [],
        trace_metadata: %{stop_reason: :end_turn}
      }

      result = Ollama.format_trace_response(acc, 200)

      assert result =~ "--- THINKING ---"
      assert result =~ "Extended internal reasoning here..."
      assert result =~ "--- METADATA ---"
      refute result =~ "--- CONTENT ---"
    end
  end
end
