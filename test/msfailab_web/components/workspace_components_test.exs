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

  alias MsfailabWeb.WorkspaceComponents

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
end
