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

defmodule Msfailab.Tracks.ChatCompactionTest do
  use Msfailab.DataCase, async: true

  alias Msfailab.Tracks.ChatCompaction

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
        content: "Summary of the conversation...",
        summarized_up_to_position: 10,
        entries_summarized_count: 10,
        input_tokens_before: 5000,
        input_tokens_after: 1000,
        compaction_model: "claude-sonnet-4-20250514"
      }

      changeset = ChatCompaction.changeset(%ChatCompaction{}, attrs)
      assert changeset.valid?
    end

    test "valid with optional fields", %{track: track} do
      attrs = %{
        track_id: track.id,
        content: "Summary of the conversation...",
        summarized_up_to_position: 10,
        entries_summarized_count: 10,
        input_tokens_before: 5000,
        input_tokens_after: 1000,
        compaction_model: "claude-sonnet-4-20250514",
        compaction_duration_ms: 2500,
        previous_compaction_id: nil
      }

      changeset = ChatCompaction.changeset(%ChatCompaction{}, attrs)
      assert changeset.valid?
    end

    test "invalid without track_id" do
      attrs = %{
        content: "Summary...",
        summarized_up_to_position: 10,
        entries_summarized_count: 10,
        input_tokens_before: 5000,
        input_tokens_after: 1000,
        compaction_model: "claude-sonnet-4-20250514"
      }

      changeset = ChatCompaction.changeset(%ChatCompaction{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).track_id
    end

    test "invalid without content", %{track: track} do
      attrs = %{
        track_id: track.id,
        summarized_up_to_position: 10,
        entries_summarized_count: 10,
        input_tokens_before: 5000,
        input_tokens_after: 1000,
        compaction_model: "claude-sonnet-4-20250514"
      }

      changeset = ChatCompaction.changeset(%ChatCompaction{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).content
    end

    test "invalid without summarized_up_to_position", %{track: track} do
      attrs = %{
        track_id: track.id,
        content: "Summary...",
        entries_summarized_count: 10,
        input_tokens_before: 5000,
        input_tokens_after: 1000,
        compaction_model: "claude-sonnet-4-20250514"
      }

      changeset = ChatCompaction.changeset(%ChatCompaction{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).summarized_up_to_position
    end

    test "invalid with summarized_up_to_position less than 1", %{track: track} do
      attrs = %{
        track_id: track.id,
        content: "Summary...",
        summarized_up_to_position: 0,
        entries_summarized_count: 10,
        input_tokens_before: 5000,
        input_tokens_after: 1000,
        compaction_model: "claude-sonnet-4-20250514"
      }

      changeset = ChatCompaction.changeset(%ChatCompaction{}, attrs)
      refute changeset.valid?
      assert "must be greater than 0" in errors_on(changeset).summarized_up_to_position
    end

    test "invalid with entries_summarized_count less than 1", %{track: track} do
      attrs = %{
        track_id: track.id,
        content: "Summary...",
        summarized_up_to_position: 10,
        entries_summarized_count: 0,
        input_tokens_before: 5000,
        input_tokens_after: 1000,
        compaction_model: "claude-sonnet-4-20250514"
      }

      changeset = ChatCompaction.changeset(%ChatCompaction{}, attrs)
      refute changeset.valid?
      assert "must be greater than 0" in errors_on(changeset).entries_summarized_count
    end

    test "invalid with input_tokens_before less than 1", %{track: track} do
      attrs = %{
        track_id: track.id,
        content: "Summary...",
        summarized_up_to_position: 10,
        entries_summarized_count: 10,
        input_tokens_before: 0,
        input_tokens_after: 1000,
        compaction_model: "claude-sonnet-4-20250514"
      }

      changeset = ChatCompaction.changeset(%ChatCompaction{}, attrs)
      refute changeset.valid?
      assert "must be greater than 0" in errors_on(changeset).input_tokens_before
    end

    test "invalid with input_tokens_after less than 1", %{track: track} do
      attrs = %{
        track_id: track.id,
        content: "Summary...",
        summarized_up_to_position: 10,
        entries_summarized_count: 10,
        input_tokens_before: 5000,
        input_tokens_after: 0,
        compaction_model: "claude-sonnet-4-20250514"
      }

      changeset = ChatCompaction.changeset(%ChatCompaction{}, attrs)
      refute changeset.valid?
      assert "must be greater than 0" in errors_on(changeset).input_tokens_after
    end

    test "invalid without compaction_model", %{track: track} do
      attrs = %{
        track_id: track.id,
        content: "Summary...",
        summarized_up_to_position: 10,
        entries_summarized_count: 10,
        input_tokens_before: 5000,
        input_tokens_after: 1000
      }

      changeset = ChatCompaction.changeset(%ChatCompaction{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).compaction_model
    end
  end

  describe "compression_ratio/1" do
    test "calculates compression ratio" do
      compaction = %ChatCompaction{
        input_tokens_before: 5000,
        input_tokens_after: 1000
      }

      assert ChatCompaction.compression_ratio(compaction) == 0.2
    end

    test "returns nil when input_tokens_before is nil" do
      compaction = %ChatCompaction{
        input_tokens_before: nil,
        input_tokens_after: 1000
      }

      assert ChatCompaction.compression_ratio(compaction) == nil
    end

    test "returns nil when input_tokens_after is nil" do
      compaction = %ChatCompaction{
        input_tokens_before: 5000,
        input_tokens_after: nil
      }

      assert ChatCompaction.compression_ratio(compaction) == nil
    end

    test "returns nil when input_tokens_before is zero" do
      compaction = %ChatCompaction{
        input_tokens_before: 0,
        input_tokens_after: 1000
      }

      assert ChatCompaction.compression_ratio(compaction) == nil
    end
  end

  describe "tokens_saved/1" do
    test "calculates tokens saved" do
      compaction = %ChatCompaction{
        input_tokens_before: 5000,
        input_tokens_after: 1000
      }

      assert ChatCompaction.tokens_saved(compaction) == 4000
    end

    test "returns nil when input_tokens_before is nil" do
      compaction = %ChatCompaction{
        input_tokens_before: nil,
        input_tokens_after: 1000
      }

      assert ChatCompaction.tokens_saved(compaction) == nil
    end

    test "returns nil when input_tokens_after is nil" do
      compaction = %ChatCompaction{
        input_tokens_before: 5000,
        input_tokens_after: nil
      }

      assert ChatCompaction.tokens_saved(compaction) == nil
    end
  end

  describe "database operations" do
    setup [:create_track]

    test "inserts valid compaction", %{track: track} do
      attrs = %{
        track_id: track.id,
        content: "The user began by scanning the network...",
        summarized_up_to_position: 10,
        entries_summarized_count: 10,
        input_tokens_before: 5000,
        input_tokens_after: 1000,
        compaction_model: "claude-sonnet-4-20250514",
        compaction_duration_ms: 2500
      }

      {:ok, compaction} =
        %ChatCompaction{}
        |> ChatCompaction.changeset(attrs)
        |> Repo.insert()

      assert compaction.id != nil
      assert compaction.track_id == track.id
      assert compaction.content == "The user began by scanning the network..."
      assert compaction.summarized_up_to_position == 10
      assert compaction.entries_summarized_count == 10
      assert compaction.input_tokens_before == 5000
      assert compaction.input_tokens_after == 1000
      assert compaction.compaction_model == "claude-sonnet-4-20250514"
      assert compaction.compaction_duration_ms == 2500
    end

    test "creates compaction chain with previous_compaction_id", %{track: track} do
      # Create first compaction
      {:ok, first} =
        %ChatCompaction{}
        |> ChatCompaction.changeset(%{
          track_id: track.id,
          content: "First summary",
          summarized_up_to_position: 5,
          entries_summarized_count: 5,
          input_tokens_before: 2000,
          input_tokens_after: 500,
          compaction_model: "claude-sonnet-4-20250514"
        })
        |> Repo.insert()

      # Create second compaction referencing first
      {:ok, second} =
        %ChatCompaction{}
        |> ChatCompaction.changeset(%{
          track_id: track.id,
          content: "Second summary (includes first)",
          summarized_up_to_position: 10,
          entries_summarized_count: 5,
          input_tokens_before: 3000,
          input_tokens_after: 600,
          compaction_model: "claude-sonnet-4-20250514",
          previous_compaction_id: first.id
        })
        |> Repo.insert()

      assert second.previous_compaction_id == first.id

      # Load with preload to verify association
      second_loaded = Repo.get!(ChatCompaction, second.id) |> Repo.preload(:previous_compaction)
      assert second_loaded.previous_compaction.id == first.id
    end
  end
end
