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

defmodule Msfailab.MsfData.Ref do
  @moduledoc """
  Ecto schema for the Metasploit Framework refs table.

  Refs represent vulnerability references such as CVE, MSB (Microsoft
  Security Bulletin), EDB (Exploit Database), etc. They are linked to
  vulnerabilities through the vulns_refs join table.

  Examples:
  - CVE-2017-0144 (EternalBlue)
  - MSB-MS17-010
  - EDB-42315

  This schema is read-only - refs are created through MSF module
  definitions, not through this application.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          created_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "refs" do
    field :name, :string
    field :created_at, :utc_datetime
    field :updated_at, :utc_datetime
  end
end
