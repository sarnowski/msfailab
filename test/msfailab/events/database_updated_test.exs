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

defmodule Msfailab.Events.DatabaseUpdatedTest do
  use ExUnit.Case, async: true

  alias Msfailab.Events.DatabaseUpdated

  describe "new/3" do
    test "creates event with all fields" do
      changes = %{hosts: 3, services: 1, vulns: 2, notes: 0, creds: 0, loots: 0, sessions: 0}

      totals = %{
        hosts: 15,
        services: 48,
        vulns: 25,
        notes: 8,
        creds: 3,
        loots: 1,
        sessions: 2,
        total: 102
      }

      event = DatabaseUpdated.new(1, changes, totals)

      assert event.workspace_id == 1
      assert event.changes == changes
      assert event.totals == totals
      assert %DateTime{} = event.timestamp
    end
  end

  describe "format_changes/1" do
    test "formats single item" do
      changes = %{hosts: 1, services: 0, vulns: 0, notes: 0, creds: 0, loots: 0, sessions: 0}

      assert DatabaseUpdated.format_changes(changes) == "1 new host discovered"
    end

    test "formats multiple items of single type" do
      changes = %{hosts: 5, services: 0, vulns: 0, notes: 0, creds: 0, loots: 0, sessions: 0}

      assert DatabaseUpdated.format_changes(changes) == "5 new hosts discovered"
    end

    test "formats two types" do
      changes = %{hosts: 3, services: 1, vulns: 0, notes: 0, creds: 0, loots: 0, sessions: 0}

      assert DatabaseUpdated.format_changes(changes) ==
               "3 new hosts, and 1 new service discovered"
    end

    test "formats three or more types" do
      changes = %{hosts: 3, services: 1, vulns: 2, notes: 0, creds: 0, loots: 0, sessions: 0}

      assert DatabaseUpdated.format_changes(changes) ==
               "3 new hosts, 1 new service, and 2 new vulnerabilities discovered"
    end

    test "uses singular for credentials" do
      changes = %{hosts: 0, services: 0, vulns: 0, notes: 0, creds: 1, loots: 0, sessions: 0}

      assert DatabaseUpdated.format_changes(changes) == "1 new credential discovered"
    end

    test "returns nil when no changes" do
      changes = %{hosts: 0, services: 0, vulns: 0, notes: 0, creds: 0, loots: 0, sessions: 0}

      assert DatabaseUpdated.format_changes(changes) == nil
    end

    test "ignores negative values" do
      changes = %{hosts: -2, services: 1, vulns: 0, notes: 0, creds: 0, loots: 0, sessions: 0}

      assert DatabaseUpdated.format_changes(changes) == "1 new service discovered"
    end
  end
end
