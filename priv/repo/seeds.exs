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

# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias Msfailab.Containers
alias Msfailab.Tracks
alias Msfailab.Workspaces

# Only seed development data in dev environment
if Mix.env() == :dev do
  # Get docker image from application config
  docker_image =
    Application.get_env(:msfailab, :docker_image, "metasploitframework/metasploit-framework")

  # Create "Development" workspace if it doesn't exist
  case Workspaces.get_workspace_by_slug("development") do
    nil ->
      {:ok, workspace} =
        Workspaces.create_workspace(%{
          slug: "development",
          name: "Development",
          description: "Development workspace for testing and experimentation"
        })

      # Create "Main" container within the workspace
      {:ok, container} =
        Containers.create_container(workspace, %{
          slug: "main",
          name: "Main",
          docker_image: docker_image
        })

      # Create "Testing" track within the container
      {:ok, _track} =
        Tracks.create_track(container, %{
          slug: "testing",
          name: "Testing",
          current_model: "qwen3:30b"
        })

      IO.puts("Created Development workspace with Main container and Testing track")

    _workspace ->
      IO.puts("Development workspace already exists, skipping seed")
  end
end
