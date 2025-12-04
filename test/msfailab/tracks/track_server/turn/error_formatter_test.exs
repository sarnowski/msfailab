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

defmodule Msfailab.Tracks.TrackServer.Turn.ErrorFormatterTest do
  use ExUnit.Case, async: true

  alias Msfailab.Tracks.TrackServer.Turn.ErrorFormatter

  describe "format_msf_data_error/1" do
    test "formats workspace_not_found error" do
      assert ErrorFormatter.format_msf_data_error(:workspace_not_found) == "Workspace not found"
    end

    test "formats host_not_found error" do
      assert ErrorFormatter.format_msf_data_error(:host_not_found) == "Host not found"
    end

    test "formats loot_not_found error" do
      assert ErrorFormatter.format_msf_data_error(:loot_not_found) == "Loot not found"
    end

    test "formats unknown_tool error" do
      assert ErrorFormatter.format_msf_data_error({:unknown_tool, "list_something"}) ==
               "Unknown tool: list_something"
    end

    test "formats validation_error with details" do
      errors = [name: {"is required", [validation: :required]}]

      assert ErrorFormatter.format_msf_data_error({:validation_error, errors}) =~
               "Validation error:"
    end

    test "formats unknown errors with inspect" do
      assert ErrorFormatter.format_msf_data_error(:some_unknown_error) == ":some_unknown_error"
      assert ErrorFormatter.format_msf_data_error({:db, :timeout}) == "{:db, :timeout}"
    end
  end

  describe "format_memory_error/1" do
    test "passes through binary errors unchanged" do
      assert ErrorFormatter.format_memory_error("Custom error message") == "Custom error message"
    end

    test "formats track_not_found error" do
      assert ErrorFormatter.format_memory_error(:track_not_found) == "Track not found"
    end

    test "formats unknown_tool error" do
      assert ErrorFormatter.format_memory_error({:unknown_tool, "add_something"}) ==
               "Unknown memory tool: add_something"
    end

    test "formats validation_error with details" do
      errors = [content: {"is required", [validation: :required]}]

      assert ErrorFormatter.format_memory_error({:validation_error, errors}) =~
               "Validation error:"
    end

    test "formats unknown errors with inspect" do
      assert ErrorFormatter.format_memory_error(:some_error) == ":some_error"
      assert ErrorFormatter.format_memory_error({:timeout, 5000}) == "{:timeout, 5000}"
    end
  end

  describe "format_tool_error/1" do
    test "formats any error with inspect" do
      assert ErrorFormatter.format_tool_error(:timeout) == ":timeout"
      assert ErrorFormatter.format_tool_error({:error, "failed"}) == "{:error, \"failed\"}"
      assert ErrorFormatter.format_tool_error(:some_error) == ":some_error"
    end
  end

  describe "format/1" do
    test "extracts message from {:type, message} tuple" do
      assert ErrorFormatter.format({:missing_parameter, "Missing required parameter: command"}) ==
               "Missing required parameter: command"

      assert ErrorFormatter.format({:not_found, "Skill not found: debugging"}) ==
               "Skill not found: debugging"

      assert ErrorFormatter.format({:workspace_not_found, "Workspace not found"}) ==
               "Workspace not found"
    end

    test "passes through binary errors unchanged" do
      assert ErrorFormatter.format("Custom error message") == "Custom error message"
    end

    test "formats unknown errors with inspect" do
      assert ErrorFormatter.format(:some_atom) == ":some_atom"
      assert ErrorFormatter.format({:complex, :tuple, 123}) == "{:complex, :tuple, 123}"
    end
  end
end
