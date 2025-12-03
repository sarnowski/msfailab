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

defmodule Msfailab.LLM.Provider do
  @moduledoc """
  Behaviour for LLM provider implementations.

  Each provider must implement:
  - Configuration detection and model discovery
  - Streaming chat requests with event emission

  ## Model Filtering

  Providers can filter models using environment variables with glob-style patterns.
  Use `filter_models/3` after fetching models to apply the filter.

  Example filters:
  - `*` - match all models
  - `gpt-5*` - match models starting with "gpt-5"
  - `deepseek:*,*:30b` - match "deepseek:*" OR "*:30b" (additive)

  ## Chat Implementation

  The `chat/3` callback must:
  1. Spawn an async task (not linked to caller)
  2. Transform messages to provider-specific format
  3. Stream events to the caller as `{:llm, ref, event}` tuples
  4. Handle errors gracefully with `StreamError` events

  See `Msfailab.LLM.Events` for the complete event type definitions.
  """

  alias Msfailab.LLM.ChatRequest
  alias Msfailab.LLM.Model

  @doc """
  Check if this provider is configured (required env vars present).
  Does not validate the configuration, only checks presence.
  """
  @callback configured?() :: boolean()

  @doc """
  Fetch available models from the provider.
  This implicitly validates the configuration by making API calls.
  Returns models with context window sizes populated.
  """
  @callback list_models() :: {:ok, [Model.t()]} | {:error, term()}

  @doc """
  Start a streaming chat request.

  Spawns an async task that sends events to the caller process.
  The task should not be linked to the caller to avoid cascading failures.

  ## Parameters

  - `request` - The chat request parameters
  - `caller` - PID to receive events
  - `ref` - Reference for correlating events

  ## Event Format

  All events must be sent as `{:llm, ref, event}` tuples where `event`
  is one of the structs from `Msfailab.LLM.Events`.

  ## Returns

  - `:ok` - Task started successfully
  - `{:error, reason}` - Failed to start task
  """
  @callback chat(request :: ChatRequest.t(), caller :: pid(), ref :: reference()) ::
              :ok | {:error, term()}

  @doc """
  Filter and sort models based on an environment variable filter.

  The filter is a comma-separated list of glob patterns (supporting `*` wildcards).
  Multiple patterns are additive (union). Results are deduplicated and sorted
  in reverse lexicographical order (e.g., "claude-opus-4.5" before "claude-opus-4.1").

  ## Parameters

  - `models` - List of Model structs to filter
  - `env_var` - Name of the environment variable containing the filter
  - `default_filter` - Default filter pattern if env var is not set

  ## Examples

      iex> filter_models(models, "OPENAI_MODEL_FILTER", "gpt-5*")
      [%Model{name: "gpt-5.1"}, %Model{name: "gpt-5.0"}]
  """
  @spec filter_models([Model.t()], String.t(), String.t()) :: [Model.t()]
  def filter_models(models, env_var, default_filter) do
    # Treat empty string same as unset - use default
    filter = get_env_or_default(env_var, default_filter)

    patterns =
      filter
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.map(&pattern_to_regex/1)

    models
    |> Enum.filter(fn model -> matches_any_pattern?(model.name, patterns) end)
    |> Enum.uniq_by(& &1.name)
    |> Enum.sort_by(& &1.name, :desc)
  end

  @doc """
  Gets an environment variable, treating empty string as unset.

  Docker compose passes `VAR: ${VAR:-}` which sets the var to empty string
  when unset, bypassing System.get_env/2's default. This function treats
  both nil and empty string as "use default".
  """
  @spec get_env_or_default(String.t(), String.t()) :: String.t()
  def get_env_or_default(env_var, default) do
    case System.get_env(env_var) do
      nil -> default
      "" -> default
      value -> value
    end
  end

  # Convert a glob pattern with * wildcards to a regex
  defp pattern_to_regex(pattern) do
    pattern
    |> Regex.escape()
    |> String.replace("\\*", ".*")
    |> then(&Regex.compile!("^#{&1}$"))
  end

  # Check if a model name matches any of the compiled regex patterns
  defp matches_any_pattern?(name, patterns) do
    Enum.any?(patterns, &Regex.match?(&1, name))
  end
end
