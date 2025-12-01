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

defmodule Msfailab.Tracks.ChatHistoryLLMResponseTest do
  use Msfailab.DataCase, async: true

  alias Msfailab.Tracks.ChatHistoryLLMResponse
  alias Msfailab.Tracks.ChatHistoryTurn

  # Helper to create a track and turn for testing
  defp create_track_and_turn(_context) do
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

    %{track: track, turn: turn}
  end

  describe "changeset/2" do
    setup [:create_track_and_turn]

    test "valid with all required fields", %{track: track, turn: turn} do
      attrs = %{
        track_id: track.id,
        turn_id: turn.id,
        model: "claude-sonnet-4-20250514",
        input_tokens: 100,
        output_tokens: 50
      }

      changeset = ChatHistoryLLMResponse.changeset(%ChatHistoryLLMResponse{}, attrs)
      assert changeset.valid?
    end

    test "valid with optional cache fields", %{track: track, turn: turn} do
      attrs = %{
        track_id: track.id,
        turn_id: turn.id,
        model: "claude-sonnet-4-20250514",
        input_tokens: 100,
        output_tokens: 50,
        cached_input_tokens: 80,
        cache_creation_tokens: 20,
        cache_context: %{"tokens" => [1, 2, 3]}
      }

      changeset = ChatHistoryLLMResponse.changeset(%ChatHistoryLLMResponse{}, attrs)
      assert changeset.valid?
    end

    test "invalid without track_id", %{turn: turn} do
      attrs = %{
        turn_id: turn.id,
        model: "claude-sonnet-4-20250514",
        input_tokens: 100,
        output_tokens: 50
      }

      changeset = ChatHistoryLLMResponse.changeset(%ChatHistoryLLMResponse{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).track_id
    end

    test "invalid without turn_id", %{track: track} do
      attrs = %{
        track_id: track.id,
        model: "claude-sonnet-4-20250514",
        input_tokens: 100,
        output_tokens: 50
      }

      changeset = ChatHistoryLLMResponse.changeset(%ChatHistoryLLMResponse{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).turn_id
    end

    test "invalid without model", %{track: track, turn: turn} do
      attrs = %{
        track_id: track.id,
        turn_id: turn.id,
        input_tokens: 100,
        output_tokens: 50
      }

      changeset = ChatHistoryLLMResponse.changeset(%ChatHistoryLLMResponse{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).model
    end

    test "invalid without input_tokens", %{track: track, turn: turn} do
      attrs = %{
        track_id: track.id,
        turn_id: turn.id,
        model: "claude-sonnet-4-20250514",
        output_tokens: 50
      }

      changeset = ChatHistoryLLMResponse.changeset(%ChatHistoryLLMResponse{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).input_tokens
    end

    test "invalid without output_tokens", %{track: track, turn: turn} do
      attrs = %{
        track_id: track.id,
        turn_id: turn.id,
        model: "claude-sonnet-4-20250514",
        input_tokens: 100
      }

      changeset = ChatHistoryLLMResponse.changeset(%ChatHistoryLLMResponse{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).output_tokens
    end

    test "invalid with negative input_tokens", %{track: track, turn: turn} do
      attrs = %{
        track_id: track.id,
        turn_id: turn.id,
        model: "claude-sonnet-4-20250514",
        input_tokens: -1,
        output_tokens: 50
      }

      changeset = ChatHistoryLLMResponse.changeset(%ChatHistoryLLMResponse{}, attrs)
      refute changeset.valid?
      assert "must be greater than or equal to 0" in errors_on(changeset).input_tokens
    end

    test "invalid with negative output_tokens", %{track: track, turn: turn} do
      attrs = %{
        track_id: track.id,
        turn_id: turn.id,
        model: "claude-sonnet-4-20250514",
        input_tokens: 100,
        output_tokens: -1
      }

      changeset = ChatHistoryLLMResponse.changeset(%ChatHistoryLLMResponse{}, attrs)
      refute changeset.valid?
      assert "must be greater than or equal to 0" in errors_on(changeset).output_tokens
    end

    test "invalid with negative cached_input_tokens", %{track: track, turn: turn} do
      attrs = %{
        track_id: track.id,
        turn_id: turn.id,
        model: "claude-sonnet-4-20250514",
        input_tokens: 100,
        output_tokens: 50,
        cached_input_tokens: -1
      }

      changeset = ChatHistoryLLMResponse.changeset(%ChatHistoryLLMResponse{}, attrs)
      refute changeset.valid?
      assert "must be greater than or equal to 0" in errors_on(changeset).cached_input_tokens
    end

    test "allows zero tokens", %{track: track, turn: turn} do
      attrs = %{
        track_id: track.id,
        turn_id: turn.id,
        model: "claude-sonnet-4-20250514",
        input_tokens: 0,
        output_tokens: 0
      }

      changeset = ChatHistoryLLMResponse.changeset(%ChatHistoryLLMResponse{}, attrs)
      assert changeset.valid?
    end
  end

  describe "database operations" do
    setup [:create_track_and_turn]

    test "inserts valid llm response", %{track: track, turn: turn} do
      attrs = %{
        track_id: track.id,
        turn_id: turn.id,
        model: "claude-sonnet-4-20250514",
        input_tokens: 100,
        output_tokens: 50,
        cached_input_tokens: 80
      }

      {:ok, response} =
        %ChatHistoryLLMResponse{}
        |> ChatHistoryLLMResponse.changeset(attrs)
        |> Repo.insert()

      assert response.id != nil
      assert response.track_id == track.id
      assert response.turn_id == turn.id
      assert response.model == "claude-sonnet-4-20250514"
      assert response.input_tokens == 100
      assert response.output_tokens == 50
      assert response.cached_input_tokens == 80
    end

    test "stores cache_context as map", %{track: track, turn: turn} do
      cache_context = %{"context" => [1, 2, 3, 4, 5]}

      {:ok, response} =
        %ChatHistoryLLMResponse{}
        |> ChatHistoryLLMResponse.changeset(%{
          track_id: track.id,
          turn_id: turn.id,
          model: "llama3",
          input_tokens: 50,
          output_tokens: 25,
          cache_context: cache_context
        })
        |> Repo.insert()

      assert response.cache_context == cache_context
    end
  end
end
