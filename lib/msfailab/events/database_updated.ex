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

defmodule Msfailab.Events.DatabaseUpdated do
  @moduledoc """
  Event broadcast when MSF database assets in a workspace change.

  This event is broadcast by the WorkspaceServer when it detects that asset
  counts have changed after a command or tool execution completes.

  Unlike most events in this system, this event carries payload data:
  - `changes` - The delta counts showing what was added/removed
  - `totals` - The current total counts for the badge display

  ## Design Rationale

  We include the counts in the payload rather than following the "notification
  + fetch" pattern because:

  1. WorkspaceServer already computed the counts and deltas
  2. Flash messages need `changes` to display "3 new hosts, 1 service..."
  3. Badge updates need `totals` for immediate UI update
  4. Avoids redundant database queries from multiple subscribers

  LiveViews can still fetch full asset lists when needed (opening modal,
  navigating tables), but for the badge/flash they use the event payload.

  ## Example

      def handle_info(%DatabaseUpdated{} = event, socket) do
        if socket.assigns.workspace.id == event.workspace_id do
          socket =
            socket
            |> assign(:asset_counts, event.totals)
            |> maybe_show_flash(event.changes)

          {:noreply, socket}
        else
          {:noreply, socket}
        end
      end
  """

  alias Msfailab.MsfData

  @type changes :: %{
          hosts: integer(),
          services: integer(),
          vulns: integer(),
          notes: integer(),
          creds: integer(),
          loots: integer(),
          sessions: integer()
        }

  @type t :: %__MODULE__{
          workspace_id: pos_integer(),
          changes: changes(),
          totals: MsfData.asset_counts(),
          timestamp: DateTime.t()
        }

  @enforce_keys [:workspace_id, :changes, :totals, :timestamp]
  defstruct [:workspace_id, :changes, :totals, :timestamp]

  @doc """
  Creates a new DatabaseUpdated event.

  ## Parameters

  - `workspace_id` - The workspace whose assets changed
  - `changes` - Map of changes per asset type (can be negative for removals)
  - `totals` - Current total counts for all asset types
  """
  @spec new(pos_integer(), changes(), MsfData.asset_counts()) :: t()
  def new(workspace_id, changes, totals)
      when is_integer(workspace_id) and is_map(changes) and is_map(totals) do
    %__MODULE__{
      workspace_id: workspace_id,
      changes: changes,
      totals: totals,
      timestamp: DateTime.utc_now()
    }
  end

  @doc """
  Formats the changes for display in a flash message.

  Returns a human-readable string like "3 new hosts, 1 service, and 2 vulnerabilities discovered"
  or nil if there are no changes.

  ## Examples

      iex> DatabaseUpdated.format_changes(%{hosts: 3, services: 1, vulns: 2, notes: 0, creds: 0, loots: 0, sessions: 0})
      "3 new hosts, 1 service, and 2 vulnerabilities discovered"

      iex> DatabaseUpdated.format_changes(%{hosts: 1, services: 0, vulns: 0, notes: 0, creds: 0, loots: 0, sessions: 0})
      "1 new host discovered"
  """
  # Asset types with their singular/plural forms
  @asset_types [
    {:hosts, "host", "hosts"},
    {:services, "service", "services"},
    {:vulns, "vulnerability", "vulnerabilities"},
    {:notes, "note", "notes"},
    {:creds, "credential", "credentials"},
    {:loots, "loot", "loots"},
    {:sessions, "session", "sessions"}
  ]

  @spec format_changes(changes()) :: String.t() | nil
  def format_changes(changes) do
    parts = format_all_counts(changes)
    format_parts(parts)
  end

  defp format_all_counts(changes) do
    @asset_types
    |> Enum.map(fn {key, singular, plural} ->
      format_count(changes[key] || 0, singular, plural)
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp format_parts([]), do: nil
  defp format_parts([single]), do: "#{single} discovered"
  defp format_parts(many), do: format_list(many) <> " discovered"

  defp format_count(count, _singular, _plural) when count <= 0, do: nil
  defp format_count(1, singular, _plural), do: "1 new #{singular}"
  defp format_count(count, _singular, plural), do: "#{count} new #{plural}"

  defp format_list([last]), do: last

  defp format_list(items) do
    [last | rest] = Enum.reverse(items)
    Enum.join(Enum.reverse(rest), ", ") <> ", and " <> last
  end
end
