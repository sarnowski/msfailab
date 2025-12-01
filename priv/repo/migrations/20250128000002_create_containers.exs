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

defmodule Msfailab.Repo.Migrations.CreateContainers do
  use Ecto.Migration

  def change do
    create table(:msfailab_containers) do
      add :slug, :string, null: false
      add :name, :string, null: false
      add :docker_image, :string, null: false
      add :workspace_id, references(:msfailab_workspaces, on_delete: :restrict), null: false

      timestamps()
    end

    create index(:msfailab_containers, [:workspace_id])
    create unique_index(:msfailab_containers, [:workspace_id, :slug])
  end
end
