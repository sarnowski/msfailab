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

defmodule Msfailab.MsfData.Host do
  @moduledoc """
  Ecto schema for the Metasploit Framework hosts table.

  Hosts represent discovered systems in the target environment, identified
  by IP address. They contain OS information, state, and are the primary
  link to services, vulnerabilities, and sessions.

  This schema is read-only - hosts are created through MSF scanning and
  exploitation, not through this application.
  """
  use Ecto.Schema

  alias Msfailab.MsfData.{MsfWorkspace, Note, Service, Session, Vuln}

  @type t :: %__MODULE__{
          id: integer() | nil,
          address: EctoNetwork.INET.t() | nil,
          mac: String.t() | nil,
          name: String.t() | nil,
          state: String.t() | nil,
          os_name: String.t() | nil,
          os_flavor: String.t() | nil,
          os_sp: String.t() | nil,
          os_lang: String.t() | nil,
          os_family: String.t() | nil,
          arch: String.t() | nil,
          purpose: String.t() | nil,
          info: String.t() | nil,
          comments: String.t() | nil,
          workspace_id: integer() | nil,
          workspace: MsfWorkspace.t() | Ecto.Association.NotLoaded.t(),
          services: [Service.t()] | Ecto.Association.NotLoaded.t(),
          vulns: [Vuln.t()] | Ecto.Association.NotLoaded.t(),
          notes: [Note.t()] | Ecto.Association.NotLoaded.t(),
          sessions: [Session.t()] | Ecto.Association.NotLoaded.t(),
          created_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "hosts" do
    field :address, EctoNetwork.INET
    field :mac, :string
    field :name, :string
    field :state, :string
    field :os_name, :string
    field :os_flavor, :string
    field :os_sp, :string
    field :os_lang, :string
    field :os_family, :string
    field :arch, :string
    field :purpose, :string
    field :info, :string
    field :comments, :string
    field :created_at, :utc_datetime
    field :updated_at, :utc_datetime

    belongs_to :workspace, MsfWorkspace
    has_many :services, Service
    has_many :vulns, Vuln
    has_many :notes, Note
    has_many :sessions, Session
  end
end
