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

defmodule Msfailab.Tracks.ChatHistoryEntryTest do
  use Msfailab.DataCase, async: true

  alias Msfailab.Tracks.ChatHistoryEntry
  alias Msfailab.Tracks.ChatHistoryLLMResponse
  alias Msfailab.Tracks.ChatHistoryTurn

  # Helper to create track, turn, and llm_response for testing
  defp create_fixtures(_context) do
    {:ok, workspace} =
      Msfailab.Workspaces.create_workspace(%{slug: "test", name: "Test"})

    {:ok, container} =
      Msfailab.Containers.create_container(workspace, %{
        slug: "container",
        name: "Container",
        docker_image: "test:latest"
      })

    {:ok, track} =
      Msfailab.Tracks.create_track(container, %{slug: "track", name: "Track"})

    {:ok, turn} =
      %ChatHistoryTurn{}
      |> ChatHistoryTurn.changeset(%{
        track_id: track.id,
        position: 1,
        trigger: "user_prompt",
        model: "claude-sonnet-4-20250514",
        tool_approval_mode: "ask_first"
      })
      |> Repo.insert()

    {:ok, llm_response} =
      %ChatHistoryLLMResponse{}
      |> ChatHistoryLLMResponse.changeset(%{
        track_id: track.id,
        turn_id: turn.id,
        model: "claude-sonnet-4-20250514",
        input_tokens: 100,
        output_tokens: 50
      })
      |> Repo.insert()

    %{track: track, turn: turn, llm_response: llm_response}
  end

  describe "changeset/2" do
    setup [:create_fixtures]

    test "valid with required fields only", %{track: track} do
      attrs = %{
        track_id: track.id,
        position: 1,
        entry_type: "message"
      }

      changeset = ChatHistoryEntry.changeset(%ChatHistoryEntry{}, attrs)
      assert changeset.valid?
    end

    test "valid with all fields", %{track: track, turn: turn, llm_response: llm_response} do
      attrs = %{
        track_id: track.id,
        turn_id: turn.id,
        llm_response_id: llm_response.id,
        position: 1,
        entry_type: "message"
      }

      changeset = ChatHistoryEntry.changeset(%ChatHistoryEntry{}, attrs)
      assert changeset.valid?
    end

    test "valid without turn_id for console_context", %{track: track} do
      attrs = %{
        track_id: track.id,
        position: 1,
        entry_type: "console_context"
      }

      changeset = ChatHistoryEntry.changeset(%ChatHistoryEntry{}, attrs)
      assert changeset.valid?
    end

    test "invalid without track_id" do
      attrs = %{
        position: 1,
        entry_type: "message"
      }

      changeset = ChatHistoryEntry.changeset(%ChatHistoryEntry{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).track_id
    end

    test "invalid without position", %{track: track} do
      attrs = %{
        track_id: track.id,
        entry_type: "message"
      }

      changeset = ChatHistoryEntry.changeset(%ChatHistoryEntry{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).position
    end

    test "invalid without entry_type", %{track: track} do
      attrs = %{
        track_id: track.id,
        position: 1
      }

      changeset = ChatHistoryEntry.changeset(%ChatHistoryEntry{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).entry_type
    end

    test "invalid with position less than 1", %{track: track} do
      attrs = %{
        track_id: track.id,
        position: 0,
        entry_type: "message"
      }

      changeset = ChatHistoryEntry.changeset(%ChatHistoryEntry{}, attrs)
      refute changeset.valid?
      assert "must be greater than 0" in errors_on(changeset).position
    end

    test "invalid with unknown entry_type", %{track: track} do
      attrs = %{
        track_id: track.id,
        position: 1,
        entry_type: "unknown_type"
      }

      changeset = ChatHistoryEntry.changeset(%ChatHistoryEntry{}, attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).entry_type
    end

    test "accepts all valid entry types", %{track: track} do
      for entry_type <- ChatHistoryEntry.entry_types() do
        attrs = %{
          track_id: track.id,
          position: 1,
          entry_type: entry_type
        }

        changeset = ChatHistoryEntry.changeset(%ChatHistoryEntry{}, attrs)
        assert changeset.valid?, "Expected entry_type #{entry_type} to be valid"
      end
    end
  end

  describe "entry_types/0" do
    test "returns all valid entry type values" do
      entry_types = ChatHistoryEntry.entry_types()

      assert "message" in entry_types
      assert "tool_invocation" in entry_types
      assert "console_context" in entry_types
    end
  end

  describe "database operations" do
    setup [:create_fixtures]

    test "inserts valid entry", %{track: track, turn: turn} do
      attrs = %{
        track_id: track.id,
        turn_id: turn.id,
        position: 1,
        entry_type: "message"
      }

      {:ok, entry} =
        %ChatHistoryEntry{}
        |> ChatHistoryEntry.changeset(attrs)
        |> Repo.insert()

      assert entry.id != nil
      assert entry.track_id == track.id
      assert entry.turn_id == turn.id
      assert entry.position == 1
      assert entry.entry_type == "message"
    end

    test "enforces unique position within track", %{track: track} do
      {:ok, _entry1} =
        %ChatHistoryEntry{}
        |> ChatHistoryEntry.changeset(%{
          track_id: track.id,
          position: 1,
          entry_type: "message"
        })
        |> Repo.insert()

      {:error, changeset} =
        %ChatHistoryEntry{}
        |> ChatHistoryEntry.changeset(%{
          track_id: track.id,
          position: 1,
          entry_type: "message"
        })
        |> Repo.insert()

      assert "has already been taken" in errors_on(changeset).position
    end

    test "allows same position in different tracks", %{track: track} do
      # Create second track
      {:ok, workspace} =
        Msfailab.Workspaces.create_workspace(%{slug: "test2", name: "Test2"})

      {:ok, container} =
        Msfailab.Containers.create_container(workspace, %{
          slug: "container2",
          name: "Container2",
          docker_image: "test:latest"
        })

      {:ok, track2} =
        Msfailab.Tracks.create_track(container, %{slug: "track2", name: "Track2"})

      {:ok, _entry1} =
        %ChatHistoryEntry{}
        |> ChatHistoryEntry.changeset(%{
          track_id: track.id,
          position: 1,
          entry_type: "message"
        })
        |> Repo.insert()

      {:ok, entry2} =
        %ChatHistoryEntry{}
        |> ChatHistoryEntry.changeset(%{
          track_id: track2.id,
          position: 1,
          entry_type: "message"
        })
        |> Repo.insert()

      assert entry2.id != nil
      assert entry2.position == 1
    end
  end
end
