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
# Reason: External system boundary module, mocked in tests via DockerAdapterMock
defmodule Msfailab.Containers.DockerAdapter.Api do
  @moduledoc """
  Docker adapter implementation using the Docker Engine API.

  This module communicates with Docker via its REST API, supporting both
  Unix socket connections (local Docker) and TCP connections (remote Docker).

  ## Configuration

  Configure the Docker endpoint in your config:

      # Unix socket (default)
      config :msfailab, :docker_endpoint, "/var/run/docker.sock"

      # Remote TCP (no TLS)
      config :msfailab, :docker_endpoint, "tcp://192.168.1.100:2375"

  ## API Version

  Uses Docker API version 1.47, which is supported by Docker 27.0+.
  """

  @behaviour Msfailab.Containers.DockerAdapter

  require Logger

  @api_version "v1.47"
  @default_socket "/var/run/docker.sock"
  @default_image "msfailab-msfconsole"
  @default_rpc_port 55_553

  @impl true
  @spec start_container(String.t(), map(), pos_integer()) :: {:ok, String.t()} | {:error, term()}
  def start_container(name, labels, rpc_port) do
    image = Application.get_env(:msfailab, :docker_image, @default_image)
    network = Application.get_env(:msfailab, :docker_network, "msfailab")
    rpc_mode = Application.get_env(:msfailab, :docker_rpc_mode, :port_mapping)

    # Add rpc_port to labels for recovery on restart
    labels_with_port = Map.put(labels, "msfailab.rpc_port", to_string(rpc_port))

    create_body =
      %{
        "Image" => image,
        "Labels" => labels_with_port,
        "Tty" => true,
        "OpenStdin" => true,
        "StdinOnce" => false,
        "Cmd" => build_msf_command(rpc_port),
        "ExposedPorts" => %{"#{rpc_port}/tcp" => %{}},
        "HostConfig" => build_host_config(network, rpc_port, rpc_mode)
      }

    Logger.info("Creating Docker container",
      name: name,
      image: image,
      network: network,
      rpc_port: rpc_port
    )

    with {:ok, container_id} <- create_container(name, create_body),
         :ok <- start_created_container(container_id) do
      Logger.info("Started Docker container", container_id: container_id, name: name)
      {:ok, container_id}
    else
      {:error, reason} = error ->
        Logger.error("Failed to start Docker container", name: name, reason: inspect(reason))
        error
    end
  end

  defp build_msf_command(rpc_port) do
    db_url = Application.get_env(:msfailab, :msf_db_url)
    rpc_pass = Application.get_env(:msfailab, :msf_rpc_pass, "secret")

    # Start msfconsole, connect to database, load msgrpc plugin
    msf_commands =
      "db_connect #{db_url}; load msgrpc ServerHost=0.0.0.0 ServerPort=#{rpc_port} Pass=#{rpc_pass}"

    ["msfconsole", "-x", msf_commands]
  end

  defp build_host_config(network, rpc_port, rpc_mode) do
    base_config = %{"NetworkMode" => network}

    case rpc_mode do
      :port_mapping ->
        # Development: map RPC port to random host port
        Map.put(base_config, "PortBindings", %{
          "#{rpc_port}/tcp" => [%{"HostIp" => "127.0.0.1", "HostPort" => ""}]
        })

      :network ->
        # Production: no port mapping, use container network
        base_config
    end
  end

  @impl true
  @spec stop_container(String.t()) :: :ok | {:error, term()}
  def stop_container(container_id) do
    Logger.info("Stopping Docker container", container_id: container_id)

    case request(:post, "/containers/#{container_id}/stop", params: [t: 10]) do
      {:ok, %{status: status}} when status in [204, 304] ->
        # 204 = stopped, 304 = already stopped
        remove_container(container_id)

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status, body: body}} ->
        {:error, {:unexpected_status, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  @spec container_running?(String.t()) :: boolean()
  def container_running?(container_id) do
    case request(:get, "/containers/#{container_id}/json") do
      {:ok, %{status: 200, body: %{"State" => %{"Running" => running}}}} ->
        running

      _ ->
        false
    end
  end

  @impl true
  @spec list_managed_containers() :: {:ok, [map()]} | {:error, term()}
  def list_managed_containers do
    filters = Jason.encode!(%{"label" => ["msfailab.managed=true"]})

    case request(:get, "/containers/json", params: [all: true, filters: filters]) do
      {:ok, %{status: 200, body: containers}} ->
        {:ok, Enum.map(containers, &parse_container_info/1)}

      {:ok, %{status: status, body: body}} ->
        {:error, {:unexpected_status, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  @spec exec(String.t(), String.t()) :: {:ok, String.t(), integer()} | {:error, term()}
  def exec(container_id, command) do
    # Create exec instance
    exec_config = %{
      "AttachStdout" => true,
      "AttachStderr" => true,
      "Cmd" => ["sh", "-c", command]
    }

    with {:ok, exec_id} <- create_exec(container_id, exec_config),
         {:ok, output} <- start_exec(exec_id),
         {:ok, exit_code} <- get_exec_exit_code(exec_id) do
      {:ok, output, exit_code}
    end
  end

  @impl true
  @spec get_rpc_endpoint(String.t()) :: {:ok, map()} | {:error, term()}
  def get_rpc_endpoint(container_id) do
    network = Application.get_env(:msfailab, :docker_network, "msfailab")
    rpc_mode = Application.get_env(:msfailab, :docker_rpc_mode, :port_mapping)

    case request(:get, "/containers/#{container_id}/json") do
      {:ok, %{status: 200, body: body}} ->
        get_endpoint_from_container(body, network, rpc_mode)

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status, body: body}} ->
        {:error, {:unexpected_status, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_endpoint_from_container(body, network, rpc_mode) do
    # Get port from container labels (set when container was started)
    rpc_port = get_rpc_port_from_labels(body)

    cond do
      # Host network mode: access via localhost
      network == "host" ->
        {:ok, %{host: "localhost", port: rpc_port}}

      # Port mapping mode (development): get mapped port
      rpc_mode == :port_mapping ->
        get_mapped_port(body, rpc_port)

      # Bridge network mode: access via container name
      true ->
        name = get_in(body, ["Name"]) || ""
        container_name = String.trim_leading(name, "/")
        {:ok, %{host: container_name, port: rpc_port}}
    end
  end

  defp get_rpc_port_from_labels(body) do
    case get_in(body, ["Config", "Labels", "msfailab.rpc_port"]) do
      nil -> @default_rpc_port
      port_str -> String.to_integer(port_str)
    end
  end

  defp get_mapped_port(body, rpc_port) do
    port_key = "#{rpc_port}/tcp"

    case get_in(body, ["NetworkSettings", "Ports", port_key]) do
      [%{"HostIp" => _host_ip, "HostPort" => host_port} | _] ->
        {:ok, %{host: "localhost", port: String.to_integer(host_port)}}

      _ ->
        {:error, :port_not_mapped}
    end
  end

  # Private functions - Container operations

  defp create_container(name, body) do
    case request(:post, "/containers/create", params: [name: name], json: body) do
      {:ok, %{status: 201, body: %{"Id" => id}}} ->
        {:ok, id}

      {:ok, %{status: 409}} ->
        # Container with this name already exists, try to remove and recreate
        handle_existing_container(name, body)

      {:ok, %{status: status, body: body}} ->
        {:error, {:create_failed, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_existing_container(name, body) do
    Logger.warning("Container already exists, removing and recreating", name: name)

    with :ok <- force_remove_container_by_name(name) do
      case request(:post, "/containers/create", params: [name: name], json: body) do
        {:ok, %{status: 201, body: %{"Id" => id}}} ->
          {:ok, id}

        {:ok, %{status: status, body: body}} ->
          {:error, {:create_failed, status, body}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp force_remove_container_by_name(name) do
    case request(:delete, "/containers/#{name}", params: [force: true]) do
      {:ok, %{status: status}} when status in [204, 404] ->
        :ok

      {:ok, %{status: status, body: body}} ->
        {:error, {:remove_failed, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp start_created_container(container_id) do
    case request(:post, "/containers/#{container_id}/start") do
      {:ok, %{status: status}} when status in [204, 304] ->
        # 204 = started, 304 = already running
        :ok

      {:ok, %{status: status, body: body}} ->
        {:error, {:start_failed, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp remove_container(container_id) do
    case request(:delete, "/containers/#{container_id}", params: [force: true]) do
      {:ok, %{status: status}} when status in [204, 404] ->
        Logger.info("Removed Docker container", container_id: container_id)
        :ok

      {:ok, %{status: status, body: body}} ->
        Logger.warning("Failed to remove Docker container",
          container_id: container_id,
          status: status,
          body: inspect(body)
        )

        # Still return :ok since stop succeeded
        :ok

      {:error, reason} ->
        Logger.warning("Failed to remove Docker container",
          container_id: container_id,
          reason: inspect(reason)
        )

        :ok
    end
  end

  # Private functions - Exec operations

  defp create_exec(container_id, config) do
    case request(:post, "/containers/#{container_id}/exec", json: config) do
      {:ok, %{status: 201, body: %{"Id" => exec_id}}} ->
        {:ok, exec_id}

      {:ok, %{status: 404}} ->
        {:error, :container_not_found}

      {:ok, %{status: 409}} ->
        {:error, :container_paused}

      {:ok, %{status: status, body: body}} ->
        {:error, {:exec_create_failed, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp start_exec(exec_id) do
    start_config = %{"Detach" => false, "Tty" => false}

    case request(:post, "/exec/#{exec_id}/start", json: start_config, raw_response: true) do
      {:ok, %{status: 200, body: output}} ->
        {:ok, clean_exec_output(output)}

      {:ok, %{status: status, body: body}} ->
        {:error, {:exec_start_failed, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_exec_exit_code(exec_id) do
    case request(:get, "/exec/#{exec_id}/json") do
      {:ok, %{status: 200, body: %{"ExitCode" => exit_code}}} ->
        {:ok, exit_code}

      {:ok, %{status: 200, body: %{"Running" => true}}} ->
        # Exec is still running, shouldn't happen after start_exec completes
        {:error, :exec_still_running}

      {:ok, %{status: 404}} ->
        {:error, :exec_not_found}

      {:ok, %{status: status, body: body}} ->
        {:error, {:exec_inspect_failed, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp clean_exec_output(output) when is_binary(output) do
    # Docker exec output includes stream headers (8 bytes per frame)
    # Format: [STREAM_TYPE(1), 0, 0, 0, SIZE(4)] + DATA
    # We need to strip these headers for clean output
    strip_docker_stream_headers(output)
  end

  defp clean_exec_output(output), do: to_string(output)

  defp strip_docker_stream_headers(<<>>), do: ""

  defp strip_docker_stream_headers(<<_type::8, 0, 0, 0, size::32-big, rest::binary>>) do
    case rest do
      <<data::binary-size(size), remaining::binary>> ->
        data <> strip_docker_stream_headers(remaining)

      _ ->
        # Incomplete frame, return what we have
        rest
    end
  end

  defp strip_docker_stream_headers(data), do: data

  # Private functions - Response parsing

  defp parse_container_info(container) do
    %{
      id: container["Id"],
      name: parse_container_name(container["Names"]),
      status: parse_container_status(container["State"]),
      labels: container["Labels"] || %{}
    }
  end

  defp parse_container_name([name | _]) do
    # Docker prefixes container names with "/"
    String.trim_leading(name, "/")
  end

  defp parse_container_name(_), do: "unknown"

  defp parse_container_status("running"), do: :running
  defp parse_container_status("exited"), do: :exited
  defp parse_container_status("created"), do: :created
  defp parse_container_status("paused"), do: :paused
  defp parse_container_status("dead"), do: :dead
  defp parse_container_status(_), do: :unknown

  # Private functions - HTTP client

  defp request(method, path, opts \\ []) do
    endpoint = Application.get_env(:msfailab, :docker_endpoint, @default_socket)
    params = Keyword.get(opts, :params, [])
    json_body = Keyword.get(opts, :json)
    raw_response = Keyword.get(opts, :raw_response, false)

    req_opts =
      build_base_req_opts(endpoint, path, method, params)
      |> maybe_add_json_body(json_body)
      |> maybe_add_raw_decode(raw_response)

    case Req.request(req_opts) do
      {:ok, response} ->
        {:ok, response}

      {:error, %Req.TransportError{reason: reason}} ->
        {:error, {:transport_error, reason}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_base_req_opts("tcp://" <> host_port, path, method, params) do
    # TCP connection to remote Docker daemon
    [
      url: "http://#{host_port}/#{@api_version}#{path}",
      method: method,
      params: params
    ]
  end

  defp build_base_req_opts(socket_path, path, method, params) do
    # Unix socket connection - use Req's unix_socket option
    [
      url: "http://localhost/#{@api_version}#{path}",
      method: method,
      params: params,
      unix_socket: socket_path
    ]
  end

  defp maybe_add_json_body(opts, nil), do: opts
  defp maybe_add_json_body(opts, body), do: Keyword.put(opts, :json, body)

  defp maybe_add_raw_decode(opts, false), do: opts

  defp maybe_add_raw_decode(opts, true) do
    # Disable JSON decoding for raw responses (exec output)
    Keyword.put(opts, :decode_body, false)
  end
end

# coveralls-ignore-stop
