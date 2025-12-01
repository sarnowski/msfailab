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

defmodule Msfailab.LLM.Registry do
  @moduledoc """
  GenServer holding cached model information and provider state.

  Initialized synchronously on application startup. The application
  will fail to start if:
  - No providers are configured
  - No models are discovered
  - MSFAILAB_DEFAULT_MODEL pattern matches no discovered models
  """

  use GenServer

  require Logger

  alias Msfailab.LLM.Model
  alias Msfailab.LLM.Provider

  # ============================================================================
  # State
  # ============================================================================

  defmodule State do
    @moduledoc """
    State for the LLM Registry GenServer.

    Tracks active providers, discovered models, and the default model.
    """

    @type t :: %__MODULE__{
            active_providers: [atom()],
            models: %{String.t() => Model.t()},
            default_model: String.t()
          }

    defstruct active_providers: [],
              models: %{},
              default_model: ""
  end

  # Default providers with their default model names
  # Can be overridden via application config for testing
  @default_providers [
    {Msfailab.LLM.Providers.OpenAI, "gpt-4.1"},
    {Msfailab.LLM.Providers.Anthropic, "claude-sonnet-4-5-20250514"},
    {Msfailab.LLM.Providers.Ollama, "qwen3:30b"}
  ]

  # Client API

  @doc """
  Starts the LLM Registry GenServer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Lists all available models across all providers.
  """
  @spec list_models() :: [Model.t()]
  def list_models do
    GenServer.call(__MODULE__, :list_models)
  end

  @doc """
  Gets a specific model by name.
  """
  @spec get_model(String.t()) :: {:ok, Model.t()} | {:error, :not_found}
  def get_model(name) do
    GenServer.call(__MODULE__, {:get_model, name})
  end

  @doc """
  Gets the default model name.
  """
  @spec get_default_model() :: String.t()
  def get_default_model do
    GenServer.call(__MODULE__, :get_default_model)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    case initialize_providers() do
      {:ok, %State{} = state} ->
        Logger.info("LLM Registry initialized",
          providers: state.active_providers,
          model_count: map_size(state.models),
          default_model: state.default_model
        )

        {:ok, state}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:list_models, _from, state) do
    # Sort by name descending to match Provider.filter_models/3 ordering
    sorted = state.models |> Map.values() |> Enum.sort_by(& &1.name, :desc)
    {:reply, sorted, state}
  end

  def handle_call({:get_model, name}, _from, state) do
    case Map.fetch(state.models, name) do
      {:ok, model} -> {:reply, {:ok, model}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call(:get_default_model, _from, state) do
    {:reply, state.default_model, state}
  end

  # Private

  defp initialize_providers do
    providers = Application.get_env(:msfailab, :llm_providers, @default_providers)

    configured =
      providers
      |> Enum.filter(fn {provider, _default} -> provider.configured?() end)

    if configured == [] do
      Logger.error(
        "No LLM providers configured. Set MSFAILAB_OLLAMA_HOST, MSFAILAB_OPENAI_API_KEY, or MSFAILAB_ANTHROPIC_API_KEY."
      )

      {:error, :no_providers_configured}
    else
      activate_and_validate(configured)
    end
  end

  defp activate_and_validate(configured_providers) do
    {active, models} = activate_providers(configured_providers)

    cond do
      active == [] ->
        Logger.error("All LLM providers failed to activate")
        {:error, :all_providers_failed}

      map_size(models) == 0 ->
        Logger.error("No models discovered from any provider")
        {:error, :no_models_available}

      true ->
        case resolve_default_model(models) do
          {:ok, default_model} ->
            state = %State{
              active_providers: active,
              models: models,
              default_model: default_model
            }

            {:ok, state}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp activate_providers(providers) do
    Enum.reduce(providers, {[], %{}}, fn {provider, _default_model}, {active, models} ->
      case provider.list_models() do
        {:ok, []} ->
          Logger.warning("Provider returned no models",
            provider: provider_name(provider)
          )

          {active, models}

        {:ok, provider_models} ->
          Logger.debug("Provider activated",
            provider: provider_name(provider),
            model_count: length(provider_models)
          )

          models_map = Map.new(provider_models, &{&1.name, &1})
          {[provider_name(provider) | active], Map.merge(models, models_map)}

        {:error, reason} ->
          Logger.warning("Provider failed to activate",
            provider: provider_name(provider),
            reason: inspect(reason)
          )

          {active, models}
      end
    end)
  end

  defp provider_name(module) do
    # Extract provider name from module (e.g., Msfailab.LLM.Providers.OpenAI -> :openai)
    # Works for both real providers and mock modules
    module
    |> Module.split()
    |> List.last()
    |> String.replace(~r/(Mock|Provider)$/, "")
    |> String.downcase()
    |> String.to_existing_atom()
  rescue
    # For test mocks that might not have atoms pre-defined
    ArgumentError -> :mock
  end

  defp resolve_default_model(models) do
    # MSFAILAB_DEFAULT_MODEL supports glob patterns like provider filters
    # Default "*" matches all models, picking first after descending sort
    all_models = Map.values(models)
    filtered = Provider.filter_models(all_models, "MSFAILAB_DEFAULT_MODEL", "*")

    case filtered do
      [] ->
        filter = System.get_env("MSFAILAB_DEFAULT_MODEL", "*")

        Logger.error("MSFAILAB_DEFAULT_MODEL='#{filter}' matched no available models",
          available: Map.keys(models)
        )

        {:error, {:no_default_model_match, filter}}

      [first | _] ->
        {:ok, first.name}
    end
  end
end
