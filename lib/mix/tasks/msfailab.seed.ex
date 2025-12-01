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

defmodule Mix.Tasks.Msfailab.Seed do
  @moduledoc """
  Runs database seeds with LLM and container subsystems disabled.

  This allows `mix setup` to complete without requiring LLM provider
  connections, which may not be available in CI or fresh installations.

  ## Usage

      mix msfailab.seed

  """
  use Mix.Task

  @shortdoc "Run database seeds without LLM initialization"

  @impl Mix.Task
  def run(_args) do
    # Disable subsystems that aren't needed for seeding
    Application.put_env(:msfailab, :start_llm, false)
    Application.put_env(:msfailab, :start_containers, false)

    # Start the application with reduced subsystems
    Mix.Task.run("app.start")

    # Run the seeds script
    Code.eval_file("priv/repo/seeds.exs")
  end
end
