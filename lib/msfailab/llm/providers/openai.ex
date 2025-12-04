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

defmodule Msfailab.LLM.Providers.OpenAI do
  @moduledoc """
  OpenAI provider implementation.

  Requires MSFAILAB_OPENAI_API_KEY environment variable.
  Context windows are hardcoded since the API doesn't expose them.
  Unknown models default to 200k context window.

  ## Architecture

  This module is a thin HTTP transport layer. All business logic for stream
  processing, message transformation, and state management is in the companion
  `Msfailab.LLM.Providers.OpenAI.Core` module, following the Core Module Pattern.

  ## Model Filtering

  Models can be filtered using the MSFAILAB_OPENAI_MODEL_FILTER environment variable.
  Default: `gpt-5*`. See `Msfailab.LLM.Provider` for filter syntax.

  ## Streaming Chat

  Uses Server-Sent Events (SSE) format with `data: {json}` lines.
  Tool call arguments are streamed incrementally and must be accumulated
  then parsed as JSON when complete.

  ## Tool Support

  OpenAI uses function calling with JSON string arguments. The `strict` option
  can be enabled for guaranteed schema conformance.
  """

  @behaviour Msfailab.LLM.Provider

  alias Msfailab.LLM.ChatRequest
  alias Msfailab.LLM.Events
  alias Msfailab.LLM.Model
  alias Msfailab.LLM.Provider
  alias Msfailab.LLM.Providers.OpenAI.Core
  alias Msfailab.Trace

  require Logger

  @base_url "https://api.openai.com/v1"
  @default_context_window 200_000
  @default_model_filter "gpt-5*"
  @stream_timeout 300_000

  # Models we support (filter the full list which includes embeddings, whisper, etc.)
  @supported_prefixes ["gpt-4", "gpt-3.5", "gpt-5", "o1", "o3", "o4"]

  # Known context windows (from OpenAI documentation)
  @context_windows %{
    "gpt-4.1" => 1_047_576,
    "gpt-4.1-mini" => 1_047_576,
    "gpt-4.1-nano" => 1_047_576,
    "gpt-4o" => 128_000,
    "gpt-4o-mini" => 128_000,
    "gpt-4-turbo" => 128_000,
    "gpt-4-turbo-preview" => 128_000,
    "gpt-4" => 8_192,
    "gpt-4-32k" => 32_768,
    "gpt-3.5-turbo" => 16_385,
    "gpt-3.5-turbo-16k" => 16_385,
    "o1" => 200_000,
    "o1-mini" => 128_000,
    "o1-preview" => 128_000,
    "o3" => 200_000,
    "o3-mini" => 200_000,
    "o4-mini" => 200_000
  }

  # ============================================================================
  # Provider Callbacks
  # ============================================================================

  @impl true
  def configured? do
    api_key() not in [nil, ""]
  end

  @impl true
  def list_models do
    list_models(req_options())
  end

  @impl true
  def chat(%ChatRequest{} = request, caller, ref) do
    metadata = Logger.metadata()

    Task.start(fn ->
      Logger.metadata(metadata)
      run_chat_stream(request, caller, ref, req_options())
    end)

    :ok
  end

  # ============================================================================
  # Internal: Model Listing
  # ============================================================================

  # coveralls-ignore-start
  # Reason: HTTP integration requiring real OpenAI API.
  # Core business logic tested in OpenAI.Core module (93%+ coverage).

  @doc false
  # Internal function that accepts request options for testing
  def list_models(req_opts) do
    merged_opts = Keyword.merge(req_options(), req_opts)

    case Req.get(@base_url <> "/models", [headers: auth_headers()] ++ merged_opts) do
      {:ok, %{status: 200, body: %{"data" => models}}} ->
        process_model_response(models)

      {:ok, %{status: 401}} ->
        Logger.warning("OpenAI API returned 401 - invalid API key")
        {:error, :invalid_api_key}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("OpenAI API returned unexpected status",
          status: status,
          body: inspect(body)
        )

        {:error, {:unexpected_status, status}}

      {:error, reason} ->
        Logger.warning("OpenAI API request failed", reason: inspect(reason))
        {:error, reason}
    end
  end

  defp process_model_response([]) do
    Logger.warning("OpenAI API returned empty model list")
    {:error, :no_models_from_api}
  end

  defp process_model_response(models) do
    model_ids = Enum.map(models, & &1["id"])

    Logger.debug("OpenAI API returned models",
      count: length(models),
      models: model_ids
    )

    supported = Enum.filter(models, &supported_model?/1)

    Logger.debug("OpenAI models after supported_model? filter",
      count: length(supported),
      models: Enum.map(supported, & &1["id"])
    )

    filter =
      Provider.get_env_or_default("MSFAILAB_OPENAI_MODEL_FILTER", @default_model_filter)

    filtered =
      supported
      |> Enum.map(&to_model/1)
      |> Provider.filter_models("MSFAILAB_OPENAI_MODEL_FILTER", @default_model_filter)

    Logger.debug("OpenAI models after filter_models",
      filter: filter,
      count: length(filtered),
      models: Enum.map(filtered, & &1.name)
    )

    validate_filtered_result(filtered, length(models), length(supported), filter)
  end

  defp validate_filtered_result([], api_count, supported_count, filter) do
    Logger.warning("OpenAI: all models filtered out",
      api_count: api_count,
      supported_count: supported_count,
      filter: filter
    )

    {:error, {:all_models_filtered, filter}}
  end

  defp validate_filtered_result(filtered, _api_count, _supported_count, _filter) do
    {:ok, filtered}
  end

  defp supported_model?(%{"id" => id}) do
    Enum.any?(@supported_prefixes, &String.starts_with?(id, &1))
  end

  defp to_model(%{"id" => id}) do
    %Model{
      name: id,
      provider: :openai,
      context_window: context_window_for(id)
    }
  end

  defp context_window_for(model_id) do
    case Map.get(@context_windows, model_id) do
      nil -> context_window_by_prefix(model_id)
      size -> size
    end
  end

  defp context_window_by_prefix(model_id) do
    @context_windows
    |> Enum.sort_by(fn {prefix, _} -> -String.length(prefix) end)
    |> Enum.find_value(@default_context_window, fn {prefix, size} ->
      if String.starts_with?(model_id, prefix), do: size
    end)
  end

  # ============================================================================
  # Internal: Chat Streaming
  # ============================================================================

  @doc false
  # Internal function that accepts request options for testing
  def run_chat_stream(%ChatRequest{} = request, caller, ref, req_opts) do
    body = Core.build_request_body(request)
    url = @base_url <> "/chat/completions"

    opts =
      req_options()
      |> Keyword.merge(req_opts)
      |> Keyword.put(:json, body)
      |> Keyword.put(:headers, auth_headers())
      |> Keyword.put(:into, build_stream_collector(caller, ref, body, url))
      |> Keyword.put(:receive_timeout, @stream_timeout)

    case Req.post(url, opts) do
      {:ok, %{status: 200, body: state}} ->
        finalize_stream_and_send(state, caller, ref)
        trace_request(state, 200)
        :ok

      {:ok, %{status: status, body: state}} ->
        error_msg = Core.extract_error_message(state, status)
        recoverable = status in [429, 500, 502, 503, 504]
        trace_request(state, status)

        send(
          caller,
          {:llm, ref, %Events.StreamError{reason: error_msg, recoverable: recoverable}}
        )

      {:error, reason} ->
        recoverable = Core.recoverable_error?(reason)
        send(caller, {:llm, ref, %Events.StreamError{reason: reason, recoverable: recoverable}})
    end
  end

  # ============================================================================
  # Internal: Stream Processing
  # ============================================================================

  defp build_stream_collector(caller, ref, request_body, url) do
    fn {:data, data}, acc ->
      state = process_stream_chunk(data, acc, caller, ref, request_body, url)
      {:cont, wrap_state_for_req(state)}
    end
  end

  defp wrap_state_for_req(%Core.State{req_resp: {req, resp}} = state) do
    {req, %{resp | body: state}}
  end

  defp process_stream_chunk(data, acc, caller, ref, request_body, url) do
    state = init_accumulator(acc, request_body, url)
    {events, new_state} = Core.process_chunk(data, state)
    send_events(events, caller, ref)
    %{new_state | req_resp: state.req_resp, response_headers: state.response_headers}
  end

  defp init_accumulator({_req, %{body: %Core.State{} = state}}, _request_body, _url) do
    state
  end

  defp init_accumulator({req, resp}, request_body, url) do
    core_state = Core.init_state(request_body, url)

    %{core_state | req_resp: {req, resp}, response_headers: resp.headers}
  end

  defp finalize_stream_and_send(state, caller, ref) do
    {events, _state} = Core.finalize_stream_buffer(state)
    send_events(events, caller, ref)
  end

  defp send_events(events, caller, ref) do
    Enum.each(events, fn event ->
      send(caller, {:llm, ref, event})
    end)
  end

  # ============================================================================
  # Internal: Helpers
  # ============================================================================

  defp auth_headers do
    [{"authorization", "Bearer #{api_key()}"}]
  end

  defp api_key, do: System.get_env("MSFAILAB_OPENAI_API_KEY")

  defp req_options do
    Application.get_env(:msfailab, :llm_req_options, receive_timeout: 10_000)
  end

  defp trace_request(%Core.State{} = state, status) do
    response_body = Core.format_trace_response(state, status)

    Trace.http(
      :openai,
      %{method: "POST", url: state.request_url, headers: [], body: state.request_body},
      %{status: status, headers: state.response_headers, body: response_body}
    )
  end

  # coveralls-ignore-stop

  # ============================================================================
  # Test Helpers (delegated to Core for testing)
  # ============================================================================

  @doc false
  defdelegate format_trace_response(state, status), to: Core
end
