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

defmodule Msfailab.Tools.MsfDataExecutor do
  @moduledoc """
  Executes MSF database tools and returns JSON-serializable results.

  Unlike `msf_command` and `bash_command` which interact with the container,
  these tools execute directly in the Elixir process and return results
  immediately.

  ## Supported Tools

  | Tool | Description |
  |------|-------------|
  | `list_hosts` | Query discovered hosts |
  | `list_services` | Query network services |
  | `list_vulns` | Query vulnerabilities (refs always included) |
  | `list_creds` | Query credentials |
  | `list_loots` | Query captured artifacts |
  | `list_notes` | Query research notes |
  | `list_sessions` | Query session history |
  | `retrieve_loot` | Get loot file contents |
  | `create_note` | Add research note |

  ## Usage

      case MsfDataExecutor.execute("list_hosts", %{"address" => "10.0.0.5"}, %{workspace_slug: "my-project"}) do
        {:ok, result} -> Jason.encode!(result)
        {:error, reason} -> format_error(reason)
      end
  """

  @behaviour Msfailab.Tools.Executor

  alias Msfailab.MsfData

  @msf_data_tools ~w(list_hosts list_services list_vulns list_creds list_loots list_notes list_sessions retrieve_loot create_note)

  @impl true
  @spec handles_tool?(String.t()) :: boolean()
  def handles_tool?(tool_name), do: tool_name in @msf_data_tools

  @doc """
  Execute a tool and return the result.

  ## Parameters

  - `tool_name` - The tool to execute
  - `arguments` - Map of arguments from the LLM
  - `context` - Map with workspace_slug

  ## Returns

  - `{:ok, result}` on success - result is JSON-serializable
  - `{:error, reason}` on failure
  """
  @impl true
  @spec execute(String.t(), map(), map()) :: {:ok, map()} | {:error, term()}

  def execute("list_hosts", args, %{workspace_slug: workspace_slug}) do
    filters = extract_filters(args, [:address, :os, :state, :search, :limit])
    MsfData.list_hosts(workspace_slug, filters)
  end

  def execute("list_services", args, %{workspace_slug: workspace_slug}) do
    filters = extract_filters(args, [:host, :port, :proto, :state, :name, :search, :limit])
    MsfData.list_services(workspace_slug, filters)
  end

  def execute("list_vulns", args, %{workspace_slug: workspace_slug}) do
    filters = extract_filters(args, [:host, :service_port, :name, :search, :exploited, :limit])
    MsfData.list_vulns(workspace_slug, filters)
  end

  def execute("list_creds", args, %{workspace_slug: workspace_slug}) do
    filters = extract_filters(args, [:host, :service_port, :service_name, :user, :ptype, :limit])
    MsfData.list_creds(workspace_slug, filters)
  end

  def execute("list_loots", args, %{workspace_slug: workspace_slug}) do
    filters = extract_filters(args, [:host, :ltype, :search, :limit])
    MsfData.list_loots(workspace_slug, filters)
  end

  def execute("list_notes", args, %{workspace_slug: workspace_slug}) do
    filters = extract_filters(args, [:host, :ntype, :critical, :search, :limit])
    MsfData.list_notes(workspace_slug, filters)
  end

  def execute("list_sessions", args, %{workspace_slug: workspace_slug}) do
    filters = extract_filters(args, [:host, :stype, :active, :limit])
    MsfData.list_sessions(workspace_slug, filters)
  end

  def execute("retrieve_loot", args, %{workspace_slug: workspace_slug}) do
    loot_id = args["loot_id"]
    max_size = args["max_size"] || 10_000
    MsfData.get_loot_content(workspace_slug, loot_id, max_size)
  end

  def execute("create_note", args, %{workspace_slug: workspace_slug}) do
    # Map "content" argument to "data" for MsfData.create_note
    attrs = %{
      ntype: args["ntype"],
      data: args["content"],
      host: args["host"],
      service_port: args["service_port"],
      critical: args["critical"] || false
    }

    case MsfData.create_note(workspace_slug, attrs) do
      {:ok, note} ->
        {:ok,
         %{
           created: true,
           note_id: note.id,
           ntype: note.ntype,
           host_id: note.host_id
         }}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, {:validation_error, format_changeset_errors(changeset)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def execute(unknown_tool, _args, _context) do
    {:error, {:unknown_tool, unknown_tool}}
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp extract_filters(args, allowed_keys) do
    args
    |> Map.take(Enum.map(allowed_keys, &to_string/1))
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      atom_key = String.to_existing_atom(key)
      Map.put(acc, atom_key, value)
    end)
  rescue
    # If key doesn't exist as atom, skip it
    ArgumentError -> %{}
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, &format_error_message/1)
  end

  defp format_error_message({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end
end
