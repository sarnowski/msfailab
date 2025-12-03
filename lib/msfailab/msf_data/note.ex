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

defmodule Msfailab.MsfData.Note do
  @moduledoc """
  Ecto schema for the Metasploit Framework notes table.

  Notes are free-form annotations that can be attached to workspaces, hosts,
  services, or vulnerabilities. The agent uses notes with the `agent.*` type
  prefix to document findings, observations, and recommendations.

  ## Standard Agent Note Types

  - `agent.observation` - General findings and observations
  - `agent.hypothesis` - Suspected vulnerabilities or attack paths
  - `agent.summary` - Session or scan summaries
  - `agent.failed_attempt` - Documentation of failed exploits
  - `agent.recommendation` - Suggested next steps
  - `agent.finding` - Confirmed security findings

  Custom types are allowed if prefixed with `agent.`.

  Unlike other MSF schemas, this one supports inserts via `create_changeset/2`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Msfailab.MsfData.{Host, MsfWorkspace, Service, Vuln}

  @type t :: %__MODULE__{
          id: integer() | nil,
          ntype: String.t() | nil,
          workspace_id: integer() | nil,
          host_id: integer() | nil,
          service_id: integer() | nil,
          vuln_id: integer() | nil,
          data: String.t() | nil,
          critical: boolean() | nil,
          seen: boolean() | nil,
          workspace: MsfWorkspace.t() | Ecto.Association.NotLoaded.t(),
          host: Host.t() | Ecto.Association.NotLoaded.t(),
          service: Service.t() | Ecto.Association.NotLoaded.t(),
          vuln: Vuln.t() | Ecto.Association.NotLoaded.t(),
          created_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "notes" do
    field :ntype, :string
    field :data, :string
    field :critical, :boolean, default: false
    field :seen, :boolean, default: false
    field :created_at, :utc_datetime
    field :updated_at, :utc_datetime

    belongs_to :workspace, MsfWorkspace
    belongs_to :host, Host
    belongs_to :service, Service
    belongs_to :vuln, Vuln
  end

  @doc """
  Changeset for creating a new note.

  Notes created by the agent must have a type prefixed with `agent.`.
  The data field is freeform text.

  ## Parameters

  - `note` - The Note struct (usually `%Note{}`)
  - `attrs` - Map with note attributes:
    - `:ntype` (required) - Note type, must start with "agent."
    - `:data` (required) - Note content
    - `:workspace_id` - Workspace to attach to (required)
    - `:host_id` - Host to attach to (optional)
    - `:service_id` - Service to attach to (optional, requires host_id)
    - `:critical` - Mark as critical finding (optional, default: false)

  ## Examples

      iex> Note.create_changeset(%Note{}, %{
      ...>   ntype: "agent.observation",
      ...>   data: "Target is running outdated Apache",
      ...>   workspace_id: 1,
      ...>   host_id: 5
      ...> })
  """
  @spec create_changeset(t(), map()) :: Ecto.Changeset.t()
  def create_changeset(note, attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    note
    |> cast(attrs, [:ntype, :data, :workspace_id, :host_id, :service_id, :vuln_id, :critical])
    |> validate_required([:ntype, :data, :workspace_id])
    |> validate_agent_type()
    |> put_change(:created_at, now)
    |> put_change(:updated_at, now)
    |> put_change(:seen, false)
    |> foreign_key_constraint(:workspace_id)
    |> foreign_key_constraint(:host_id)
    |> foreign_key_constraint(:service_id)
    |> foreign_key_constraint(:vuln_id)
  end

  defp validate_agent_type(changeset) do
    validate_change(changeset, :ntype, fn :ntype, ntype ->
      if String.starts_with?(ntype, "agent.") do
        []
      else
        [ntype: "must start with 'agent.' prefix"]
      end
    end)
  end
end
