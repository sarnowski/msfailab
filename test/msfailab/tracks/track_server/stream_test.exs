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

defmodule Msfailab.Tracks.TrackServer.StreamTest do
  use ExUnit.Case, async: true

  alias Msfailab.Tracks.ChatEntry
  alias Msfailab.Tracks.TrackServer.State.Stream, as: StreamState
  alias Msfailab.Tracks.TrackServer.Stream

  describe "block_start/4" do
    test "creates thinking entry for :thinking type" do
      stream = StreamState.new(1)
      entries = []

      {new_stream, new_entries, actions} = Stream.block_start(stream, entries, 0, :thinking)

      assert new_stream.next_position == 2
      assert Map.has_key?(new_stream.blocks, 0)
      assert new_stream.blocks[0] == 1
      assert Map.has_key?(new_stream.documents, 1)

      assert [entry] = new_entries
      assert entry.entry_type == :message
      assert entry.message_type == :thinking
      assert entry.role == :assistant
      assert entry.streaming == true
      assert entry.position == 1
      assert entry.content == ""

      assert actions == [:broadcast_chat_state]
    end

    test "creates response entry for :text type" do
      stream = StreamState.new(1)
      entries = []

      {new_stream, new_entries, actions} = Stream.block_start(stream, entries, 0, :text)

      assert new_stream.next_position == 2

      assert [entry] = new_entries
      assert entry.message_type == :response
      assert entry.streaming == true

      assert actions == [:broadcast_chat_state]
    end

    test "handles multiple content blocks" do
      stream = StreamState.new(1)
      entries = []

      {stream, entries, _} = Stream.block_start(stream, entries, 0, :thinking)
      {stream, entries, _} = Stream.block_start(stream, entries, 1, :text)

      assert stream.next_position == 3
      assert stream.blocks[0] == 1
      assert stream.blocks[1] == 2

      assert length(entries) == 2
      assert Enum.at(entries, 0).position == 1
      assert Enum.at(entries, 1).position == 2
    end

    test "preserves existing entries" do
      stream = StreamState.new(2)
      existing_entry = ChatEntry.user_prompt("existing", 1, "Hello", DateTime.utc_now())
      entries = [existing_entry]

      {_new_stream, new_entries, _actions} = Stream.block_start(stream, entries, 0, :text)

      assert length(new_entries) == 2
      assert Enum.at(new_entries, 0) == existing_entry
    end
  end

  describe "apply_delta/4" do
    test "appends delta to correct entry" do
      stream = StreamState.new(1)
      entries = []

      # Start a block
      {stream, entries, _} = Stream.block_start(stream, entries, 0, :text)

      # Apply delta
      {new_stream, new_entries, actions} = Stream.apply_delta(stream, entries, 0, "Hello ")

      assert [entry] = new_entries
      assert entry.content == "Hello "
      assert entry.rendered_html != nil

      assert Map.has_key?(new_stream.documents, 1)
      assert actions == [:broadcast_chat_state]
    end

    test "appends multiple deltas" do
      stream = StreamState.new(1)
      entries = []

      {stream, entries, _} = Stream.block_start(stream, entries, 0, :text)
      {stream, entries, _} = Stream.apply_delta(stream, entries, 0, "Hello ")
      {_stream, entries, _} = Stream.apply_delta(stream, entries, 0, "World!")

      assert [entry] = entries
      assert entry.content == "Hello World!"
    end

    test "ignores delta for unknown block index" do
      stream = StreamState.new(1)
      entries = []

      {new_stream, new_entries, actions} = Stream.apply_delta(stream, entries, 99, "ignored")

      assert new_stream == stream
      assert new_entries == entries
      assert actions == []
    end

    test "handles delta for block with missing document" do
      stream = %StreamState{
        blocks: %{0 => 1},
        documents: %{},
        next_position: 2
      }

      entry =
        ChatEntry.assistant_response("entry-1", 1, "existing", "<p>existing</p>", true)

      entries = [entry]

      {new_stream, new_entries, actions} = Stream.apply_delta(stream, entries, 0, " more")

      # Should still append content even without document
      assert [updated_entry] = new_entries
      assert updated_entry.content == "existing more"
      # Stream state should not be modified
      assert new_stream == stream
      assert actions == [:broadcast_chat_state]
    end

    test "applies delta to correct entry among multiple" do
      stream = StreamState.new(1)
      entries = []

      {stream, entries, _} = Stream.block_start(stream, entries, 0, :thinking)
      {stream, entries, _} = Stream.block_start(stream, entries, 1, :text)

      # Apply delta only to second block
      {_stream, new_entries, _} = Stream.apply_delta(stream, entries, 1, "Response text")

      assert length(new_entries) == 2
      assert Enum.at(new_entries, 0).content == ""
      assert Enum.at(new_entries, 1).content == "Response text"
    end
  end

  describe "block_stop/5" do
    test "marks entry as not streaming and returns persist action" do
      stream = StreamState.new(1)
      entries = []

      {stream, entries, _} = Stream.block_start(stream, entries, 0, :text)
      {stream, entries, _} = Stream.apply_delta(stream, entries, 0, "Content")

      {new_stream, new_entries, actions} = Stream.block_stop(stream, entries, 0, 42, "turn-123")

      assert [entry] = new_entries
      assert entry.streaming == false

      # Document should be cleaned up
      refute Map.has_key?(new_stream.documents, 1)

      # Should have persist action and broadcast
      assert {:persist_message, 42, "turn-123", 1, message_attrs} = Enum.at(actions, 0)
      assert message_attrs.role == "assistant"
      assert message_attrs.message_type == "response"
      assert message_attrs.content == "Content"
      assert :broadcast_chat_state in actions
    end

    test "ignores stop for unknown block index" do
      stream = StreamState.new(1)
      entries = []

      {new_stream, new_entries, actions} = Stream.block_stop(stream, entries, 99, 42, "turn-123")

      assert new_stream == stream
      assert new_entries == entries
      assert actions == []
    end

    test "handles thinking block stop" do
      stream = StreamState.new(1)
      entries = []

      {stream, entries, _} = Stream.block_start(stream, entries, 0, :thinking)
      {stream, entries, _} = Stream.apply_delta(stream, entries, 0, "Let me think...")

      {_new_stream, new_entries, actions} = Stream.block_stop(stream, entries, 0, 42, "turn-123")

      assert [entry] = new_entries
      assert entry.streaming == false
      assert entry.message_type == :thinking

      assert {:persist_message, 42, "turn-123", 1, message_attrs} = Enum.at(actions, 0)
      assert message_attrs.message_type == "thinking"
    end

    test "handles nil turn_id" do
      stream = StreamState.new(1)
      entries = []

      {stream, entries, _} = Stream.block_start(stream, entries, 0, :text)

      {_new_stream, _new_entries, actions} = Stream.block_stop(stream, entries, 0, 42, nil)

      assert {:persist_message, 42, nil, 1, _} = Enum.at(actions, 0)
    end
  end

  describe "finalize/4" do
    test "finalizes all streaming entries" do
      stream = StreamState.new(1)
      entries = []

      {stream, entries, _} = Stream.block_start(stream, entries, 0, :thinking)
      {stream, entries, _} = Stream.apply_delta(stream, entries, 0, "Thought")
      {stream, entries, _} = Stream.block_start(stream, entries, 1, :text)
      {stream, entries, _} = Stream.apply_delta(stream, entries, 1, "Response")

      {new_stream, new_entries, actions} = Stream.finalize(stream, entries, 42, "turn-123")

      # Both entries should be marked as not streaming
      assert Enum.all?(new_entries, &(!&1.streaming))

      # Stream state should be reset
      assert new_stream.blocks == %{}
      assert new_stream.documents == %{}
      # But next_position should be preserved
      assert new_stream.next_position == stream.next_position

      # Should have persist actions for both plus broadcast
      persist_actions = Enum.filter(actions, &match?({:persist_message, _, _, _, _}, &1))
      assert length(persist_actions) == 2
      assert :broadcast_chat_state in actions
    end

    test "handles empty entries" do
      stream = StreamState.new(1)

      {new_stream, new_entries, actions} = Stream.finalize(stream, [], 42, "turn-123")

      assert new_stream.blocks == %{}
      assert new_entries == []
      assert actions == [:broadcast_chat_state]
    end

    test "skips non-streaming entries" do
      stream = StreamState.new(3)

      non_streaming_entry =
        ChatEntry.assistant_response("e1", 1, "Done", "<p>Done</p>", false)

      streaming_entry =
        ChatEntry.assistant_response("e2", 2, "Streaming", "<p>Streaming</p>", true)

      entries = [non_streaming_entry, streaming_entry]

      {_new_stream, new_entries, actions} = Stream.finalize(stream, entries, 42, "turn-123")

      # First entry should remain unchanged
      assert Enum.at(new_entries, 0).streaming == false
      # Second entry should be finalized
      assert Enum.at(new_entries, 1).streaming == false

      # Only one persist action (for the streaming entry)
      persist_actions = Enum.filter(actions, &match?({:persist_message, _, _, _, _}, &1))
      assert length(persist_actions) == 1
    end

    test "skips non-message entries" do
      stream = StreamState.new(2)

      # Create a tool invocation entry (not a message)
      tool_entry =
        ChatEntry.tool_invocation(
          "tool-1",
          1,
          "call_123",
          "msf_command",
          %{"command" => "help"},
          :pending,
          "",
          DateTime.utc_now()
        )

      # Note: tool_invocation sets streaming: false by default, but let's verify
      # the function correctly identifies it as a non-message entry
      entries = [tool_entry]

      {_new_stream, new_entries, actions} = Stream.finalize(stream, entries, 42, "turn-123")

      # Tool entry should be unchanged
      assert [^tool_entry] = new_entries

      # No persist actions for non-message entries
      persist_actions = Enum.filter(actions, &match?({:persist_message, _, _, _, _}, &1))
      assert persist_actions == []
    end
  end
end
