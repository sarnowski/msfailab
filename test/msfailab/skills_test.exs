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

defmodule Msfailab.SkillsTest do
  use ExUnit.Case, async: true

  alias Msfailab.Skills
  alias Msfailab.Skills.Skill

  describe "Skill struct" do
    test "has required fields: name, description, filename, body" do
      skill = %Skill{
        name: "test_skill",
        description: "A test skill",
        filename: "test_skill.md",
        body: "# Test\n\nBody content"
      }

      assert skill.name == "test_skill"
      assert skill.description == "A test skill"
      assert skill.filename == "test_skill.md"
      assert skill.body == "# Test\n\nBody content"
    end

    test "enforces required keys" do
      assert_raise ArgumentError, fn ->
        struct!(Skill, %{name: "test"})
      end
    end
  end

  describe "parse_file/2" do
    test "extracts frontmatter name from markdown content" do
      content = """
      ---
      name: my_skill
      description: A skill description
      ---
      # Body Content
      """

      {:ok, skill} = Skills.parse_file("my_skill.md", content)
      assert skill.name == "my_skill"
    end

    test "extracts frontmatter description from markdown content" do
      content = """
      ---
      name: my_skill
      description: A skill description
      ---
      # Body Content
      """

      {:ok, skill} = Skills.parse_file("my_skill.md", content)
      assert skill.description == "A skill description"
    end

    test "extracts body content after frontmatter" do
      content = """
      ---
      name: my_skill
      description: A skill description
      ---
      # Body Content

      This is the body.
      """

      {:ok, skill} = Skills.parse_file("my_skill.md", content)
      assert skill.body =~ "# Body Content"
      assert skill.body =~ "This is the body."
    end

    test "stores filename in skill" do
      content = """
      ---
      name: my_skill
      description: A skill description
      ---
      Body
      """

      {:ok, skill} = Skills.parse_file("custom_name.md", content)
      assert skill.filename == "custom_name.md"
    end

    test "returns error for files without frontmatter" do
      content = """
      # No Frontmatter

      Just regular content.
      """

      assert {:error, :missing_frontmatter} = Skills.parse_file("test.md", content)
    end

    test "returns error when name is missing from frontmatter" do
      content = """
      ---
      description: A description only
      ---
      Body
      """

      assert {:error, :missing_name} = Skills.parse_file("test.md", content)
    end

    test "returns error when description is missing from frontmatter" do
      content = """
      ---
      name: my_skill
      ---
      Body
      """

      assert {:error, :missing_description} = Skills.parse_file("test.md", content)
    end

    test "handles multiline descriptions" do
      content = """
      ---
      name: my_skill
      description: A very long description
        that spans multiple lines
      ---
      Body
      """

      {:ok, skill} = Skills.parse_file("test.md", content)
      assert skill.description =~ "A very long description"
    end
  end

  describe "list_skills/0" do
    test "returns list of skills from registry" do
      skills = [
        %Skill{name: "skill1", description: "Desc 1", filename: "skill1.md", body: "Body 1"},
        %Skill{name: "skill2", description: "Desc 2", filename: "skill2.md", body: "Body 2"}
      ]

      start_supervised!({Msfailab.Skills.Registry, skills: skills})

      result = Skills.list_skills()

      assert length(result) == 2
      assert Enum.any?(result, &(&1.name == "skill1"))
      assert Enum.any?(result, &(&1.name == "skill2"))
    end

    test "returns empty list when no skills registered" do
      start_supervised!({Msfailab.Skills.Registry, skills: []})

      assert Skills.list_skills() == []
    end
  end

  describe "get_skill/1" do
    test "returns {:ok, skill} when skill name exists" do
      skill = %Skill{name: "test_skill", description: "Test", filename: "test.md", body: "Body"}
      start_supervised!({Msfailab.Skills.Registry, skills: [skill]})

      assert {:ok, found} = Skills.get_skill("test_skill")
      assert found.name == "test_skill"
      assert found.body == "Body"
    end

    test "returns {:error, :not_found} when skill name doesn't exist" do
      start_supervised!({Msfailab.Skills.Registry, skills: []})

      assert {:error, :not_found} = Skills.get_skill("nonexistent")
    end
  end

  describe "generate_overview/0" do
    test "returns markdown overview with skill table" do
      skills = [
        %Skill{name: "skill1", description: "First skill", filename: "skill1.md", body: "Body 1"},
        %Skill{name: "skill2", description: "Second skill", filename: "skill2.md", body: "Body 2"}
      ]

      start_supervised!({Msfailab.Skills.Registry, skills: skills})

      overview = Skills.generate_overview()

      # Should contain header
      assert overview =~ "## Skill Library"
      # Should contain table
      assert overview =~ "| Skill name | Description |"
      # Should contain skill entries
      assert overview =~ "skill1"
      assert overview =~ "First skill"
      assert overview =~ "skill2"
      assert overview =~ "Second skill"
      # Should contain instructions
      assert overview =~ "learn_skill"
    end

    test "returns empty overview when no skills" do
      start_supervised!({Msfailab.Skills.Registry, skills: []})

      overview = Skills.generate_overview()

      assert overview =~ "Skill Library"
      assert overview =~ "No skills available"
    end
  end
end
