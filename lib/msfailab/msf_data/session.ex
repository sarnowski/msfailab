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

defmodule Msfailab.MsfData.Session do
  @moduledoc """
  Ecto schema for the Metasploit Framework sessions table.

  Sessions represent active or historical connections to compromised hosts.
  They include the session type, exploit/payload used, and connection details.

  ## Session Types (stype)

  - `meterpreter` - Meterpreter shell
  - `shell` - Command shell
  - `vnc` - VNC session
  - `powershell` - PowerShell session

  Active sessions have `closed_at` as nil. Historical sessions have both
  `opened_at` and `closed_at` populated.

  This schema is read-only - sessions are created through MSF exploitation,
  not through this application.
  """
  use Ecto.Schema

  alias Msfailab.MsfData.Host

  @type t :: %__MODULE__{
          id: integer() | nil,
          host_id: integer() | nil,
          stype: String.t() | nil,
          via_exploit: String.t() | nil,
          via_payload: String.t() | nil,
          desc: String.t() | nil,
          port: integer() | nil,
          platform: String.t() | nil,
          opened_at: DateTime.t() | nil,
          closed_at: DateTime.t() | nil,
          host: Host.t() | Ecto.Association.NotLoaded.t()
        }

  # Note: MSF sessions table doesn't have created_at/updated_at - only opened_at/closed_at
  @primary_key {:id, :id, autogenerate: true}
  @timestamps_opts []
  schema "sessions" do
    field :stype, :string
    field :via_exploit, :string
    field :via_payload, :string
    field :desc, :string
    field :port, :integer
    field :platform, :string
    field :opened_at, :utc_datetime
    field :closed_at, :utc_datetime

    belongs_to :host, Host
  end
end
