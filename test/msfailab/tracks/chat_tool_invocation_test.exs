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

defmodule Msfailab.Tracks.ChatToolInvocationTest do
  use Msfailab.DataCase, async: true

  alias Msfailab.Tracks.ChatHistoryEntry
  alias Msfailab.Tracks.ChatToolInvocation

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
        entry_type: "tool_invocation"
      })
      |> Repo.insert()

    %{track: track, entry: entry}
  end

  describe "changeset/2" do
    setup [:create_entry]

    test "valid with required fields", %{entry: entry} do
      attrs = %{
        entry_id: entry.id,
        tool_call_id: "call_abc123",
        tool_name: "execute_msfconsole_command"
      }

      changeset = ChatToolInvocation.changeset(%ChatToolInvocation{}, attrs)
      assert changeset.valid?
    end

    test "valid with all fields", %{entry: entry} do
      attrs = %{
        entry_id: entry.id,
        tool_call_id: "call_abc123",
        tool_name: "execute_msfconsole_command",
        arguments: %{"command" => "nmap -sV 10.0.0.1"},
        status: "pending"
      }

      changeset = ChatToolInvocation.changeset(%ChatToolInvocation{}, attrs)
      assert changeset.valid?
    end

    test "defaults status to pending", %{entry: entry} do
      attrs = %{
        entry_id: entry.id,
        tool_call_id: "call_abc123",
        tool_name: "execute_msfconsole_command"
      }

      changeset = ChatToolInvocation.changeset(%ChatToolInvocation{}, attrs)
      assert get_field(changeset, :status) == "pending"
    end

    test "defaults arguments to empty map", %{entry: entry} do
      attrs = %{
        entry_id: entry.id,
        tool_call_id: "call_abc123",
        tool_name: "execute_msfconsole_command"
      }

      changeset = ChatToolInvocation.changeset(%ChatToolInvocation{}, attrs)
      assert get_field(changeset, :arguments) == %{}
    end

    test "invalid without entry_id" do
      attrs = %{
        tool_call_id: "call_abc123",
        tool_name: "execute_msfconsole_command"
      }

      changeset = ChatToolInvocation.changeset(%ChatToolInvocation{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).entry_id
    end

    test "invalid without tool_call_id", %{entry: entry} do
      attrs = %{
        entry_id: entry.id,
        tool_name: "execute_msfconsole_command"
      }

      changeset = ChatToolInvocation.changeset(%ChatToolInvocation{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).tool_call_id
    end

    test "invalid without tool_name", %{entry: entry} do
      attrs = %{
        entry_id: entry.id,
        tool_call_id: "call_abc123"
      }

      changeset = ChatToolInvocation.changeset(%ChatToolInvocation{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).tool_name
    end

    test "invalid with unknown status", %{entry: entry} do
      attrs = %{
        entry_id: entry.id,
        tool_call_id: "call_abc123",
        tool_name: "execute_msfconsole_command",
        status: "unknown_status"
      }

      changeset = ChatToolInvocation.changeset(%ChatToolInvocation{}, attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).status
    end

    test "accepts all valid statuses", %{entry: entry} do
      for status <- ChatToolInvocation.statuses() do
        attrs = %{
          entry_id: entry.id,
          tool_call_id: "call_abc123",
          tool_name: "execute_msfconsole_command",
          status: status
        }

        changeset = ChatToolInvocation.changeset(%ChatToolInvocation{}, attrs)
        assert changeset.valid?, "Expected status #{status} to be valid"
      end
    end
  end

  describe "status transition helpers" do
    setup [:create_entry]

    test "approve/1 transitions to approved", %{entry: entry} do
      invocation = %ChatToolInvocation{entry_id: entry.id, status: "pending"}
      changeset = ChatToolInvocation.approve(invocation)
      assert get_change(changeset, :status) == "approved"
    end

    test "deny/2 transitions to denied with reason", %{entry: entry} do
      invocation = %ChatToolInvocation{entry_id: entry.id, status: "pending"}
      changeset = ChatToolInvocation.deny(invocation, "User rejected")
      assert get_change(changeset, :status) == "denied"
      assert get_change(changeset, :denied_reason) == "User rejected"
    end

    test "start_execution/1 transitions to executing", %{entry: entry} do
      invocation = %ChatToolInvocation{entry_id: entry.id, status: "approved"}
      changeset = ChatToolInvocation.start_execution(invocation)
      assert get_change(changeset, :status) == "executing"
    end

    test "complete_success/3 transitions to success with result", %{entry: entry} do
      invocation = %ChatToolInvocation{entry_id: entry.id, status: "executing"}
      changeset = ChatToolInvocation.complete_success(invocation, "Command output", 1500)
      assert get_change(changeset, :status) == "success"
      assert get_change(changeset, :result_content) == "Command output"
      assert get_change(changeset, :duration_ms) == 1500
    end

    test "complete_error/3 transitions to error with message", %{entry: entry} do
      invocation = %ChatToolInvocation{entry_id: entry.id, status: "executing"}
      changeset = ChatToolInvocation.complete_error(invocation, "Connection failed", 500)
      assert get_change(changeset, :status) == "error"
      assert get_change(changeset, :error_message) == "Connection failed"
      assert get_change(changeset, :duration_ms) == 500
    end

    test "complete_timeout/2 transitions to timeout", %{entry: entry} do
      invocation = %ChatToolInvocation{entry_id: entry.id, status: "executing"}
      changeset = ChatToolInvocation.complete_timeout(invocation, 30_000)
      assert get_change(changeset, :status) == "timeout"
      assert get_change(changeset, :duration_ms) == 30_000
    end
  end

  describe "statuses/0" do
    test "returns all valid status values" do
      statuses = ChatToolInvocation.statuses()

      assert "pending" in statuses
      assert "approved" in statuses
      assert "denied" in statuses
      assert "executing" in statuses
      assert "success" in statuses
      assert "error" in statuses
      assert "timeout" in statuses
    end
  end

  describe "terminal?/1" do
    test "returns true for terminal statuses" do
      assert ChatToolInvocation.terminal?(%ChatToolInvocation{status: "denied"})
      assert ChatToolInvocation.terminal?(%ChatToolInvocation{status: "success"})
      assert ChatToolInvocation.terminal?(%ChatToolInvocation{status: "error"})
      assert ChatToolInvocation.terminal?(%ChatToolInvocation{status: "timeout"})
    end

    test "returns false for non-terminal statuses" do
      refute ChatToolInvocation.terminal?(%ChatToolInvocation{status: "pending"})
      refute ChatToolInvocation.terminal?(%ChatToolInvocation{status: "approved"})
      refute ChatToolInvocation.terminal?(%ChatToolInvocation{status: "executing"})
    end
  end

  describe "pending?/1" do
    test "returns true for pending status" do
      assert ChatToolInvocation.pending?(%ChatToolInvocation{status: "pending"})
    end

    test "returns false for non-pending statuses" do
      refute ChatToolInvocation.pending?(%ChatToolInvocation{status: "approved"})
      refute ChatToolInvocation.pending?(%ChatToolInvocation{status: "executing"})
      refute ChatToolInvocation.pending?(%ChatToolInvocation{status: "success"})
    end
  end

  describe "database operations" do
    setup [:create_entry]

    test "inserts valid tool invocation", %{entry: entry} do
      attrs = %{
        entry_id: entry.id,
        tool_call_id: "call_abc123",
        tool_name: "execute_msfconsole_command",
        arguments: %{"command" => "nmap -sV 10.0.0.1"}
      }

      {:ok, invocation} =
        %ChatToolInvocation{}
        |> ChatToolInvocation.changeset(attrs)
        |> Repo.insert()

      assert invocation.entry_id == entry.id
      assert invocation.tool_call_id == "call_abc123"
      assert invocation.tool_name == "execute_msfconsole_command"
      assert invocation.arguments == %{"command" => "nmap -sV 10.0.0.1"}
      assert invocation.status == "pending"
    end

    test "updates invocation through lifecycle", %{entry: entry} do
      {:ok, invocation} =
        %ChatToolInvocation{}
        |> ChatToolInvocation.changeset(%{
          entry_id: entry.id,
          tool_call_id: "call_abc123",
          tool_name: "execute_bash_command",
          arguments: %{"command" => "ls -la"}
        })
        |> Repo.insert()

      # Approve
      {:ok, approved} =
        invocation
        |> ChatToolInvocation.approve()
        |> Repo.update()

      assert approved.status == "approved"

      # Start execution
      {:ok, executing} =
        approved
        |> ChatToolInvocation.start_execution()
        |> Repo.update()

      assert executing.status == "executing"

      # Complete with success
      {:ok, completed} =
        executing
        |> ChatToolInvocation.complete_success("total 42\ndrwxr-xr-x...", 250)
        |> Repo.update()

      assert completed.status == "success"
      assert completed.result_content == "total 42\ndrwxr-xr-x..."
      assert completed.duration_ms == 250
    end
  end
end
