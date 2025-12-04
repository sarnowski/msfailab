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

defmodule MsfailabWeb.WorkspaceLive.CommandHandler do
  @moduledoc """
  Pure functions for command handling in WorkspaceLive.

  Extracts business logic from the LiveView for testability.
  This module handles:
  - Error message formatting for MSF command failures
  - Error message formatting for chat turn failures
  """

  @doc """
  Formats MSF command errors into user-friendly messages.

  ## Examples

      iex> CommandHandler.format_msf_error(:container_not_running)
      "Container is not running"

      iex> CommandHandler.format_msf_error(:console_busy)
      "Console is busy processing a command"

  """
  @spec format_msf_error(atom()) :: String.t()
  def format_msf_error(:container_not_running), do: "Container is not running"
  def format_msf_error(:console_starting), do: "Console is still starting up, please wait"
  def format_msf_error(:console_busy), do: "Console is busy processing a command"
  def format_msf_error(:console_offline), do: "Console is offline"
  def format_msf_error(:console_not_registered), do: "Console is not registered for this track"
  def format_msf_error(reason), do: "Command failed: #{inspect(reason)}"

  @doc """
  Formats chat turn errors into user-friendly messages.

  ## Examples

      iex> CommandHandler.format_chat_error(:not_found)
      "Track server not found"

      iex> CommandHandler.format_chat_error({:timeout, 5000})
      "Failed to send message: {:timeout, 5000}"

  """
  @spec format_chat_error(term()) :: String.t()
  def format_chat_error(:not_found), do: "Track server not found"
  def format_chat_error(reason), do: "Failed to send message: #{inspect(reason)}"

  @doc """
  Returns the error message for when no track is selected.
  """
  @spec no_track_error() :: String.t()
  def no_track_error, do: "No track selected"
end
