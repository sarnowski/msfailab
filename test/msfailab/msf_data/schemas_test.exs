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

defmodule Msfailab.MsfData.SchemasTest do
  use ExUnit.Case, async: true

  alias Msfailab.MsfData.{Cred, Host, Loot, MsfWorkspace, Note, Ref, Service, Session, Vuln}

  describe "MsfWorkspace schema" do
    test "has expected fields" do
      fields = MsfWorkspace.__schema__(:fields)

      assert :id in fields
      assert :name in fields
      assert :boundary in fields
      assert :description in fields
    end

    test "maps to workspaces table" do
      assert MsfWorkspace.__schema__(:source) == "workspaces"
    end
  end

  describe "Host schema" do
    test "has expected fields" do
      fields = Host.__schema__(:fields)

      assert :id in fields
      assert :address in fields
      assert :mac in fields
      assert :name in fields
      assert :state in fields
      assert :os_name in fields
      assert :os_flavor in fields
      assert :os_sp in fields
      assert :os_lang in fields
      assert :os_family in fields
      assert :arch in fields
      assert :purpose in fields
      assert :info in fields
      assert :comments in fields
      assert :workspace_id in fields
    end

    test "maps to hosts table" do
      assert Host.__schema__(:source) == "hosts"
    end

    test "belongs to workspace" do
      assoc = Host.__schema__(:association, :workspace)
      assert assoc != nil
      assert assoc.related == MsfWorkspace
    end
  end

  describe "Service schema" do
    test "has expected fields" do
      fields = Service.__schema__(:fields)

      assert :id in fields
      assert :host_id in fields
      assert :port in fields
      assert :proto in fields
      assert :state in fields
      assert :name in fields
      assert :info in fields
    end

    test "maps to services table" do
      assert Service.__schema__(:source) == "services"
    end

    test "belongs to host" do
      assoc = Service.__schema__(:association, :host)
      assert assoc != nil
      assert assoc.related == Host
    end
  end

  describe "Vuln schema" do
    test "has expected fields" do
      fields = Vuln.__schema__(:fields)

      assert :id in fields
      assert :host_id in fields
      assert :service_id in fields
      assert :name in fields
      assert :info in fields
      assert :exploited_at in fields
    end

    test "maps to vulns table" do
      assert Vuln.__schema__(:source) == "vulns"
    end

    test "belongs to host" do
      assoc = Vuln.__schema__(:association, :host)
      assert assoc != nil
      assert assoc.related == Host
    end

    test "has many_to_many refs" do
      assoc = Vuln.__schema__(:association, :refs)
      assert assoc != nil
      assert assoc.related == Ref
    end
  end

  describe "Ref schema" do
    test "has expected fields" do
      fields = Ref.__schema__(:fields)

      assert :id in fields
      assert :name in fields
    end

    test "maps to refs table" do
      assert Ref.__schema__(:source) == "refs"
    end
  end

  describe "Note schema" do
    test "has expected fields" do
      fields = Note.__schema__(:fields)

      assert :id in fields
      assert :ntype in fields
      assert :workspace_id in fields
      assert :host_id in fields
      assert :service_id in fields
      assert :data in fields
      assert :critical in fields
      assert :seen in fields
    end

    test "maps to notes table" do
      assert Note.__schema__(:source) == "notes"
    end

    test "belongs to workspace" do
      assoc = Note.__schema__(:association, :workspace)
      assert assoc != nil
      assert assoc.related == MsfWorkspace
    end

    test "has create_changeset that validates ntype prefix" do
      changeset = Note.create_changeset(%Note{}, %{ntype: "invalid", data: "test"})
      assert changeset.errors[:ntype] != nil

      changeset = Note.create_changeset(%Note{}, %{ntype: "agent.test", data: "test"})
      assert changeset.errors[:ntype] == nil
    end
  end

  describe "Cred schema" do
    test "has expected fields" do
      fields = Cred.__schema__(:fields)

      assert :id in fields
      assert :service_id in fields
      assert :user in fields
      assert :pass in fields
      assert :ptype in fields
      assert :active in fields
      assert :proof in fields
    end

    test "maps to creds table" do
      assert Cred.__schema__(:source) == "creds"
    end
  end

  describe "Loot schema" do
    test "has expected fields" do
      fields = Loot.__schema__(:fields)

      assert :id in fields
      assert :workspace_id in fields
      assert :host_id in fields
      assert :service_id in fields
      assert :ltype in fields
      assert :path in fields
      assert :data in fields
      assert :content_type in fields
      assert :name in fields
      assert :info in fields
    end

    test "maps to loots table" do
      assert Loot.__schema__(:source) == "loots"
    end

    test "belongs to workspace" do
      assoc = Loot.__schema__(:association, :workspace)
      assert assoc != nil
      assert assoc.related == MsfWorkspace
    end
  end

  describe "Session schema" do
    test "has expected fields" do
      fields = Session.__schema__(:fields)

      assert :id in fields
      assert :host_id in fields
      assert :stype in fields
      assert :via_exploit in fields
      assert :via_payload in fields
      assert :desc in fields
      assert :port in fields
      assert :platform in fields
      assert :opened_at in fields
      assert :closed_at in fields
    end

    test "maps to sessions table" do
      assert Session.__schema__(:source) == "sessions"
    end

    test "belongs to host" do
      assoc = Session.__schema__(:association, :host)
      assert assoc != nil
      assert assoc.related == Host
    end
  end
end
