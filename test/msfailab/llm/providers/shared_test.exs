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

defmodule Msfailab.LLM.Providers.SharedTest do
  @moduledoc """
  Unit tests for shared LLM provider utilities.

  These functions are also tested indirectly via Core module tests,
  but dedicated tests here provide clearer documentation and coverage.
  """

  use ExUnit.Case, async: true

  alias Msfailab.LLM.Providers.Shared

  describe "extract_error_message/2" do
    test "extracts Anthropic-format nested error message" do
      body = %{"error" => %{"message" => "Rate limit exceeded", "type" => "rate_limit_error"}}

      assert Shared.extract_error_message(body, 429) == "Rate limit exceeded"
    end

    test "extracts Ollama-format top-level error string" do
      body = %{"error" => "model not found"}

      assert Shared.extract_error_message(body, 404) == "model not found"
    end

    test "extracts error from buffer field in state map" do
      state = %{
        buffer: ~s({"error": {"message": "Invalid API key"}}),
        other_field: "ignored"
      }

      assert Shared.extract_error_message(state, 401) == "Invalid API key"
    end

    test "parses JSON string body" do
      body = ~s({"error": {"message": "Server overloaded"}})

      assert Shared.extract_error_message(body, 503) == "Server overloaded"
    end

    test "falls back to HTTP status when error is map without message" do
      body = %{"error" => %{"code" => "internal_error"}}

      assert Shared.extract_error_message(body, 500) == "HTTP 500"
    end

    test "falls back to HTTP status when error is nil" do
      body = %{"error" => nil}

      assert Shared.extract_error_message(body, 400) == "HTTP 400"
    end

    test "falls back to HTTP status when body is invalid JSON string" do
      body = "Not valid JSON"

      assert Shared.extract_error_message(body, 502) == "HTTP 502"
    end

    test "falls back to HTTP status when body is empty map" do
      body = %{}

      assert Shared.extract_error_message(body, 504) == "HTTP 504"
    end

    test "falls back to HTTP status for non-map, non-string body" do
      assert Shared.extract_error_message(nil, 500) == "HTTP 500"
      assert Shared.extract_error_message(123, 400) == "HTTP 400"
    end

    test "handles empty buffer field" do
      state = %{buffer: ""}

      assert Shared.extract_error_message(state, 500) == "HTTP 500"
    end

    test "extracts OpenAI-format nested error message" do
      body = %{
        "error" => %{
          "message" => "The model `gpt-5` does not exist",
          "type" => "invalid_request_error",
          "code" => "model_not_found"
        }
      }

      assert Shared.extract_error_message(body, 404) == "The model `gpt-5` does not exist"
    end
  end

  describe "recoverable_error?/1" do
    test "returns true for Req.TransportError" do
      error = %Req.TransportError{reason: :timeout}

      assert Shared.recoverable_error?(error) == true
    end

    test "returns true for Mint.TransportError" do
      error = %Mint.TransportError{reason: :closed}

      assert Shared.recoverable_error?(error) == true
    end

    test "returns false for other exceptions" do
      error = %RuntimeError{message: "something went wrong"}

      assert Shared.recoverable_error?(error) == false
    end

    test "returns false for non-exception values" do
      assert Shared.recoverable_error?("error") == false
      assert Shared.recoverable_error?(:error) == false
      assert Shared.recoverable_error?(nil) == false
      assert Shared.recoverable_error?(%{reason: :timeout}) == false
    end

    test "returns false for ArgumentError" do
      error = %ArgumentError{message: "bad argument"}

      assert Shared.recoverable_error?(error) == false
    end
  end

  describe "format_json/1" do
    test "formats map as pretty-printed JSON" do
      data = %{"key" => "value", "number" => 42}

      result = Shared.format_json(data)

      assert result =~ "\"key\": \"value\""
      assert result =~ "\"number\": 42"
    end

    test "formats list as pretty-printed JSON" do
      data = [%{"id" => 1}, %{"id" => 2}]

      result = Shared.format_json(data)

      assert result =~ "\"id\": 1"
      assert result =~ "\"id\": 2"
    end

    test "formats nested structures" do
      data = %{
        "outer" => %{
          "inner" => [1, 2, 3]
        }
      }

      result = Shared.format_json(data)

      assert result =~ "\"outer\""
      assert result =~ "\"inner\""
    end

    test "falls back to inspect for non-JSON-encodable data" do
      # Tuples cannot be JSON-encoded
      data = {:ok, "value"}

      result = Shared.format_json(data)

      assert result =~ "{:ok, \"value\"}"
    end

    test "handles atoms" do
      # Atoms can be JSON-encoded as strings
      data = %{status: :ok}

      result = Shared.format_json(data)

      assert result =~ "\"status\": \"ok\""
    end
  end

  describe "extract_raw_error_body/1" do
    test "extracts and pretty-prints valid JSON raw body" do
      state = %{
        raw_body: ~s({"error":{"message":"Rate limit exceeded","type":"rate_limit_error"}})
      }

      result = Shared.extract_raw_error_body(state)

      assert result =~ "\"error\""
      assert result =~ "\"message\": \"Rate limit exceeded\""
    end

    test "returns raw body as-is when not valid JSON" do
      state = %{raw_body: "Service temporarily unavailable"}

      result = Shared.extract_raw_error_body(state)

      assert result == "Service temporarily unavailable"
    end

    test "returns nil when raw_body is empty string" do
      state = %{raw_body: ""}

      assert Shared.extract_raw_error_body(state) == nil
    end

    test "returns nil when raw_body is missing" do
      state = %{other_field: "value"}

      assert Shared.extract_raw_error_body(state) == nil
    end

    test "returns nil when state is empty map" do
      assert Shared.extract_raw_error_body(%{}) == nil
    end

    test "returns nil for non-map input" do
      assert Shared.extract_raw_error_body("not a map") == nil
      assert Shared.extract_raw_error_body(nil) == nil
    end

    test "handles deeply nested JSON error body" do
      state = %{
        raw_body:
          Jason.encode!(%{
            "error" => %{
              "message" => "Too many requests",
              "details" => %{
                "retry_after" => 30,
                "quota" => %{"limit" => 100, "remaining" => 0}
              }
            }
          })
      }

      result = Shared.extract_raw_error_body(state)

      assert result =~ "\"message\": \"Too many requests\""
      assert result =~ "\"retry_after\": 30"
    end
  end
end
