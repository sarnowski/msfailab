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
      assert tool.approval_required == true
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

  describe "OpenAI strict mode compatibility" do
    test "tools with optional parameters must not use strict mode" do
      # OpenAI strict mode requires ALL properties to be in the required array.
      # Tools with optional parameters (properties not in required) must have strict: false.
      tools = Tools.list_tools()

      for tool <- tools do
        properties = tool.parameters["properties"] || %{}
        required = tool.parameters["required"] || []
        property_names = Map.keys(properties)
        has_optional_params = length(property_names) > length(required)

        if has_optional_params do
          assert tool.strict == false,
                 "Tool '#{tool.name}' has optional parameters but strict: true. " <>
                   "OpenAI strict mode requires all properties in 'required'. " <>
                   "Properties: #{inspect(property_names)}, Required: #{inspect(required)}"
        end
      end
    end

    test "tools with all required parameters can use strict mode" do
      # Tools where all properties are required can safely use strict: true
      tools = Tools.list_tools()

      for tool <- tools do
        properties = tool.parameters["properties"] || %{}
        required = tool.parameters["required"] || []
        property_names = MapSet.new(Map.keys(properties))
        required_set = MapSet.new(required)

        all_required = MapSet.equal?(property_names, required_set)

        if all_required and map_size(properties) > 0 do
          # These tools CAN use strict mode (msf_command, bash_command)
          # Just verify they have the expected strict setting
          assert is_boolean(tool.strict),
                 "Tool '#{tool.name}' has all parameters required, strict should be boolean"
        end
      end
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
        short_title: "Testing",
        description: "A test tool",
        parameters: %{"type" => "object", "properties" => %{}, "required" => []}
      }

      assert tool.strict == false
      assert tool.cacheable == true
      assert tool.approval_required == true
      assert tool.timeout == nil
      assert tool.mutex == nil
    end

    test "allows overriding defaults" do
      tool = %Tool{
        name: "test",
        short_title: "Testing",
        description: "A test tool",
        parameters: %{"type" => "object", "properties" => %{}, "required" => []},
        strict: true,
        cacheable: false,
        approval_required: false,
        timeout: 30_000
      }

      assert tool.strict == true
      assert tool.cacheable == false
      assert tool.approval_required == false
      assert tool.timeout == 30_000
    end

    test "allows setting mutex to an atom" do
      tool = %Tool{
        name: "test",
        short_title: "Testing",
        description: "A test tool",
        parameters: %{"type" => "object", "properties" => %{}, "required" => []},
        mutex: :test_mutex
      }

      assert tool.mutex == :test_mutex
    end
  end

  describe "mutex assignments" do
    test "msf_command has mutex :msf_console" do
      {:ok, tool} = Tools.get_tool("msf_command")
      assert tool.mutex == :msf_console
    end

    test "bash_command has mutex nil (true parallel)" do
      {:ok, tool} = Tools.get_tool("bash_command")
      assert tool.mutex == nil
    end

    test "memory tools have mutex :memory" do
      memory_tools = ["read_memory", "update_memory", "add_task", "update_task", "remove_task"]

      for name <- memory_tools do
        {:ok, tool} = Tools.get_tool(name)

        assert tool.mutex == :memory,
               "Expected #{name} to have mutex :memory, got #{inspect(tool.mutex)}"
      end
    end

    test "msf_data query tools have mutex nil (true parallel)" do
      msf_data_tools = [
        "list_hosts",
        "list_services",
        "list_vulns",
        "list_creds",
        "list_loots",
        "list_notes",
        "list_sessions",
        "retrieve_loot",
        "create_note"
      ]

      for name <- msf_data_tools do
        {:ok, tool} = Tools.get_tool(name)

        assert tool.mutex == nil,
               "Expected #{name} to have mutex nil, got #{inspect(tool.mutex)}"
      end
    end

    test "all tools have mutex field (atom or nil)" do
      tools = Tools.list_tools()

      for tool <- tools do
        assert is_nil(tool.mutex) or is_atom(tool.mutex),
               "Tool #{tool.name} has invalid mutex: #{inspect(tool.mutex)}"
      end
    end
  end
end
