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

defmodule Msfailab.Tracks.ChatConsoleContextTest do
  use Msfailab.DataCase, async: true

  alias Msfailab.Tracks.ChatConsoleContext
  alias Msfailab.Tracks.ChatHistoryEntry

  # Helper to create track and entry for testing
  defp create_entry(_context) do
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

    {:ok, entry} =
      %ChatHistoryEntry{}
      |> ChatHistoryEntry.changeset(%{
        track_id: track.id,
        position: 1,
        entry_type: "console_context"
      })
      |> Repo.insert()

    %{track: track, entry: entry}
  end

  describe "changeset/2" do
    setup [:create_entry]

    test "valid with required fields", %{entry: entry} do
      attrs = %{
        entry_id: entry.id,
        content: "msf6 > sessions -l\nNo active sessions."
      }

      changeset = ChatConsoleContext.changeset(%ChatConsoleContext{}, attrs)
      assert changeset.valid?
    end

    test "valid with optional console_history_block_id", %{entry: entry} do
      attrs = %{
        entry_id: entry.id,
        content: "msf6 > sessions -l\nNo active sessions.",
        console_history_block_id: 123
      }

      changeset = ChatConsoleContext.changeset(%ChatConsoleContext{}, attrs)
      assert changeset.valid?
    end

    test "invalid without entry_id" do
      attrs = %{
        content: "msf6 > sessions -l"
      }

      changeset = ChatConsoleContext.changeset(%ChatConsoleContext{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).entry_id
    end

    test "invalid without content", %{entry: entry} do
      attrs = %{
        entry_id: entry.id
      }

      changeset = ChatConsoleContext.changeset(%ChatConsoleContext{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).content
    end
  end

  describe "database operations" do
    setup [:create_entry]

    test "inserts valid console context", %{entry: entry} do
      block_id = 42

      attrs = %{
        entry_id: entry.id,
        content: "msf6 > use exploit/multi/handler\nmsf6 exploit(multi/handler) >",
        console_history_block_id: block_id
      }

      {:ok, context} =
        %ChatConsoleContext{}
        |> ChatConsoleContext.changeset(attrs)
        |> Repo.insert()

      assert context.entry_id == entry.id
      assert context.content == "msf6 > use exploit/multi/handler\nmsf6 exploit(multi/handler) >"
      assert context.console_history_block_id == block_id
    end

    test "allows nil console_history_block_id", %{entry: entry} do
      attrs = %{
        entry_id: entry.id,
        content: "Manual context injection"
      }

      {:ok, context} =
        %ChatConsoleContext{}
        |> ChatConsoleContext.changeset(attrs)
        |> Repo.insert()

      assert context.console_history_block_id == nil
    end
  end
end
