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

defmodule MsfailabWeb.DatabaseBrowser do
  @moduledoc """
  Full-screen modal component for browsing Metasploit database assets.

  Provides a tabbed interface for viewing hosts, services, vulnerabilities,
  notes, credentials, loot, and sessions with global search, sorting,
  filtering, and pagination.
  """
  use Phoenix.Component

  import MsfailabWeb.CoreComponents, only: [icon: 1]

  alias Phoenix.LiveView.JS

  # Asset type definitions with icons and labels
  @asset_types [
    {:hosts, "hero-server", "Hosts"},
    {:services, "hero-globe-alt", "Services"},
    {:vulns, "hero-shield-exclamation", "Vulnerabilities"},
    {:notes, "hero-document-text", "Notes"},
    {:creds, "hero-key", "Credentials"},
    {:loots, "hero-archive-box", "Loot"},
    {:sessions, "hero-command-line", "Sessions"}
  ]

  # coveralls-ignore-start
  # Reason: Pure presentation components - UI templates without business logic

  @doc """
  Renders the full-screen database browser modal.

  ## Attributes

  - `show` - Whether the modal is visible
  - `on_close` - JS command to execute when closing the modal
  - `asset_counts` - Map of asset type to count
  - `active_tab` - Currently active asset type tab (:hosts, :services, etc.)
  - `search_term` - Current search term
  - `on_search` - Event name for search input changes
  - `on_tab_change` - Event name for tab changes

  ## Example

      <.database_browser
        show={@show_database_modal}
        on_close={JS.push("close_database_modal")}
        asset_counts={@asset_counts}
        active_tab={@database_active_tab}
        search_term={@database_search_term}
      />
  """
  attr :show, :boolean, default: false
  attr :on_close, JS, default: %JS{}
  attr :asset_counts, :map, required: true
  attr :active_tab, :atom, default: :hosts
  attr :search_term, :string, default: ""
  attr :on_search, :string, default: "database_search"
  attr :on_tab_change, :string, default: "database_tab_change"
  attr :detail_asset, :map, default: nil
  attr :detail_type, :atom, default: nil
  attr :on_back, :string, default: "database_back"

  # Slots for table content (provided by LiveView)
  slot :table_content

  def database_browser(assigns) do
    assigns = assign(assigns, :asset_types, @asset_types)

    ~H"""
    <!-- Full-screen database browser modal -->
    <div
      id="database-browser-modal"
      class={["modal", @show && "modal-open"]}
      phx-window-keydown={@show && @on_close}
      phx-key="Escape"
    >
      <!-- Modal backdrop -->
      <div class="modal-backdrop bg-base-300/90" phx-click={@on_close} />
      <!-- Full-screen modal content -->
      <div class="fixed inset-4 bg-base-100 rounded-box border-2 border-base-300 flex flex-col overflow-hidden shadow-2xl">
        <!-- Header with tabs -->
        <header class="bg-base-100 border-b-2 border-base-300">
          <nav class="flex items-center h-12 px-4">
            <!-- Left section -->
            <div class="flex items-center flex-1 gap-2">
              <!-- Back button (detail view only) -->
              <button
                :if={@detail_asset}
                type="button"
                class="btn btn-sm btn-ghost gap-1"
                phx-click={@on_back}
              >
                <.icon name="hero-arrow-left" class="size-4" /> Back
              </button>
              <div :if={@detail_asset} class="divider divider-horizontal mx-0 h-6"></div>
              <!-- Database icon -->
              <.icon name="hero-circle-stack" class="size-5 text-primary" />
              <!-- Detail title or asset tabs -->
              <%= if @detail_asset do %>
                <h2 class="text-lg font-bold font-mono">
                  {detail_title(@detail_type, @detail_asset)}
                </h2>
              <% else %>
                <div class="flex items-center gap-1">
                  <.asset_tab
                    :for={{type, icon, label} <- @asset_types}
                    type={type}
                    icon={icon}
                    label={label}
                    count={Map.get(@asset_counts, type, 0)}
                    active={@active_tab == type}
                    on_click={@on_tab_change}
                    highlight_count={@search_term != "" && Map.get(@asset_counts, type, 0) > 0}
                  />
                </div>
              <% end %>
            </div>
            <!-- Right section: Search + Close button -->
            <div class="flex items-center gap-2">
              <!-- Search input (only in list view) -->
              <div :if={!@detail_asset} class="flex-shrink-0 w-72">
                <label class={[
                  "input input-bordered input-sm flex items-center gap-2 bg-base-100",
                  @search_term != "" && "border-primary",
                  @search_term == "" && "border-base-300 focus-within:border-primary"
                ]}>
                  <.icon name="hero-magnifying-glass" class="size-4 text-base-content/50" />
                  <input
                    type="text"
                    placeholder="Search all assets..."
                    class="grow bg-transparent focus:outline-none"
                    value={@search_term}
                    phx-keyup={@on_search}
                    phx-debounce="300"
                    name="search"
                  />
                  <button
                    :if={@search_term != ""}
                    type="button"
                    class="btn btn-ghost btn-xs btn-circle"
                    phx-click={@on_search}
                    phx-value-search=""
                  >
                    <.icon name="hero-x-mark" class="size-3" />
                  </button>
                </label>
              </div>
              <!-- Close button -->
              <button
                type="button"
                class="btn btn-sm btn-circle btn-ghost border border-base-300"
                phx-click={@on_close}
                aria-label="Close"
              >
                <.icon name="hero-x-mark" class="size-5" />
              </button>
            </div>
          </nav>
        </header>
        <!-- Content area -->
        <div class="flex-1 overflow-auto p-6">
          <%= if @detail_asset do %>
            <!-- Detail view -->
            <.asset_detail asset={@detail_asset} type={@detail_type} />
          <% else %>
            <!-- List view -->
            <%= if @table_content != [] do %>
              {render_slot(@table_content)}
            <% else %>
              <.empty_state active_tab={@active_tab} />
            <% end %>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Returns detailed title for asset detail view
  # Host: 192.168.1.1 (hostname)
  defp detail_title(:host, asset) do
    base = "Host: #{asset.address}"
    if asset.name && asset.name != "", do: "#{base} (#{asset.name})", else: base
  end

  # Service: 192.168.1.1 tcp/80 (http)
  defp detail_title(:service, asset) do
    base = "Service: #{asset.host_address} #{asset.proto}/#{asset.port}"
    if asset.name && asset.name != "", do: "#{base} (#{asset.name})", else: base
  end

  # Vuln: 192.168.1.1 - CVE-2021-44228
  defp detail_title(:vuln, asset) do
    "Vuln: #{asset.host_address} - #{truncate(asset.name, 40)}"
  end

  # Note: 192.168.1.1 - host.os.nmap_fingerprint
  defp detail_title(:note, asset) do
    host = asset[:host_address] || "workspace"
    "Note: #{host} - #{asset.ntype}"
  end

  # Cred: 192.168.1.1:22 - root
  defp detail_title(:cred, asset) do
    host_port = "#{asset.host_address}:#{asset.service_port}"
    "Cred: #{host_port} - #{asset.user || "unknown"}"
  end

  # Loot: 192.168.1.1 - /etc/passwd
  defp detail_title(:loot, asset) do
    host = asset[:host_address] || "workspace"
    identifier = asset.name || asset.ltype || "unknown"
    "Loot: #{host} - #{truncate(identifier, 30)}"
  end

  # Session: 192.168.1.1 - meterpreter
  defp detail_title(:session, asset) do
    "Session: #{asset.host_address} - #{asset.stype}"
  end

  defp detail_title(_, _), do: "Asset Details"

  defp truncate(nil, _max), do: ""
  defp truncate(str, max) when byte_size(str) <= max, do: str
  defp truncate(str, max), do: String.slice(str, 0, max) <> "..."

  @doc """
  Renders an asset type tab styled like the workspace header tabs.
  """
  attr :type, :atom, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :count, :integer, required: true
  attr :active, :boolean, default: false
  attr :on_click, :string, required: true
  attr :highlight_count, :boolean, default: false

  def asset_tab(assigns) do
    ~H"""
    <button
      type="button"
      class={[
        "flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-sm font-medium cursor-pointer",
        @active && "bg-base-200 text-base-content",
        !@active && "text-base-content/60 hover:bg-base-200/50 hover:text-base-content"
      ]}
      phx-click={@on_click}
      phx-value-tab={@type}
    >
      <.icon name={@icon} class="size-4" />
      <span class="hidden lg:inline">{@label}</span>
      <span class={[
        "text-xs px-1.5 py-0.5 rounded",
        @highlight_count && "bg-primary text-primary-content",
        !@highlight_count && @active && "bg-base-300",
        !@highlight_count && !@active && "bg-base-300/50"
      ]}>
        {format_number(@count)}
      </span>
    </button>
    """
  end

  @doc """
  Renders the empty state when no assets exist for the selected tab.
  """
  attr :active_tab, :atom, required: true

  def empty_state(assigns) do
    {_type, icon, label} =
      Enum.find(@asset_types, fn {type, _, _} -> type == assigns.active_tab end) ||
        {:hosts, "hero-server", "Hosts"}

    assigns = assigns |> assign(:icon, icon) |> assign(:label, label)

    ~H"""
    <div class="flex flex-col items-center justify-center h-full text-base-content/50">
      <.icon name={@icon} class="size-16 mb-4" />
      <p class="text-lg font-medium">No {@label} found</p>
      <p class="text-sm">Run a scan to discover assets</p>
    </div>
    """
  end

  # Formats a number for display (e.g., 1234 -> "1,234")
  defp format_number(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  defp format_number(_), do: "0"

  # ===========================================================================
  # Asset Table Components
  # ===========================================================================

  @doc """
  Renders a sortable table header cell.
  """
  attr :label, :string, required: true
  attr :sort_field, :atom, required: true
  attr :current_sort, :atom, default: nil
  attr :sort_dir, :atom, default: :asc
  attr :on_sort, :string, default: "database_sort"
  attr :class, :string, default: ""

  def sort_header(assigns) do
    ~H"""
    <th class={["cursor-pointer hover:bg-base-200 select-none", @class]}>
      <button
        type="button"
        class="flex items-center gap-1 w-full"
        phx-click={@on_sort}
        phx-value-field={@sort_field}
      >
        {@label}
        <span class="text-base-content/40">
          <%= cond do %>
            <% @current_sort == @sort_field && @sort_dir == :asc -> %>
              <.icon name="hero-chevron-up" class="size-4" />
            <% @current_sort == @sort_field && @sort_dir == :desc -> %>
              <.icon name="hero-chevron-down" class="size-4" />
            <% true -> %>
              <.icon name="hero-chevron-up-down" class="size-4 opacity-0 group-hover:opacity-100" />
          <% end %>
        </span>
      </button>
    </th>
    """
  end

  @doc """
  Renders the hosts table.
  """
  attr :hosts, :list, required: true
  attr :sort_field, :atom, default: :address
  attr :sort_dir, :atom, default: :asc
  attr :search_term, :string, default: ""
  attr :on_sort, :string, default: "database_sort"
  attr :on_select, :string, default: "database_select"

  def hosts_table(assigns) do
    ~H"""
    <div class="overflow-x-auto">
      <table class="table table-zebra table-sm w-full">
        <thead>
          <tr class="bg-base-200">
            <.sort_header
              label="Address"
              sort_field={:address}
              current_sort={@sort_field}
              sort_dir={@sort_dir}
              on_sort={@on_sort}
            />
            <.sort_header
              label="Name"
              sort_field={:name}
              current_sort={@sort_field}
              sort_dir={@sort_dir}
              on_sort={@on_sort}
            />
            <.sort_header
              label="OS"
              sort_field={:os_name}
              current_sort={@sort_field}
              sort_dir={@sort_dir}
              on_sort={@on_sort}
            />
            <.sort_header
              label="State"
              sort_field={:state}
              current_sort={@sort_field}
              sort_dir={@sort_dir}
              on_sort={@on_sort}
            />
            <.sort_header
              label="Purpose"
              sort_field={:purpose}
              current_sort={@sort_field}
              sort_dir={@sort_dir}
              on_sort={@on_sort}
            />
            <.sort_header
              label="Created"
              sort_field={:created_at}
              current_sort={@sort_field}
              sort_dir={@sort_dir}
              on_sort={@on_sort}
            />
          </tr>
        </thead>
        <tbody>
          <tr
            :for={host <- @hosts}
            class="hover:bg-base-200 cursor-pointer"
            phx-click={@on_select}
            phx-value-type="host"
            phx-value-id={host.id}
          >
            <td class="font-mono">{highlight(host.address, @search_term)}</td>
            <td>{highlight(host.name, @search_term)}</td>
            <td class="truncate max-w-48">{highlight(format_os(host), @search_term)}</td>
            <td><.state_badge state={host.state} /></td>
            <td>{highlight(host.purpose, @search_term)}</td>
            <td class="text-base-content/60">{format_datetime(host.created_at)}</td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @doc """
  Renders the services table.
  """
  attr :services, :list, required: true
  attr :sort_field, :atom, default: :port
  attr :sort_dir, :atom, default: :asc
  attr :search_term, :string, default: ""
  attr :on_sort, :string, default: "database_sort"
  attr :on_select, :string, default: "database_select"

  def services_table(assigns) do
    ~H"""
    <div class="overflow-x-auto">
      <table class="table table-zebra table-sm w-full">
        <thead>
          <tr class="bg-base-200">
            <th>Host</th>
            <.sort_header
              label="Port"
              sort_field={:port}
              current_sort={@sort_field}
              sort_dir={@sort_dir}
              on_sort={@on_sort}
            />
            <.sort_header
              label="Proto"
              sort_field={:proto}
              current_sort={@sort_field}
              sort_dir={@sort_dir}
              on_sort={@on_sort}
            />
            <.sort_header
              label="Name"
              sort_field={:name}
              current_sort={@sort_field}
              sort_dir={@sort_dir}
              on_sort={@on_sort}
            />
            <.sort_header
              label="State"
              sort_field={:state}
              current_sort={@sort_field}
              sort_dir={@sort_dir}
              on_sort={@on_sort}
            />
            <th>Info</th>
          </tr>
        </thead>
        <tbody>
          <tr
            :for={service <- @services}
            class="hover:bg-base-200 cursor-pointer"
            phx-click={@on_select}
            phx-value-type="service"
            phx-value-id={service.id}
          >
            <td class="font-mono">{highlight(service[:host_address], @search_term)}</td>
            <td class="font-mono">{service.port}</td>
            <td>{service.proto}</td>
            <td>{highlight(service.name, @search_term)}</td>
            <td><.state_badge state={service.state} /></td>
            <td class="truncate max-w-48">{highlight(service.info, @search_term)}</td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @doc """
  Renders the vulnerabilities table.
  """
  attr :vulns, :list, required: true
  attr :sort_field, :atom, default: :name
  attr :sort_dir, :atom, default: :asc
  attr :search_term, :string, default: ""
  attr :on_sort, :string, default: "database_sort"
  attr :on_select, :string, default: "database_select"

  def vulns_table(assigns) do
    ~H"""
    <div class="overflow-x-auto">
      <table class="table table-zebra table-sm w-full">
        <thead>
          <tr class="bg-base-200">
            <.sort_header
              label="Name"
              sort_field={:name}
              current_sort={@sort_field}
              sort_dir={@sort_dir}
              on_sort={@on_sort}
              class="min-w-48"
            />
            <th>Host</th>
            <th>Service</th>
            <.sort_header
              label="Exploited"
              sort_field={:exploited_at}
              current_sort={@sort_field}
              sort_dir={@sort_dir}
              on_sort={@on_sort}
            />
            <th>Info</th>
          </tr>
        </thead>
        <tbody>
          <tr
            :for={vuln <- @vulns}
            class="hover:bg-base-200 cursor-pointer"
            phx-click={@on_select}
            phx-value-type="vuln"
            phx-value-id={vuln.id}
          >
            <td class="font-mono truncate max-w-64">{highlight(vuln.name, @search_term)}</td>
            <td class="font-mono">{highlight(vuln[:host_address], @search_term)}</td>
            <td>{vuln[:service_ref] || "-"}</td>
            <td>
              <span :if={vuln.exploited_at} class="badge badge-error badge-sm">Exploited</span>
              <span :if={!vuln.exploited_at} class="text-base-content/40">-</span>
            </td>
            <td class="truncate max-w-48">{highlight(vuln.info, @search_term)}</td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @doc """
  Renders the notes table.
  """
  attr :notes, :list, required: true
  attr :sort_field, :atom, default: :created_at
  attr :sort_dir, :atom, default: :desc
  attr :search_term, :string, default: ""
  attr :on_sort, :string, default: "database_sort"
  attr :on_select, :string, default: "database_select"

  def notes_table(assigns) do
    ~H"""
    <div class="overflow-x-auto">
      <table class="table table-zebra table-sm w-full">
        <thead>
          <tr class="bg-base-200">
            <.sort_header
              label="Type"
              sort_field={:ntype}
              current_sort={@sort_field}
              sort_dir={@sort_dir}
              on_sort={@on_sort}
            />
            <th class="min-w-64">Data</th>
            <th>Host</th>
            <.sort_header
              label="Critical"
              sort_field={:critical}
              current_sort={@sort_field}
              sort_dir={@sort_dir}
              on_sort={@on_sort}
            />
            <.sort_header
              label="Created"
              sort_field={:created_at}
              current_sort={@sort_field}
              sort_dir={@sort_dir}
              on_sort={@on_sort}
            />
          </tr>
        </thead>
        <tbody>
          <tr
            :for={note <- @notes}
            class="hover:bg-base-200 cursor-pointer"
            phx-click={@on_select}
            phx-value-type="note"
            phx-value-id={note.id}
          >
            <td><span class="badge badge-ghost badge-sm font-mono">{note.ntype}</span></td>
            <td class="truncate max-w-96">
              {highlight(truncate_text(note.data, 100), @search_term)}
            </td>
            <td class="font-mono">{highlight(note[:host_address], @search_term)}</td>
            <td>
              <span :if={note.critical} class="badge badge-warning badge-sm">Critical</span>
              <span :if={!note.critical} class="text-base-content/40">-</span>
            </td>
            <td class="text-base-content/60">{format_datetime(note.created_at)}</td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @doc """
  Renders the credentials table.
  """
  attr :creds, :list, required: true
  attr :sort_field, :atom, default: :user
  attr :sort_dir, :atom, default: :asc
  attr :search_term, :string, default: ""
  attr :on_sort, :string, default: "database_sort"
  attr :on_select, :string, default: "database_select"

  def creds_table(assigns) do
    ~H"""
    <div class="overflow-x-auto">
      <table class="table table-zebra table-sm w-full">
        <thead>
          <tr class="bg-base-200">
            <.sort_header
              label="User"
              sort_field={:user}
              current_sort={@sort_field}
              sort_dir={@sort_dir}
              on_sort={@on_sort}
            />
            <.sort_header
              label="Type"
              sort_field={:ptype}
              current_sort={@sort_field}
              sort_dir={@sort_dir}
              on_sort={@on_sort}
            />
            <th>Service</th>
            <.sort_header
              label="Active"
              sort_field={:active}
              current_sort={@sort_field}
              sort_dir={@sort_dir}
              on_sort={@on_sort}
            />
            <th>Proof</th>
          </tr>
        </thead>
        <tbody>
          <tr
            :for={cred <- @creds}
            class="hover:bg-base-200 cursor-pointer"
            phx-click={@on_select}
            phx-value-type="cred"
            phx-value-id={cred.id}
          >
            <td class="font-mono">{highlight(cred.user, @search_term)}</td>
            <td><span class="badge badge-ghost badge-sm">{cred.ptype}</span></td>
            <td class="font-mono">{cred[:service_ref] || "-"}</td>
            <td>
              <span :if={cred.active} class="badge badge-success badge-sm">Active</span>
              <span :if={!cred.active} class="badge badge-ghost badge-sm">Inactive</span>
            </td>
            <td class="truncate max-w-48">{highlight(cred.proof, @search_term)}</td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @doc """
  Renders the loot table.
  """
  attr :loots, :list, required: true
  attr :sort_field, :atom, default: :created_at
  attr :sort_dir, :atom, default: :desc
  attr :search_term, :string, default: ""
  attr :on_sort, :string, default: "database_sort"
  attr :on_select, :string, default: "database_select"

  def loots_table(assigns) do
    ~H"""
    <div class="overflow-x-auto">
      <table class="table table-zebra table-sm w-full">
        <thead>
          <tr class="bg-base-200">
            <.sort_header
              label="Name"
              sort_field={:name}
              current_sort={@sort_field}
              sort_dir={@sort_dir}
              on_sort={@on_sort}
            />
            <.sort_header
              label="Type"
              sort_field={:ltype}
              current_sort={@sort_field}
              sort_dir={@sort_dir}
              on_sort={@on_sort}
            />
            <th>Host</th>
            <.sort_header
              label="Content Type"
              sort_field={:content_type}
              current_sort={@sort_field}
              sort_dir={@sort_dir}
              on_sort={@on_sort}
            />
            <.sort_header
              label="Created"
              sort_field={:created_at}
              current_sort={@sort_field}
              sort_dir={@sort_dir}
              on_sort={@on_sort}
            />
          </tr>
        </thead>
        <tbody>
          <tr
            :for={loot <- @loots}
            class="hover:bg-base-200 cursor-pointer"
            phx-click={@on_select}
            phx-value-type="loot"
            phx-value-id={loot.id}
          >
            <td>{highlight(loot.name, @search_term)}</td>
            <td><span class="badge badge-ghost badge-sm font-mono">{loot.ltype}</span></td>
            <td class="font-mono">{highlight(loot[:host_address], @search_term)}</td>
            <td>{loot.content_type || "-"}</td>
            <td class="text-base-content/60">{format_datetime(loot.created_at)}</td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @doc """
  Renders the sessions table.
  """
  attr :sessions, :list, required: true
  attr :sort_field, :atom, default: :opened_at
  attr :sort_dir, :atom, default: :desc
  attr :search_term, :string, default: ""
  attr :on_sort, :string, default: "database_sort"
  attr :on_select, :string, default: "database_select"

  def sessions_table(assigns) do
    ~H"""
    <div class="overflow-x-auto">
      <table class="table table-zebra table-sm w-full">
        <thead>
          <tr class="bg-base-200">
            <.sort_header
              label="Type"
              sort_field={:stype}
              current_sort={@sort_field}
              sort_dir={@sort_dir}
              on_sort={@on_sort}
            />
            <th>Host</th>
            <.sort_header
              label="Port"
              sort_field={:port}
              current_sort={@sort_field}
              sort_dir={@sort_dir}
              on_sort={@on_sort}
            />
            <.sort_header
              label="Platform"
              sort_field={:platform}
              current_sort={@sort_field}
              sort_dir={@sort_dir}
              on_sort={@on_sort}
            />
            <th>Exploit</th>
            <.sort_header
              label="Opened"
              sort_field={:opened_at}
              current_sort={@sort_field}
              sort_dir={@sort_dir}
              on_sort={@on_sort}
            />
            <th>Status</th>
          </tr>
        </thead>
        <tbody>
          <tr
            :for={session <- @sessions}
            class="hover:bg-base-200 cursor-pointer"
            phx-click={@on_select}
            phx-value-type="session"
            phx-value-id={session.id}
          >
            <td><span class="badge badge-primary badge-sm">{session.stype}</span></td>
            <td class="font-mono">{highlight(session[:host_address], @search_term)}</td>
            <td class="font-mono">{session.port || "-"}</td>
            <td>{highlight(session.platform, @search_term)}</td>
            <td class="truncate max-w-32 font-mono text-xs">
              {highlight(session.via_exploit, @search_term)}
            </td>
            <td class="text-base-content/60">{format_datetime(session.opened_at)}</td>
            <td>
              <span :if={!session.closed_at} class="badge badge-success badge-sm">Active</span>
              <span :if={session.closed_at} class="badge badge-ghost badge-sm">Closed</span>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @doc """
  Renders pagination controls.
  """
  attr :page, :integer, default: 1
  attr :total_pages, :integer, default: 1
  attr :total_count, :integer, default: 0
  attr :page_size, :integer, default: 25
  attr :on_page_change, :string, default: "database_page"

  def pagination(assigns) do
    ~H"""
    <div class="flex items-center justify-between mt-4 text-sm">
      <div class="text-base-content/60">
        Showing {(@page - 1) * @page_size + 1} - {min(@page * @page_size, @total_count)} of {format_number(
          @total_count
        )}
      </div>
      <div class="join">
        <button
          class="join-item btn btn-sm"
          disabled={@page == 1}
          phx-click={@on_page_change}
          phx-value-page={@page - 1}
        >
          <.icon name="hero-chevron-left" class="size-4" />
        </button>
        <button class="join-item btn btn-sm">Page {@page} of {@total_pages}</button>
        <button
          class="join-item btn btn-sm"
          disabled={@page >= @total_pages}
          phx-click={@on_page_change}
          phx-value-page={@page + 1}
        >
          <.icon name="hero-chevron-right" class="size-4" />
        </button>
      </div>
    </div>
    """
  end

  # ===========================================================================
  # Asset Detail Views
  # ===========================================================================

  @doc """
  Renders the appropriate detail view based on asset type.
  """
  attr :asset, :map, required: true
  attr :type, :atom, required: true
  attr :on_navigate, :string, default: "database_navigate"

  def asset_detail(assigns) do
    ~H"""
    <div class="space-y-6">
      <%= case @type do %>
        <% :host -> %>
          <.host_detail asset={@asset} on_navigate={@on_navigate} />
        <% :service -> %>
          <.service_detail asset={@asset} on_navigate={@on_navigate} />
        <% :vuln -> %>
          <.vuln_detail asset={@asset} on_navigate={@on_navigate} />
        <% :note -> %>
          <.note_detail asset={@asset} on_navigate={@on_navigate} />
        <% :cred -> %>
          <.cred_detail asset={@asset} on_navigate={@on_navigate} />
        <% :loot -> %>
          <.loot_detail asset={@asset} on_navigate={@on_navigate} />
        <% :session -> %>
          <.session_detail asset={@asset} on_navigate={@on_navigate} />
        <% _ -> %>
          <div class="text-base-content/50">Unknown asset type</div>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders host detail view.
  """
  attr :asset, :map, required: true
  attr :on_navigate, :string, default: "database_navigate"

  def host_detail(assigns) do
    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
      <!-- Main info card -->
      <div class="card bg-base-200">
        <div class="card-body">
          <h3 class="card-title text-lg">
            <.icon name="hero-server" class="size-5" /> Host Information
          </h3>
          <.detail_grid>
            <.detail_item label="Address" value={@asset.address} mono />
            <.detail_item label="Hostname" value={@asset.name} />
            <.detail_item label="State">
              <.state_badge state={@asset.state} />
            </.detail_item>
            <.detail_item label="MAC Address" value={@asset.mac} mono />
            <.detail_item label="Purpose" value={@asset.purpose} />
            <.detail_item label="Architecture" value={@asset.arch} />
          </.detail_grid>
        </div>
      </div>
      <!-- OS info card -->
      <div class="card bg-base-200">
        <div class="card-body">
          <h3 class="card-title text-lg">
            <.icon name="hero-cpu-chip" class="size-5" /> Operating System
          </h3>
          <.detail_grid>
            <.detail_item label="OS Name" value={@asset.os_name} />
            <.detail_item label="OS Flavor" value={@asset.os_flavor} />
            <.detail_item label="Service Pack" value={@asset.os_sp} />
            <.detail_item label="OS Family" value={@asset.os_family} />
          </.detail_grid>
        </div>
      </div>
      <!-- Additional info -->
      <div :if={@asset.info || @asset.comments} class="card bg-base-200 lg:col-span-2">
        <div class="card-body">
          <h3 class="card-title text-lg">
            <.icon name="hero-information-circle" class="size-5" /> Additional Information
          </h3>
          <div :if={@asset.info} class="mb-4">
            <div class="text-sm text-base-content/60 mb-1">Info</div>
            <div class="font-mono text-sm bg-base-300 p-3 rounded-lg">
              {@asset.info}
            </div>
          </div>
          <div :if={@asset.comments}>
            <div class="text-sm text-base-content/60 mb-1">Comments</div>
            <div class="text-sm bg-base-300 p-3 rounded-lg">
              {@asset.comments}
            </div>
          </div>
        </div>
      </div>
      <!-- Related assets -->
      <div
        :if={has_host_related_assets?(@asset)}
        class="card bg-base-200 lg:col-span-2"
      >
        <div class="card-body">
          <h3 class="card-title text-lg">
            <.icon name="hero-link" class="size-5" /> Related Assets
          </h3>
          <div class="space-y-2 text-sm">
            <.related_asset_row
              :if={@asset[:related_services] && @asset.related_services != []}
              label="Services"
              assets={@asset.related_services}
              type="service"
              format_fn={&format_service_link/1}
              on_navigate={@on_navigate}
            />
            <.related_asset_row
              :if={@asset[:related_vulns] && @asset.related_vulns != []}
              label="Vulns"
              assets={@asset.related_vulns}
              type="vuln"
              format_fn={&format_vuln_link/1}
              on_navigate={@on_navigate}
            />
            <.related_asset_row
              :if={@asset[:related_notes] && @asset.related_notes != []}
              label="Notes"
              assets={@asset.related_notes}
              type="note"
              format_fn={&format_note_link/1}
              on_navigate={@on_navigate}
            />
            <.related_asset_row
              :if={@asset[:related_sessions] && @asset.related_sessions != []}
              label="Sessions"
              assets={@asset.related_sessions}
              type="session"
              format_fn={&format_session_link/1}
              on_navigate={@on_navigate}
            />
            <.related_asset_row
              :if={@asset[:related_loots] && @asset.related_loots != []}
              label="Loots"
              assets={@asset.related_loots}
              type="loot"
              format_fn={&format_loot_link/1}
              on_navigate={@on_navigate}
            />
          </div>
        </div>
      </div>
      <!-- Timestamps -->
      <.timestamp_card created_at={@asset.created_at} updated_at={@asset.updated_at} />
    </div>
    """
  end

  @doc """
  Renders service detail view.
  """
  attr :asset, :map, required: true
  attr :on_navigate, :string, default: "database_navigate"

  def service_detail(assigns) do
    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
      <!-- Main info card -->
      <div class="card bg-base-200">
        <div class="card-body">
          <h3 class="card-title text-lg">
            <.icon name="hero-globe-alt" class="size-5" /> Service Information
          </h3>
          <.detail_grid>
            <.detail_item label="Port" value={@asset.port} mono />
            <.detail_item label="Protocol" value={@asset.proto} />
            <.detail_item label="Service Name" value={@asset.name} />
            <.detail_item label="State">
              <.state_badge state={@asset.state} />
            </.detail_item>
          </.detail_grid>
        </div>
      </div>
      <!-- Host info card -->
      <div class="card bg-base-200">
        <div class="card-body">
          <h3 class="card-title text-lg">
            <.icon name="hero-server" class="size-5" /> Host
          </h3>
          <.detail_grid>
            <.detail_item label="Address">
              <.nav_link
                type="host"
                id={@asset.host_id}
                label={@asset.host_address}
                on_navigate={@on_navigate}
              />
            </.detail_item>
            <.detail_item label="Hostname" value={@asset[:host_name]} />
            <.detail_item label="OS" value={@asset[:host_os]} />
          </.detail_grid>
        </div>
      </div>
      <!-- Service info -->
      <div :if={@asset.info} class="card bg-base-200 lg:col-span-2">
        <div class="card-body">
          <h3 class="card-title text-lg">
            <.icon name="hero-information-circle" class="size-5" /> Banner / Info
          </h3>
          <div class="font-mono text-sm bg-base-300 p-3 rounded-lg">
            {@asset.info}
          </div>
        </div>
      </div>
      <!-- Related assets -->
      <div
        :if={has_service_related_assets?(@asset)}
        class="card bg-base-200 lg:col-span-2"
      >
        <div class="card-body">
          <h3 class="card-title text-lg">
            <.icon name="hero-link" class="size-5" /> Related Assets
          </h3>
          <div class="space-y-2 text-sm">
            <.related_asset_row
              :if={@asset[:related_vulns] && @asset.related_vulns != []}
              label="Vulns"
              assets={@asset.related_vulns}
              type="vuln"
              format_fn={&format_vuln_link/1}
              on_navigate={@on_navigate}
            />
            <.related_asset_row
              :if={@asset[:related_creds] && @asset.related_creds != []}
              label="Creds"
              assets={@asset.related_creds}
              type="cred"
              format_fn={&format_cred_link/1}
              on_navigate={@on_navigate}
            />
            <.related_asset_row
              :if={@asset[:related_notes] && @asset.related_notes != []}
              label="Notes"
              assets={@asset.related_notes}
              type="note"
              format_fn={&format_note_link/1}
              on_navigate={@on_navigate}
            />
          </div>
        </div>
      </div>
      <!-- Timestamps -->
      <.timestamp_card created_at={@asset.created_at} updated_at={@asset.updated_at} />
    </div>
    """
  end

  @doc """
  Renders vulnerability detail view.
  """
  attr :asset, :map, required: true
  attr :on_navigate, :string, default: "database_navigate"

  def vuln_detail(assigns) do
    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
      <!-- Main info card -->
      <div class="card bg-base-200 lg:col-span-2">
        <div class="card-body">
          <h3 class="card-title text-lg">
            <.icon name="hero-shield-exclamation" class="size-5" /> Vulnerability Information
          </h3>
          <.detail_grid cols={3}>
            <.detail_item label="Name" value={@asset.name} mono />
            <.detail_item label="Exploited">
              <span :if={@asset.exploited_at} class="badge badge-error">
                Exploited {format_datetime(@asset.exploited_at)}
              </span>
              <span :if={!@asset.exploited_at} class="text-base-content/50">-</span>
            </.detail_item>
          </.detail_grid>
        </div>
      </div>
      <!-- Host/Service info -->
      <div class="card bg-base-200">
        <div class="card-body">
          <h3 class="card-title text-lg">
            <.icon name="hero-server" class="size-5" /> Target
          </h3>
          <.detail_grid>
            <.detail_item label="Host">
              <.nav_link
                type="host"
                id={@asset.host_id}
                label={@asset.host_address}
                on_navigate={@on_navigate}
              />
            </.detail_item>
            <.detail_item label="Hostname" value={@asset[:host_name]} />
            <.detail_item :if={@asset[:service_port]} label="Service">
              <.nav_link
                :if={@asset.service_id}
                type="service"
                id={@asset.service_id}
                label={"#{@asset.service_port}/#{@asset[:service_proto] || "tcp"}"}
                on_navigate={@on_navigate}
              />
            </.detail_item>
            <.detail_item
              :if={@asset[:service_name]}
              label="Service Name"
              value={@asset.service_name}
            />
          </.detail_grid>
        </div>
      </div>
      <!-- References -->
      <div class="card bg-base-200">
        <div class="card-body">
          <h3 class="card-title text-lg">
            <.icon name="hero-document-duplicate" class="size-5" /> References
          </h3>
          <%= if @asset.refs && length(@asset.refs) > 0 do %>
            <div class="flex flex-wrap gap-2">
              <span :for={ref <- @asset.refs} class="badge badge-outline font-mono text-xs">
                {ref}
              </span>
            </div>
          <% else %>
            <span class="text-base-content/50 text-sm">No references</span>
          <% end %>
        </div>
      </div>
      <!-- Info -->
      <div :if={@asset.info} class="card bg-base-200 lg:col-span-2">
        <div class="card-body">
          <h3 class="card-title text-lg">
            <.icon name="hero-information-circle" class="size-5" /> Details
          </h3>
          <div class="font-mono text-sm bg-base-300 p-3 rounded-lg">
            {@asset.info}
          </div>
        </div>
      </div>
      <!-- Timestamps -->
      <.timestamp_card created_at={@asset.created_at} updated_at={@asset.updated_at} />
    </div>
    """
  end

  @doc """
  Renders note detail view.
  """
  attr :asset, :map, required: true
  attr :on_navigate, :string, default: "database_navigate"

  def note_detail(assigns) do
    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
      <!-- Main info card -->
      <div class="card bg-base-200">
        <div class="card-body">
          <h3 class="card-title text-lg">
            <.icon name="hero-document-text" class="size-5" /> Note Information
          </h3>
          <.detail_grid>
            <.detail_item label="Type">
              <span class="badge badge-ghost font-mono">{@asset.ntype}</span>
            </.detail_item>
            <.detail_item label="Critical">
              <span :if={@asset.critical} class="badge badge-warning">Critical</span>
              <span :if={!@asset.critical} class="text-base-content/50">-</span>
            </.detail_item>
            <.detail_item label="Seen">
              <span :if={@asset.seen} class="badge badge-success badge-sm">Seen</span>
              <span :if={!@asset.seen} class="badge badge-ghost badge-sm">Unseen</span>
            </.detail_item>
          </.detail_grid>
        </div>
      </div>
      <!-- Host/Service info -->
      <div class="card bg-base-200">
        <div class="card-body">
          <h3 class="card-title text-lg">
            <.icon name="hero-link" class="size-5" /> Attached To
          </h3>
          <.detail_grid>
            <.detail_item label="Host">
              <%= if @asset.host_id do %>
                <.nav_link
                  type="host"
                  id={@asset.host_id}
                  label={@asset.host_address}
                  on_navigate={@on_navigate}
                />
              <% else %>
                <span class="text-base-content/50">-</span>
              <% end %>
            </.detail_item>
            <.detail_item :if={@asset[:service_port]} label="Service">
              <.nav_link
                :if={@asset.service_id}
                type="service"
                id={@asset.service_id}
                label={"#{@asset.service_port}/#{@asset[:service_proto] || "tcp"}"}
                on_navigate={@on_navigate}
              />
            </.detail_item>
          </.detail_grid>
        </div>
      </div>
      <!-- Note content -->
      <div class="card bg-base-200 lg:col-span-2">
        <div class="card-body">
          <h3 class="card-title text-lg">
            <.icon name="hero-document" class="size-5" /> Content
          </h3>
          <div class="font-mono text-sm bg-base-300 p-4 rounded-lg max-h-96 overflow-auto">
            {format_note_data(@asset.data)}
          </div>
          <!-- Successfully deserialized -->
          <div
            :if={
              @asset[:is_serialized] && Map.has_key?(@asset, :deserialization_error) &&
                !@asset[:deserialization_error]
            }
            class="text-xs text-base-content/50 mt-2"
          >
            <.icon name="hero-check-circle" class="size-4 inline" />
            Deserialized from Ruby Marshal format
          </div>
          <!-- Deserialization failed -->
          <div
            :if={@asset[:is_serialized] && @asset[:deserialization_error]}
            class="alert alert-warning mt-4"
          >
            <.icon name="hero-exclamation-triangle" class="size-5" />
            <div>
              <div class="font-semibold">Ruby Marshal Data</div>
              <div class="text-sm">
                This note contains serialized Ruby data that could not be decoded: {@asset.deserialization_error}
              </div>
            </div>
          </div>
          <!-- No container available to deserialize -->
          <div
            :if={@asset[:is_serialized] && !Map.has_key?(@asset, :deserialization_error)}
            class="alert alert-info mt-4"
          >
            <.icon name="hero-information-circle" class="size-5" />
            <div>
              <div class="font-semibold">Ruby Marshal Data</div>
              <div class="text-sm">
                This note contains serialized Ruby data. Start a container to decode it.
              </div>
            </div>
          </div>
        </div>
      </div>
      <!-- Timestamps -->
      <.timestamp_card created_at={@asset.created_at} updated_at={@asset.updated_at} />
    </div>
    """
  end

  @doc """
  Renders credential detail view.
  """
  attr :asset, :map, required: true
  attr :on_navigate, :string, default: "database_navigate"

  def cred_detail(assigns) do
    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
      <!-- Credential info card -->
      <div class="card bg-base-200">
        <div class="card-body">
          <h3 class="card-title text-lg">
            <.icon name="hero-key" class="size-5" /> Credential Information
          </h3>
          <.detail_grid>
            <.detail_item label="Username" value={@asset.user} mono />
            <.detail_item label="Password" value={mask_password(@asset.pass)} mono />
            <.detail_item label="Type">
              <span class="badge badge-ghost">{@asset.ptype}</span>
            </.detail_item>
            <.detail_item label="Status">
              <span :if={@asset.active} class="badge badge-success">Active</span>
              <span :if={!@asset.active} class="badge badge-ghost">Inactive</span>
            </.detail_item>
          </.detail_grid>
        </div>
      </div>
      <!-- Target info -->
      <div class="card bg-base-200">
        <div class="card-body">
          <h3 class="card-title text-lg">
            <.icon name="hero-server" class="size-5" /> Target
          </h3>
          <.detail_grid>
            <.detail_item label="Host">
              <.nav_link
                type="host"
                id={@asset[:host_id]}
                label={@asset.host_address}
                on_navigate={@on_navigate}
              />
            </.detail_item>
            <.detail_item label="Service">
              <.nav_link
                :if={@asset[:service_id]}
                type="service"
                id={@asset.service_id}
                label={"#{@asset.service_port}/#{@asset[:service_proto] || "tcp"} (#{@asset.service_name || "unknown"})"}
                on_navigate={@on_navigate}
              />
            </.detail_item>
          </.detail_grid>
        </div>
      </div>
      <!-- Proof -->
      <div :if={@asset.proof} class="card bg-base-200 lg:col-span-2">
        <div class="card-body">
          <h3 class="card-title text-lg">
            <.icon name="hero-check-badge" class="size-5" /> Proof
          </h3>
          <div class="font-mono text-sm bg-base-300 p-3 rounded-lg">
            {@asset.proof}
          </div>
        </div>
      </div>
      <!-- Timestamps -->
      <.timestamp_card created_at={@asset.created_at} updated_at={@asset.updated_at} />
    </div>
    """
  end

  @doc """
  Renders loot detail view.
  """
  attr :asset, :map, required: true
  attr :on_navigate, :string, default: "database_navigate"

  def loot_detail(assigns) do
    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
      <!-- Main info card -->
      <div class="card bg-base-200">
        <div class="card-body">
          <h3 class="card-title text-lg">
            <.icon name="hero-archive-box" class="size-5" /> Loot Information
          </h3>
          <.detail_grid>
            <.detail_item label="Name" value={@asset.name} />
            <.detail_item label="Type">
              <span class="badge badge-ghost font-mono">{@asset.ltype}</span>
            </.detail_item>
            <.detail_item label="Content Type" value={@asset.content_type} />
            <.detail_item label="Path" value={@asset.path} mono />
          </.detail_grid>
        </div>
      </div>
      <!-- Host info -->
      <div class="card bg-base-200">
        <div class="card-body">
          <h3 class="card-title text-lg">
            <.icon name="hero-server" class="size-5" /> Source
          </h3>
          <.detail_grid>
            <.detail_item label="Host">
              <%= if @asset.host_id do %>
                <.nav_link
                  type="host"
                  id={@asset.host_id}
                  label={@asset.host_address}
                  on_navigate={@on_navigate}
                />
              <% else %>
                <span class="text-base-content/50">-</span>
              <% end %>
            </.detail_item>
            <.detail_item label="Hostname" value={@asset[:host_name]} />
          </.detail_grid>
        </div>
      </div>
      <!-- Info -->
      <div :if={@asset.info} class="card bg-base-200 lg:col-span-2">
        <div class="card-body">
          <h3 class="card-title text-lg">
            <.icon name="hero-information-circle" class="size-5" /> Description
          </h3>
          <div class="text-sm bg-base-300 p-3 rounded-lg">
            {@asset.info}
          </div>
        </div>
      </div>
      <!-- Content preview -->
      <div :if={@asset[:data]} class="card bg-base-200 lg:col-span-2">
        <div class="card-body">
          <h3 class="card-title text-lg">
            <.icon name="hero-document" class="size-5" /> Content Preview
          </h3>
          <div class="font-mono text-xs bg-base-300 p-4 rounded-lg max-h-96 overflow-auto">
            {truncate_text(@asset.data, 5000)}
          </div>
        </div>
      </div>
      <!-- Timestamps -->
      <.timestamp_card created_at={@asset.created_at} updated_at={@asset.updated_at} />
    </div>
    """
  end

  @doc """
  Renders session detail view.
  """
  attr :asset, :map, required: true
  attr :on_navigate, :string, default: "database_navigate"

  def session_detail(assigns) do
    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
      <!-- Session info card -->
      <div class="card bg-base-200">
        <div class="card-body">
          <h3 class="card-title text-lg">
            <.icon name="hero-command-line" class="size-5" /> Session Information
          </h3>
          <.detail_grid>
            <.detail_item label="Type">
              <span class="badge badge-primary">{@asset.stype}</span>
            </.detail_item>
            <.detail_item label="Port" value={@asset.port} mono />
            <.detail_item label="Platform" value={@asset.platform} />
            <.detail_item label="Status">
              <span :if={!@asset.closed_at} class="badge badge-success">Active</span>
              <span :if={@asset.closed_at} class="badge badge-ghost">Closed</span>
            </.detail_item>
          </.detail_grid>
        </div>
      </div>
      <!-- Host info -->
      <div class="card bg-base-200">
        <div class="card-body">
          <h3 class="card-title text-lg">
            <.icon name="hero-server" class="size-5" /> Target
          </h3>
          <.detail_grid>
            <.detail_item label="Host">
              <.nav_link
                type="host"
                id={@asset.host_id}
                label={@asset.host_address}
                on_navigate={@on_navigate}
              />
            </.detail_item>
            <.detail_item label="Hostname" value={@asset[:host_name]} />
            <.detail_item label="OS" value={@asset[:host_os]} />
          </.detail_grid>
        </div>
      </div>
      <!-- Exploit info -->
      <div class="card bg-base-200 lg:col-span-2">
        <div class="card-body">
          <h3 class="card-title text-lg">
            <.icon name="hero-bolt" class="size-5" /> Exploitation
          </h3>
          <.detail_grid cols={2}>
            <.detail_item label="Exploit" value={@asset.via_exploit} mono />
            <.detail_item label="Payload" value={@asset.via_payload} mono />
          </.detail_grid>
        </div>
      </div>
      <!-- Description -->
      <div :if={@asset.desc} class="card bg-base-200 lg:col-span-2">
        <div class="card-body">
          <h3 class="card-title text-lg">
            <.icon name="hero-information-circle" class="size-5" /> Description
          </h3>
          <div class="text-sm bg-base-300 p-3 rounded-lg">
            {@asset.desc}
          </div>
        </div>
      </div>
      <!-- Session times -->
      <div class="card bg-base-200 lg:col-span-2">
        <div class="card-body">
          <h3 class="card-title text-lg">
            <.icon name="hero-clock" class="size-5" /> Timeline
          </h3>
          <.detail_grid cols={2}>
            <.detail_item label="Opened" value={format_datetime(@asset.opened_at)} />
            <.detail_item label="Closed" value={format_datetime(@asset.closed_at)} />
          </.detail_grid>
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Detail View Helper Components
  # ---------------------------------------------------------------------------

  attr :class, :string, default: ""
  attr :cols, :integer, default: 2
  slot :inner_block, required: true

  defp detail_grid(assigns) do
    grid_class =
      case assigns.cols do
        3 -> "grid-cols-1 sm:grid-cols-2 lg:grid-cols-3"
        _ -> "grid-cols-1 sm:grid-cols-2"
      end

    assigns = assign(assigns, :grid_class, grid_class)

    ~H"""
    <div class={["grid gap-4", @grid_class, @class]}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, default: nil
  attr :mono, :boolean, default: false
  slot :inner_block

  defp detail_item(assigns) do
    ~H"""
    <div>
      <div class="text-xs text-base-content/60 mb-1">{@label}</div>
      <div class={[@mono && "font-mono"]}>
        <%= if @inner_block != [] do %>
          {render_slot(@inner_block)}
        <% else %>
          {@value || "-"}
        <% end %>
      </div>
    </div>
    """
  end

  attr :type, :string, required: true
  attr :id, :any, required: true
  attr :label, :string, required: true
  attr :on_navigate, :string, required: true

  defp nav_link(assigns) do
    ~H"""
    <button
      type="button"
      class="link link-primary font-mono"
      phx-click={@on_navigate}
      phx-value-type={@type}
      phx-value-id={@id}
    >
      {@label}
    </button>
    """
  end

  # Renders a row of related asset links in compact inline format
  # Example: "Services: tcp/80 (http), tcp/443 (https), udp/53 (domain)"
  attr :label, :string, required: true
  attr :assets, :list, required: true
  attr :type, :string, required: true
  attr :format_fn, :any, required: true
  attr :on_navigate, :string, required: true

  defp related_asset_row(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-1.5">
      <span class="font-medium text-base-content/70 mr-1">{@label}:</span>
      <button
        :for={asset <- @assets}
        type="button"
        class="inline-flex items-center px-2 py-0.5 text-xs font-mono bg-base-300 hover:bg-base-100 border border-base-content/20 rounded cursor-pointer transition-colors"
        phx-click={@on_navigate}
        phx-value-type={@type}
        phx-value-id={asset.id}
      >
        {@format_fn.(asset)}
      </button>
    </div>
    """
  end

  attr :created_at, :any, required: true
  attr :updated_at, :any, required: true

  defp timestamp_card(assigns) do
    ~H"""
    <div class="card bg-base-200 lg:col-span-2">
      <div class="card-body py-3">
        <div class="flex gap-8 text-sm text-base-content/60">
          <div>
            <span class="font-medium">Created:</span> {format_datetime(@created_at)}
          </div>
          <div>
            <span class="font-medium">Updated:</span> {format_datetime(@updated_at)}
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Check if host has related assets
  defp has_host_related_assets?(asset) do
    [:related_services, :related_vulns, :related_notes, :related_sessions, :related_loots]
    |> Enum.any?(fn key -> Map.get(asset, key, []) != [] end)
  end

  # Check if service has related assets
  defp has_service_related_assets?(asset) do
    [:related_vulns, :related_creds, :related_notes]
    |> Enum.any?(fn key -> Map.get(asset, key, []) != [] end)
  end

  # Format functions for related asset links
  # Service: tcp/80 (http)
  defp format_service_link(service) do
    base = "#{service.proto}/#{service.port}"
    if service.name && service.name != "", do: "#{base} (#{service.name})", else: base
  end

  # Vuln: CVE-2021-44228 or truncated name
  defp format_vuln_link(vuln) do
    truncate(vuln.name || "unknown", 30)
  end

  # Note: host.os.nmap_fingerprint
  defp format_note_link(note) do
    truncate(note.ntype || "unknown", 25)
  end

  # Cred: root (password)
  defp format_cred_link(cred) do
    user = cred.user || "unknown"
    if cred.ptype, do: "#{user} (#{cred.ptype})", else: user
  end

  # Loot: /etc/passwd or ltype
  defp format_loot_link(loot) do
    truncate(loot.name || loot.ltype || "unknown", 25)
  end

  # Session: meterpreter (active) or shell (closed)
  defp format_session_link(session) do
    status = if session.closed_at, do: "closed", else: "active"
    "#{session.stype} (#{status})"
  end

  # Masks password for display
  defp mask_password(nil), do: "-"
  defp mask_password(""), do: "-"
  defp mask_password(pass), do: String.duplicate("*", min(String.length(pass), 16))

  # ===========================================================================
  # Helper Functions
  # ===========================================================================

  defp state_badge(assigns) do
    badge_class =
      case assigns.state do
        "alive" -> "badge-success"
        "open" -> "badge-success"
        "closed" -> "badge-ghost"
        "filtered" -> "badge-warning"
        _ -> "badge-ghost"
      end

    assigns = assign(assigns, :badge_class, badge_class)

    ~H"""
    <span class={["badge badge-sm", @badge_class]}>{@state || "-"}</span>
    """
  end

  defp format_os(host) do
    [host.os_name, host.os_flavor, host.os_sp]
    |> Enum.reject(&(is_nil(&1) || &1 == ""))
    |> Enum.join(" ")
    |> case do
      "" -> "-"
      os -> os
    end
  end

  defp format_datetime(nil), do: "-"

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M")
  end

  defp truncate_text(nil, _), do: "-"
  defp truncate_text(text, max_len) when byte_size(text) <= max_len, do: text
  defp truncate_text(text, max_len), do: String.slice(text, 0, max_len) <> "..."

  # Highlights search term matches in text with a background color
  defp highlight(nil, _search_term), do: "-"
  defp highlight(text, ""), do: text
  defp highlight(text, nil), do: text

  defp highlight(text, search_term) when is_binary(text) do
    case Regex.compile(Regex.escape(search_term), "i") do
      {:ok, regex} -> highlight_with_regex(text, search_term, regex)
      {:error, _} -> text
    end
  end

  defp highlight(text, _search_term), do: to_string(text)

  # sobelow_skip ["XSS.Raw"]
  defp highlight_with_regex(text, search_term, regex) do
    # Safe: all user content is escaped via escape_html before being included
    parts = Regex.split(regex, text, include_captures: true)
    html = Enum.map_join(parts, &highlight_part(&1, search_term))
    Phoenix.HTML.raw(html)
  end

  defp highlight_part(part, search_term) do
    escaped = escape_html(part)

    if String.downcase(part) == String.downcase(search_term) do
      ~s(<mark class="bg-warning/40 rounded px-0.5">#{escaped}</mark>)
    else
      escaped
    end
  end

  defp escape_html(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end

  defp format_note_data(nil), do: "-"
  defp format_note_data(data) when is_binary(data), do: data

  defp format_note_data(data) when is_map(data) do
    # Format deserialized Ruby Marshal data as readable key-value pairs
    Enum.map_join(data, "\n", fn {key, value} -> "#{key}: #{inspect(value)}" end)
  end

  defp format_note_data(data), do: inspect(data)

  # coveralls-ignore-stop
end
