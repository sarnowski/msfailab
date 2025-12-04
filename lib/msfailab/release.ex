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

# coveralls-ignore-start
# Reason: Production release tooling, thin wrapper around Ecto.Migrator
defmodule Msfailab.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.

  Provides database migration functions that can be called from release scripts
  in production environments where Mix is not available.

  ## Usage

  From the release console:

      Msfailab.Release.migrate()

  Or via the bundled migrate script:

      bin/migrate
  """
  @app :msfailab

  @doc """
  Runs all pending database migrations.

  Loads the application configuration, starts SSL (required by many cloud
  databases), and runs all migrations for configured repositories.
  """
  @spec migrate() :: :ok
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    :ok
  end

  @doc """
  Rolls back migrations to the specified version.

  ## Parameters

    * `repo` - The Ecto repository module to rollback
    * `version` - The migration version to rollback to
  """
  @spec rollback(module(), integer()) :: {:ok, term(), term()}
  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end

# coveralls-ignore-stop
