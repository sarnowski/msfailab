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

defmodule Msfailab.MsfData.MsfWorkspace do
  @moduledoc """
  Ecto schema for the Metasploit Framework workspaces table.

  This represents MSF workspaces which provide data isolation for hosts,
  services, vulnerabilities, and other findings. There is a 1:1 mapping
  between msfailab workspace slugs and MSF workspace names.

  This schema is read-only - workspaces are created through MSF, not
  through this application.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          boundary: String.t() | nil,
          description: String.t() | nil,
          created_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "workspaces" do
    field :name, :string
    field :boundary, :string
    field :description, :string
    field :created_at, :utc_datetime
    field :updated_at, :utc_datetime
  end
end
