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

defmodule Msfailab.LLM.MessageTest do
  use ExUnit.Case, async: true

  alias Msfailab.LLM.Message

  describe "user/1" do
    test "creates a user message with text content" do
      message = Message.user("Hello!")

      assert message.role == :user
      assert message.content == [%{type: :text, text: "Hello!"}]
    end

    test "handles empty string" do
      message = Message.user("")

      assert message.role == :user
      assert message.content == [%{type: :text, text: ""}]
    end

    test "handles multi-line text" do
      message = Message.user("Line 1\nLine 2\nLine 3")

      assert message.content == [%{type: :text, text: "Line 1\nLine 2\nLine 3"}]
    end
  end

  describe "assistant/1" do
    test "creates an assistant message with text content" do
      message = Message.assistant("I can help with that.")

      assert message.role == :assistant
      assert message.content == [%{type: :text, text: "I can help with that."}]
    end

    test "handles empty string" do
      message = Message.assistant("")

      assert message.role == :assistant
      assert message.content == [%{type: :text, text: ""}]
    end
  end

  describe "tool_call/3" do
    test "creates an assistant message with a tool call" do
      message =
        Message.tool_call("call_123", "execute_msfconsole_command", %{"command" => "help"})

      assert message.role == :assistant

      assert message.content == [
               %{
                 type: :tool_call,
                 id: "call_123",
                 name: "execute_msfconsole_command",
                 arguments: %{"command" => "help"}
               }
             ]
    end

    test "handles empty arguments" do
      message = Message.tool_call("call_1", "some_tool", %{})

      assert message.content == [
               %{type: :tool_call, id: "call_1", name: "some_tool", arguments: %{}}
             ]
    end

    test "handles complex arguments" do
      args = %{
        "command" => "search type:exploit",
        "options" => %{"timeout" => 30},
        "flags" => ["verbose", "json"]
      }

      message = Message.tool_call("call_1", "complex_tool", args)

      assert message.content == [
               %{type: :tool_call, id: "call_1", name: "complex_tool", arguments: args}
             ]
    end
  end

  describe "tool_result/3" do
    test "creates a tool message with success result" do
      message = Message.tool_result("call_123", "Command executed successfully", false)

      assert message.role == :tool

      assert message.content == [
               %{
                 type: :tool_result,
                 tool_call_id: "call_123",
                 content: "Command executed successfully",
                 is_error: false
               }
             ]
    end

    test "creates a tool message with error result" do
      message = Message.tool_result("call_456", "Connection failed", true)

      assert message.role == :tool

      assert message.content == [
               %{
                 type: :tool_result,
                 tool_call_id: "call_456",
                 content: "Connection failed",
                 is_error: true
               }
             ]
    end

    test "defaults is_error to false" do
      message = Message.tool_result("call_1", "Result")

      assert message.content == [
               %{type: :tool_result, tool_call_id: "call_1", content: "Result", is_error: false}
             ]
    end
  end

  describe "struct" do
    test "requires role key" do
      assert_raise ArgumentError, ~r/the following keys must also be given/, fn ->
        struct!(Message, [])
      end
    end

    test "has empty content by default" do
      message = %Message{role: :user}

      assert message.content == []
    end
  end
end
