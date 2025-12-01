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

# coveralls-ignore-start
# Reason: External system boundary module, mocked in tests via MsgrpcClientMock
defmodule Msfailab.Containers.Msgrpc.Client.Http do
  @moduledoc """
  HTTP implementation of the MSGRPC client.

  Communicates with Metasploit Framework via its RPC API using
  MessagePack encoding over HTTP POST.
  """

  @behaviour Msfailab.Containers.Msgrpc.Client

  @default_username "msf"

  @impl true
  @spec login(map(), String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def login(endpoint, password, username \\ @default_username) do
    case call_raw(endpoint, "auth.login", [username, password]) do
      {:ok, %{"result" => "success", "token" => token}} ->
        {:ok, token}

      {:ok, %{"error" => true, "error_message" => message}} ->
        {:error, {:auth_failed, message}}

      {:ok, response} ->
        {:error, {:unexpected_response, response}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  @spec call(map(), String.t(), String.t(), list()) :: {:ok, map()} | {:error, term()}
  def call(endpoint, token, method, args) do
    call_raw(endpoint, method, [token | args])
  end

  @impl true
  @spec console_create(map(), String.t()) :: {:ok, map()} | {:error, term()}
  def console_create(endpoint, token) do
    case call(endpoint, token, "console.create", []) do
      {:ok, %{"id" => _id} = console} ->
        {:ok, console}

      {:ok, %{"error" => true, "error_message" => message}} ->
        {:error, {:console_create_failed, message}}

      result ->
        result
    end
  end

  @impl true
  @spec console_destroy(map(), String.t(), String.t()) :: :ok | {:error, term()}
  def console_destroy(endpoint, token, console_id) do
    case call(endpoint, token, "console.destroy", [console_id]) do
      {:ok, %{"result" => "success"}} ->
        :ok

      {:ok, %{"error" => true, "error_message" => message}} ->
        {:error, {:console_destroy_failed, message}}

      {:error, reason} ->
        {:error, reason}

      {:ok, _} ->
        :ok
    end
  end

  @impl true
  @spec console_write(map(), String.t(), String.t(), String.t()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def console_write(endpoint, token, console_id, data) do
    case call(endpoint, token, "console.write", [console_id, data]) do
      {:ok, %{"wrote" => wrote}} ->
        {:ok, wrote}

      {:ok, %{"error" => true, "error_message" => message}} ->
        {:error, {:console_write_failed, message}}

      result ->
        result
    end
  end

  @impl true
  @spec console_read(map(), String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def console_read(endpoint, token, console_id) do
    case call(endpoint, token, "console.read", [console_id]) do
      {:ok, %{"data" => _data, "busy" => _busy} = result} ->
        {:ok, result}

      {:ok, %{"error" => true, "error_message" => message}} ->
        {:error, {:console_read_failed, message}}

      result ->
        result
    end
  end

  # Private functions

  defp call_raw(endpoint, method, args) do
    url = build_url(endpoint)
    body = encode_request(method, args)

    case Req.post(url, body: body, headers: [{"content-type", "binary/message-pack"}]) do
      {:ok, %Req.Response{status: 200, body: response_body}} ->
        decode_response(response_body)

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  defp build_url(%{host: host, port: port}) do
    "http://#{host}:#{port}/api/"
  end

  defp encode_request(method, args) do
    [method | args]
    |> Msgpax.pack!(iodata: false)
  end

  defp decode_response(body) when is_binary(body) do
    case Msgpax.unpack(body) do
      {:ok, decoded} ->
        {:ok, decoded}

      {:error, reason} ->
        {:error, {:decode_failed, reason}}
    end
  end

  defp decode_response(body) do
    # Already decoded (shouldn't happen but handle it)
    {:ok, body}
  end
end

# coveralls-ignore-stop
