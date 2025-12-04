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

defmodule Msfailab.Skills.Registry do
  @moduledoc """
  In-memory registry for skills.

  Stores all loaded skills and provides lookup operations. In production,
  skills are loaded from `priv/prompts/skills/` on application start.
  In tests, skills can be provided directly via the `:skills` option.

  ## Usage

      # Start with default skills directory
      {:ok, pid} = Registry.start_link([])

      # Start with custom skills (for testing)
      {:ok, pid} = Registry.start_link(skills: [%Skill{...}])

      # Query skills
      Registry.list_skills()
      Registry.get_skill("skill_name")
  """

  use GenServer

  alias Msfailab.Skills.Skill

  @type state :: %{skills: %{String.t() => Skill.t()}}

  # ============================================================================
  # Client API
  # ============================================================================

  @doc """
  Starts the skills registry.

  ## Options

  - `:skills` - List of skills to register (for testing). If not provided,
    skills are loaded from `priv/prompts/skills/`.
  - `:name` - Process name (defaults to `__MODULE__`)
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Returns all registered skills.
  """
  @spec list_skills(GenServer.server()) :: [Skill.t()]
  def list_skills(server \\ __MODULE__) do
    GenServer.call(server, :list_skills)
  end

  @doc """
  Gets a skill by name.
  """
  @spec get_skill(GenServer.server(), String.t()) :: {:ok, Skill.t()} | {:error, :not_found}
  def get_skill(server \\ __MODULE__, name) do
    GenServer.call(server, {:get_skill, name})
  end

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(opts) do
    skills =
      case Keyword.get(opts, :skills) do
        nil -> load_skills_from_directory()
        skills when is_list(skills) -> skills
      end

    # Build a map indexed by name for fast lookups
    skills_map =
      skills
      |> Enum.map(fn skill -> {skill.name, skill} end)
      |> Map.new()

    {:ok, %{skills: skills_map}}
  end

  @impl true
  def handle_call(:list_skills, _from, %{skills: skills} = state) do
    {:reply, Map.values(skills), state}
  end

  @impl true
  def handle_call({:get_skill, name}, _from, %{skills: skills} = state) do
    result =
      case Map.get(skills, name) do
        nil -> {:error, :not_found}
        skill -> {:ok, skill}
      end

    {:reply, result, state}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp load_skills_from_directory do
    skills_dir = Application.app_dir(:msfailab, "priv/prompts/skills")

    case File.ls(skills_dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".md"))
        |> Enum.flat_map(&load_skill_file(skills_dir, &1))

      {:error, _reason} ->
        []
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  # False positive: filename comes from File.ls/1 of a controlled directory,
  # not from user input. Directory traversal is not possible.
  defp load_skill_file(skills_dir, filename) do
    path = Path.join(skills_dir, filename)

    with {:ok, content} <- File.read(path),
         {:ok, skill} <- Msfailab.Skills.parse_file(filename, content) do
      [skill]
    else
      _error -> []
    end
  end
end
