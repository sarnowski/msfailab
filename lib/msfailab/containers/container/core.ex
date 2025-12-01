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

defmodule Msfailab.Containers.Container.Core do
  @moduledoc """
  Pure functions for Container GenServer business logic.

  This module contains all decision-making logic extracted from the Container
  GenServer, making it trivially testable without process setup.
  """

  @typedoc "Container status"
  @type container_status :: :offline | :starting | :running

  @typedoc "Console info tracked in Container state"
  @type console_info :: %{
          pid: pid() | nil,
          ref: reference() | nil,
          restart_attempts: non_neg_integer(),
          last_restart_at: DateTime.t() | nil
        }

  @typedoc "Running bash command info"
  @type bash_command_info :: %{
          pid: pid(),
          ref: reference(),
          track_id: integer(),
          command: map(),
          started_at: DateTime.t()
        }

  @doc """
  Calculates exponential backoff delay for retries.

  ## Parameters

  - `attempt` - The current attempt number (1-based)
  - `base_ms` - Base delay in milliseconds
  - `max_ms` - Maximum delay in milliseconds

  ## Examples

      iex> Core.calculate_backoff(1, 1000, 60000)
      1000

      iex> Core.calculate_backoff(3, 1000, 60000)
      4000

      iex> Core.calculate_backoff(10, 1000, 60000)
      60000
  """
  @spec calculate_backoff(non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          non_neg_integer()
  def calculate_backoff(attempt, base_ms, max_ms) do
    backoff = base_ms * round(:math.pow(2, attempt - 1))
    min(backoff, max_ms)
  end

  @doc """
  Finds a console entry by its monitor reference.

  Returns `{track_id, console_info}` if found, `nil` otherwise.
  """
  @spec find_console_by_ref(%{integer() => console_info()}, reference()) ::
          {integer(), console_info()} | nil
  def find_console_by_ref(consoles, ref) do
    Enum.find(consoles, fn {_track_id, info} -> info.ref == ref end)
  end

  @doc """
  Finds a bash command entry by its monitor reference.

  Returns `{command_id, bash_command_info}` if found, `nil` otherwise.
  """
  @spec find_bash_command_by_ref(%{String.t() => bash_command_info()}, reference()) ::
          {String.t(), bash_command_info()} | nil
  def find_bash_command_by_ref(bash_commands, ref) do
    Enum.find(bash_commands, fn {_cmd_id, info} -> info.ref == ref end)
  end

  @doc """
  Validates that a console can potentially receive commands.

  Returns `{:ok, pid}` if a Console process exists for the track,
  `{:error, reason}` otherwise. The caller should forward commands
  to the Console, which will return appropriate errors (`:starting`,
  `:busy`) based on its actual state.

  ## Error reasons

  - `:container_not_running` - Container status is not `:running`
  - `:console_not_registered` - Track ID is not in registered_tracks
  - `:console_offline` - No Console process exists for this track
  """
  @spec validate_console_for_command(map(), integer()) :: {:ok, pid()} | {:error, atom()}
  def validate_console_for_command(state, track_id) do
    cond do
      state.status != :running ->
        {:error, :container_not_running}

      not MapSet.member?(state.registered_tracks, track_id) ->
        {:error, :console_not_registered}

      true ->
        get_console_pid(state.consoles, track_id)
    end
  end

  @doc """
  Gets the Console process pid for a track if available.

  Returns `{:ok, pid}` if console process exists, `{:error, :console_offline}` otherwise.
  The caller should forward commands to the Console which will return appropriate
  errors (:starting, :busy) based on its actual state.
  """
  @spec get_console_pid(%{integer() => console_info()}, integer()) ::
          {:ok, pid()} | {:error, atom()}
  def get_console_pid(consoles, track_id) do
    case Map.get(consoles, track_id) do
      nil -> {:error, :console_offline}
      %{pid: nil} -> {:error, :console_offline}
      %{pid: pid} -> {:ok, pid}
    end
  end

  @doc """
  Determines if container should attempt restart based on restart count.

  Returns `true` if restart should be attempted, `false` if max restarts exceeded.
  """
  @spec should_restart?(non_neg_integer(), non_neg_integer()) :: boolean()
  def should_restart?(restart_count, max_restart_count) do
    restart_count < max_restart_count
  end

  @doc """
  Determines if MSGRPC connection should be retried.

  Returns `true` if retry should be attempted, `false` if max attempts exceeded.
  """
  @spec should_retry_msgrpc?(non_neg_integer(), non_neg_integer()) :: boolean()
  def should_retry_msgrpc?(connect_attempts, max_attempts) do
    connect_attempts < max_attempts
  end

  @doc """
  Determines if console should be restarted after crash.

  Returns `true` if restart should be attempted based on:
  - Track is still registered
  - Container is running
  - Max restart attempts not exceeded
  """
  @spec should_restart_console?(MapSet.t(), atom(), non_neg_integer(), non_neg_integer()) ::
          boolean()
  def should_restart_console?(registered_tracks, container_status, restart_attempts, max_attempts) do
    MapSet.size(registered_tracks) > 0 and
      container_status == :running and
      restart_attempts < max_attempts
  end

  @doc """
  Builds Docker container labels for a managed container.
  """
  @spec build_container_labels(integer(), String.t(), String.t()) :: map()
  def build_container_labels(container_record_id, workspace_slug, container_slug) do
    %{
      "msfailab.managed" => "true",
      "msfailab.container_id" => to_string(container_record_id),
      "msfailab.workspace_slug" => workspace_slug,
      "msfailab.container_slug" => container_slug
    }
  end

  @doc """
  Generates Docker container name from workspace and container slugs.
  """
  @spec container_name(String.t(), String.t()) :: String.t()
  def container_name(workspace_slug, container_slug) do
    "msfailab-#{workspace_slug}-#{container_slug}"
  end

  @doc """
  Creates initial console info for a newly spawned console.
  """
  @spec new_console_info(pid(), reference()) :: console_info()
  def new_console_info(pid, ref) do
    %{
      pid: pid,
      ref: ref,
      restart_attempts: 0,
      last_restart_at: nil
    }
  end

  @doc """
  Creates console info for a console pending restart.
  """
  @spec console_info_pending_restart(non_neg_integer()) :: console_info()
  def console_info_pending_restart(restart_attempts) do
    %{
      pid: nil,
      ref: nil,
      restart_attempts: restart_attempts,
      last_restart_at: DateTime.utc_now()
    }
  end
end
