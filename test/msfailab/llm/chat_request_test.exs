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

defmodule Msfailab.LLM.ChatRequestTest do
  use ExUnit.Case, async: true

  alias Msfailab.LLM.ChatRequest
  alias Msfailab.LLM.Message

  describe "new/3" do
    test "creates a chat request with required fields" do
      messages = [Message.user("Hello")]
      request = ChatRequest.new("gpt-4o", messages)

      assert request.model == "gpt-4o"
      assert request.messages == messages
      assert request.max_tokens == 8192
      assert request.temperature == 0.1
    end

    test "accepts optional system_prompt" do
      messages = [Message.user("Hello")]
      request = ChatRequest.new("gpt-4o", messages, system_prompt: "You are helpful.")

      assert request.system_prompt == "You are helpful."
    end

    test "accepts optional tools" do
      messages = [Message.user("Hello")]
      tools = [%{name: "test", description: "A test tool", parameters: %{}}]
      request = ChatRequest.new("gpt-4o", messages, tools: tools)

      assert request.tools == tools
    end

    test "accepts optional cache_context" do
      messages = [Message.user("Hello")]
      cache = %{context: [1, 2, 3]}
      request = ChatRequest.new("gpt-4o", messages, cache_context: cache)

      assert request.cache_context == cache
    end

    test "accepts custom max_tokens" do
      messages = [Message.user("Hello")]
      request = ChatRequest.new("gpt-4o", messages, max_tokens: 4096)

      assert request.max_tokens == 4096
    end

    test "accepts custom temperature" do
      messages = [Message.user("Hello")]
      request = ChatRequest.new("gpt-4o", messages, temperature: 0.7)

      assert request.temperature == 0.7
    end
  end

  describe "struct" do
    test "requires model and messages" do
      assert_raise ArgumentError, ~r/the following keys must also be given/, fn ->
        struct!(ChatRequest, [])
      end
    end

    test "has default values for optional fields" do
      request = %ChatRequest{model: "test", messages: []}

      assert request.system_prompt == nil
      assert request.tools == nil
      assert request.cache_context == nil
      assert request.max_tokens == 8192
      assert request.temperature == 0.1
    end
  end
end
