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

defmodule Msfailab.Skills do
  @moduledoc """
  Skills context for AI agent learning.

  Skills are markdown documents with YAML frontmatter that teach the AI agent
  specific capabilities. The agent can use the `learn_skill` tool to retrieve
  a skill's content.

  ## Skill File Format

  Skills are stored in `priv/prompts/skills/` as markdown files with frontmatter:

      ---
      name: skill_name
      description: A brief description of what this skill teaches
      ---
      # Skill Content

      The markdown body that teaches the skill...

  ## Usage

      # List all available skills
      skills = Skills.list_skills()

      # Get a specific skill by name
      {:ok, skill} = Skills.get_skill("skill_name")

      # Generate overview for injection into chat context
      overview = Skills.generate_overview()
  """

  alias Msfailab.Skills.Skill

  @doc """
  Parses a skill file content and returns a Skill struct.

  ## Parameters

  - `filename` - The original filename
  - `content` - The file content including frontmatter

  ## Returns

  - `{:ok, skill}` - Successfully parsed skill
  - `{:error, :missing_frontmatter}` - No YAML frontmatter found
  - `{:error, :missing_name}` - Frontmatter lacks `name` field
  - `{:error, :missing_description}` - Frontmatter lacks `description` field
  """
  @spec parse_file(String.t(), String.t()) ::
          {:ok, Skill.t()} | {:error, :missing_frontmatter | :missing_name | :missing_description}
  def parse_file(filename, content) do
    with {:ok, frontmatter, body} <- extract_frontmatter(content),
         {:ok, name} <- extract_field(frontmatter, "name", :missing_name),
         {:ok, description} <- extract_field(frontmatter, "description", :missing_description) do
      {:ok,
       %Skill{
         name: name,
         description: description,
         filename: filename,
         body: String.trim(body)
       }}
    end
  end

  # Extracts YAML frontmatter delimited by --- markers
  defp extract_frontmatter(content) do
    # Match content that starts with --- and has another --- to close
    case Regex.run(~r/\A---\s*\n(.*?)\n---\s*\n?(.*)\z/s, content) do
      [_, frontmatter, body] -> {:ok, frontmatter, body}
      nil -> {:error, :missing_frontmatter}
    end
  end

  # Extracts a field value from YAML-style frontmatter
  # Handles both single-line and multi-line (indented continuation) values
  defp extract_field(frontmatter, field_name, error_atom) do
    # Match field: value (possibly with continuation lines that start with whitespace)
    pattern = ~r/^#{field_name}:\s*(.+?)(?=\n[^\s]|\z)/ms

    case Regex.run(pattern, frontmatter) do
      [_, value] -> {:ok, String.trim(value)}
      nil -> {:error, error_atom}
    end
  end

  @doc """
  Lists all registered skills.

  Returns a list of all skills that were loaded from `priv/prompts/skills/`.
  """
  @spec list_skills() :: [Skill.t()]
  def list_skills do
    Msfailab.Skills.Registry.list_skills()
  end

  @doc """
  Gets a skill by name.

  ## Parameters

  - `name` - The skill name (from frontmatter)

  ## Returns

  - `{:ok, skill}` - Skill found
  - `{:error, :not_found}` - No skill with that name
  """
  @spec get_skill(String.t()) :: {:ok, Skill.t()} | {:error, :not_found}
  def get_skill(name) do
    Msfailab.Skills.Registry.get_skill(name)
  end

  @doc """
  Generates a compact list of all available skills.

  Returns a markdown list suitable for injecting into the system prompt's
  `{{SKILLS_LIBRARY}}` placeholder.

  ## Example Output

      - **metasploit_usecase_pentest** — Penetration testing methodology
      - **pentest_reporting** — Structure and write professional reports

  """
  @spec generate_overview() :: String.t()
  def generate_overview do
    skills = list_skills()

    if skills == [] do
      "*No skills available*"
    else
      skills
      |> Enum.sort_by(& &1.name)
      |> Enum.map_join("\n", fn skill ->
        "- **#{skill.name}** — #{skill.description}"
      end)
    end
  end
end
