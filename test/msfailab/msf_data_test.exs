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

defmodule Msfailab.MsfDataTest do
  use Msfailab.DataCase, async: true

  alias Msfailab.MsfData
  alias Msfailab.MsfData.{Host, MsfWorkspace, Note, Service, Session, Vuln}
  alias Msfailab.Repo

  # ============================================================================
  # Test Helpers
  # ============================================================================

  defp create_msf_workspace(attrs \\ %{}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    default = %{
      name: "test-workspace-#{System.unique_integer([:positive])}",
      boundary: "10.0.0.0/24",
      description: "Test workspace",
      created_at: now,
      updated_at: now
    }

    %MsfWorkspace{}
    |> Ecto.Changeset.cast(Map.merge(default, attrs), [
      :name,
      :boundary,
      :description,
      :created_at,
      :updated_at
    ])
    |> Repo.insert!()
  end

  defp create_host(workspace, attrs \\ %{}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    default = %{
      address: "10.0.0.#{:rand.uniform(254)}",
      state: "alive",
      os_name: "Linux",
      workspace_id: workspace.id,
      created_at: now,
      updated_at: now
    }

    %Host{}
    |> Ecto.Changeset.cast(Map.merge(default, attrs), [
      :address,
      :mac,
      :name,
      :state,
      :os_name,
      :os_flavor,
      :os_sp,
      :os_lang,
      :os_family,
      :arch,
      :purpose,
      :info,
      :comments,
      :workspace_id,
      :created_at,
      :updated_at
    ])
    |> Repo.insert!()
  end

  defp create_service(host, attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    default = %{
      port: :rand.uniform(65_535),
      proto: "tcp",
      state: "open",
      name: "http",
      host_id: host.id,
      created_at: now,
      updated_at: now
    }

    %Service{}
    |> Ecto.Changeset.cast(Map.merge(default, attrs), [
      :port,
      :proto,
      :state,
      :name,
      :info,
      :host_id,
      :created_at,
      :updated_at
    ])
    |> Repo.insert!()
  end

  defp create_vuln(host, attrs \\ %{}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    default = %{
      name: "exploit/test/vulnerability",
      info: "Test vulnerability",
      host_id: host.id,
      created_at: now,
      updated_at: now
    }

    %Vuln{}
    |> Ecto.Changeset.cast(Map.merge(default, attrs), [
      :name,
      :info,
      :exploited_at,
      :host_id,
      :service_id,
      :created_at,
      :updated_at
    ])
    |> Repo.insert!()
  end

  defp create_note(workspace, attrs \\ %{}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    default = %{
      ntype: "agent.test",
      data: "Test note content",
      workspace_id: workspace.id,
      critical: false,
      seen: false,
      created_at: now,
      updated_at: now
    }

    %Note{}
    |> Ecto.Changeset.cast(Map.merge(default, attrs), [
      :ntype,
      :data,
      :workspace_id,
      :host_id,
      :service_id,
      :vuln_id,
      :critical,
      :seen,
      :created_at,
      :updated_at
    ])
    |> Repo.insert!()
  end

  defp create_session(host, attrs \\ %{}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    default = %{
      stype: "meterpreter",
      via_exploit: "exploit/test/module",
      opened_at: now,
      host_id: host.id,
      created_at: now,
      updated_at: now
    }

    %Session{}
    |> Ecto.Changeset.cast(Map.merge(default, attrs), [
      :stype,
      :via_exploit,
      :via_payload,
      :desc,
      :port,
      :platform,
      :opened_at,
      :closed_at,
      :host_id,
      :created_at,
      :updated_at
    ])
    |> Repo.insert!()
  end

  # ============================================================================
  # get_msf_workspace_id/1
  # ============================================================================

  describe "get_msf_workspace_id/1" do
    test "returns workspace id for matching name" do
      workspace = create_msf_workspace(%{name: "test-slug"})

      assert {:ok, workspace.id} == MsfData.get_msf_workspace_id("test-slug")
    end

    test "returns error for non-existent workspace" do
      assert {:error, :workspace_not_found} == MsfData.get_msf_workspace_id("nonexistent")
    end
  end

  # ============================================================================
  # list_hosts/2
  # ============================================================================

  describe "list_hosts/2" do
    test "returns hosts for workspace" do
      workspace = create_msf_workspace()
      host = create_host(workspace, %{address: "10.0.0.5"})
      _other_workspace = create_msf_workspace()

      {:ok, result} = MsfData.list_hosts(workspace.name)

      assert result.count == 1
      assert length(result.hosts) == 1
      assert hd(result.hosts).id == host.id
    end

    test "filters by address" do
      workspace = create_msf_workspace()
      host1 = create_host(workspace, %{address: "10.0.0.5"})
      _host2 = create_host(workspace, %{address: "10.0.0.6"})

      {:ok, result} = MsfData.list_hosts(workspace.name, %{address: "10.0.0.5"})

      assert result.count == 1
      assert hd(result.hosts).id == host1.id
    end

    test "filters by state" do
      workspace = create_msf_workspace()
      host1 = create_host(workspace, %{state: "alive"})
      _host2 = create_host(workspace, %{state: "down"})

      {:ok, result} = MsfData.list_hosts(workspace.name, %{state: "alive"})

      assert result.count == 1
      assert hd(result.hosts).id == host1.id
    end

    test "respects limit" do
      workspace = create_msf_workspace()
      for i <- 1..10, do: create_host(workspace, %{address: "10.0.0.#{i}"})

      {:ok, result} = MsfData.list_hosts(workspace.name, %{limit: 3})

      assert result.count == 3
      assert length(result.hosts) == 3
    end

    test "returns error for non-existent workspace" do
      assert {:error, :workspace_not_found} == MsfData.list_hosts("nonexistent")
    end
  end

  # ============================================================================
  # list_services/2
  # ============================================================================

  describe "list_services/2" do
    test "returns services for workspace" do
      workspace = create_msf_workspace()
      host = create_host(workspace)
      service = create_service(host, %{port: 80, name: "http"})

      {:ok, result} = MsfData.list_services(workspace.name)

      assert result.count == 1
      assert hd(result.services).id == service.id
    end

    test "filters by port" do
      workspace = create_msf_workspace()
      host = create_host(workspace)
      service1 = create_service(host, %{port: 80})
      _service2 = create_service(host, %{port: 443})

      {:ok, result} = MsfData.list_services(workspace.name, %{port: 80})

      assert result.count == 1
      assert hd(result.services).id == service1.id
    end

    test "filters by name" do
      workspace = create_msf_workspace()
      host = create_host(workspace)
      service1 = create_service(host, %{name: "ssh"})
      _service2 = create_service(host, %{name: "http"})

      {:ok, result} = MsfData.list_services(workspace.name, %{name: "ssh"})

      assert result.count == 1
      assert hd(result.services).id == service1.id
    end

    test "includes host address in result" do
      workspace = create_msf_workspace()
      host = create_host(workspace, %{address: "10.0.0.5"})
      _service = create_service(host, %{port: 80})

      {:ok, result} = MsfData.list_services(workspace.name)

      assert hd(result.services).host_address == "10.0.0.5"
    end
  end

  # ============================================================================
  # list_vulns/2
  # ============================================================================

  describe "list_vulns/2" do
    test "returns vulns for workspace" do
      workspace = create_msf_workspace()
      host = create_host(workspace)
      vuln = create_vuln(host)

      {:ok, result} = MsfData.list_vulns(workspace.name)

      assert result.count == 1
      assert hd(result.vulns).id == vuln.id
    end

    test "filters by host address" do
      workspace = create_msf_workspace()
      host1 = create_host(workspace, %{address: "10.0.0.5"})
      host2 = create_host(workspace, %{address: "10.0.0.6"})
      vuln1 = create_vuln(host1)
      _vuln2 = create_vuln(host2)

      {:ok, result} = MsfData.list_vulns(workspace.name, %{host: "10.0.0.5"})

      assert result.count == 1
      assert hd(result.vulns).id == vuln1.id
    end

    test "filters by exploited status" do
      workspace = create_msf_workspace()
      host = create_host(workspace)
      vuln1 = create_vuln(host, %{exploited_at: DateTime.utc_now()})
      _vuln2 = create_vuln(host, %{exploited_at: nil})

      {:ok, result} = MsfData.list_vulns(workspace.name, %{exploited: true})

      assert result.count == 1
      assert hd(result.vulns).id == vuln1.id
    end

    test "includes host address in result" do
      workspace = create_msf_workspace()
      host = create_host(workspace, %{address: "10.0.0.5"})
      _vuln = create_vuln(host)

      {:ok, result} = MsfData.list_vulns(workspace.name)

      assert hd(result.vulns).host_address == "10.0.0.5"
    end
  end

  # ============================================================================
  # list_notes/2
  # ============================================================================

  describe "list_notes/2" do
    test "returns notes for workspace" do
      workspace = create_msf_workspace()
      note = create_note(workspace)

      {:ok, result} = MsfData.list_notes(workspace.name)

      assert result.count == 1
      assert hd(result.notes).id == note.id
    end

    test "filters by ntype" do
      workspace = create_msf_workspace()
      note1 = create_note(workspace, %{ntype: "agent.observation"})
      _note2 = create_note(workspace, %{ntype: "agent.finding"})

      {:ok, result} = MsfData.list_notes(workspace.name, %{ntype: "agent.observation"})

      assert result.count == 1
      assert hd(result.notes).id == note1.id
    end

    test "filters by critical" do
      workspace = create_msf_workspace()
      note1 = create_note(workspace, %{critical: true})
      _note2 = create_note(workspace, %{critical: false})

      {:ok, result} = MsfData.list_notes(workspace.name, %{critical: true})

      assert result.count == 1
      assert hd(result.notes).id == note1.id
    end
  end

  # ============================================================================
  # list_sessions/2
  # ============================================================================

  describe "list_sessions/2" do
    test "returns sessions for workspace" do
      workspace = create_msf_workspace()
      host = create_host(workspace)
      session = create_session(host)

      {:ok, result} = MsfData.list_sessions(workspace.name)

      assert result.count == 1
      assert hd(result.sessions).id == session.id
    end

    test "filters by active status" do
      workspace = create_msf_workspace()
      host = create_host(workspace)
      session1 = create_session(host, %{closed_at: nil})
      _session2 = create_session(host, %{closed_at: DateTime.utc_now()})

      {:ok, result} = MsfData.list_sessions(workspace.name, %{active: true})

      assert result.count == 1
      assert hd(result.sessions).id == session1.id
    end

    test "filters by session type" do
      workspace = create_msf_workspace()
      host = create_host(workspace)
      session1 = create_session(host, %{stype: "meterpreter"})
      _session2 = create_session(host, %{stype: "shell"})

      {:ok, result} = MsfData.list_sessions(workspace.name, %{stype: "meterpreter"})

      assert result.count == 1
      assert hd(result.sessions).id == session1.id
    end

    test "includes host address in result" do
      workspace = create_msf_workspace()
      host = create_host(workspace, %{address: "10.0.0.5"})
      _session = create_session(host)

      {:ok, result} = MsfData.list_sessions(workspace.name)

      assert hd(result.sessions).host_address == "10.0.0.5"
    end
  end

  # ============================================================================
  # create_note/2
  # ============================================================================

  describe "create_note/2" do
    test "creates note with valid data" do
      workspace = create_msf_workspace()

      {:ok, note} =
        MsfData.create_note(workspace.name, %{
          ntype: "agent.observation",
          data: "Found vulnerable service"
        })

      assert note.ntype == "agent.observation"
      assert note.data == "Found vulnerable service"
      assert note.workspace_id == workspace.id
    end

    test "creates note attached to host" do
      workspace = create_msf_workspace()
      host = create_host(workspace, %{address: "10.0.0.5"})

      {:ok, note} =
        MsfData.create_note(workspace.name, %{
          ntype: "agent.observation",
          data: "Test",
          host: "10.0.0.5"
        })

      assert note.host_id == host.id
    end

    test "returns error for invalid ntype" do
      workspace = create_msf_workspace()

      {:error, changeset} =
        MsfData.create_note(workspace.name, %{
          ntype: "invalid",
          data: "Test"
        })

      assert changeset.errors[:ntype] != nil
    end

    test "returns error for non-existent workspace" do
      assert {:error, :workspace_not_found} ==
               MsfData.create_note("nonexistent", %{ntype: "agent.test", data: "test"})
    end

    test "returns error for non-existent host" do
      workspace = create_msf_workspace()

      {:error, :host_not_found} =
        MsfData.create_note(workspace.name, %{
          ntype: "agent.test",
          data: "test",
          host: "10.99.99.99"
        })
    end
  end
end
