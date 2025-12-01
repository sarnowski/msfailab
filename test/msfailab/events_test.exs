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

defmodule Msfailab.EventsTest do
  use ExUnit.Case, async: true

  alias Msfailab.Events
  alias Msfailab.Events.ChatChanged
  alias Msfailab.Events.CommandIssued
  alias Msfailab.Events.CommandResult
  alias Msfailab.Events.ConsoleChanged
  alias Msfailab.Events.ConsoleUpdated
  alias Msfailab.Events.WorkspaceChanged
  alias Msfailab.Events.WorkspacesChanged

  describe "application_topic/0" do
    test "returns application topic string" do
      assert Events.application_topic() == "application"
    end
  end

  describe "workspace_topic/1" do
    test "generates topic string from workspace id" do
      assert Events.workspace_topic(1) == "workspace:1"
      assert Events.workspace_topic(42) == "workspace:42"
      assert Events.workspace_topic(999_999) == "workspace:999999"
    end
  end

  describe "subscribe_to_application/0" do
    test "subscribes current process to application topic" do
      assert :ok = Events.subscribe_to_application()

      # Verify subscription by broadcasting and receiving
      event = WorkspacesChanged.new()
      Events.broadcast(event)

      assert_receive %WorkspacesChanged{}
    end
  end

  describe "unsubscribe_from_application/0" do
    test "unsubscribes current process from application topic" do
      Events.subscribe_to_application()
      assert :ok = Events.unsubscribe_from_application()

      # Verify unsubscription by broadcasting and NOT receiving
      event = WorkspacesChanged.new()
      Events.broadcast(event)

      refute_receive %WorkspacesChanged{}, 50
    end
  end

  describe "subscribe_to_workspace/1" do
    test "subscribes current process to workspace topic" do
      workspace_id = unique_workspace_id()
      assert :ok = Events.subscribe_to_workspace(workspace_id)

      # Verify subscription by broadcasting and receiving
      event = WorkspaceChanged.new(workspace_id)
      Events.broadcast(event)

      assert_receive %WorkspaceChanged{workspace_id: ^workspace_id}
    end
  end

  describe "unsubscribe_from_workspace/1" do
    test "unsubscribes current process from workspace topic" do
      workspace_id = unique_workspace_id()
      Events.subscribe_to_workspace(workspace_id)
      assert :ok = Events.unsubscribe_from_workspace(workspace_id)

      # Verify unsubscription by broadcasting and NOT receiving
      event = WorkspaceChanged.new(workspace_id)
      Events.broadcast(event)

      refute_receive %WorkspaceChanged{}, 50
    end
  end

  describe "broadcast/1" do
    setup do
      workspace_id = unique_workspace_id()
      Events.subscribe_to_workspace(workspace_id)
      Events.subscribe_to_application()
      %{workspace_id: workspace_id}
    end

    test "broadcasts WorkspacesChanged to application topic" do
      event = WorkspacesChanged.new()
      assert :ok = Events.broadcast(event)

      assert_receive %WorkspacesChanged{}
    end

    test "broadcasts WorkspaceChanged to workspace topic", %{workspace_id: workspace_id} do
      event = WorkspaceChanged.new(workspace_id)
      assert :ok = Events.broadcast(event)

      assert_receive %WorkspaceChanged{workspace_id: ^workspace_id}
    end

    test "broadcasts ConsoleChanged to workspace topic", %{workspace_id: workspace_id} do
      event = ConsoleChanged.new(workspace_id, 10)
      assert :ok = Events.broadcast(event)

      assert_receive %ConsoleChanged{
        workspace_id: ^workspace_id,
        track_id: 10
      }
    end

    test "broadcasts ChatChanged to workspace topic", %{workspace_id: workspace_id} do
      event = ChatChanged.new(workspace_id, 10)
      assert :ok = Events.broadcast(event)

      assert_receive %ChatChanged{
        workspace_id: ^workspace_id,
        track_id: 10
      }
    end

    test "broadcasts CommandIssued to workspace topic", %{workspace_id: workspace_id} do
      event = CommandIssued.new(workspace_id, 1, 10, "cmd-123", :metasploit, "db_status")
      assert :ok = Events.broadcast(event)

      assert_receive %CommandIssued{
        workspace_id: ^workspace_id,
        command_id: "cmd-123",
        type: :metasploit,
        command: "db_status"
      }
    end

    test "broadcasts CommandResult to workspace topic", %{workspace_id: workspace_id} do
      issued = CommandIssued.new(workspace_id, 1, 10, "cmd-123", :metasploit, "db_status")
      event = CommandResult.finished(issued, "Connected to database")
      assert :ok = Events.broadcast(event)

      assert_receive %CommandResult{
        workspace_id: ^workspace_id,
        command_id: "cmd-123",
        status: :finished,
        output: "Connected to database"
      }
    end

    test "broadcasts ConsoleUpdated to workspace topic", %{workspace_id: workspace_id} do
      event = ConsoleUpdated.ready(workspace_id, 1, 10, "msf6 > ")
      assert :ok = Events.broadcast(event)

      assert_receive %ConsoleUpdated{
        workspace_id: ^workspace_id,
        status: :ready,
        prompt: "msf6 > "
      }
    end
  end

  describe "broadcast_local/1" do
    setup do
      workspace_id = unique_workspace_id()
      Events.subscribe_to_workspace(workspace_id)
      Events.subscribe_to_application()
      %{workspace_id: workspace_id}
    end

    test "broadcasts WorkspacesChanged locally" do
      event = WorkspacesChanged.new()
      assert :ok = Events.broadcast_local(event)
      assert_receive %WorkspacesChanged{}
    end

    test "broadcasts WorkspaceChanged locally", %{workspace_id: workspace_id} do
      event = WorkspaceChanged.new(workspace_id)
      assert :ok = Events.broadcast_local(event)
      assert_receive %WorkspaceChanged{workspace_id: ^workspace_id}
    end

    test "broadcasts ConsoleChanged locally", %{workspace_id: workspace_id} do
      event = ConsoleChanged.new(workspace_id, 10)
      assert :ok = Events.broadcast_local(event)
      assert_receive %ConsoleChanged{workspace_id: ^workspace_id}
    end

    test "broadcasts ChatChanged locally", %{workspace_id: workspace_id} do
      event = ChatChanged.new(workspace_id, 10)
      assert :ok = Events.broadcast_local(event)
      assert_receive %ChatChanged{workspace_id: ^workspace_id}
    end

    test "broadcasts CommandIssued locally", %{workspace_id: workspace_id} do
      event = CommandIssued.new(workspace_id, 1, 10, "cmd-123", :metasploit, "db_status")
      assert :ok = Events.broadcast_local(event)
      assert_receive %CommandIssued{workspace_id: ^workspace_id}
    end

    test "broadcasts CommandResult locally", %{workspace_id: workspace_id} do
      issued = CommandIssued.new(workspace_id, 1, 10, "cmd-123", :metasploit, "db_status")
      event = CommandResult.finished(issued, "Done")
      assert :ok = Events.broadcast_local(event)
      assert_receive %CommandResult{workspace_id: ^workspace_id}
    end

    test "broadcasts ConsoleUpdated locally", %{workspace_id: workspace_id} do
      event = ConsoleUpdated.offline(workspace_id, 1, 10)
      assert :ok = Events.broadcast_local(event)
      assert_receive %ConsoleUpdated{workspace_id: ^workspace_id}
    end
  end

  describe "event struct constructors" do
    test "WorkspacesChanged.new/0 creates event" do
      event = WorkspacesChanged.new()
      assert %DateTime{} = event.timestamp
    end

    test "WorkspaceChanged.new/1 creates event" do
      event = WorkspaceChanged.new(42)
      assert event.workspace_id == 42
      assert %DateTime{} = event.timestamp
    end

    test "ConsoleChanged.new/2 creates event" do
      event = ConsoleChanged.new(1, 10)

      assert event.workspace_id == 1
      assert event.track_id == 10
      assert %DateTime{} = event.timestamp
    end

    test "ChatChanged.new/2 creates event" do
      event = ChatChanged.new(1, 10)

      assert event.workspace_id == 1
      assert event.track_id == 10
      assert %DateTime{} = event.timestamp
    end

    test "CommandResult.running/2 creates running result with default prompt" do
      issued = CommandIssued.new(1, 2, 10, "cmd-123", :metasploit, "db_status")
      result = CommandResult.running(issued, "Scanning...")

      assert result.workspace_id == 1
      assert result.container_id == 2
      assert result.track_id == 10
      assert result.command_id == "cmd-123"
      assert result.type == :metasploit
      assert result.command == "db_status"
      assert result.output == "Scanning..."
      assert result.prompt == ""
      assert result.status == :running
      assert result.exit_code == nil
      assert result.error == nil
      assert %DateTime{} = result.timestamp
    end

    test "CommandResult.running/3 with prompt option" do
      issued = CommandIssued.new(1, 2, 10, "cmd-123", :metasploit, "use exploit/multi/handler")

      result =
        CommandResult.running(issued, "Loading module...",
          prompt: "msf6 exploit(multi/handler) > "
        )

      assert result.prompt == "msf6 exploit(multi/handler) > "
      assert result.status == :running
    end

    test "CommandResult.error/2 creates error result" do
      issued = CommandIssued.new(1, 2, 10, "cmd-123", :metasploit, "db_status")
      result = CommandResult.error(issued, :msgrpc_not_ready)

      assert result.workspace_id == 1
      assert result.container_id == 2
      assert result.track_id == 10
      assert result.command_id == "cmd-123"
      assert result.type == :metasploit
      assert result.command == "db_status"
      assert result.output == ""
      assert result.prompt == ""
      assert result.status == :error
      assert result.exit_code == nil
      assert result.error == :msgrpc_not_ready
    end

    test "CommandResult.error/2 with complex error" do
      issued = CommandIssued.new(1, 2, 10, "cmd-123", :bash, "ls")
      result = CommandResult.error(issued, {:console_create_failed, :timeout})

      assert result.status == :error
      assert result.error == {:console_create_failed, :timeout}
    end

    test "CommandResult.finished/2 with exit_code option" do
      issued = CommandIssued.new(1, 2, 10, "cmd-123", :bash, "ls -la")
      result = CommandResult.finished(issued, "file.txt\n", exit_code: 0)

      assert result.status == :finished
      assert result.output == "file.txt\n"
      assert result.exit_code == 0
      assert result.prompt == ""
    end

    test "CommandResult.finished/2 with prompt option" do
      issued = CommandIssued.new(1, 2, 10, "cmd-123", :metasploit, "db_status")
      result = CommandResult.finished(issued, "Connected", prompt: "msf6 > ")

      assert result.status == :finished
      assert result.prompt == "msf6 > "
      assert result.exit_code == nil
    end

    test "ConsoleUpdated.offline/3 creates offline event" do
      event = ConsoleUpdated.offline(1, 2, 10)

      assert event.workspace_id == 1
      assert event.container_id == 2
      assert event.track_id == 10
      assert event.status == :offline
      assert event.command_id == nil
      assert event.command == nil
      assert event.output == ""
      assert event.prompt == ""
    end

    test "ConsoleUpdated.starting/4 creates starting event" do
      event = ConsoleUpdated.starting(1, 2, 10, "=[ metasploit v6.x ]...")

      assert event.status == :starting
      assert event.output == "=[ metasploit v6.x ]..."
      assert event.prompt == ""
    end

    test "ConsoleUpdated.ready/4 creates ready event" do
      event = ConsoleUpdated.ready(1, 2, 10, "msf6 > ")

      assert event.status == :ready
      assert event.output == ""
      assert event.prompt == "msf6 > "
    end

    test "ConsoleUpdated.busy/6 creates busy event" do
      event = ConsoleUpdated.busy(1, 2, 10, "cmd-123", "db_status", "[*] Connected...")

      assert event.status == :busy
      assert event.command_id == "cmd-123"
      assert event.command == "db_status"
      assert event.output == "[*] Connected..."
      assert event.prompt == ""
    end

    test "CommandIssued.new/6 creates command issued event" do
      event = CommandIssued.new(1, 2, 10, "cmd-123", :bash, "whoami")

      assert event.workspace_id == 1
      assert event.container_id == 2
      assert event.track_id == 10
      assert event.command_id == "cmd-123"
      assert event.type == :bash
      assert event.command == "whoami"
      assert %DateTime{} = event.timestamp
    end
  end

  # Helper functions

  defp unique_workspace_id do
    System.unique_integer([:positive])
  end
end
