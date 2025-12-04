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

defmodule Msfailab.Tracks.TrackServer.Turn.ErrorFormatter do
  @moduledoc """
  Pure functions for formatting tool execution errors.

  Extracts error formatting logic from Turn module for testability.
  """

  @doc """
  Formats MSF data tool errors into user-friendly messages.

  ## Examples

      iex> ErrorFormatter.format_msf_data_error(:workspace_not_found)
      "Workspace not found"

      iex> ErrorFormatter.format_msf_data_error({:unknown_tool, "foo"})
      "Unknown tool: foo"

  """
  @spec format_msf_data_error(term()) :: String.t()
  def format_msf_data_error(:workspace_not_found), do: "Workspace not found"
  def format_msf_data_error(:host_not_found), do: "Host not found"
  def format_msf_data_error(:loot_not_found), do: "Loot not found"
  def format_msf_data_error({:unknown_tool, name}), do: "Unknown tool: #{name}"

  def format_msf_data_error({:validation_error, errors}),
    do: "Validation error: #{inspect(errors)}"

  def format_msf_data_error(reason), do: inspect(reason)

  @doc """
  Formats memory tool errors into user-friendly messages.

  ## Examples

      iex> ErrorFormatter.format_memory_error(:track_not_found)
      "Track not found"

      iex> ErrorFormatter.format_memory_error("custom error")
      "custom error"

      iex> ErrorFormatter.format_memory_error({:db_error, :timeout})
      "{:db_error, :timeout}"

  """
  @spec format_memory_error(term()) :: String.t()
  def format_memory_error(reason) when is_binary(reason), do: reason
  def format_memory_error(:track_not_found), do: "Track not found"
  def format_memory_error({:unknown_tool, name}), do: "Unknown memory tool: #{name}"

  def format_memory_error({:validation_error, errors}),
    do: "Validation error: #{inspect(errors)}"

  def format_memory_error(reason), do: inspect(reason)

  @doc """
  Formats generic tool errors.

  ## Examples

      iex> ErrorFormatter.format_tool_error(:timeout)
      "timeout"

      iex> ErrorFormatter.format_tool_error({:error, "connection failed"})
      "{:error, \\"connection failed\\"}"

  """
  @spec format_tool_error(term()) :: String.t()
  def format_tool_error(reason), do: inspect(reason)
end
