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

defmodule Msfailab.Tools.SkillsExecutorTest do
  use ExUnit.Case, async: true

  alias Msfailab.Skills.Skill
  alias Msfailab.Tools.SkillsExecutor

  describe "handles_tool?/1" do
    test "returns true for learn_skill" do
      assert SkillsExecutor.handles_tool?("learn_skill")
    end

    test "returns false for other tools" do
      refute SkillsExecutor.handles_tool?("execute_msfconsole_command")
      refute SkillsExecutor.handles_tool?("list_hosts")
      refute SkillsExecutor.handles_tool?("unknown")
    end
  end

  describe "execute/3" do
    setup do
      skill = %Skill{
        name: "test_skill",
        description: "A test skill for testing",
        filename: "test_skill.md",
        body: "# Test Skill\n\nThis is the skill body content."
      }

      start_supervised!({Msfailab.Skills.Registry, skills: [skill]})
      :ok
    end

    test "returns {:ok, body} for valid skill name" do
      args = %{"skill_name" => "test_skill"}
      context = %{}

      assert {:ok, result} = SkillsExecutor.execute("learn_skill", args, context)
      assert result =~ "# Test Skill"
      assert result =~ "This is the skill body content."
    end

    test "returns error for unknown skill name" do
      args = %{"skill_name" => "nonexistent_skill"}
      context = %{}

      assert {:error, {:skill_not_found, message}} =
               SkillsExecutor.execute("learn_skill", args, context)

      assert message =~ "not found" or message =~ "nonexistent_skill"
    end

    test "returns error when skill_name not provided" do
      args = %{}
      context = %{}

      assert {:error, {:missing_parameter, message}} =
               SkillsExecutor.execute("learn_skill", args, context)

      assert message =~ "skill_name"
    end
  end
end
