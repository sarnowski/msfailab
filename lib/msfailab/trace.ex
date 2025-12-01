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

defmodule Msfailab.Trace do
  @moduledoc """
  Development-only tracing for external system interactions.

  Writes detailed dumps to separate log files for debugging. Each trace type
  has its own file in the `log/` directory. All functions are no-ops outside
  of the `:dev` environment.

  ## Files

  - `log/metasploit.log` - Console commands with prompt, command, and output
  - `log/bash.log` - Shell commands with command, output, and exit code
  - `log/ollama.log` - Full HTTP request/response for Ollama API
  - `log/openai.log` - Full HTTP request/response for OpenAI API
  - `log/anthropic.log` - Full HTTP request/response for Anthropic API
  - `log/events.log` - PubSub event broadcasts with full event content

  ## Usage

      # After a Metasploit command completes
      Trace.metasploit("msf6 >", "db_status", "Connected to database...")

      # After a bash command completes
      Trace.bash("ls -la", "total 42\\n...", 0)

      # After an LLM API call completes
      Trace.http(:ollama, %{method: "POST", url: "...", body: %{}}, %{status: 200, body: %{}})

      # After a PubSub event broadcast
      Trace.event(%ContainerCreated{workspace_id: 1, ...})

  """

  @trace_dir "log"
  @trace_types [:metasploit, :bash, :ollama, :openai, :anthropic, :events]

  @type http_request :: %{
          method: String.t(),
          url: String.t(),
          headers: [{String.t(), String.t()}] | map(),
          body: term()
        }

  @type http_response :: %{
          status: non_neg_integer(),
          headers: [{String.t(), String.t()}] | map(),
          body: term()
        }

  @type http_provider :: :ollama | :openai | :anthropic

  @doc """
  Traces a completed Metasploit console command.

  Records the prompt, command, and full output as a single entry.
  """
  @spec metasploit(prompt :: String.t(), command :: String.t(), output :: String.t()) :: :ok
  def metasploit(prompt, command, output) do
    if enabled?() do
      write(:metasploit, """
      ================================================================================
      [#{timestamp()}]
      PROMPT: #{prompt}
      COMMAND: #{command}
      OUTPUT:
      #{output}
      """)
    end

    :ok
  end

  @doc """
  Traces a completed bash command.

  Records the command, output, and exit code as a single entry.
  """
  @spec bash(command :: String.t(), output :: String.t(), exit_code :: integer()) :: :ok
  def bash(command, output, exit_code) do
    if enabled?() do
      write(:bash, """
      ================================================================================
      [#{timestamp()}] EXIT=#{exit_code}
      COMMAND: #{command}
      OUTPUT:
      #{output}
      """)
    end

    :ok
  end

  @doc """
  Traces a completed HTTP request/response to an LLM provider.

  Records the full request and response including headers and bodies.
  The body is pretty-printed for readability.
  """
  @spec http(provider :: http_provider(), request :: http_request(), response :: http_response()) ::
          :ok
  def http(provider, request, response) when provider in [:ollama, :openai, :anthropic] do
    if enabled?() do
      write(provider, """
      ================================================================================
      [#{timestamp()}] #{request.method} #{request.url}
      REQUEST HEADERS:
      #{format_headers(request[:headers])}
      REQUEST BODY:
      #{format_body(request.body)}
      RESPONSE STATUS: #{response.status}
      RESPONSE HEADERS:
      #{format_headers(response[:headers])}
      RESPONSE BODY:
      #{format_body(response.body)}
      """)
    end

    :ok
  end

  @doc """
  Traces a broadcast event.

  Records the event struct type and full content.
  """
  @spec event(struct()) :: :ok
  def event(event) when is_struct(event) do
    event_type = event.__struct__ |> Module.split() |> List.last()

    if enabled?() do
      write(:events, """
      ================================================================================
      [#{timestamp()}] #{event_type}
      #{format_body(Map.from_struct(event))}
      """)
    end

    :ok
  end

  @doc """
  Resets all trace files.

  Called on application start in dev to truncate files from previous sessions.
  """
  @spec reset_files() :: :ok
  # sobelow_skip ["Traversal.FileModule"]
  def reset_files do
    if enabled?() do
      File.mkdir_p!(@trace_dir)

      for type <- @trace_types do
        path = Path.join(@trace_dir, "#{type}.log")
        File.write!(path, "# Trace log started at #{timestamp()}\n\n")
      end
    end

    :ok
  end

  defp enabled? do
    Application.get_env(:msfailab, :env) == :dev
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp write(type, content) when type in @trace_types do
    path = Path.join(@trace_dir, "#{type}.log")
    File.write!(path, content, [:append])
  end

  defp timestamp do
    DateTime.utc_now() |> DateTime.to_iso8601()
  end

  defp format_headers(nil), do: "(none)"
  defp format_headers(headers) when is_map(headers), do: format_headers(Map.to_list(headers))
  defp format_headers([]), do: "(none)"

  defp format_headers(headers) when is_list(headers) do
    Enum.map_join(headers, "\n", fn {k, v} -> "  #{k}: #{v}" end)
  end

  defp format_body(nil), do: "(empty)"
  defp format_body(""), do: "(empty)"
  defp format_body(body) when is_binary(body), do: body

  defp format_body(body) do
    inspect(body, pretty: true, limit: :infinity, printable_limit: :infinity)
  end
end
