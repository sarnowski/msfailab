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

defmodule Msfailab.Tracks.ChatContextTest do
  use Msfailab.DataCase

  alias Msfailab.Containers
  alias Msfailab.Tracks
  alias Msfailab.Tracks.ChatContext
  alias Msfailab.Workspaces

  setup do
    {:ok, workspace} =
      Workspaces.create_workspace(%{slug: "test-workspace", name: "Test Workspace"})

    {:ok, container} =
      Containers.create_container(workspace, %{
        slug: "test-container",
        name: "Test Container",
        docker_image: "test:latest"
      })

    {:ok, track} = Tracks.create_track(container, %{slug: "test-track", name: "Test Track"})
    %{track: track}
  end

  describe "create_turn/3" do
    test "creates a turn with required fields", %{track: track} do
      {:ok, turn} = ChatContext.create_turn(track.id, "gpt-4o")

      assert turn.track_id == track.id
      assert turn.model == "gpt-4o"
      assert turn.status == "pending"
      assert turn.trigger == "user_prompt"
      assert turn.tool_approval_mode == "confirm"
      assert turn.position == 1
    end

    test "creates a turn with custom tool_approval_mode", %{track: track} do
      {:ok, turn} = ChatContext.create_turn(track.id, "gpt-4o", "autonomous")

      assert turn.tool_approval_mode == "autonomous"
    end

    test "increments position for each turn", %{track: track} do
      {:ok, turn1} = ChatContext.create_turn(track.id, "gpt-4o")
      {:ok, turn2} = ChatContext.create_turn(track.id, "gpt-4o")
      {:ok, turn3} = ChatContext.create_turn(track.id, "gpt-4o")

      assert turn1.position == 1
      assert turn2.position == 2
      assert turn3.position == 3
    end
  end

  describe "update_turn_status/2" do
    test "updates turn status", %{track: track} do
      {:ok, turn} = ChatContext.create_turn(track.id, "gpt-4o")

      {:ok, updated} = ChatContext.update_turn_status(turn, "streaming")

      assert updated.status == "streaming"
    end
  end

  describe "get_active_turn_model/1" do
    test "returns model from active turn", %{track: track} do
      {:ok, _turn} = ChatContext.create_turn(track.id, "claude-sonnet")

      assert ChatContext.get_active_turn_model(track.id) == "claude-sonnet"
    end

    test "returns model from latest active turn when multiple exist", %{track: track} do
      {:ok, turn1} = ChatContext.create_turn(track.id, "gpt-4o")
      {:ok, _} = ChatContext.update_turn_status(turn1, "finished")
      {:ok, _turn2} = ChatContext.create_turn(track.id, "claude-sonnet")

      assert ChatContext.get_active_turn_model(track.id) == "claude-sonnet"
    end

    test "returns nil when no active turns", %{track: track} do
      {:ok, turn} = ChatContext.create_turn(track.id, "gpt-4o")
      {:ok, _} = ChatContext.update_turn_status(turn, "finished")

      assert ChatContext.get_active_turn_model(track.id) == nil
    end

    test "returns nil when all turns are in terminal status", %{track: track} do
      {:ok, turn1} = ChatContext.create_turn(track.id, "gpt-4o")
      {:ok, _} = ChatContext.update_turn_status(turn1, "error")
      {:ok, turn2} = ChatContext.create_turn(track.id, "claude-sonnet")
      {:ok, _} = ChatContext.update_turn_status(turn2, "interrupted")

      assert ChatContext.get_active_turn_model(track.id) == nil
    end

    test "returns nil when track has no turns", %{track: track} do
      assert ChatContext.get_active_turn_model(track.id) == nil
    end
  end

  describe "create_message_entry/5" do
    test "creates a user message entry", %{track: track} do
      {:ok, turn} = ChatContext.create_turn(track.id, "gpt-4o")

      {:ok, entry} =
        ChatContext.create_message_entry(track.id, turn.id, nil, 1, %{
          role: "user",
          message_type: "prompt",
          content: "Hello!"
        })

      assert entry.track_id == track.id
      assert entry.turn_id == turn.id
      assert entry.position == 1
      assert entry.entry_type == "message"
      assert entry.message.role == "user"
      assert entry.message.message_type == "prompt"
      assert entry.message.content == "Hello!"
    end

    test "creates an assistant response entry", %{track: track} do
      {:ok, turn} = ChatContext.create_turn(track.id, "gpt-4o")

      {:ok, entry} =
        ChatContext.create_message_entry(track.id, turn.id, nil, 1, %{
          role: "assistant",
          message_type: "response",
          content: "Hi there!"
        })

      assert entry.message.role == "assistant"
      assert entry.message.message_type == "response"
      assert entry.message.content == "Hi there!"
    end

    test "creates an assistant thinking entry", %{track: track} do
      {:ok, turn} = ChatContext.create_turn(track.id, "gpt-4o")

      {:ok, entry} =
        ChatContext.create_message_entry(track.id, turn.id, nil, 1, %{
          role: "assistant",
          message_type: "thinking",
          content: "Let me think..."
        })

      assert entry.message.message_type == "thinking"
    end
  end

  describe "create_tool_invocation_entry/5" do
    test "creates a tool invocation entry", %{track: track} do
      {:ok, turn} = ChatContext.create_turn(track.id, "gpt-4o")

      {:ok, entry} =
        ChatContext.create_tool_invocation_entry(track.id, turn.id, nil, 1, %{
          tool_call_id: "call_123",
          tool_name: "msf_command",
          arguments: %{"command" => "help"},
          console_prompt: "msf6 > "
        })

      assert entry.track_id == track.id
      assert entry.turn_id == turn.id
      assert entry.position == 1
      assert entry.entry_type == "tool_invocation"
      assert entry.tool_invocation.tool_call_id == "call_123"
      assert entry.tool_invocation.tool_name == "msf_command"
      assert entry.tool_invocation.arguments == %{"command" => "help"}
      assert entry.tool_invocation.console_prompt == "msf6 > "
      assert entry.tool_invocation.status == "pending"
    end
  end

  describe "update_tool_invocation/4" do
    setup %{track: track} do
      {:ok, turn} = ChatContext.create_turn(track.id, "gpt-4o")

      {:ok, entry} =
        ChatContext.create_tool_invocation_entry(track.id, turn.id, nil, 1, %{
          tool_call_id: "call_123",
          tool_name: "msf_command",
          arguments: %{}
        })

      %{entry: entry, track: track}
    end

    test "updates status to approved", %{track: track, entry: entry} do
      {:ok, updated} = ChatContext.update_tool_invocation(track.id, entry.position, "approved")

      assert updated.status == "approved"
    end

    test "updates status to denied with reason", %{track: track, entry: entry} do
      {:ok, updated} =
        ChatContext.update_tool_invocation(track.id, entry.position, "denied",
          denied_reason: "Not safe"
        )

      assert updated.status == "denied"
      assert updated.denied_reason == "Not safe"
    end

    test "updates status to success with result", %{track: track, entry: entry} do
      {:ok, _} = ChatContext.update_tool_invocation(track.id, entry.position, "approved")

      {:ok, updated} =
        ChatContext.update_tool_invocation(track.id, entry.position, "success",
          result_content: "Command executed",
          duration_ms: 150
        )

      assert updated.status == "success"
      assert updated.result_content == "Command executed"
      assert updated.duration_ms == 150
    end

    test "updates status to error with message", %{track: track, entry: entry} do
      {:ok, _} = ChatContext.update_tool_invocation(track.id, entry.position, "approved")

      {:ok, updated} =
        ChatContext.update_tool_invocation(track.id, entry.position, "error",
          error_message: "Connection failed",
          duration_ms: 100
        )

      assert updated.status == "error"
      assert updated.error_message == "Connection failed"
    end

    test "returns error for non-existent entry", %{track: track} do
      assert {:error, :not_found} =
               ChatContext.update_tool_invocation(track.id, 999_999, "approved")
    end
  end

  describe "next_entry_position/1" do
    test "returns 1 for empty track", %{track: track} do
      assert ChatContext.next_entry_position(track.id) == 1
    end

    test "returns next position after entries", %{track: track} do
      {:ok, turn} = ChatContext.create_turn(track.id, "gpt-4o")

      {:ok, _} =
        ChatContext.create_message_entry(track.id, turn.id, nil, 1, %{
          role: "user",
          message_type: "prompt",
          content: "First"
        })

      {:ok, _} =
        ChatContext.create_message_entry(track.id, turn.id, nil, 2, %{
          role: "assistant",
          message_type: "response",
          content: "Second"
        })

      assert ChatContext.next_entry_position(track.id) == 3
    end
  end

  describe "load_entries/1" do
    test "returns empty list for empty track", %{track: track} do
      assert ChatContext.load_entries(track.id) == []
    end

    test "returns entries in position order", %{track: track} do
      {:ok, turn} = ChatContext.create_turn(track.id, "gpt-4o")

      {:ok, _} =
        ChatContext.create_message_entry(track.id, turn.id, nil, 2, %{
          role: "assistant",
          message_type: "response",
          content: "Response"
        })

      {:ok, _} =
        ChatContext.create_message_entry(track.id, turn.id, nil, 1, %{
          role: "user",
          message_type: "prompt",
          content: "Prompt"
        })

      entries = ChatContext.load_entries(track.id)

      assert length(entries) == 2
      assert Enum.at(entries, 0).position == 1
      assert Enum.at(entries, 1).position == 2
    end

    test "preloads message associations", %{track: track} do
      {:ok, turn} = ChatContext.create_turn(track.id, "gpt-4o")

      {:ok, _} =
        ChatContext.create_message_entry(track.id, turn.id, nil, 1, %{
          role: "user",
          message_type: "prompt",
          content: "Hello"
        })

      [entry] = ChatContext.load_entries(track.id)

      assert entry.message.content == "Hello"
    end

    test "preloads tool_invocation associations", %{track: track} do
      {:ok, turn} = ChatContext.create_turn(track.id, "gpt-4o")

      {:ok, _} =
        ChatContext.create_tool_invocation_entry(track.id, turn.id, nil, 1, %{
          tool_call_id: "call_1",
          tool_name: "msf_command",
          arguments: %{}
        })

      [entry] = ChatContext.load_entries(track.id)

      assert entry.tool_invocation.tool_call_id == "call_1"
    end
  end

  describe "entries_to_chat_entries/1" do
    test "converts message entries to chat entries", %{track: track} do
      {:ok, turn} = ChatContext.create_turn(track.id, "gpt-4o")

      {:ok, _} =
        ChatContext.create_message_entry(track.id, turn.id, nil, 1, %{
          role: "user",
          message_type: "prompt",
          content: "Hello"
        })

      entries = ChatContext.load_entries(track.id)
      chat_entries = ChatContext.entries_to_chat_entries(entries)

      assert length(chat_entries) == 1
      [chat_entry] = chat_entries
      assert chat_entry.entry_type == :message
      assert chat_entry.role == :user
      assert chat_entry.message_type == :prompt
      assert chat_entry.content == "Hello"
    end

    test "converts tool invocation entries to chat entries", %{track: track} do
      {:ok, turn} = ChatContext.create_turn(track.id, "gpt-4o")

      {:ok, _} =
        ChatContext.create_tool_invocation_entry(track.id, turn.id, nil, 1, %{
          tool_call_id: "call_1",
          tool_name: "msf_command",
          arguments: %{"command" => "help"}
        })

      entries = ChatContext.load_entries(track.id)
      chat_entries = ChatContext.entries_to_chat_entries(entries)

      assert length(chat_entries) == 1
      [chat_entry] = chat_entries
      assert chat_entry.entry_type == :tool_invocation
      assert chat_entry.tool_name == "msf_command"
      assert chat_entry.tool_status == :pending
    end

    test "renders markdown for assistant entries", %{track: track} do
      {:ok, turn} = ChatContext.create_turn(track.id, "gpt-4o")

      {:ok, _} =
        ChatContext.create_message_entry(track.id, turn.id, nil, 1, %{
          role: "assistant",
          message_type: "response",
          content: "**Bold** text"
        })

      entries = ChatContext.load_entries(track.id)
      [chat_entry] = ChatContext.entries_to_chat_entries(entries)

      assert chat_entry.rendered_html =~ "<strong>Bold</strong>"
    end
  end

  describe "entries_to_llm_messages/1" do
    test "converts user prompt to user message", %{track: track} do
      {:ok, turn} = ChatContext.create_turn(track.id, "gpt-4o")

      {:ok, _} =
        ChatContext.create_message_entry(track.id, turn.id, nil, 1, %{
          role: "user",
          message_type: "prompt",
          content: "Hello"
        })

      entries = ChatContext.load_entries(track.id)
      messages = ChatContext.entries_to_llm_messages(entries)

      assert length(messages) == 1
      [message] = messages
      assert message.role == :user
      assert message.content == [%{type: :text, text: "Hello"}]
    end

    test "converts assistant response to assistant message", %{track: track} do
      {:ok, turn} = ChatContext.create_turn(track.id, "gpt-4o")

      {:ok, _} =
        ChatContext.create_message_entry(track.id, turn.id, nil, 1, %{
          role: "assistant",
          message_type: "response",
          content: "Hi there"
        })

      entries = ChatContext.load_entries(track.id)
      [message] = ChatContext.entries_to_llm_messages(entries)

      assert message.role == :assistant
      assert message.content == [%{type: :text, text: "Hi there"}]
    end

    test "filters out thinking entries", %{track: track} do
      {:ok, turn} = ChatContext.create_turn(track.id, "gpt-4o")

      {:ok, _} =
        ChatContext.create_message_entry(track.id, turn.id, nil, 1, %{
          role: "assistant",
          message_type: "thinking",
          content: "Let me think..."
        })

      entries = ChatContext.load_entries(track.id)
      messages = ChatContext.entries_to_llm_messages(entries)

      assert messages == []
    end

    test "converts successful tool invocation to call + result messages", %{track: track} do
      {:ok, turn} = ChatContext.create_turn(track.id, "gpt-4o")

      {:ok, entry} =
        ChatContext.create_tool_invocation_entry(track.id, turn.id, nil, 1, %{
          tool_call_id: "call_1",
          tool_name: "msf_command",
          arguments: %{"command" => "help"}
        })

      {:ok, _} = ChatContext.update_tool_invocation(track.id, entry.position, "approved")

      {:ok, _} =
        ChatContext.update_tool_invocation(track.id, entry.position, "success",
          result_content: "Help output"
        )

      entries = ChatContext.load_entries(track.id)
      messages = ChatContext.entries_to_llm_messages(entries)

      assert length(messages) == 2
      [call_msg, result_msg] = messages

      assert call_msg.role == :assistant
      assert [%{type: :tool_call, id: "call_1", name: "msf_command"}] = call_msg.content

      assert result_msg.role == :tool

      assert [
               %{
                 type: :tool_result,
                 tool_call_id: "call_1",
                 content: "Help output",
                 is_error: false
               }
             ] = result_msg.content
    end

    test "converts error tool invocation to call + error result", %{track: track} do
      {:ok, turn} = ChatContext.create_turn(track.id, "gpt-4o")

      {:ok, entry} =
        ChatContext.create_tool_invocation_entry(track.id, turn.id, nil, 1, %{
          tool_call_id: "call_1",
          tool_name: "msf_command",
          arguments: %{}
        })

      {:ok, _} = ChatContext.update_tool_invocation(track.id, entry.position, "approved")

      {:ok, _} =
        ChatContext.update_tool_invocation(track.id, entry.position, "error",
          error_message: "Failed"
        )

      entries = ChatContext.load_entries(track.id)
      [_, result_msg] = ChatContext.entries_to_llm_messages(entries)

      assert [%{is_error: true, content: "Error: Failed"}] = result_msg.content
    end

    test "converts denied tool invocation to call + denied result", %{track: track} do
      {:ok, turn} = ChatContext.create_turn(track.id, "gpt-4o")

      {:ok, entry} =
        ChatContext.create_tool_invocation_entry(track.id, turn.id, nil, 1, %{
          tool_call_id: "call_1",
          tool_name: "msf_command",
          arguments: %{}
        })

      {:ok, _} =
        ChatContext.update_tool_invocation(track.id, entry.position, "denied",
          denied_reason: "Not safe"
        )

      entries = ChatContext.load_entries(track.id)
      [_, result_msg] = ChatContext.entries_to_llm_messages(entries)

      assert [%{is_error: true, content: "Tool call denied by user: Not safe"}] =
               result_msg.content
    end

    test "converts timeout tool invocation to call + timeout result", %{track: track} do
      {:ok, turn} = ChatContext.create_turn(track.id, "gpt-4o")

      {:ok, entry} =
        ChatContext.create_tool_invocation_entry(track.id, turn.id, nil, 1, %{
          tool_call_id: "call_1",
          tool_name: "msf_command",
          arguments: %{}
        })

      {:ok, _} = ChatContext.update_tool_invocation(track.id, entry.position, "approved")
      {:ok, _} = ChatContext.update_tool_invocation(track.id, entry.position, "timeout")

      entries = ChatContext.load_entries(track.id)
      [_, result_msg] = ChatContext.entries_to_llm_messages(entries)

      assert [%{is_error: true, content: "Error: Tool execution timed out"}] = result_msg.content
    end

    test "filters out pending/approved/executing tool invocations", %{track: track} do
      {:ok, turn} = ChatContext.create_turn(track.id, "gpt-4o")

      {:ok, _} =
        ChatContext.create_tool_invocation_entry(track.id, turn.id, nil, 1, %{
          tool_call_id: "call_1",
          tool_name: "msf_command",
          arguments: %{}
        })

      entries = ChatContext.load_entries(track.id)
      messages = ChatContext.entries_to_llm_messages(entries)

      assert messages == []
    end
  end
end
