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

defmodule Msfailab.Tools.SkillsExecutor do
  @moduledoc """
  Executor for skill-related tools.

  Handles the `learn_skill` tool which allows the AI agent to retrieve
  skill documents from the skills registry.
  """

  @behaviour Msfailab.Tools.Executor

  alias Msfailab.Skills

  @impl true
  def handles_tool?("learn_skill"), do: true
  def handles_tool?(_), do: false

  @impl true
  def execute("learn_skill", arguments, _context) do
    case Map.get(arguments, "skill_name") do
      nil ->
        {:error, {:missing_parameter, "Missing required parameter: skill_name"}}

      skill_name ->
        case Skills.get_skill(skill_name) do
          {:ok, skill} ->
            {:ok, skill.body}

          {:error, :not_found} ->
            {:error, {:skill_not_found, "Skill not found: #{skill_name}"}}
        end
    end
  end
end
