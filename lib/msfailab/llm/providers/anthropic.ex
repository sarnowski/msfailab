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

defmodule Msfailab.LLM.Providers.Anthropic do
  @moduledoc """
  Anthropic provider implementation.

  Requires MSFAILAB_ANTHROPIC_API_KEY environment variable.
  Context windows are hardcoded since all Claude models use 200k.

  ## Architecture

  This module is a thin HTTP transport layer. All business logic for stream
  processing, message transformation, and state management is in the companion
  `Msfailab.LLM.Providers.Anthropic.Core` module, following the Core Module Pattern.

  ## Model Filtering

  Models can be filtered using the MSFAILAB_ANTHROPIC_MODEL_FILTER environment variable.
  Default: `claude-opus-4*,claude-sonnet-4*`. See `Msfailab.LLM.Provider` for filter syntax.

  ## Streaming Chat

  Uses Server-Sent Events (SSE) format with typed events:
  - `message_start` - Initial message metadata
  - `content_block_start` - New content block (text, thinking, or tool_use)
  - `content_block_delta` - Incremental content
  - `content_block_stop` - Block complete
  - `message_delta` - Final stop reason and usage
  - `message_stop` - Stream complete

  ## Tool Support

  Anthropic uses `tool_use` content blocks with `input_schema` for parameters.
  Tool results are sent as `tool_result` blocks in user messages.

  ## Extended Thinking

  Claude models may emit `:thinking` content blocks for extended reasoning.
  These are captured and emitted as separate content blocks.
  """

  @behaviour Msfailab.LLM.Provider

  alias Msfailab.LLM.ChatRequest
  alias Msfailab.LLM.Events
  alias Msfailab.LLM.Model
  alias Msfailab.LLM.Provider
  alias Msfailab.LLM.Providers.Anthropic.Core
  alias Msfailab.Trace

  @base_url "https://api.anthropic.com/v1"
  @api_version "2023-06-01"
  @default_context_window 200_000
  @default_model_filter "claude-opus-4*,claude-sonnet-4*"
  @stream_timeout 300_000

  # Known context windows (all Claude 3+ models use 200k)
  @context_windows %{
    "claude-sonnet-4-5-20250514" => 200_000,
    "claude-opus-4-20250514" => 200_000,
    "claude-3-7-sonnet-20250219" => 200_000,
    "claude-3-5-sonnet-20241022" => 200_000,
    "claude-3-5-haiku-20241022" => 200_000,
    "claude-3-opus-20240229" => 200_000,
    "claude-3-sonnet-20240229" => 200_000,
    "claude-3-haiku-20240307" => 200_000
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

  @doc false
  def list_models(req_opts) do
    merged_opts = Keyword.merge(req_options(), req_opts)

    case Req.get(@base_url <> "/models", [headers: auth_headers()] ++ merged_opts) do
      {:ok, %{status: 200, body: %{"data" => models}}} ->
        filtered =
          models
          |> Enum.filter(&supported_model?/1)
          |> Enum.map(&to_model/1)
          |> Provider.filter_models("MSFAILAB_ANTHROPIC_MODEL_FILTER", @default_model_filter)

        {:ok, filtered}

      {:ok, %{status: 401}} ->
        {:error, :invalid_api_key}

      {:ok, %{status: status}} ->
        {:error, {:unexpected_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp supported_model?(%{"type" => "model", "id" => id}) do
    String.starts_with?(id, "claude-")
  end

  defp supported_model?(_), do: false

  defp to_model(%{"id" => id}) do
    %Model{
      name: id,
      provider: :anthropic,
      context_window: context_window_for(id)
    }
  end

  defp context_window_for(model_id) do
    Map.get(@context_windows, model_id, @default_context_window)
  end

  # ============================================================================
  # Internal: Chat Streaming
  # ============================================================================

  @doc false
  def run_chat_stream(%ChatRequest{} = request, caller, ref, req_opts) do
    body = Core.build_request_body(request)
    url = @base_url <> "/messages"

    opts =
      req_options()
      |> Keyword.merge(req_opts)
      |> Keyword.put(:json, body)
      |> Keyword.put(:headers, auth_headers())
      |> Keyword.put(:into, build_stream_collector(caller, ref, body, url))
      |> Keyword.put(:receive_timeout, @stream_timeout)

    case Req.post(url, opts) do
      {:ok, %{status: 200, body: acc}} ->
        finalize_stream_and_send(acc, caller, ref)
        trace_request(acc, 200)
        :ok

      {:ok, %{status: status, body: acc}} ->
        error_msg = Core.extract_error_message(acc, status)
        recoverable = status in [429, 500, 502, 503, 529]
        trace_request(acc, status)

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

  defp wrap_state_for_req(%{req_resp: {req, resp}} = state) do
    {req, %{resp | body: state}}
  end

  defp process_stream_chunk(data, acc, caller, ref, request_body, url) do
    acc = init_accumulator(acc, request_body, url)

    {events, new_state} = Core.process_chunk(data, acc)
    send_events(events, caller, ref)

    %{new_state | req_resp: acc.req_resp, response_headers: acc.response_headers}
  end

  defp init_accumulator({_req, %{body: %{req_resp: _} = state}}, _request_body, _url) do
    state
  end

  defp init_accumulator({req, resp}, request_body, url) do
    core_state = Core.init_state(request_body, url)

    Map.merge(core_state, %{
      req_resp: {req, resp},
      response_headers: resp.headers
    })
  end

  defp finalize_stream_and_send(acc, caller, ref) do
    {events, _state} = Core.finalize_stream(acc)
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
    [
      {"x-api-key", api_key()},
      {"anthropic-version", @api_version}
    ]
  end

  defp api_key, do: System.get_env("MSFAILAB_ANTHROPIC_API_KEY")

  defp req_options do
    Application.get_env(:msfailab, :llm_req_options, receive_timeout: 10_000)
  end

  defp trace_request(%{} = acc, status) do
    response_body = Core.format_trace_response(acc, status)

    Trace.http(
      :anthropic,
      %{method: "POST", url: acc.request_url, headers: [], body: acc.request_body},
      %{status: status, headers: acc.response_headers, body: response_body}
    )
  end

  # ============================================================================
  # Test Helpers (delegated to Core for testing)
  # ============================================================================

  @doc false
  defdelegate format_trace_response(acc, status), to: Core
end
