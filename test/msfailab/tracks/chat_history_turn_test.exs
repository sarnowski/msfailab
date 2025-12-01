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

defmodule Msfailab.Tracks.ChatHistoryTurnTest do
  use Msfailab.DataCase, async: true

  alias Msfailab.Tracks.ChatHistoryTurn

  # Helper to create a track for testing
  defp create_track(_context) do
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

    %{track: track}
  end

  describe "changeset/2" do
    setup [:create_track]

    test "valid with all required fields", %{track: track} do
      attrs = %{
        track_id: track.id,
        position: 1,
        trigger: "user_prompt",
        model: "claude-sonnet-4-20250514",
        tool_approval_mode: "ask_first"
      }

      changeset = ChatHistoryTurn.changeset(%ChatHistoryTurn{}, attrs)
      assert changeset.valid?
    end

    test "invalid without track_id" do
      attrs = %{
        position: 1,
        trigger: "user_prompt",
        model: "claude-sonnet-4-20250514",
        tool_approval_mode: "ask_first"
      }

      changeset = ChatHistoryTurn.changeset(%ChatHistoryTurn{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).track_id
    end

    test "invalid without position" do
      attrs = %{
        track_id: 1,
        trigger: "user_prompt",
        model: "claude-sonnet-4-20250514",
        tool_approval_mode: "ask_first"
      }

      changeset = ChatHistoryTurn.changeset(%ChatHistoryTurn{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).position
    end

    test "invalid without trigger" do
      attrs = %{
        track_id: 1,
        position: 1,
        model: "claude-sonnet-4-20250514",
        tool_approval_mode: "ask_first"
      }

      changeset = ChatHistoryTurn.changeset(%ChatHistoryTurn{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).trigger
    end

    test "invalid without model" do
      attrs = %{
        track_id: 1,
        position: 1,
        trigger: "user_prompt",
        tool_approval_mode: "ask_first"
      }

      changeset = ChatHistoryTurn.changeset(%ChatHistoryTurn{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).model
    end

    test "invalid without tool_approval_mode" do
      attrs = %{
        track_id: 1,
        position: 1,
        trigger: "user_prompt",
        model: "claude-sonnet-4-20250514"
      }

      changeset = ChatHistoryTurn.changeset(%ChatHistoryTurn{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).tool_approval_mode
    end

    test "invalid with position less than 1" do
      attrs = %{
        track_id: 1,
        position: 0,
        trigger: "user_prompt",
        model: "claude-sonnet-4-20250514",
        tool_approval_mode: "ask_first"
      }

      changeset = ChatHistoryTurn.changeset(%ChatHistoryTurn{}, attrs)
      refute changeset.valid?
      assert "must be greater than 0" in errors_on(changeset).position
    end

    test "invalid with unknown trigger" do
      attrs = %{
        track_id: 1,
        position: 1,
        trigger: "unknown_trigger",
        model: "claude-sonnet-4-20250514",
        tool_approval_mode: "ask_first"
      }

      changeset = ChatHistoryTurn.changeset(%ChatHistoryTurn{}, attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).trigger
    end

    test "invalid with unknown status" do
      attrs = %{
        track_id: 1,
        position: 1,
        trigger: "user_prompt",
        status: "unknown_status",
        model: "claude-sonnet-4-20250514",
        tool_approval_mode: "ask_first"
      }

      changeset = ChatHistoryTurn.changeset(%ChatHistoryTurn{}, attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).status
    end

    test "defaults status to pending" do
      attrs = %{
        track_id: 1,
        position: 1,
        trigger: "user_prompt",
        model: "claude-sonnet-4-20250514",
        tool_approval_mode: "ask_first"
      }

      changeset = ChatHistoryTurn.changeset(%ChatHistoryTurn{}, attrs)
      assert get_field(changeset, :status) == "pending"
    end

    test "accepts all valid triggers" do
      for trigger <- ChatHistoryTurn.triggers() do
        attrs = %{
          track_id: 1,
          position: 1,
          trigger: trigger,
          model: "claude-sonnet-4-20250514",
          tool_approval_mode: "ask_first"
        }

        changeset = ChatHistoryTurn.changeset(%ChatHistoryTurn{}, attrs)
        assert changeset.valid?, "Expected trigger #{trigger} to be valid"
      end
    end

    test "accepts all valid statuses" do
      for status <- ChatHistoryTurn.statuses() do
        attrs = %{
          track_id: 1,
          position: 1,
          trigger: "user_prompt",
          status: status,
          model: "claude-sonnet-4-20250514",
          tool_approval_mode: "ask_first"
        }

        changeset = ChatHistoryTurn.changeset(%ChatHistoryTurn{}, attrs)
        assert changeset.valid?, "Expected status #{status} to be valid"
      end
    end
  end

  describe "status_changeset/2" do
    test "updates status with valid value" do
      turn = %ChatHistoryTurn{status: "pending"}
      changeset = ChatHistoryTurn.status_changeset(turn, "streaming")
      assert changeset.valid?
      assert get_change(changeset, :status) == "streaming"
    end

    test "invalid with unknown status" do
      turn = %ChatHistoryTurn{status: "pending"}
      changeset = ChatHistoryTurn.status_changeset(turn, "invalid")
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).status
    end
  end

  describe "statuses/0" do
    test "returns all valid status values" do
      statuses = ChatHistoryTurn.statuses()

      assert "pending" in statuses
      assert "streaming" in statuses
      assert "pending_approval" in statuses
      assert "executing_tools" in statuses
      assert "finished" in statuses
      assert "error" in statuses
      assert "interrupted" in statuses
    end
  end

  describe "triggers/0" do
    test "returns all valid trigger values" do
      triggers = ChatHistoryTurn.triggers()

      assert "user_prompt" in triggers
      assert "scheduled_prompt" in triggers
      assert "script_triggered" in triggers
    end
  end

  describe "database operations" do
    setup [:create_track]

    test "inserts valid turn", %{track: track} do
      attrs = %{
        track_id: track.id,
        position: 1,
        trigger: "user_prompt",
        model: "claude-sonnet-4-20250514",
        tool_approval_mode: "ask_first"
      }

      {:ok, turn} =
        %ChatHistoryTurn{}
        |> ChatHistoryTurn.changeset(attrs)
        |> Repo.insert()

      assert turn.id != nil
      assert turn.track_id == track.id
      assert turn.position == 1
      assert turn.trigger == "user_prompt"
      assert turn.status == "pending"
    end

    test "updates turn status", %{track: track} do
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

      {:ok, updated} =
        turn
        |> ChatHistoryTurn.status_changeset("streaming")
        |> Repo.update()

      assert updated.status == "streaming"
    end
  end
end
