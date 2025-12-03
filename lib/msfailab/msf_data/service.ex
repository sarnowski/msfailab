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

defmodule Msfailab.MsfData.Service do
  @moduledoc """
  Ecto schema for the Metasploit Framework services table.

  Services represent network services discovered on hosts, identified by
  port number and protocol. They contain service name, banner information,
  and link to credentials and vulnerabilities.

  This schema is read-only - services are created through MSF scanning,
  not through this application.
  """
  use Ecto.Schema

  alias Msfailab.MsfData.{Cred, Host, Note, Vuln}

  @type t :: %__MODULE__{
          id: integer() | nil,
          host_id: integer() | nil,
          port: integer() | nil,
          proto: String.t() | nil,
          state: String.t() | nil,
          name: String.t() | nil,
          info: String.t() | nil,
          host: Host.t() | Ecto.Association.NotLoaded.t(),
          vulns: [Vuln.t()] | Ecto.Association.NotLoaded.t(),
          notes: [Note.t()] | Ecto.Association.NotLoaded.t(),
          creds: [Cred.t()] | Ecto.Association.NotLoaded.t(),
          created_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "services" do
    field :port, :integer
    field :proto, :string
    field :state, :string
    field :name, :string
    field :info, :string
    field :created_at, :utc_datetime
    field :updated_at, :utc_datetime

    belongs_to :host, Host
    has_many :vulns, Vuln
    has_many :notes, Note
    has_many :creds, Cred
  end
end
