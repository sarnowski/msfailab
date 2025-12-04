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

defmodule MsfailabWeb.WorkspaceComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Msfailab.Tracks.ChatEntry
  alias MsfailabWeb.WorkspaceComponents

  # Helper to create a mock chat entry for tool testing
  defp mock_tool_entry(attrs) do
    base = %{
      id: "test-entry-1",
      position: 1,
      entry_type: :tool_invocation,
      streaming: false,
      timestamp: DateTime.utc_now(),
      tool_call_id: "call_123",
      tool_name: "msf_command",
      tool_arguments: %{"command" => "show options"},
      tool_status: :success,
      console_prompt: "msf6 exploit(test) > ",
      result_content: "Module options:"
    }

    struct(ChatEntry, Map.merge(base, attrs))
  end

  describe "msf_data_tool?/1" do
    test "returns true for list_hosts" do
      assert WorkspaceComponents.msf_data_tool?("list_hosts") == true
    end

    test "returns true for list_services" do
      assert WorkspaceComponents.msf_data_tool?("list_services") == true
    end

    test "returns true for list_vulns" do
      assert WorkspaceComponents.msf_data_tool?("list_vulns") == true
    end

    test "returns true for list_creds" do
      assert WorkspaceComponents.msf_data_tool?("list_creds") == true
    end

    test "returns true for list_loots" do
      assert WorkspaceComponents.msf_data_tool?("list_loots") == true
    end

    test "returns true for list_notes" do
      assert WorkspaceComponents.msf_data_tool?("list_notes") == true
    end

    test "returns true for list_sessions" do
      assert WorkspaceComponents.msf_data_tool?("list_sessions") == true
    end

    test "returns true for retrieve_loot" do
      assert WorkspaceComponents.msf_data_tool?("retrieve_loot") == true
    end

    test "returns true for create_note" do
      assert WorkspaceComponents.msf_data_tool?("create_note") == true
    end

    test "returns false for msf_command" do
      assert WorkspaceComponents.msf_data_tool?("msf_command") == false
    end

    test "returns false for bash_command" do
      assert WorkspaceComponents.msf_data_tool?("bash_command") == false
    end

    test "returns false for unknown tool" do
      assert WorkspaceComponents.msf_data_tool?("unknown_tool") == false
    end
  end

  describe "msf_data_active_label/1" do
    test "returns 'Listing hosts...' for list_hosts" do
      assert WorkspaceComponents.msf_data_active_label("list_hosts") == "Listing hosts..."
    end

    test "returns 'Listing services...' for list_services" do
      assert WorkspaceComponents.msf_data_active_label("list_services") == "Listing services..."
    end

    test "returns 'Listing vulnerabilities...' for list_vulns" do
      assert WorkspaceComponents.msf_data_active_label("list_vulns") ==
               "Listing vulnerabilities..."
    end

    test "returns 'Listing credentials...' for list_creds" do
      assert WorkspaceComponents.msf_data_active_label("list_creds") == "Listing credentials..."
    end

    test "returns 'Listing loot...' for list_loots" do
      assert WorkspaceComponents.msf_data_active_label("list_loots") == "Listing loot..."
    end

    test "returns 'Listing notes...' for list_notes" do
      assert WorkspaceComponents.msf_data_active_label("list_notes") == "Listing notes..."
    end

    test "returns 'Listing sessions...' for list_sessions" do
      assert WorkspaceComponents.msf_data_active_label("list_sessions") == "Listing sessions..."
    end

    test "returns 'Retrieving loot...' for retrieve_loot" do
      assert WorkspaceComponents.msf_data_active_label("retrieve_loot") == "Retrieving loot..."
    end

    test "returns 'Creating note...' for create_note" do
      assert WorkspaceComponents.msf_data_active_label("create_note") == "Creating note..."
    end
  end

  describe "render_msf_command_approval_subject/1" do
    test "renders console prompt and command" do
      entry =
        mock_tool_entry(%{
          console_prompt: "msf6 > ",
          tool_arguments: %{"command" => "search apache"}
        })

      html =
        render_component(&WorkspaceComponents.render_msf_command_approval_subject/1, entry: entry)

      # Console renders styled prompt - "msf" is underlined
      assert html =~ "<u>msf</u>6"
      assert html =~ "search apache"
      assert html =~ "bg-neutral"
    end

    test "uses default prompt when console_prompt is nil" do
      entry = mock_tool_entry(%{console_prompt: nil, tool_arguments: %{"command" => "help"}})

      html =
        render_component(&WorkspaceComponents.render_msf_command_approval_subject/1, entry: entry)

      # Console renders styled prompt - "msf" is underlined
      assert html =~ "<u>msf</u>6"
      assert html =~ "help"
    end
  end

  describe "render_msf_command_collapsed/1" do
    test "renders collapsed terminal view with command" do
      entry =
        mock_tool_entry(%{tool_status: :success, tool_arguments: %{"command" => "db_status"}})

      html = render_component(&WorkspaceComponents.render_msf_command_collapsed/1, entry: entry)

      assert html =~ "db_status"
      assert html =~ "cursor-pointer"
      assert html =~ "truncate"
    end

    test "renders with executing status shows spinner icon" do
      entry = mock_tool_entry(%{tool_status: :executing})

      html = render_component(&WorkspaceComponents.render_msf_command_collapsed/1, entry: entry)

      assert html =~ "loading"
    end

    test "renders with success status shows check icon" do
      entry = mock_tool_entry(%{tool_status: :success})

      html = render_component(&WorkspaceComponents.render_msf_command_collapsed/1, entry: entry)

      assert html =~ "hero-check"
    end

    test "renders with error status shows x-mark icon" do
      entry = mock_tool_entry(%{tool_status: :error})

      html = render_component(&WorkspaceComponents.render_msf_command_collapsed/1, entry: entry)

      assert html =~ "hero-x-mark"
    end
  end

  describe "render_msf_command_expanded/1" do
    test "renders expanded terminal box with output" do
      entry =
        mock_tool_entry(%{
          tool_status: :success,
          tool_arguments: %{"command" => "show exploits"},
          result_content: "Exploit modules:\n  exploit/multi/handler"
        })

      html = render_component(&WorkspaceComponents.render_msf_command_expanded/1, entry: entry)

      assert html =~ "msfconsole"
      assert html =~ "show exploits"
      assert html =~ "Exploit modules:"
    end

    test "renders cursor when executing" do
      entry = mock_tool_entry(%{tool_status: :executing, result_content: ""})

      html = render_component(&WorkspaceComponents.render_msf_command_expanded/1, entry: entry)

      assert html =~ "terminal-cursor"
    end

    test "hides output section when result_content is empty and not executing" do
      entry = mock_tool_entry(%{tool_status: :success, result_content: ""})

      html = render_component(&WorkspaceComponents.render_msf_command_expanded/1, entry: entry)

      # Should still have the command but no extra output div
      assert html =~ "show options"
      refute html =~ "terminal-cursor"
    end
  end

  describe "render_bash_command_approval_subject/1" do
    test "renders bash prompt and command" do
      entry =
        mock_tool_entry(%{tool_name: "bash_command", tool_arguments: %{"command" => "ls -la"}})

      html =
        render_component(&WorkspaceComponents.render_bash_command_approval_subject/1,
          entry: entry
        )

      assert html =~ "ls -la"
      assert html =~ "bg-neutral"
    end
  end

  describe "render_bash_command_collapsed/1" do
    test "renders collapsed terminal view with command" do
      entry =
        mock_tool_entry(%{
          tool_name: "bash_command",
          tool_status: :success,
          tool_arguments: %{"command" => "pwd"}
        })

      html = render_component(&WorkspaceComponents.render_bash_command_collapsed/1, entry: entry)

      assert html =~ "pwd"
      assert html =~ "cursor-pointer"
    end

    test "renders status-appropriate icon" do
      entry = mock_tool_entry(%{tool_name: "bash_command", tool_status: :error})

      html = render_component(&WorkspaceComponents.render_bash_command_collapsed/1, entry: entry)

      assert html =~ "hero-x-mark"
    end
  end

  describe "render_bash_command_expanded/1" do
    test "renders expanded terminal box with output" do
      entry =
        mock_tool_entry(%{
          tool_name: "bash_command",
          tool_status: :success,
          tool_arguments: %{"command" => "echo hello"},
          result_content: "hello"
        })

      html = render_component(&WorkspaceComponents.render_bash_command_expanded/1, entry: entry)

      assert html =~ "bash"
      assert html =~ "echo hello"
      assert html =~ "hello"
    end

    test "renders cursor when executing" do
      entry =
        mock_tool_entry(%{tool_name: "bash_command", tool_status: :executing, result_content: ""})

      html = render_component(&WorkspaceComponents.render_bash_command_expanded/1, entry: entry)

      assert html =~ "terminal-cursor"
    end
  end
end
