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

defmodule Msfailab.Workspaces.WorkspaceServer do
  @moduledoc """
  GenServer that monitors MSF database changes for a workspace.

  Each workspace has one WorkspaceServer that:
  1. Subscribes to workspace events (CommandResult, tool executions)
  2. Caches asset counts from MsfData
  3. Queries for new counts after commands complete
  4. Broadcasts DatabaseUpdated events when counts change

  ## Architecture

  ```
  WorkspaceServer (one per workspace)
  ├── Subscribes to workspace:<id> topic
  ├── Caches asset counts
  ├── Listens for CommandResult (status: :finished)
  └── Broadcasts DatabaseUpdated when counts change
  ```

  ## State

  - `workspace_id` - Database ID of the workspace
  - `workspace_slug` - Workspace name/slug for MsfData queries
  - `counts` - Cached asset counts from MsfData.count_assets/1

  ## Triggering Count Refresh

  The server refreshes counts when it receives:
  - CommandResult with status: :finished (console command completed)
  - Tool execution completed events (future)

  To avoid excessive refreshes, commands that complete within a short
  interval are debounced.
  """

  use GenServer, restart: :transient

  require Logger

  alias Msfailab.Events
  alias Msfailab.Events.CommandResult
  alias Msfailab.Events.DatabaseUpdated
  alias Msfailab.MsfData

  @debounce_ms 500

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Starts a WorkspaceServer process linked to the calling process.

  ## Options

  - `:workspace_id` - Required. The database ID of the workspace.
  - `:workspace_slug` - Required. The workspace name/slug.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    workspace_id = Keyword.fetch!(opts, :workspace_id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(workspace_id))
  end

  @doc """
  Returns the via tuple for Registry lookup by workspace_id.
  """
  @spec via_tuple(integer()) :: {:via, Registry, {module(), integer()}}
  def via_tuple(workspace_id) do
    {:via, Registry, {Msfailab.Workspaces.Registry, workspace_id}}
  end

  @doc """
  Looks up the pid of a WorkspaceServer GenServer by workspace_id.

  Returns the pid if found, nil otherwise.
  """
  @spec whereis(integer()) :: pid() | nil
  def whereis(workspace_id) do
    case Registry.lookup(Msfailab.Workspaces.Registry, workspace_id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @doc """
  Gets the current asset counts for a workspace.

  Returns the cached counts without querying the database.
  """
  @spec get_counts(integer()) :: MsfData.asset_counts()
  def get_counts(workspace_id) do
    GenServer.call(via_tuple(workspace_id), :get_counts)
  end

  @doc """
  Forces a refresh of asset counts.

  Used for testing or when counts need to be recalculated manually.
  """
  @spec refresh_counts(integer()) :: :ok
  def refresh_counts(workspace_id) do
    GenServer.cast(via_tuple(workspace_id), :refresh_counts)
  end

  # ===========================================================================
  # GenServer Callbacks
  # ===========================================================================

  @impl true
  def init(opts) do
    workspace_id = Keyword.fetch!(opts, :workspace_id)
    workspace_slug = Keyword.fetch!(opts, :workspace_slug)

    Logger.metadata(workspace_id: workspace_id)
    Logger.info("WorkspaceServer starting for workspace #{workspace_slug}")

    # Subscribe to workspace events to receive CommandResult
    Events.subscribe_to_workspace(workspace_id)

    # Get initial asset counts
    counts = fetch_counts(workspace_slug)

    state = %{
      workspace_id: workspace_id,
      workspace_slug: workspace_slug,
      counts: counts,
      refresh_timer: nil
    }

    Logger.info(
      "WorkspaceServer initialized: #{counts.total} assets (#{counts.hosts} hosts, #{counts.services} services)"
    )

    {:ok, state}
  end

  @impl true
  def handle_call(:get_counts, _from, state) do
    {:reply, state.counts, state}
  end

  @impl true
  def handle_cast(:refresh_counts, state) do
    new_state = do_refresh_counts(state)
    {:noreply, new_state}
  end

  # CommandResult with :finished status triggers a count refresh
  @impl true
  def handle_info(
        %CommandResult{workspace_id: workspace_id, status: :finished},
        %{workspace_id: workspace_id} = state
      ) do
    # Debounce multiple rapid commands
    new_state = schedule_refresh(state)
    {:noreply, new_state}
  end

  # Ignore other CommandResult statuses and events for other workspaces
  def handle_info(%CommandResult{}, state), do: {:noreply, state}

  # Debounce timer fired - perform the refresh
  def handle_info(:do_refresh, state) do
    new_state = %{do_refresh_counts(state) | refresh_timer: nil}
    {:noreply, new_state}
  end

  # Ignore other events
  def handle_info(_event, state), do: {:noreply, state}

  # ===========================================================================
  # Private Functions
  # ===========================================================================

  defp fetch_counts(workspace_slug) do
    case MsfData.count_assets(workspace_slug) do
      {:ok, counts} ->
        counts

      {:error, :workspace_not_found} ->
        Logger.warning("MSF workspace not found: #{workspace_slug}")
        empty_counts()
    end
  end

  defp empty_counts do
    %{
      hosts: 0,
      services: 0,
      vulns: 0,
      notes: 0,
      creds: 0,
      loots: 0,
      sessions: 0,
      total: 0
    }
  end

  defp schedule_refresh(%{refresh_timer: nil} = state) do
    timer = Process.send_after(self(), :do_refresh, @debounce_ms)
    %{state | refresh_timer: timer}
  end

  defp schedule_refresh(state) do
    # Timer already scheduled, don't reschedule
    state
  end

  defp do_refresh_counts(state) do
    new_counts = fetch_counts(state.workspace_slug)
    old_counts = state.counts

    changes = calculate_changes(old_counts, new_counts)

    if any_changes?(changes) do
      Logger.info("Database assets changed: #{inspect(changes)}, total: #{new_counts.total}")

      event = DatabaseUpdated.new(state.workspace_id, changes, new_counts)
      Events.broadcast(event)
    end

    %{state | counts: new_counts}
  end

  defp calculate_changes(old, new) do
    %{
      hosts: new.hosts - old.hosts,
      services: new.services - old.services,
      vulns: new.vulns - old.vulns,
      notes: new.notes - old.notes,
      creds: new.creds - old.creds,
      loots: new.loots - old.loots,
      sessions: new.sessions - old.sessions
    }
  end

  defp any_changes?(changes) do
    Enum.any?(changes, fn {_key, value} -> value != 0 end)
  end
end
