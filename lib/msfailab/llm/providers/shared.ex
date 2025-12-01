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

defmodule Msfailab.LLM.Providers.Shared do
  @moduledoc """
  Shared utilities for LLM providers.

  This module contains common functions used across multiple provider implementations
  to reduce code duplication and ensure consistent error handling.
  """

  @doc """
  Extract error message from response body or buffer.

  Handles various response formats:
  - State map with buffer field
  - Map with nested error message (Anthropic format)
  - Map with top-level error string (Ollama format)
  - JSON string body
  - Raw string body

  Falls back to "HTTP {status}" when no error message is found.
  """
  @spec extract_error_message(map() | String.t(), non_neg_integer()) :: String.t()
  def extract_error_message(%{buffer: buffer}, status) when is_binary(buffer) and buffer != "" do
    extract_error_message(buffer, status)
  end

  def extract_error_message(body, status) when is_map(body) do
    # Use Map.get instead of Access syntax to support both maps and structs
    case Map.get(body, "error") do
      # Anthropic format: nested map with "message" key
      %{"message" => message} when is_binary(message) -> message
      # Ollama format: top-level error string
      error when is_binary(error) -> error
      # Fallback
      _ -> "HTTP #{status}"
    end
  end

  def extract_error_message(body, status) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, parsed} -> extract_error_message(parsed, status)
      {:error, _} -> "HTTP #{status}"
    end
  end

  def extract_error_message(_body, status), do: "HTTP #{status}"

  @doc """
  Check if an error is recoverable (transient network issues).

  Transport errors from Req and Mint are considered recoverable since
  they typically indicate network issues that may resolve on retry.
  """
  @spec recoverable_error?(term()) :: boolean()
  def recoverable_error?(error) when is_exception(error) do
    error.__struct__ in [Req.TransportError, Mint.TransportError]
  end

  def recoverable_error?(_), do: false

  @doc """
  Format data as pretty-printed JSON.

  Falls back to `inspect/2` with pretty printing if JSON encoding fails.
  """
  @spec format_json(term()) :: String.t()
  def format_json(data) do
    case Jason.encode(data, pretty: true) do
      {:ok, json} -> json
      {:error, _} -> inspect(data, pretty: true)
    end
  end

  @doc """
  Extract raw error body from state for trace logging.

  Attempts to pretty-print JSON if the raw body is valid JSON.
  """
  @spec extract_raw_error_body(map()) :: String.t() | nil
  def extract_raw_error_body(%{raw_body: raw_body})
      when is_binary(raw_body) and raw_body != "" do
    case Jason.decode(raw_body) do
      {:ok, parsed} -> format_json(parsed)
      {:error, _} -> raw_body
    end
  end

  def extract_raw_error_body(_), do: nil
end
