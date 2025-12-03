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

defmodule Msfailab.MsfData.Vuln do
  @moduledoc """
  Ecto schema for the Metasploit Framework vulns table.

  Vulns represent discovered vulnerabilities on hosts and services.
  They contain the vulnerability name (usually MSF module name), info,
  exploitation status, and links to external references (CVE, MSB, etc.).

  This schema is read-only - vulns are created through MSF scanning and
  exploitation, not through this application.
  """
  use Ecto.Schema

  alias Msfailab.MsfData.{Host, Note, Ref, Service}

  @type t :: %__MODULE__{
          id: integer() | nil,
          host_id: integer() | nil,
          service_id: integer() | nil,
          name: String.t() | nil,
          info: String.t() | nil,
          exploited_at: DateTime.t() | nil,
          host: Host.t() | Ecto.Association.NotLoaded.t(),
          service: Service.t() | Ecto.Association.NotLoaded.t(),
          refs: [Ref.t()] | Ecto.Association.NotLoaded.t(),
          notes: [Note.t()] | Ecto.Association.NotLoaded.t(),
          created_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "vulns" do
    field :name, :string
    field :info, :string
    field :exploited_at, :utc_datetime
    field :created_at, :utc_datetime
    field :updated_at, :utc_datetime

    belongs_to :host, Host
    belongs_to :service, Service
    has_many :notes, Note
    many_to_many :refs, Ref, join_through: "vulns_refs"
  end
end
