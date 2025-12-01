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

defmodule Msfailab.Tracks.ChatStateTest do
  use ExUnit.Case, async: true

  alias Msfailab.Tracks.ChatEntry
  alias Msfailab.Tracks.ChatState

  describe "new/3" do
    test "creates a chat state with entries and status" do
      entry = ChatEntry.user_prompt("id", 1, "Hello")
      state = ChatState.new([entry], :idle)

      assert state.entries == [entry]
      assert state.turn_status == :idle
      assert state.current_turn_id == nil
    end

    test "creates a chat state with current_turn_id" do
      state = ChatState.new([], :streaming, "turn-123")

      assert state.entries == []
      assert state.turn_status == :streaming
      assert state.current_turn_id == "turn-123"
    end

    test "accepts all valid turn statuses" do
      valid_statuses = [
        :idle,
        :pending,
        :streaming,
        :pending_approval,
        :executing_tools,
        :finished,
        :error
      ]

      for status <- valid_statuses do
        state = ChatState.new([], status)
        assert state.turn_status == status
      end
    end
  end

  describe "empty/0" do
    test "creates an empty chat state in idle status" do
      state = ChatState.empty()

      assert state.entries == []
      assert state.turn_status == :idle
      assert state.current_turn_id == nil
    end
  end

  describe "busy?/1" do
    test "returns true for pending status" do
      assert ChatState.busy?(:pending) == true
    end

    test "returns true for streaming status" do
      assert ChatState.busy?(:streaming) == true
    end

    test "returns true for pending_approval status" do
      assert ChatState.busy?(:pending_approval) == true
    end

    test "returns true for executing_tools status" do
      assert ChatState.busy?(:executing_tools) == true
    end

    test "returns false for idle status" do
      assert ChatState.busy?(:idle) == false
    end

    test "returns false for finished status" do
      assert ChatState.busy?(:finished) == false
    end

    test "returns false for error status" do
      assert ChatState.busy?(:error) == false
    end
  end

  describe "struct enforcement" do
    test "requires enforce_keys" do
      assert_raise ArgumentError, ~r/the following keys must also be given/, fn ->
        struct!(ChatState, [])
      end
    end

    test "has default values" do
      state = %ChatState{entries: [], turn_status: :idle}

      assert state.current_turn_id == nil
    end
  end
end
