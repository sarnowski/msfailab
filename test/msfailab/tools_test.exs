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

defmodule Msfailab.ToolsTest do
  use ExUnit.Case, async: true

  alias Msfailab.Tools
  alias Msfailab.Tools.Tool

  describe "list_tools/0" do
    test "returns a list of tool definitions" do
      tools = Tools.list_tools()

      assert is_list(tools)
      assert length(tools) > 0
      assert Enum.all?(tools, &match?(%Tool{}, &1))
    end

    test "includes msf_command tool" do
      tools = Tools.list_tools()
      names = Enum.map(tools, & &1.name)

      assert "msf_command" in names
    end

    test "all tools have required fields" do
      tools = Tools.list_tools()

      for tool <- tools do
        assert is_binary(tool.name)
        assert is_binary(tool.description)
        assert is_map(tool.parameters)
        assert is_boolean(tool.strict)
        assert is_boolean(tool.cacheable)
        assert is_boolean(tool.approval_required)
        assert is_nil(tool.timeout) or is_integer(tool.timeout)
      end
    end

    test "all tools have valid JSON Schema parameters" do
      tools = Tools.list_tools()

      for tool <- tools do
        assert tool.parameters["type"] == "object"
        assert is_map(tool.parameters["properties"])
        assert is_list(tool.parameters["required"])
      end
    end
  end

  describe "get_tool/1" do
    test "returns msf_command tool" do
      assert {:ok, tool} = Tools.get_tool("msf_command")
      assert tool.name == "msf_command"
      assert tool.strict == true
      assert tool.cacheable == true
      assert tool.approval_required == false
      assert tool.timeout == 60_000
    end

    test "returns error for nonexistent tool" do
      assert {:error, :not_found} = Tools.get_tool("nonexistent")
    end

    test "returns error for empty string" do
      assert {:error, :not_found} = Tools.get_tool("")
    end
  end

  describe "msf_command tool" do
    setup do
      {:ok, tool} = Tools.get_tool("msf_command")
      %{tool: tool}
    end

    test "has proper description", %{tool: tool} do
      assert tool.description =~ "Metasploit Framework console"
      assert tool.description =~ "security research"
    end

    test "requires command parameter", %{tool: tool} do
      assert "command" in tool.parameters["required"]
    end

    test "command parameter is a string", %{tool: tool} do
      command_schema = tool.parameters["properties"]["command"]
      assert command_schema["type"] == "string"
      assert is_binary(command_schema["description"])
    end
  end

  describe "Tool struct" do
    test "enforces required keys" do
      assert_raise ArgumentError, ~r/the following keys must also be given/, fn ->
        struct!(Tool, [])
      end
    end

    test "has correct defaults" do
      tool = %Tool{
        name: "test",
        description: "A test tool",
        parameters: %{"type" => "object", "properties" => %{}, "required" => []}
      }

      assert tool.strict == false
      assert tool.cacheable == true
      assert tool.approval_required == false
      assert tool.timeout == nil
    end

    test "allows overriding defaults" do
      tool = %Tool{
        name: "test",
        description: "A test tool",
        parameters: %{"type" => "object", "properties" => %{}, "required" => []},
        strict: true,
        cacheable: false,
        approval_required: true,
        timeout: 30_000
      }

      assert tool.strict == true
      assert tool.cacheable == false
      assert tool.approval_required == true
      assert tool.timeout == 30_000
    end
  end
end
