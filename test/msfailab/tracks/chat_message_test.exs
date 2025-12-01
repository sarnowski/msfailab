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

defmodule Msfailab.Tracks.ChatMessageTest do
  use Msfailab.DataCase, async: true

  alias Msfailab.Tracks.ChatHistoryEntry
  alias Msfailab.Tracks.ChatMessage

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
        entry_type: "message"
      })
      |> Repo.insert()

    %{track: track, entry: entry}
  end

  describe "changeset/2" do
    setup [:create_entry]

    test "valid user prompt", %{entry: entry} do
      attrs = %{
        entry_id: entry.id,
        role: "user",
        message_type: "prompt",
        content: "Hello, AI!"
      }

      changeset = ChatMessage.changeset(%ChatMessage{}, attrs)
      assert changeset.valid?
    end

    test "valid assistant thinking", %{entry: entry} do
      attrs = %{
        entry_id: entry.id,
        role: "assistant",
        message_type: "thinking",
        content: "Let me analyze this..."
      }

      changeset = ChatMessage.changeset(%ChatMessage{}, attrs)
      assert changeset.valid?
    end

    test "valid assistant response", %{entry: entry} do
      attrs = %{
        entry_id: entry.id,
        role: "assistant",
        message_type: "response",
        content: "Here is my answer."
      }

      changeset = ChatMessage.changeset(%ChatMessage{}, attrs)
      assert changeset.valid?
    end

    test "defaults content to empty string", %{entry: entry} do
      attrs = %{
        entry_id: entry.id,
        role: "user",
        message_type: "prompt"
      }

      changeset = ChatMessage.changeset(%ChatMessage{}, attrs)
      assert changeset.valid?
      assert get_field(changeset, :content) == ""
    end

    test "invalid without entry_id" do
      attrs = %{
        role: "user",
        message_type: "prompt",
        content: "Hello"
      }

      changeset = ChatMessage.changeset(%ChatMessage{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).entry_id
    end

    test "invalid without role", %{entry: entry} do
      attrs = %{
        entry_id: entry.id,
        message_type: "prompt",
        content: "Hello"
      }

      changeset = ChatMessage.changeset(%ChatMessage{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).role
    end

    test "invalid without message_type", %{entry: entry} do
      attrs = %{
        entry_id: entry.id,
        role: "user",
        content: "Hello"
      }

      changeset = ChatMessage.changeset(%ChatMessage{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).message_type
    end

    test "invalid with unknown role", %{entry: entry} do
      attrs = %{
        entry_id: entry.id,
        role: "system",
        message_type: "prompt",
        content: "Hello"
      }

      changeset = ChatMessage.changeset(%ChatMessage{}, attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).role
    end

    test "invalid with unknown message_type", %{entry: entry} do
      attrs = %{
        entry_id: entry.id,
        role: "user",
        message_type: "unknown",
        content: "Hello"
      }

      changeset = ChatMessage.changeset(%ChatMessage{}, attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).message_type
    end

    # Role/message_type combination validation tests
    test "invalid: user + thinking", %{entry: entry} do
      attrs = %{
        entry_id: entry.id,
        role: "user",
        message_type: "thinking",
        content: "Thinking..."
      }

      changeset = ChatMessage.changeset(%ChatMessage{}, attrs)
      refute changeset.valid?
      assert errors_on(changeset).message_type != []
    end

    test "invalid: user + response", %{entry: entry} do
      attrs = %{
        entry_id: entry.id,
        role: "user",
        message_type: "response",
        content: "Response"
      }

      changeset = ChatMessage.changeset(%ChatMessage{}, attrs)
      refute changeset.valid?
      assert errors_on(changeset).message_type != []
    end

    test "invalid: assistant + prompt", %{entry: entry} do
      attrs = %{
        entry_id: entry.id,
        role: "assistant",
        message_type: "prompt",
        content: "Question?"
      }

      changeset = ChatMessage.changeset(%ChatMessage{}, attrs)
      refute changeset.valid?
      assert errors_on(changeset).message_type != []
    end
  end

  describe "update_changeset/2" do
    setup [:create_entry]

    test "updates content", %{entry: entry} do
      {:ok, message} =
        %ChatMessage{}
        |> ChatMessage.changeset(%{
          entry_id: entry.id,
          role: "assistant",
          message_type: "response",
          content: "Initial"
        })
        |> Repo.insert()

      changeset = ChatMessage.update_changeset(message, %{content: "Updated content"})
      assert changeset.valid?
      assert get_change(changeset, :content) == "Updated content"
    end
  end

  describe "roles/0" do
    test "returns all valid role values" do
      roles = ChatMessage.roles()

      assert "user" in roles
      assert "assistant" in roles
    end
  end

  describe "message_types/0" do
    test "returns all valid message type values" do
      types = ChatMessage.message_types()

      assert "prompt" in types
      assert "thinking" in types
      assert "response" in types
    end
  end

  describe "database operations" do
    setup [:create_entry]

    test "inserts valid message", %{entry: entry} do
      attrs = %{
        entry_id: entry.id,
        role: "user",
        message_type: "prompt",
        content: "Test message"
      }

      {:ok, message} =
        %ChatMessage{}
        |> ChatMessage.changeset(attrs)
        |> Repo.insert()

      assert message.entry_id == entry.id
      assert message.role == "user"
      assert message.message_type == "prompt"
      assert message.content == "Test message"
    end

    test "updates message content", %{entry: entry} do
      {:ok, message} =
        %ChatMessage{}
        |> ChatMessage.changeset(%{
          entry_id: entry.id,
          role: "assistant",
          message_type: "response",
          content: ""
        })
        |> Repo.insert()

      {:ok, updated} =
        message
        |> ChatMessage.update_changeset(%{content: "Streamed content here"})
        |> Repo.update()

      assert updated.content == "Streamed content here"
    end
  end
end
