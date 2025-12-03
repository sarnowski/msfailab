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

defmodule Msfailab.MsfData.Cred do
  @moduledoc """
  Ecto schema for the Metasploit Framework creds table.

  Creds represent captured credentials associated with services. They
  contain username, password/hash, credential type, and validation status.

  ## Credential Types (ptype)

  - `password` - Plain text password
  - `hash` - Password hash (various formats)
  - `ntlm_hash` - NTLM hash
  - `ssh_key` - SSH private key

  This schema is read-only - credentials are captured through MSF
  exploitation and post-exploitation, not through this application.
  """
  use Ecto.Schema

  alias Msfailab.MsfData.Service

  @type t :: %__MODULE__{
          id: integer() | nil,
          service_id: integer() | nil,
          user: String.t() | nil,
          pass: String.t() | nil,
          ptype: String.t() | nil,
          active: boolean() | nil,
          proof: String.t() | nil,
          source_id: integer() | nil,
          source_type: String.t() | nil,
          service: Service.t() | Ecto.Association.NotLoaded.t(),
          created_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "creds" do
    field :user, :string
    field :pass, :string
    field :ptype, :string
    field :active, :boolean
    field :proof, :string
    field :source_id, :integer
    field :source_type, :string
    field :created_at, :utc_datetime
    field :updated_at, :utc_datetime

    belongs_to :service, Service
  end
end
