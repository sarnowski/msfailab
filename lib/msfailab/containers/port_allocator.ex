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

defmodule Msfailab.Containers.PortAllocator do
  @moduledoc """
  Allocates unique RPC ports for msfconsole containers.

  In host network mode, each msfconsole container must bind to a unique port
  since they all share the host's network namespace. This module handles
  random port selection within a defined range, avoiding ports already in use.

  ## Port Range

  Ports are allocated in the range 50000-60000, providing 10,001 possible ports.
  """

  @port_range 50_000..60_000
  @max_attempts 100

  @doc """
  Returns the port range used for allocation.
  """
  @spec port_range() :: Range.t()
  def port_range, do: @port_range

  @doc """
  Allocates a random port not in the used_ports list.

  Returns `{:ok, port}` on success or `{:error, :no_ports_available}` if
  all ports in the range are in use.
  """
  @spec allocate_port([integer()]) :: {:ok, integer()} | {:error, :no_ports_available}
  def allocate_port(used_ports) do
    used_set = MapSet.new(used_ports)
    range_size = Range.size(@port_range)

    # If all ports are used, return error immediately
    if MapSet.size(used_set) >= range_size do
      {:error, :no_ports_available}
    else
      find_free_port(used_set, @max_attempts)
    end
  end

  defp find_free_port(used_set, 0) do
    # Exhausted random attempts, fall back to sequential search
    find_free_port_sequential(used_set)
  end

  defp find_free_port(used_set, attempts_remaining) do
    port = Enum.random(@port_range)

    if MapSet.member?(used_set, port) do
      find_free_port(used_set, attempts_remaining - 1)
    else
      {:ok, port}
    end
  end

  defp find_free_port_sequential(used_set) do
    case Enum.find(@port_range, fn port -> not MapSet.member?(used_set, port) end) do
      nil -> {:error, :no_ports_available}
      port -> {:ok, port}
    end
  end
end
