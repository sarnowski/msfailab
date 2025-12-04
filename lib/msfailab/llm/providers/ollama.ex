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

defmodule Msfailab.LLM.Providers.Ollama do
  @moduledoc """
  Ollama provider implementation.

  Requires MSFAILAB_OLLAMA_HOST environment variable (e.g., http://localhost:11434).
  Fetches model list via /api/tags, then context windows via /api/show per model.

  ## Architecture

  This module is a thin HTTP transport layer. All business logic for stream
  processing, message transformation, and state management is in the companion
  `Msfailab.LLM.Providers.Ollama.Core` module, following the Core Module Pattern.

  ## Model Filtering

  Models can be filtered using the MSFAILAB_OLLAMA_MODEL_FILTER environment variable.
  Default: `*` (all models). See `Msfailab.LLM.Provider` for filter syntax.

  ## Context Window Detection

  Context windows are extracted from model info in this priority:
  1. `model_info.llama.context_length`
  2. `model_info.qwen2.context_length`
  3. `model_info.gemma2.context_length`
  4. `parameters` string (num_ctx value)
  5. Default: 200,000 tokens (logged at debug level)

  ## Streaming Chat

  The chat endpoint (`/api/chat`) streams NDJSON responses. Each line contains
  a partial response with content deltas. The final line includes token counts
  and an optional context array for cache continuation.

  Chat requests spawn an unlinked task (`Task.start/1`) to avoid cascading failures
  if the caller crashes. The stream will terminate gracefully when it detects the
  caller is no longer alive.

  ## Tool Support

  Ollama uses OpenAI-compatible tool format. Tool calls are returned in the
  final response's `tool_calls` array within the message object.
  """

  @behaviour Msfailab.LLM.Provider

  alias Msfailab.LLM.ChatRequest
  alias Msfailab.LLM.Events
  alias Msfailab.LLM.Model
  alias Msfailab.LLM.Provider
  alias Msfailab.LLM.Providers.Ollama.Core
  alias Msfailab.Trace

  require Logger

  @default_model_filter "*"
  @stream_timeout 300_000

  # ============================================================================
  # Provider Callbacks
  # ============================================================================

  @impl true
  def configured? do
    raw_host() not in [nil, ""]
  end

  @impl true
  def list_models do
    list_models(req_options())
  end

  @impl true
  def chat(%ChatRequest{} = request, caller, ref) do
    # Capture Logger metadata to preserve context (workspace_id, track_id) in the task
    metadata = Logger.metadata()

    # Use Task.start (not start_link) to avoid cascading failures.
    # If the caller crashes, the stream will fail gracefully when
    # attempting to send to the dead process.
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
  # Reason: HTTP integration requiring real Ollama service.
  # Core business logic tested in Ollama.Core module (96%+ coverage).

  @doc false
  # Internal function that accepts request options for testing
  def list_models(req_opts) do
    merged_opts = Keyword.merge(req_options(), req_opts)

    with {:ok, model_names} <- fetch_model_names(merged_opts) do
      fetch_model_details(model_names, merged_opts)
    end
  end

  @spec fetch_model_names(keyword()) :: {:ok, [String.t()]} | {:error, term()}
  defp fetch_model_names(req_opts) do
    url = host() <> "/api/tags"

    case Req.get(url, req_opts) do
      {:ok, %{status: 200, body: %{"models" => models}}} ->
        names = Enum.map(models, & &1["name"])

        Logger.debug("Ollama API returned models",
          url: url,
          count: length(names),
          models: names
        )

        if names == [] do
          Logger.warning("Ollama API returned empty model list", url: url)
          {:error, :no_models_from_api}
        else
          {:ok, names}
        end

      {:ok, %{status: status, body: body}} ->
        Logger.warning("Ollama API returned unexpected status",
          url: url,
          status: status,
          body: inspect(body)
        )

        {:error, {:unexpected_status, status}}

      {:error, reason} ->
        Logger.warning("Ollama API request failed",
          url: url,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  @spec fetch_model_details([String.t()], keyword()) ::
          {:ok, [Model.t()]} | {:error, term()}
  defp fetch_model_details(model_names, req_opts) do
    fetched =
      model_names
      |> Task.async_stream(&fetch_single_model(&1, req_opts), timeout: 30_000, max_concurrency: 5)
      |> Enum.reduce([], fn
        {:ok, {:ok, model}}, acc -> [model | acc]
        {:ok, {:error, _reason}}, acc -> acc
        {:exit, _reason}, acc -> acc
      end)

    Logger.debug("Ollama models after fetching details",
      count: length(fetched),
      models: Enum.map(fetched, & &1.name)
    )

    filter = Provider.get_env_or_default("MSFAILAB_OLLAMA_MODEL_FILTER", @default_model_filter)

    filtered =
      Provider.filter_models(fetched, "MSFAILAB_OLLAMA_MODEL_FILTER", @default_model_filter)

    Logger.debug("Ollama models after filter_models",
      filter: filter,
      count: length(filtered),
      models: Enum.map(filtered, & &1.name)
    )

    if filtered == [] do
      Logger.warning("Ollama: all models filtered out",
        api_count: length(model_names),
        fetched_count: length(fetched),
        filter: filter
      )

      {:error, {:all_models_filtered, filter}}
    else
      {:ok, filtered}
    end
  end

  @spec fetch_single_model(String.t(), keyword()) :: {:ok, Model.t()} | {:error, term()}
  defp fetch_single_model(name, req_opts) do
    case Req.post(host() <> "/api/show", [json: %{name: name}] ++ req_opts) do
      {:ok, %{status: 200, body: body}} ->
        context_window = Core.extract_context_window(body, name)
        model = %Model{name: name, provider: :ollama, context_window: context_window}
        {:ok, model}

      {:ok, %{status: status}} ->
        {:error, {:unexpected_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ============================================================================
  # Internal: Chat Streaming
  # ============================================================================

  @doc false
  # Internal function that accepts request options for testing
  def run_chat_stream(%ChatRequest{} = request, caller, ref, req_opts) do
    body = Core.build_request_body(request, thinking_enabled?())
    url = host() <> "/api/chat"

    # Merge options with explicit streaming timeout last to ensure it takes precedence
    # (Keyword.put replaces existing keys, avoiding duplicate key issues)
    opts =
      req_options()
      |> Keyword.merge(req_opts)
      |> Keyword.put(:json, body)
      |> Keyword.put(:into, build_stream_collector(caller, ref, body, url))
      |> Keyword.put(:receive_timeout, @stream_timeout)

    case Req.post(url, opts) do
      {:ok, %{status: 200, body: acc}} ->
        # Process any remaining buffer content when stream ends
        finalize_stream_and_send(acc, caller, ref)
        trace_request(acc, 200)
        :ok

      {:ok, %{status: status, body: acc}} ->
        error_msg = Core.extract_error_message(acc, status)
        trace_request(acc, status)
        send(caller, {:llm, ref, %Events.StreamError{reason: error_msg, recoverable: false}})

      {:error, reason} ->
        Logger.warning("Ollama stream connection failed",
          url: url,
          model: request.model,
          reason: inspect(reason)
        )

        recoverable = Core.recoverable_error?(reason)
        send(caller, {:llm, ref, %Events.StreamError{reason: reason, recoverable: recoverable}})
    end
  end

  # ============================================================================
  # Internal: Stream Processing
  # ============================================================================

  @spec build_stream_collector(pid(), reference(), map(), String.t()) ::
          ({:data, binary()}, term() -> {:cont, {Req.Request.t(), Req.Response.t()}})
  defp build_stream_collector(caller, ref, request_body, url) do
    fn {:data, data}, acc ->
      state = process_stream_chunk(data, acc, caller, ref, request_body, url)
      {:cont, wrap_state_for_req(state)}
    end
  end

  # Store state in response body so Req gets {req, resp} back
  @spec wrap_state_for_req(Core.State.t()) :: {Req.Request.t(), Req.Response.t()}
  defp wrap_state_for_req(%Core.State{req_resp: {req, resp}} = state) do
    {req, %{resp | body: state}}
  end

  @spec process_stream_chunk(binary(), term(), pid(), reference(), map(), String.t()) ::
          Core.State.t()
  defp process_stream_chunk(data, acc, caller, ref, request_body, url) do
    # Req passes {request, response} tuple as initial accumulator
    acc = init_accumulator(acc, request_body, url)

    {events, %Core.State{} = new_state} = Core.process_chunk(data, acc)
    send_events(events, caller, ref)

    %Core.State{new_state | req_resp: acc.req_resp, response_headers: acc.response_headers}
  end

  # Req passes {request, response} tuple as initial accumulator
  # We store it so we can return it when streaming completes
  # After first chunk, state is stored in resp.body
  @spec init_accumulator(term(), map(), String.t()) :: Core.State.t()
  defp init_accumulator({_req, %{body: %Core.State{} = state}}, _request_body, _url) do
    # State already initialized, stored in response body - just extract it
    state
  end

  defp init_accumulator({req, resp}, request_body, url) do
    # First chunk - initialize state using Core module
    core_state = Core.init_state(request_body, url)
    %Core.State{core_state | req_resp: {req, resp}, response_headers: resp.headers}
  end

  @spec finalize_stream_and_send(Core.State.t(), pid(), reference()) :: :ok
  defp finalize_stream_and_send(acc, caller, ref) do
    {events, _state} = Core.finalize_stream(acc)
    send_events(events, caller, ref)
  end

  @spec send_events([Events.t()], pid(), reference()) :: :ok
  defp send_events(events, caller, ref) do
    Enum.each(events, fn event ->
      send(caller, {:llm, ref, event})
    end)
  end

  # ============================================================================
  # Internal: Helpers
  # ============================================================================

  @spec raw_host() :: String.t() | nil
  defp raw_host, do: System.get_env("MSFAILAB_OLLAMA_HOST")

  @spec host() :: String.t()
  defp host do
    url = raw_host()

    if String.starts_with?(url, "http://") or String.starts_with?(url, "https://") do
      String.trim_trailing(url, "/")
    else
      "http://#{String.trim_trailing(url, "/")}"
    end
  end

  @spec req_options() :: keyword()
  defp req_options do
    Application.get_env(:msfailab, :llm_req_options, receive_timeout: 10_000)
  end

  @spec thinking_enabled?() :: boolean()
  defp thinking_enabled? do
    Application.get_env(:msfailab, :ollama_thinking, true)
  end

  @spec trace_request(Core.State.t(), non_neg_integer()) :: :ok
  defp trace_request(%{} = acc, status) do
    response_body = Core.format_trace_response(acc, status)

    Trace.http(
      :ollama,
      %{method: "POST", url: acc.request_url, headers: [], body: acc.request_body},
      %{status: status, headers: acc.response_headers, body: response_body}
    )
  end

  # coveralls-ignore-stop

  # ============================================================================
  # Test Helpers (exposed for testing)
  # ============================================================================

  @doc false
  # Exposed for testing trace accumulation logic
  defdelegate format_trace_response(acc, status), to: Core
end
