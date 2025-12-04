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

defmodule MsfailabWeb.WorkspaceLive.ModelSelector do
  @moduledoc """
  Pure functions for LLM model selection in WorkspaceLive.

  Extracts model selection logic from LiveView for testability.
  """

  @doc """
  Selects the model for a track, falling back to the first available model.

  Returns the model name string or nil if no models are available.

  ## Examples

      iex> ModelSelector.select_model_for_track(%{current_model: "claude-3-haiku"}, [])
      "claude-3-haiku"

      iex> ModelSelector.select_model_for_track(%{current_model: nil}, [%{name: "default"}])
      "default"

      iex> ModelSelector.select_model_for_track(%{current_model: nil}, [])
      nil

  """
  @spec select_model_for_track(map() | nil, [map()]) :: String.t() | nil
  def select_model_for_track(nil, _available_models), do: nil

  def select_model_for_track(track, available_models) do
    case track.current_model do
      nil -> first_model_name(available_models)
      model -> model
    end
  end

  @doc """
  Gets the name of the first available model, or nil if none available.

  ## Examples

      iex> ModelSelector.first_model_name([%{name: "claude-3-opus"}, %{name: "claude-3-haiku"}])
      "claude-3-opus"

      iex> ModelSelector.first_model_name([])
      nil

  """
  @spec first_model_name([map()]) :: String.t() | nil
  def first_model_name([]), do: nil
  def first_model_name([model | _]), do: model.name
end
