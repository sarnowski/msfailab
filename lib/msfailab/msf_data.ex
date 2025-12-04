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

defmodule Msfailab.MsfData do
  @moduledoc """
  Context for querying the Metasploit Framework database tables.

  All queries are scoped to a workspace for security isolation. The workspace
  is identified by its name, which has a 1:1 mapping to msfailab workspace slugs.

  ## Available Functions

  | Function | Description |
  |----------|-------------|
  | `list_hosts/2` | Query discovered hosts |
  | `list_services/2` | Query network services |
  | `list_vulns/2` | Query vulnerabilities |
  | `list_creds/2` | Query captured credentials |
  | `list_loots/2` | Query captured artifacts |
  | `list_notes/2` | Query research notes |
  | `list_sessions/2` | Query session history |
  | `get_loot_content/3` | Retrieve loot file contents |
  | `create_note/2` | Create a new research note |

  ## Workspace Scoping

  All queries are scoped to a workspace. The workspace is identified by name
  which corresponds to the msfailab workspace slug:

      {:ok, result} = MsfData.list_hosts("my-workspace")

  ## Filter Support

  All list functions accept an optional filters map:

      {:ok, result} = MsfData.list_hosts("my-workspace", %{
        state: "alive",
        os: "Windows",
        limit: 50
      })
  """

  import Ecto.Query

  alias Msfailab.MsfData.{Cred, Host, Loot, MsfWorkspace, Note, Service, Session, Vuln}
  alias Msfailab.Repo

  @default_limit 50
  @max_limit 200

  # ============================================================================
  # Workspace Mapping
  # ============================================================================

  @doc """
  Returns the MSF workspace ID for a given workspace name.

  ## Parameters

  - `workspace_name` - The workspace name (matches msfailab slug)

  ## Returns

  - `{:ok, workspace_id}` on success
  - `{:error, :workspace_not_found}` if workspace doesn't exist

  ## Example

      iex> MsfData.get_msf_workspace_id("my-project")
      {:ok, 1}
  """
  @spec get_msf_workspace_id(String.t()) :: {:ok, integer()} | {:error, :workspace_not_found}
  def get_msf_workspace_id(workspace_name) do
    case Repo.get_by(MsfWorkspace, name: workspace_name) do
      nil -> {:error, :workspace_not_found}
      workspace -> {:ok, workspace.id}
    end
  end

  # ============================================================================
  # Count Assets
  # ============================================================================

  @typedoc "Asset counts map returned by count_assets/1 and count_assets/2"
  @type asset_counts :: %{
          hosts: non_neg_integer(),
          services: non_neg_integer(),
          vulns: non_neg_integer(),
          notes: non_neg_integer(),
          creds: non_neg_integer(),
          loots: non_neg_integer(),
          sessions: non_neg_integer(),
          total: non_neg_integer()
        }

  @doc """
  Counts all assets in a workspace.

  Returns counts for each asset type plus a total.

  ## Parameters

  - `workspace_name` - The workspace name

  ## Returns

  - `{:ok, counts}` where counts is a map with keys:
    - `:hosts` - Number of discovered hosts
    - `:services` - Number of network services
    - `:vulns` - Number of vulnerabilities
    - `:notes` - Number of notes
    - `:creds` - Number of credentials
    - `:loots` - Number of loot entries
    - `:sessions` - Number of sessions
    - `:total` - Sum of all counts
  - `{:error, :workspace_not_found}` if workspace doesn't exist

  ## Example

      iex> MsfData.count_assets("my-project")
      {:ok, %{hosts: 12, services: 47, vulns: 23, notes: 8, creds: 3, loots: 1, sessions: 2, total: 96}}
  """
  @spec count_assets(String.t()) :: {:ok, asset_counts()} | {:error, :workspace_not_found}
  def count_assets(workspace_name) do
    count_assets(workspace_name, nil)
  end

  @doc """
  Counts assets in a workspace with optional search filter.

  When a search term is provided, only assets matching the search term
  in their searchable fields are counted.

  ## Parameters

  - `workspace_name` - The workspace name
  - `search_term` - Optional search term (nil or empty string returns all)

  ## Search Fields by Asset Type

  - **Hosts**: address, name, os_name, info, comments
  - **Services**: name, info
  - **Vulns**: name, info
  - **Notes**: ntype, data
  - **Creds**: user, proof
  - **Loots**: name, info, ltype
  - **Sessions**: desc, via_exploit

  ## Returns

  Same as `count_assets/1`

  ## Example

      iex> MsfData.count_assets("my-project", "apache")
      {:ok, %{hosts: 3, services: 5, vulns: 7, notes: 2, creds: 0, loots: 0, sessions: 0, total: 17}}
  """
  @spec count_assets(String.t(), String.t() | nil) ::
          {:ok, asset_counts()} | {:error, :workspace_not_found}
  def count_assets(workspace_name, search_term) do
    with {:ok, workspace_id} <- get_msf_workspace_id(workspace_name) do
      search_term = normalize_search_term(search_term)

      hosts = count_hosts(workspace_id, search_term)
      services = count_services(workspace_id, search_term)
      vulns = count_vulns(workspace_id, search_term)
      notes = count_notes(workspace_id, search_term)
      creds = count_creds(workspace_id, search_term)
      loots = count_loots(workspace_id, search_term)
      sessions = count_sessions(workspace_id, search_term)

      total = hosts + services + vulns + notes + creds + loots + sessions

      {:ok,
       %{
         hosts: hosts,
         services: services,
         vulns: vulns,
         notes: notes,
         creds: creds,
         loots: loots,
         sessions: sessions,
         total: total
       }}
    end
  end

  defp normalize_search_term(nil), do: nil
  defp normalize_search_term(""), do: nil
  defp normalize_search_term(term) when is_binary(term), do: term

  defp count_hosts(workspace_id, nil) do
    from(h in Host, where: h.workspace_id == ^workspace_id, select: count(h.id))
    |> Repo.one()
  end

  defp count_hosts(workspace_id, search_term) do
    pattern = "%#{search_term}%"

    from(h in Host,
      where: h.workspace_id == ^workspace_id,
      where:
        ilike(fragment("?::text", h.address), ^pattern) or
          ilike(h.name, ^pattern) or
          ilike(h.os_name, ^pattern) or
          ilike(h.info, ^pattern) or
          ilike(h.comments, ^pattern),
      select: count(h.id)
    )
    |> Repo.one()
  end

  defp count_services(workspace_id, nil) do
    from(s in Service,
      join: h in Host,
      on: s.host_id == h.id,
      where: h.workspace_id == ^workspace_id,
      select: count(s.id)
    )
    |> Repo.one()
  end

  defp count_services(workspace_id, search_term) do
    pattern = "%#{search_term}%"

    from(s in Service,
      join: h in Host,
      on: s.host_id == h.id,
      where: h.workspace_id == ^workspace_id,
      where: ilike(s.name, ^pattern) or ilike(s.info, ^pattern),
      select: count(s.id)
    )
    |> Repo.one()
  end

  defp count_vulns(workspace_id, nil) do
    from(v in Vuln,
      join: h in Host,
      on: v.host_id == h.id,
      where: h.workspace_id == ^workspace_id,
      select: count(v.id)
    )
    |> Repo.one()
  end

  defp count_vulns(workspace_id, search_term) do
    pattern = "%#{search_term}%"

    from(v in Vuln,
      join: h in Host,
      on: v.host_id == h.id,
      where: h.workspace_id == ^workspace_id,
      where: ilike(v.name, ^pattern) or ilike(v.info, ^pattern),
      select: count(v.id)
    )
    |> Repo.one()
  end

  defp count_notes(workspace_id, nil) do
    from(n in Note, where: n.workspace_id == ^workspace_id, select: count(n.id))
    |> Repo.one()
  end

  defp count_notes(workspace_id, search_term) do
    pattern = "%#{search_term}%"

    from(n in Note,
      where: n.workspace_id == ^workspace_id,
      where: ilike(n.ntype, ^pattern) or ilike(n.data, ^pattern),
      select: count(n.id)
    )
    |> Repo.one()
  end

  defp count_creds(workspace_id, nil) do
    from(c in Cred,
      join: s in Service,
      on: c.service_id == s.id,
      join: h in Host,
      on: s.host_id == h.id,
      where: h.workspace_id == ^workspace_id,
      select: count(c.id)
    )
    |> Repo.one()
  end

  defp count_creds(workspace_id, search_term) do
    pattern = "%#{search_term}%"

    from(c in Cred,
      join: s in Service,
      on: c.service_id == s.id,
      join: h in Host,
      on: s.host_id == h.id,
      where: h.workspace_id == ^workspace_id,
      where: ilike(c.user, ^pattern) or ilike(c.proof, ^pattern),
      select: count(c.id)
    )
    |> Repo.one()
  end

  defp count_loots(workspace_id, nil) do
    from(l in Loot, where: l.workspace_id == ^workspace_id, select: count(l.id))
    |> Repo.one()
  end

  defp count_loots(workspace_id, search_term) do
    pattern = "%#{search_term}%"

    from(l in Loot,
      where: l.workspace_id == ^workspace_id,
      where: ilike(l.name, ^pattern) or ilike(l.info, ^pattern) or ilike(l.ltype, ^pattern),
      select: count(l.id)
    )
    |> Repo.one()
  end

  defp count_sessions(workspace_id, nil) do
    from(s in Session,
      join: h in Host,
      on: s.host_id == h.id,
      where: h.workspace_id == ^workspace_id,
      select: count(s.id)
    )
    |> Repo.one()
  end

  defp count_sessions(workspace_id, search_term) do
    pattern = "%#{search_term}%"

    from(s in Session,
      join: h in Host,
      on: s.host_id == h.id,
      where: h.workspace_id == ^workspace_id,
      where: ilike(s.desc, ^pattern) or ilike(s.via_exploit, ^pattern),
      select: count(s.id)
    )
    |> Repo.one()
  end

  # ============================================================================
  # List Hosts
  # ============================================================================

  @doc """
  Lists hosts in a workspace with optional filters.

  ## Parameters

  - `workspace_name` - The workspace name
  - `filters` - Optional filter map:
    - `:address` - Filter by IP address (exact match)
    - `:os` - Filter by OS name (case-insensitive partial match)
    - `:state` - Filter by state ("alive", "down", "unknown")
    - `:search` - Search in hostname, comments, and info
    - `:sort_by` - Field to sort by (:address, :name, :os_name, :state, :updated_at)
    - `:sort_dir` - Sort direction (:asc or :desc, default: :desc)
    - `:offset` - Number of records to skip (for pagination)
    - `:limit` - Maximum results (default: 50, max: 200)

  ## Returns

  - `{:ok, %{count: n, total_count: n, hosts: [...]}}` on success
  - `{:error, :workspace_not_found}` if workspace doesn't exist
  """
  @spec list_hosts(String.t(), map()) :: {:ok, map()} | {:error, atom()}
  def list_hosts(workspace_name, filters \\ %{}) do
    with {:ok, workspace_id} <- get_msf_workspace_id(workspace_name) do
      limit = normalize_limit(filters[:limit])
      offset = normalize_offset(filters[:offset])
      {sort_field, sort_dir} = normalize_sort(filters, :updated_at)

      base_query =
        from(h in Host,
          where: h.workspace_id == ^workspace_id
        )
        |> apply_host_filters(filters)

      # Get total count before pagination
      total_count = Repo.aggregate(base_query, :count, :id)

      # Apply sorting and pagination
      query =
        base_query
        |> apply_sort(sort_field, sort_dir)
        |> offset(^offset)
        |> limit(^limit)

      hosts = Repo.all(query)

      result = %{
        count: length(hosts),
        total_count: total_count,
        hosts: Enum.map(hosts, &serialize_host/1)
      }

      {:ok, result}
    end
  end

  defp apply_host_filters(query, filters) do
    query
    |> maybe_filter_by(:address, filters[:address], fn q, v ->
      where(q, [h], h.address == ^v)
    end)
    |> maybe_filter_by(:os, filters[:os], fn q, v ->
      pattern = "%#{v}%"
      where(q, [h], ilike(h.os_name, ^pattern) or ilike(h.os_family, ^pattern))
    end)
    |> maybe_filter_by(:state, filters[:state], fn q, v ->
      where(q, [h], h.state == ^v)
    end)
    |> maybe_filter_by(:search, filters[:search], fn q, v ->
      pattern = "%#{v}%"

      where(
        q,
        [h],
        ilike(h.name, ^pattern) or ilike(h.comments, ^pattern) or ilike(h.info, ^pattern)
      )
    end)
  end

  defp serialize_host(host) do
    %{
      id: host.id,
      address: format_inet(host.address),
      mac: host.mac,
      name: host.name,
      state: host.state,
      os_name: host.os_name,
      os_flavor: host.os_flavor,
      os_sp: host.os_sp,
      os_family: host.os_family,
      arch: host.arch,
      purpose: host.purpose,
      info: host.info,
      comments: host.comments,
      created_at: host.created_at,
      updated_at: host.updated_at
    }
  end

  # Converts INET types to string (EctoNetwork.INET returns Postgrex.INET structs)
  defp format_inet(nil), do: nil
  defp format_inet(%Postgrex.INET{} = inet), do: to_string(inet)
  defp format_inet(address) when is_binary(address), do: address

  # ============================================================================
  # Get Host
  # ============================================================================

  @doc """
  Gets a single host by ID with related asset counts.

  ## Parameters

  - `workspace_name` - The workspace name
  - `host_id` - The host ID

  ## Returns

  - `{:ok, host}` - Host with related counts
  - `{:error, :workspace_not_found}` if workspace doesn't exist
  - `{:error, :not_found}` if host doesn't exist
  """
  @spec get_host(String.t(), integer()) :: {:ok, map()} | {:error, atom()}
  def get_host(workspace_name, host_id) do
    with {:ok, workspace_id} <- get_msf_workspace_id(workspace_name) do
      case Repo.get_by(Host, id: host_id, workspace_id: workspace_id) do
        nil ->
          {:error, :not_found}

        host ->
          # Get related counts
          services_count =
            from(s in Service, where: s.host_id == ^host_id, select: count(s.id))
            |> Repo.one()

          vulns_count =
            from(v in Vuln, where: v.host_id == ^host_id, select: count(v.id))
            |> Repo.one()

          notes_count =
            from(n in Note, where: n.host_id == ^host_id, select: count(n.id))
            |> Repo.one()

          sessions_count =
            from(s in Session, where: s.host_id == ^host_id, select: count(s.id))
            |> Repo.one()

          loots_count =
            from(l in Loot, where: l.host_id == ^host_id, select: count(l.id))
            |> Repo.one()

          host_data =
            host
            |> serialize_host()
            |> Map.put(:services_count, services_count)
            |> Map.put(:vulns_count, vulns_count)
            |> Map.put(:notes_count, notes_count)
            |> Map.put(:sessions_count, sessions_count)
            |> Map.put(:loots_count, loots_count)

          {:ok, host_data}
      end
    end
  end

  # ============================================================================
  # List Services
  # ============================================================================

  @doc """
  Lists services in a workspace with optional filters.

  ## Parameters

  - `workspace_name` - The workspace name
  - `filters` - Optional filter map:
    - `:host` - Filter by host IP address
    - `:port` - Filter by port number
    - `:proto` - Filter by protocol ("tcp", "udp")
    - `:state` - Filter by state ("open", "closed", "filtered")
    - `:name` - Filter by service name (e.g., "http", "ssh")
    - `:search` - Search in service info/banner
    - `:sort_by` - Field to sort by (:port, :proto, :state, :name, :updated_at)
    - `:sort_dir` - Sort direction (:asc or :desc, default: :desc)
    - `:offset` - Number of records to skip (for pagination)
    - `:limit` - Maximum results (default: 50, max: 200)

  ## Returns

  - `{:ok, %{count: n, total_count: n, services: [...]}}` on success
  - `{:error, :workspace_not_found}` if workspace doesn't exist
  """
  @spec list_services(String.t(), map()) :: {:ok, map()} | {:error, atom()}
  def list_services(workspace_name, filters \\ %{}) do
    with {:ok, workspace_id} <- get_msf_workspace_id(workspace_name) do
      limit = normalize_limit(filters[:limit])
      offset = normalize_offset(filters[:offset])
      {sort_field, sort_dir} = normalize_sort(filters, :updated_at)

      base_query =
        from(s in Service,
          join: h in Host,
          on: s.host_id == h.id,
          where: h.workspace_id == ^workspace_id,
          select: %{service: s, host_address: h.address}
        )
        |> apply_service_filters(filters)

      # Get total count before pagination
      count_query =
        from(s in Service,
          join: h in Host,
          on: s.host_id == h.id,
          where: h.workspace_id == ^workspace_id
        )
        |> apply_service_filters(filters)

      total_count = Repo.aggregate(count_query, :count, :id)

      # Apply sorting and pagination
      query =
        base_query
        |> apply_service_sort(sort_field, sort_dir)
        |> offset(^offset)
        |> limit(^limit)

      results = Repo.all(query)

      services =
        Enum.map(results, fn %{service: s, host_address: addr} ->
          serialize_service(s, addr)
        end)

      {:ok, %{count: length(services), total_count: total_count, services: services}}
    end
  end

  defp apply_service_filters(query, filters) do
    query
    |> maybe_filter_by(:host, filters[:host], fn q, v ->
      where(q, [s, h], h.address == ^v)
    end)
    |> maybe_filter_by(:port, filters[:port], fn q, v ->
      where(q, [s, h], s.port == ^v)
    end)
    |> maybe_filter_by(:proto, filters[:proto], fn q, v ->
      where(q, [s, h], s.proto == ^v)
    end)
    |> maybe_filter_by(:state, filters[:state], fn q, v ->
      where(q, [s, h], s.state == ^v)
    end)
    |> maybe_filter_by(:name, filters[:name], fn q, v ->
      where(q, [s, h], s.name == ^v)
    end)
    |> maybe_filter_by(:search, filters[:search], fn q, v ->
      pattern = "%#{v}%"
      where(q, [s, h], ilike(s.info, ^pattern))
    end)
  end

  defp apply_service_sort(query, field, :asc) do
    order_by(query, [s, h], asc: field(s, ^field))
  end

  defp apply_service_sort(query, field, :desc) do
    order_by(query, [s, h], desc: field(s, ^field))
  end

  defp serialize_service(service, host_address) do
    %{
      id: service.id,
      host_id: service.host_id,
      host_address: format_inet(host_address),
      port: service.port,
      proto: service.proto,
      state: service.state,
      name: service.name,
      info: service.info,
      created_at: service.created_at,
      updated_at: service.updated_at
    }
  end

  # ============================================================================
  # Get Service
  # ============================================================================

  @doc """
  Gets a single service by ID with host info and related counts.

  ## Parameters

  - `workspace_name` - The workspace name
  - `service_id` - The service ID

  ## Returns

  - `{:ok, service}` - Service with host info and related counts
  - `{:error, :workspace_not_found}` if workspace doesn't exist
  - `{:error, :not_found}` if service doesn't exist
  """
  @spec get_service(String.t(), integer()) :: {:ok, map()} | {:error, atom()}
  def get_service(workspace_name, service_id) do
    with {:ok, workspace_id} <- get_msf_workspace_id(workspace_name) do
      query =
        from(s in Service,
          join: h in Host,
          on: s.host_id == h.id,
          where: s.id == ^service_id and h.workspace_id == ^workspace_id,
          select: %{service: s, host: h}
        )

      case Repo.one(query) do
        nil ->
          {:error, :not_found}

        %{service: service, host: host} ->
          vulns_count =
            from(v in Vuln, where: v.service_id == ^service_id, select: count(v.id))
            |> Repo.one()

          creds_count =
            from(c in Cred, where: c.service_id == ^service_id, select: count(c.id))
            |> Repo.one()

          notes_count =
            from(n in Note, where: n.service_id == ^service_id, select: count(n.id))
            |> Repo.one()

          service_data =
            service
            |> serialize_service(host.address)
            |> Map.put(:host_name, host.name)
            |> Map.put(:host_os, host.os_name)
            |> Map.put(:vulns_count, vulns_count)
            |> Map.put(:creds_count, creds_count)
            |> Map.put(:notes_count, notes_count)

          {:ok, service_data}
      end
    end
  end

  # ============================================================================
  # List Vulns
  # ============================================================================

  @doc """
  Lists vulnerabilities in a workspace with optional filters.

  ## Parameters

  - `workspace_name` - The workspace name
  - `filters` - Optional filter map:
    - `:host` - Filter by host IP address
    - `:service_port` - Filter by service port
    - `:name` - Filter by vulnerability/module name (partial match)
    - `:ref` - Filter by reference (CVE, MSB, EDB)
    - `:search` - Search in name and info
    - `:exploited` - Filter by exploitation status (true/false)
    - `:limit` - Maximum results (default: 50, max: 200)

  ## Returns

  - `{:ok, %{count: n, total_count: n, vulns: [...]}}` on success
  - `{:error, :workspace_not_found}` if workspace doesn't exist
  """
  @spec list_vulns(String.t(), map()) :: {:ok, map()} | {:error, atom()}
  def list_vulns(workspace_name, filters \\ %{}) do
    with {:ok, workspace_id} <- get_msf_workspace_id(workspace_name) do
      limit = normalize_limit(filters[:limit])
      offset = normalize_offset(filters[:offset])

      base_query =
        from(v in Vuln,
          join: h in Host,
          on: v.host_id == h.id,
          where: h.workspace_id == ^workspace_id
        )
        |> apply_vuln_filters(filters)

      # Get total count before pagination
      total_count = Repo.aggregate(base_query, :count, :id)

      query =
        from([v, h] in base_query,
          order_by: [desc: v.updated_at],
          offset: ^offset,
          limit: ^limit,
          preload: [:refs],
          select: %{vuln: v, host_address: h.address}
        )

      results = Repo.all(query)

      vulns =
        Enum.map(results, fn %{vuln: v, host_address: addr} ->
          serialize_vuln(v, addr)
        end)

      {:ok, %{count: length(vulns), total_count: total_count, vulns: vulns}}
    end
  end

  defp apply_vuln_filters(query, filters) do
    query
    |> maybe_filter_by(:host, filters[:host], fn q, v ->
      where(q, [vuln, h], h.address == ^v)
    end)
    |> maybe_filter_by(:service_port, filters[:service_port], fn q, v ->
      from([vuln, h] in q,
        join: s in Service,
        on: vuln.service_id == s.id,
        where: s.port == ^v
      )
    end)
    |> maybe_filter_by(:name, filters[:name], fn q, v ->
      pattern = "%#{v}%"
      where(q, [vuln, h], ilike(vuln.name, ^pattern))
    end)
    |> maybe_filter_by(:search, filters[:search], fn q, v ->
      pattern = "%#{v}%"
      where(q, [vuln, h], ilike(vuln.name, ^pattern) or ilike(vuln.info, ^pattern))
    end)
    |> maybe_filter_by(:exploited, filters[:exploited], fn q, v ->
      if v do
        where(q, [vuln, h], not is_nil(vuln.exploited_at))
      else
        where(q, [vuln, h], is_nil(vuln.exploited_at))
      end
    end)
  end

  defp serialize_vuln(vuln, host_address) do
    %{
      id: vuln.id,
      host_id: vuln.host_id,
      host_address: format_inet(host_address),
      service_id: vuln.service_id,
      name: vuln.name,
      info: vuln.info,
      exploited_at: vuln.exploited_at,
      refs: Enum.map(vuln.refs, & &1.name),
      created_at: vuln.created_at,
      updated_at: vuln.updated_at
    }
  end

  # ============================================================================
  # Get Vuln
  # ============================================================================

  @doc """
  Gets a single vulnerability by ID with host/service info.

  ## Parameters

  - `workspace_name` - The workspace name
  - `vuln_id` - The vulnerability ID

  ## Returns

  - `{:ok, vuln}` - Vulnerability with host and service info
  - `{:error, :workspace_not_found}` if workspace doesn't exist
  - `{:error, :not_found}` if vuln doesn't exist
  """
  @spec get_vuln(String.t(), integer()) :: {:ok, map()} | {:error, atom()}
  def get_vuln(workspace_name, vuln_id) do
    with {:ok, workspace_id} <- get_msf_workspace_id(workspace_name) do
      query =
        from(v in Vuln,
          join: h in Host,
          on: v.host_id == h.id,
          left_join: s in Service,
          on: v.service_id == s.id,
          where: v.id == ^vuln_id and h.workspace_id == ^workspace_id,
          preload: [:refs],
          select: %{vuln: v, host: h, service: s}
        )

      case Repo.one(query) do
        nil ->
          {:error, :not_found}

        %{vuln: vuln, host: host, service: service} ->
          vuln_data =
            vuln
            |> serialize_vuln(host.address)
            |> Map.put(:host_name, host.name)
            |> Map.put(:host_os, host.os_name)

          vuln_data =
            if service do
              vuln_data
              |> Map.put(:service_port, service.port)
              |> Map.put(:service_proto, service.proto)
              |> Map.put(:service_name, service.name)
            else
              vuln_data
            end

          {:ok, vuln_data}
      end
    end
  end

  # ============================================================================
  # List Notes
  # ============================================================================

  @doc """
  Lists notes in a workspace with optional filters.

  ## Parameters

  - `workspace_name` - The workspace name
  - `filters` - Optional filter map:
    - `:host` - Filter by host IP address
    - `:ntype` - Filter by note type (e.g., "agent.observation")
    - `:critical` - Filter by critical flag (true/false)
    - `:search` - Search in note data content
    - `:limit` - Maximum results (default: 50, max: 200)

  ## Returns

  - `{:ok, %{count: n, total_count: n, notes: [...]}}` on success
  - `{:error, :workspace_not_found}` if workspace doesn't exist
  """
  @spec list_notes(String.t(), map()) :: {:ok, map()} | {:error, atom()}
  def list_notes(workspace_name, filters \\ %{}) do
    with {:ok, workspace_id} <- get_msf_workspace_id(workspace_name) do
      limit = normalize_limit(filters[:limit])
      offset = normalize_offset(filters[:offset])

      base_query =
        from(n in Note,
          left_join: h in Host,
          on: n.host_id == h.id,
          where: n.workspace_id == ^workspace_id
        )
        |> apply_note_filters(filters)

      # Get total count before pagination
      total_count = Repo.aggregate(base_query, :count, :id)

      query =
        from([n, h] in base_query,
          order_by: [desc: n.updated_at],
          offset: ^offset,
          limit: ^limit,
          select: %{note: n, host_address: h.address}
        )

      results = Repo.all(query)

      notes =
        Enum.map(results, fn %{note: n, host_address: addr} ->
          serialize_note(n, addr)
        end)

      {:ok, %{count: length(notes), total_count: total_count, notes: notes}}
    end
  end

  defp apply_note_filters(query, filters) do
    query
    |> maybe_filter_by(:host, filters[:host], fn q, v ->
      where(q, [n, h], h.address == ^v)
    end)
    |> maybe_filter_by(:ntype, filters[:ntype], fn q, v ->
      where(q, [n, h], n.ntype == ^v)
    end)
    |> maybe_filter_by(:critical, filters[:critical], fn q, v ->
      where(q, [n, h], n.critical == ^v)
    end)
    |> maybe_filter_by(:search, filters[:search], fn q, v ->
      pattern = "%#{v}%"
      where(q, [n, h], ilike(n.data, ^pattern))
    end)
  end

  defp serialize_note(note, host_address) do
    %{
      id: note.id,
      ntype: note.ntype,
      data: note.data,
      critical: note.critical,
      seen: note.seen,
      host_id: note.host_id,
      host_address: format_inet(host_address),
      service_id: note.service_id,
      vuln_id: note.vuln_id,
      created_at: note.created_at,
      updated_at: note.updated_at
    }
  end

  # ============================================================================
  # Get Note
  # ============================================================================

  @doc """
  Gets a single note by ID with host/service info.

  ## Parameters

  - `workspace_name` - The workspace name
  - `note_id` - The note ID

  ## Returns

  - `{:ok, note}` - Note with host and service info
  - `{:error, :workspace_not_found}` if workspace doesn't exist
  - `{:error, :not_found}` if note doesn't exist
  """
  @spec get_note(String.t(), integer()) :: {:ok, map()} | {:error, atom()}
  def get_note(workspace_name, note_id) do
    with {:ok, workspace_id} <- get_msf_workspace_id(workspace_name) do
      query =
        from(n in Note,
          left_join: h in Host,
          on: n.host_id == h.id,
          left_join: s in Service,
          on: n.service_id == s.id,
          where: n.id == ^note_id and n.workspace_id == ^workspace_id,
          select: %{note: n, host: h, service: s}
        )

      case Repo.one(query) do
        nil ->
          {:error, :not_found}

        %{note: note, host: host, service: service} ->
          note_data =
            note
            |> serialize_note(host && host.address)
            |> Map.put(:host_name, host && host.name)
            |> Map.put(:host_os, host && host.os_name)

          note_data =
            if service do
              note_data
              |> Map.put(:service_port, service.port)
              |> Map.put(:service_proto, service.proto)
              |> Map.put(:service_name, service.name)
            else
              note_data
            end

          {:ok, note_data}
      end
    end
  end

  # ============================================================================
  # List Creds
  # ============================================================================

  @doc """
  Lists credentials in a workspace with optional filters.

  ## Parameters

  - `workspace_name` - The workspace name
  - `filters` - Optional filter map:
    - `:host` - Filter by host IP address
    - `:service_port` - Filter by service port
    - `:service_name` - Filter by service name (e.g., "ssh", "smb")
    - `:user` - Filter by username (partial match)
    - `:ptype` - Filter by credential type
    - `:limit` - Maximum results (default: 50, max: 200)

  ## Returns

  - `{:ok, %{count: n, total_count: n, creds: [...]}}` on success
  - `{:error, :workspace_not_found}` if workspace doesn't exist
  """
  @spec list_creds(String.t(), map()) :: {:ok, map()} | {:error, atom()}
  def list_creds(workspace_name, filters \\ %{}) do
    with {:ok, workspace_id} <- get_msf_workspace_id(workspace_name) do
      limit = normalize_limit(filters[:limit])
      offset = normalize_offset(filters[:offset])

      base_query =
        from(c in Cred,
          join: s in Service,
          on: c.service_id == s.id,
          join: h in Host,
          on: s.host_id == h.id,
          where: h.workspace_id == ^workspace_id
        )
        |> apply_cred_filters(filters)

      # Get total count before pagination
      total_count = Repo.aggregate(base_query, :count, :id)

      query =
        from([c, s, h] in base_query,
          order_by: [desc: c.updated_at],
          offset: ^offset,
          limit: ^limit,
          select: %{cred: c, host_address: h.address, service_port: s.port, service_name: s.name}
        )

      results = Repo.all(query)

      creds =
        Enum.map(results, fn %{
                               cred: c,
                               host_address: addr,
                               service_port: port,
                               service_name: sname
                             } ->
          serialize_cred(c, addr, port, sname)
        end)

      {:ok, %{count: length(creds), total_count: total_count, creds: creds}}
    end
  end

  defp apply_cred_filters(query, filters) do
    query
    |> maybe_filter_by(:host, filters[:host], fn q, v ->
      where(q, [c, s, h], h.address == ^v)
    end)
    |> maybe_filter_by(:service_port, filters[:service_port], fn q, v ->
      where(q, [c, s, h], s.port == ^v)
    end)
    |> maybe_filter_by(:service_name, filters[:service_name], fn q, v ->
      where(q, [c, s, h], s.name == ^v)
    end)
    |> maybe_filter_by(:user, filters[:user], fn q, v ->
      pattern = "%#{v}%"
      where(q, [c, s, h], ilike(c.user, ^pattern))
    end)
    |> maybe_filter_by(:ptype, filters[:ptype], fn q, v ->
      where(q, [c, s, h], c.ptype == ^v)
    end)
  end

  defp serialize_cred(cred, host_address, service_port, service_name) do
    %{
      id: cred.id,
      user: cred.user,
      pass: cred.pass,
      ptype: cred.ptype,
      active: cred.active,
      proof: cred.proof,
      host_address: format_inet(host_address),
      service_port: service_port,
      service_name: service_name,
      created_at: cred.created_at,
      updated_at: cred.updated_at
    }
  end

  # ============================================================================
  # Get Cred
  # ============================================================================

  @doc """
  Gets a single credential by ID with host/service info.

  ## Parameters

  - `workspace_name` - The workspace name
  - `cred_id` - The credential ID

  ## Returns

  - `{:ok, cred}` - Credential with host and service info
  - `{:error, :workspace_not_found}` if workspace doesn't exist
  - `{:error, :not_found}` if credential doesn't exist
  """
  @spec get_cred(String.t(), integer()) :: {:ok, map()} | {:error, atom()}
  def get_cred(workspace_name, cred_id) do
    with {:ok, workspace_id} <- get_msf_workspace_id(workspace_name) do
      query =
        from(c in Cred,
          join: s in Service,
          on: c.service_id == s.id,
          join: h in Host,
          on: s.host_id == h.id,
          where: c.id == ^cred_id and h.workspace_id == ^workspace_id,
          select: %{cred: c, service: s, host: h}
        )

      case Repo.one(query) do
        nil ->
          {:error, :not_found}

        %{cred: cred, service: service, host: host} ->
          cred_data =
            cred
            |> serialize_cred(host.address, service.port, service.name)
            |> Map.put(:host_id, host.id)
            |> Map.put(:host_name, host.name)
            |> Map.put(:host_os, host.os_name)
            |> Map.put(:service_id, service.id)
            |> Map.put(:service_proto, service.proto)
            |> Map.put(:service_info, service.info)

          {:ok, cred_data}
      end
    end
  end

  # ============================================================================
  # List Loots
  # ============================================================================

  @doc """
  Lists loot entries in a workspace with optional filters.

  Returns metadata only - use `get_loot_content/3` to retrieve actual content.

  ## Parameters

  - `workspace_name` - The workspace name
  - `filters` - Optional filter map:
    - `:host` - Filter by host IP address
    - `:ltype` - Filter by loot type (e.g., "windows.hashes")
    - `:search` - Search in loot name and info
    - `:limit` - Maximum results (default: 50, max: 200)

  ## Returns

  - `{:ok, %{count: n, total_count: n, loots: [...]}}` on success
  - `{:error, :workspace_not_found}` if workspace doesn't exist
  """
  @spec list_loots(String.t(), map()) :: {:ok, map()} | {:error, atom()}
  def list_loots(workspace_name, filters \\ %{}) do
    with {:ok, workspace_id} <- get_msf_workspace_id(workspace_name) do
      limit = normalize_limit(filters[:limit])
      offset = normalize_offset(filters[:offset])

      base_query =
        from(l in Loot,
          left_join: h in Host,
          on: l.host_id == h.id,
          where: l.workspace_id == ^workspace_id
        )
        |> apply_loot_filters(filters)

      # Get total count before pagination
      total_count = Repo.aggregate(base_query, :count, :id)

      query =
        from([l, h] in base_query,
          order_by: [desc: l.updated_at],
          offset: ^offset,
          limit: ^limit,
          select: %{loot: l, host_address: h.address}
        )

      results = Repo.all(query)

      loots =
        Enum.map(results, fn %{loot: l, host_address: addr} ->
          serialize_loot(l, addr)
        end)

      {:ok, %{count: length(loots), total_count: total_count, loots: loots}}
    end
  end

  defp apply_loot_filters(query, filters) do
    query
    |> maybe_filter_by(:host, filters[:host], fn q, v ->
      where(q, [l, h], h.address == ^v)
    end)
    |> maybe_filter_by(:ltype, filters[:ltype], fn q, v ->
      where(q, [l, h], l.ltype == ^v)
    end)
    |> maybe_filter_by(:search, filters[:search], fn q, v ->
      pattern = "%#{v}%"
      where(q, [l, h], ilike(l.name, ^pattern) or ilike(l.info, ^pattern))
    end)
  end

  defp serialize_loot(loot, host_address) do
    %{
      id: loot.id,
      ltype: loot.ltype,
      name: loot.name,
      info: loot.info,
      content_type: loot.content_type,
      path: loot.path,
      host_id: loot.host_id,
      host_address: format_inet(host_address),
      created_at: loot.created_at,
      updated_at: loot.updated_at
    }
  end

  # ============================================================================
  # Get Loot
  # ============================================================================

  @doc """
  Gets a single loot entry by ID with host info.

  ## Parameters

  - `workspace_name` - The workspace name
  - `loot_id` - The loot ID

  ## Returns

  - `{:ok, loot}` - Loot with host info
  - `{:error, :workspace_not_found}` if workspace doesn't exist
  - `{:error, :not_found}` if loot doesn't exist
  """
  @spec get_loot(String.t(), integer()) :: {:ok, map()} | {:error, atom()}
  def get_loot(workspace_name, loot_id) do
    with {:ok, workspace_id} <- get_msf_workspace_id(workspace_name) do
      query =
        from(l in Loot,
          left_join: h in Host,
          on: l.host_id == h.id,
          where: l.id == ^loot_id and l.workspace_id == ^workspace_id,
          select: %{loot: l, host: h}
        )

      case Repo.one(query) do
        nil ->
          {:error, :not_found}

        %{loot: loot, host: host} ->
          loot_data =
            loot
            |> serialize_loot(host && host.address)
            |> Map.put(:host_name, host && host.name)
            |> Map.put(:host_os, host && host.os_name)
            |> Map.put(:data, loot.data)

          {:ok, loot_data}
      end
    end
  end

  # ============================================================================
  # List Sessions
  # ============================================================================

  @doc """
  Lists sessions in a workspace with optional filters.

  ## Parameters

  - `workspace_name` - The workspace name
  - `filters` - Optional filter map:
    - `:host` - Filter by host IP address
    - `:stype` - Filter by session type (e.g., "meterpreter", "shell")
    - `:active` - Filter by active status (true = currently open)
    - `:limit` - Maximum results (default: 50, max: 200)

  ## Returns

  - `{:ok, %{count: n, total_count: n, sessions: [...]}}` on success
  - `{:error, :workspace_not_found}` if workspace doesn't exist
  """
  @spec list_sessions(String.t(), map()) :: {:ok, map()} | {:error, atom()}
  def list_sessions(workspace_name, filters \\ %{}) do
    with {:ok, workspace_id} <- get_msf_workspace_id(workspace_name) do
      limit = normalize_limit(filters[:limit])
      offset = normalize_offset(filters[:offset])

      base_query =
        from(s in Session,
          join: h in Host,
          on: s.host_id == h.id,
          where: h.workspace_id == ^workspace_id
        )
        |> apply_session_filters(filters)

      # Get total count before pagination
      total_count = Repo.aggregate(base_query, :count, :id)

      query =
        from([s, h] in base_query,
          order_by: [desc: s.opened_at],
          offset: ^offset,
          limit: ^limit,
          select: %{session: s, host_address: h.address}
        )

      results = Repo.all(query)

      sessions =
        Enum.map(results, fn %{session: s, host_address: addr} ->
          serialize_session(s, addr)
        end)

      {:ok, %{count: length(sessions), total_count: total_count, sessions: sessions}}
    end
  end

  defp apply_session_filters(query, filters) do
    query
    |> maybe_filter_by(:host, filters[:host], fn q, v ->
      where(q, [s, h], h.address == ^v)
    end)
    |> maybe_filter_by(:stype, filters[:stype], fn q, v ->
      where(q, [s, h], s.stype == ^v)
    end)
    |> maybe_filter_by(:active, filters[:active], fn q, v ->
      if v do
        where(q, [s, h], is_nil(s.closed_at))
      else
        where(q, [s, h], not is_nil(s.closed_at))
      end
    end)
  end

  defp serialize_session(session, host_address) do
    %{
      id: session.id,
      stype: session.stype,
      via_exploit: session.via_exploit,
      via_payload: session.via_payload,
      desc: session.desc,
      port: session.port,
      platform: session.platform,
      opened_at: session.opened_at,
      closed_at: session.closed_at,
      host_id: session.host_id,
      host_address: format_inet(host_address)
    }
  end

  # ============================================================================
  # Get Session
  # ============================================================================

  @doc """
  Gets a single session by ID with host info.

  ## Parameters

  - `workspace_name` - The workspace name
  - `session_id` - The session ID

  ## Returns

  - `{:ok, session}` - Session with host info
  - `{:error, :workspace_not_found}` if workspace doesn't exist
  - `{:error, :not_found}` if session doesn't exist
  """
  @spec get_session(String.t(), integer()) :: {:ok, map()} | {:error, atom()}
  def get_session(workspace_name, session_id) do
    with {:ok, workspace_id} <- get_msf_workspace_id(workspace_name) do
      query =
        from(s in Session,
          join: h in Host,
          on: s.host_id == h.id,
          where: s.id == ^session_id and h.workspace_id == ^workspace_id,
          select: %{session: s, host: h}
        )

      case Repo.one(query) do
        nil ->
          {:error, :not_found}

        %{session: session, host: host} ->
          session_data =
            session
            |> serialize_session(host.address)
            |> Map.put(:host_name, host.name)
            |> Map.put(:host_os, host.os_name)

          {:ok, session_data}
      end
    end
  end

  # ============================================================================
  # Get Loot Content
  # ============================================================================

  @doc """
  Retrieves the content of a loot entry.

  ## Parameters

  - `workspace_name` - The workspace name
  - `loot_id` - The loot entry ID
  - `max_size` - Maximum bytes to return (default: 10000, max: 100000)

  ## Returns

  - `{:ok, %{content: "...", truncated: false}}` on success
  - `{:error, :workspace_not_found}` if workspace doesn't exist
  - `{:error, :loot_not_found}` if loot doesn't exist
  - `{:error, :not_text}` if loot is not text-based
  """
  @spec get_loot_content(String.t(), integer(), integer()) :: {:ok, map()} | {:error, atom()}
  def get_loot_content(workspace_name, loot_id, max_size \\ 10_000) do
    max_size = min(max_size, 100_000)

    with {:ok, workspace_id} <- get_msf_workspace_id(workspace_name) do
      case Repo.get_by(Loot, id: loot_id, workspace_id: workspace_id) do
        nil ->
          {:error, :loot_not_found}

        loot ->
          content = loot.data || ""
          truncated = String.length(content) > max_size
          content = if truncated, do: String.slice(content, 0, max_size), else: content

          {:ok, %{content: content, truncated: truncated, loot_id: loot_id}}
      end
    end
  end

  # ============================================================================
  # Create Note
  # ============================================================================

  @doc """
  Creates a new note in the workspace.

  ## Parameters

  - `workspace_name` - The workspace name
  - `attrs` - Note attributes:
    - `:ntype` (required) - Note type, must start with "agent."
    - `:data` (required) - Note content
    - `:host` - Host IP address to attach to (optional)
    - `:service_port` - Service port to attach to (optional, requires host)
    - `:critical` - Mark as critical finding (optional, default: false)

  ## Returns

  - `{:ok, note}` on success
  - `{:error, :workspace_not_found}` if workspace doesn't exist
  - `{:error, :host_not_found}` if host doesn't exist
  - `{:error, changeset}` if validation fails
  """
  @spec create_note(String.t(), map()) :: {:ok, Note.t()} | {:error, atom() | Ecto.Changeset.t()}
  def create_note(workspace_name, attrs) do
    with {:ok, workspace_id} <- get_msf_workspace_id(workspace_name),
         {:ok, host_id} <- resolve_host_id(workspace_id, attrs[:host]),
         {:ok, service_id} <- resolve_service_id(host_id, attrs[:service_port]) do
      note_attrs =
        attrs
        |> Map.put(:workspace_id, workspace_id)
        |> Map.put(:host_id, host_id)
        |> Map.put(:service_id, service_id)
        |> Map.delete(:host)
        |> Map.delete(:service_port)

      %Note{}
      |> Note.create_changeset(note_attrs)
      |> Repo.insert()
    end
  end

  defp resolve_host_id(_workspace_id, nil), do: {:ok, nil}

  defp resolve_host_id(workspace_id, host_address) do
    case Repo.get_by(Host, workspace_id: workspace_id, address: host_address) do
      nil -> {:error, :host_not_found}
      host -> {:ok, host.id}
    end
  end

  defp resolve_service_id(nil, _), do: {:ok, nil}
  defp resolve_service_id(_, nil), do: {:ok, nil}

  defp resolve_service_id(host_id, service_port) do
    case Repo.get_by(Service, host_id: host_id, port: service_port) do
      nil -> {:ok, nil}
      service -> {:ok, service.id}
    end
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp normalize_limit(nil), do: @default_limit
  defp normalize_limit(limit) when is_integer(limit), do: min(limit, @max_limit)
  defp normalize_limit(_), do: @default_limit

  defp normalize_offset(nil), do: 0
  defp normalize_offset(offset) when is_integer(offset) and offset >= 0, do: offset
  defp normalize_offset(_), do: 0

  defp maybe_filter_by(query, _key, nil, _filter_fn), do: query
  defp maybe_filter_by(query, _key, value, filter_fn), do: filter_fn.(query, value)

  @doc false
  defp normalize_sort(filters, default_field) do
    sort_by = filters[:sort_by] || default_field
    sort_dir = filters[:sort_dir] || :desc
    {sort_by, sort_dir}
  end

  @doc false
  defp apply_sort(query, field, :asc) do
    order_by(query, [q], asc: field(q, ^field))
  end

  defp apply_sort(query, field, :desc) do
    order_by(query, [q], desc: field(q, ^field))
  end
end
