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
  alias Msfailab.Events.CommandIssued
  alias Msfailab.Events.CommandResult
  alias Msfailab.Events.ConsoleUpdated
  alias Msfailab.Events.ContainerCreated
  alias Msfailab.Events.ContainerUpdated
  alias Msfailab.Events.TrackCreated
  alias Msfailab.Events.TrackStateUpdated
  alias Msfailab.Events.TrackUpdated

  describe "workspace_topic/1" do
    test "generates topic string from workspace id" do
      assert Events.workspace_topic(1) == "workspace:1"
      assert Events.workspace_topic(42) == "workspace:42"
      assert Events.workspace_topic(999_999) == "workspace:999999"
    end
  end

  describe "subscribe_to_workspace/1" do
    test "subscribes current process to workspace topic" do
      workspace_id = unique_workspace_id()
      assert :ok = Events.subscribe_to_workspace(workspace_id)

      # Verify subscription by broadcasting and receiving
      event = container_created_event(workspace_id)
      Events.broadcast(event)

      assert_receive %ContainerCreated{workspace_id: ^workspace_id}
    end
  end

  describe "unsubscribe_from_workspace/1" do
    test "unsubscribes current process from workspace topic" do
      workspace_id = unique_workspace_id()
      Events.subscribe_to_workspace(workspace_id)
      assert :ok = Events.unsubscribe_from_workspace(workspace_id)

      # Verify unsubscription by broadcasting and NOT receiving
      event = container_created_event(workspace_id)
      Events.broadcast(event)

      refute_receive %ContainerCreated{}, 50
    end
  end

  describe "broadcast/1" do
    setup do
      workspace_id = unique_workspace_id()
      Events.subscribe_to_workspace(workspace_id)
      %{workspace_id: workspace_id}
    end

    test "broadcasts ContainerCreated to workspace topic", %{workspace_id: workspace_id} do
      event = container_created_event(workspace_id)
      assert :ok = Events.broadcast(event)

      assert_receive %ContainerCreated{
        workspace_id: ^workspace_id,
        container_id: 1,
        slug: "test-container"
      }
    end

    test "broadcasts ContainerUpdated to workspace topic", %{workspace_id: workspace_id} do
      event = container_updated_event(workspace_id)
      assert :ok = Events.broadcast(event)

      assert_receive %ContainerUpdated{
        workspace_id: ^workspace_id,
        status: :running
      }
    end

    test "broadcasts TrackCreated to workspace topic", %{workspace_id: workspace_id} do
      event = track_created_event(workspace_id)
      assert :ok = Events.broadcast(event)

      assert_receive %TrackCreated{
        workspace_id: ^workspace_id,
        track_id: 10,
        slug: "test-track"
      }
    end

    test "broadcasts TrackUpdated to workspace topic", %{workspace_id: workspace_id} do
      event = track_updated_event(workspace_id)
      assert :ok = Events.broadcast(event)

      assert_receive %TrackUpdated{
        workspace_id: ^workspace_id,
        track_id: 10
      }
    end

    test "broadcasts TrackStateUpdated to workspace topic", %{workspace_id: workspace_id} do
      event = TrackStateUpdated.new(workspace_id, 10)
      assert :ok = Events.broadcast(event)

      assert_receive %TrackStateUpdated{
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
      %{workspace_id: workspace_id}
    end

    test "broadcasts ContainerCreated locally", %{workspace_id: workspace_id} do
      event = container_created_event(workspace_id)
      assert :ok = Events.broadcast_local(event)
      assert_receive %ContainerCreated{workspace_id: ^workspace_id}
    end

    test "broadcasts ContainerUpdated locally", %{workspace_id: workspace_id} do
      event = container_updated_event(workspace_id)
      assert :ok = Events.broadcast_local(event)
      assert_receive %ContainerUpdated{workspace_id: ^workspace_id}
    end

    test "broadcasts TrackCreated locally", %{workspace_id: workspace_id} do
      event = track_created_event(workspace_id)
      assert :ok = Events.broadcast_local(event)
      assert_receive %TrackCreated{workspace_id: ^workspace_id}
    end

    test "broadcasts TrackUpdated locally", %{workspace_id: workspace_id} do
      event = track_updated_event(workspace_id)
      assert :ok = Events.broadcast_local(event)
      assert_receive %TrackUpdated{workspace_id: ^workspace_id}
    end

    test "broadcasts TrackStateUpdated locally", %{workspace_id: workspace_id} do
      event = TrackStateUpdated.new(workspace_id, 10)
      assert :ok = Events.broadcast_local(event)
      assert_receive %TrackStateUpdated{workspace_id: ^workspace_id}
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

    test "TrackStateUpdated.new/2 creates state updated event" do
      event = TrackStateUpdated.new(1, 10)

      assert event.workspace_id == 1
      assert event.track_id == 10
      assert %DateTime{} = event.timestamp
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

  defp container_created_event(workspace_id) do
    %ContainerCreated{
      workspace_id: workspace_id,
      container_id: 1,
      slug: "test-container",
      name: "Test Container",
      docker_image: "metasploitframework/metasploit-framework",
      timestamp: DateTime.utc_now()
    }
  end

  defp container_updated_event(workspace_id) do
    %ContainerUpdated{
      workspace_id: workspace_id,
      container_id: 1,
      slug: "test-container",
      name: "Test Container",
      docker_image: "metasploitframework/metasploit-framework",
      status: :running,
      docker_container_id: "abc123",
      timestamp: DateTime.utc_now()
    }
  end

  defp track_created_event(workspace_id) do
    %TrackCreated{
      workspace_id: workspace_id,
      container_id: 1,
      track_id: 10,
      slug: "test-track",
      name: "Test Track",
      timestamp: DateTime.utc_now()
    }
  end

  defp track_updated_event(workspace_id) do
    %TrackUpdated{
      workspace_id: workspace_id,
      container_id: 1,
      track_id: 10,
      slug: "test-track",
      name: "Test Track",
      archived_at: nil,
      timestamp: DateTime.utc_now()
    }
  end
end
