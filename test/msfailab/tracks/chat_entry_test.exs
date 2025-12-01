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

defmodule Msfailab.Tracks.ChatEntryTest do
  use ExUnit.Case, async: true

  alias Msfailab.Tracks.ChatEntry

  describe "user_prompt/4" do
    test "creates a user prompt entry with all required fields" do
      timestamp = DateTime.utc_now()
      entry = ChatEntry.user_prompt("uuid-123", 1, "Hello world", timestamp)

      assert entry.id == "uuid-123"
      assert entry.position == 1
      assert entry.entry_type == :message
      assert entry.role == :user
      assert entry.message_type == :prompt
      assert entry.content == "Hello world"
      assert entry.rendered_html == nil
      assert entry.streaming == false
      assert entry.timestamp == timestamp
    end

    test "uses default timestamp when not provided" do
      entry = ChatEntry.user_prompt("uuid", 1, "Hello")

      assert %DateTime{} = entry.timestamp
    end
  end

  describe "assistant_thinking/6" do
    test "creates an assistant thinking entry with all fields" do
      timestamp = DateTime.utc_now()

      entry =
        ChatEntry.assistant_thinking(
          "uuid-456",
          2,
          "Let me think...",
          "<p>Let me think...</p>",
          true,
          timestamp
        )

      assert entry.id == "uuid-456"
      assert entry.position == 2
      assert entry.entry_type == :message
      assert entry.role == :assistant
      assert entry.message_type == :thinking
      assert entry.content == "Let me think..."
      assert entry.rendered_html == "<p>Let me think...</p>"
      assert entry.streaming == true
      assert entry.timestamp == timestamp
    end

    test "defaults streaming to false" do
      entry = ChatEntry.assistant_thinking("uuid", 1, "thinking", "<p>thinking</p>")

      assert entry.streaming == false
    end
  end

  describe "assistant_response/6" do
    test "creates an assistant response entry with all fields" do
      timestamp = DateTime.utc_now()

      entry =
        ChatEntry.assistant_response(
          "uuid-789",
          3,
          "Here is my response",
          "<p>Here is my response</p>",
          false,
          timestamp
        )

      assert entry.id == "uuid-789"
      assert entry.position == 3
      assert entry.entry_type == :message
      assert entry.role == :assistant
      assert entry.message_type == :response
      assert entry.content == "Here is my response"
      assert entry.rendered_html == "<p>Here is my response</p>"
      assert entry.streaming == false
      assert entry.timestamp == timestamp
    end

    test "defaults streaming to false" do
      entry = ChatEntry.assistant_response("uuid", 1, "response", "<p>response</p>")

      assert entry.streaming == false
    end
  end

  describe "tool_invocation/7" do
    test "creates a tool invocation entry with all fields" do
      timestamp = DateTime.utc_now()

      entry =
        ChatEntry.tool_invocation(
          123,
          5,
          "call_abc",
          "msf_command",
          %{"command" => "search apache"},
          :pending,
          console_prompt: "msf6 > ",
          timestamp: timestamp
        )

      assert entry.id == 123
      assert entry.position == 5
      assert entry.entry_type == :tool_invocation
      assert entry.tool_call_id == "call_abc"
      assert entry.tool_name == "msf_command"
      assert entry.tool_arguments == %{"command" => "search apache"}
      assert entry.tool_status == :pending
      assert entry.console_prompt == "msf6 > "
      assert entry.streaming == false
      assert entry.timestamp == timestamp
    end

    test "supports all tool status values" do
      for status <- [:pending, :approved, :denied, :executing, :success, :error, :timeout] do
        entry = ChatEntry.tool_invocation("id", 1, "call", "tool", %{}, status)
        assert entry.tool_status == status
      end
    end

    test "defaults console_prompt to empty string" do
      entry = ChatEntry.tool_invocation("id", 1, "call", "tool", %{}, :pending)
      assert entry.console_prompt == ""
    end

    test "defaults result_content to nil" do
      entry = ChatEntry.tool_invocation("id", 1, "call", "tool", %{}, :success)
      assert entry.result_content == nil
    end

    test "accepts result_content option" do
      entry =
        ChatEntry.tool_invocation("id", 1, "call", "tool", %{}, :success,
          result_content: "command output here"
        )

      assert entry.result_content == "command output here"
    end
  end

  describe "message?/1" do
    test "returns true for user prompt entries" do
      entry = ChatEntry.user_prompt("id", 1, "Hello")
      assert ChatEntry.message?(entry) == true
    end

    test "returns true for assistant thinking entries" do
      entry = ChatEntry.assistant_thinking("id", 1, "thinking", "<p>thinking</p>")
      assert ChatEntry.message?(entry) == true
    end

    test "returns true for assistant response entries" do
      entry = ChatEntry.assistant_response("id", 1, "response", "<p>response</p>")
      assert ChatEntry.message?(entry) == true
    end

    test "returns false for tool invocation entries" do
      entry = ChatEntry.tool_invocation("id", 1, "call", "tool", %{}, :pending)
      assert ChatEntry.message?(entry) == false
    end
  end

  describe "tool_invocation?/1" do
    test "returns true for tool invocation entries" do
      entry = ChatEntry.tool_invocation("id", 1, "call", "tool", %{}, :pending)
      assert ChatEntry.tool_invocation?(entry) == true
    end

    test "returns false for message entries" do
      entry = ChatEntry.user_prompt("id", 1, "Hello")
      assert ChatEntry.tool_invocation?(entry) == false
    end
  end

  describe "struct enforcement" do
    test "requires enforce_keys" do
      assert_raise ArgumentError, ~r/the following keys must also be given/, fn ->
        struct!(ChatEntry, [])
      end
    end

    test "can create valid struct with all required keys" do
      entry = %ChatEntry{
        id: "test",
        position: 1,
        entry_type: :message,
        streaming: false,
        timestamp: DateTime.utc_now()
      }

      assert entry.id == "test"
    end
  end

  describe "from_tool_invocation_ecto/1" do
    test "uses position as ID for consistency with streaming entries" do
      # Simulate an Ecto entry with database ID different from position
      ecto_entry = %Msfailab.Tracks.ChatHistoryEntry{
        id: 12_345,
        position: 3,
        entry_type: "tool_invocation",
        inserted_at: ~U[2025-01-15 10:30:00Z],
        tool_invocation: %Msfailab.Tracks.ChatToolInvocation{
          tool_call_id: "call_abc",
          tool_name: "msf_command",
          arguments: %{"command" => "search apache"},
          status: "pending",
          console_prompt: "msf6 > "
        }
      }

      chat_entry = ChatEntry.from_tool_invocation_ecto(ecto_entry)

      # ID should be position (3), not database ID (12345)
      # This ensures tool_invocations map (keyed by position) matches entry.id
      assert chat_entry.id == 3
      assert chat_entry.position == 3
      assert chat_entry.entry_type == :tool_invocation
      assert chat_entry.tool_call_id == "call_abc"
      assert chat_entry.tool_name == "msf_command"
      assert chat_entry.tool_arguments == %{"command" => "search apache"}
      assert chat_entry.tool_status == :pending
      assert chat_entry.console_prompt == "msf6 > "
      assert chat_entry.streaming == false
    end
  end
end
