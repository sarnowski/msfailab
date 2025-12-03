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

defmodule Msfailab.MsfData.Loot do
  @moduledoc """
  Ecto schema for the Metasploit Framework loots table.

  Loots represent captured files and artifacts from target systems. They
  include the file path, content type, and metadata. The actual file content
  is stored on disk at the `path` location, with a copy in the `data` field
  for smaller items.

  ## Common Loot Types (ltype)

  - `windows.hashes` - Windows password hashes
  - `linux.hashes` - Linux password hashes
  - `host.files` - Captured files
  - `windows.registry` - Registry exports
  - `host.screenshot` - Desktop screenshots

  Use `list_loots` to find loot entries, then `retrieve_loot` to get contents.

  This schema is read-only - loot is captured through MSF post-exploitation,
  not through this application.
  """
  use Ecto.Schema

  alias Msfailab.MsfData.{Host, MsfWorkspace, Service}

  @type t :: %__MODULE__{
          id: integer() | nil,
          workspace_id: integer() | nil,
          host_id: integer() | nil,
          service_id: integer() | nil,
          ltype: String.t() | nil,
          path: String.t() | nil,
          data: String.t() | nil,
          content_type: String.t() | nil,
          name: String.t() | nil,
          info: String.t() | nil,
          workspace: MsfWorkspace.t() | Ecto.Association.NotLoaded.t(),
          host: Host.t() | Ecto.Association.NotLoaded.t(),
          service: Service.t() | Ecto.Association.NotLoaded.t(),
          created_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "loots" do
    field :ltype, :string
    field :path, :string
    field :data, :string
    field :content_type, :string
    field :name, :string
    field :info, :string
    field :created_at, :utc_datetime
    field :updated_at, :utc_datetime

    belongs_to :workspace, MsfWorkspace
    belongs_to :host, Host
    belongs_to :service, Service
  end
end
