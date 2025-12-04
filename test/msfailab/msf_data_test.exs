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

  import Mox

  alias Msfailab.Containers.Msgrpc.ClientMock, as: MsgrpcClientMock
  alias Msfailab.MsfData
  alias Msfailab.MsfData.{Cred, Host, Loot, MsfWorkspace, Note, Service, Session, Vuln}
  alias Msfailab.Repo

  setup :verify_on_exit!

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
      host_id: host.id
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
      :host_id
    ])
    |> Repo.insert!()
  end

  defp create_cred(service, attrs \\ %{}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    default = %{
      user: "admin",
      pass: "password123",
      ptype: "password",
      active: true,
      service_id: service.id,
      created_at: now,
      updated_at: now
    }

    %Cred{}
    |> Ecto.Changeset.cast(Map.merge(default, attrs), [
      :user,
      :pass,
      :ptype,
      :active,
      :proof,
      :service_id,
      :created_at,
      :updated_at
    ])
    |> Repo.insert!()
  end

  defp create_loot(workspace, attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    default = %{
      ltype: "host.files",
      name: "test_loot.txt",
      info: "Test loot file",
      content_type: "text/plain",
      path: "/tmp/test_loot.txt",
      workspace_id: workspace.id,
      created_at: now,
      updated_at: now
    }

    %Loot{}
    |> Ecto.Changeset.cast(Map.merge(default, attrs), [
      :ltype,
      :name,
      :info,
      :content_type,
      :path,
      :data,
      :workspace_id,
      :host_id,
      :service_id,
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

    test "sorts by address ascending" do
      workspace = create_msf_workspace()
      _h1 = create_host(workspace, %{address: "10.0.0.3"})
      _h2 = create_host(workspace, %{address: "10.0.0.1"})
      _h3 = create_host(workspace, %{address: "10.0.0.2"})

      {:ok, result} = MsfData.list_hosts(workspace.name, %{sort_by: :address, sort_dir: :asc})

      addresses = Enum.map(result.hosts, & &1.address)
      assert addresses == ["10.0.0.1", "10.0.0.2", "10.0.0.3"]
    end

    test "sorts by address descending" do
      workspace = create_msf_workspace()
      _h1 = create_host(workspace, %{address: "10.0.0.1"})
      _h2 = create_host(workspace, %{address: "10.0.0.3"})
      _h3 = create_host(workspace, %{address: "10.0.0.2"})

      {:ok, result} = MsfData.list_hosts(workspace.name, %{sort_by: :address, sort_dir: :desc})

      addresses = Enum.map(result.hosts, & &1.address)
      assert addresses == ["10.0.0.3", "10.0.0.2", "10.0.0.1"]
    end

    test "sorts by name" do
      workspace = create_msf_workspace()
      _h1 = create_host(workspace, %{address: "10.0.0.1", name: "charlie"})
      _h2 = create_host(workspace, %{address: "10.0.0.2", name: "alpha"})
      _h3 = create_host(workspace, %{address: "10.0.0.3", name: "bravo"})

      {:ok, result} = MsfData.list_hosts(workspace.name, %{sort_by: :name, sort_dir: :asc})

      names = Enum.map(result.hosts, & &1.name)
      assert names == ["alpha", "bravo", "charlie"]
    end

    test "defaults to updated_at desc when no sort specified" do
      workspace = create_msf_workspace()
      base_time = DateTime.utc_now() |> DateTime.truncate(:second)

      _h1 =
        create_host(workspace, %{address: "10.0.0.1", updated_at: DateTime.add(base_time, -60)})

      _h2 = create_host(workspace, %{address: "10.0.0.2", updated_at: base_time})

      _h3 =
        create_host(workspace, %{address: "10.0.0.3", updated_at: DateTime.add(base_time, -30)})

      {:ok, result} = MsfData.list_hosts(workspace.name)

      # Default is updated_at desc, so most recent first
      addresses = Enum.map(result.hosts, & &1.address)
      assert addresses == ["10.0.0.2", "10.0.0.3", "10.0.0.1"]
    end

    test "paginates with offset and returns total_count" do
      workspace = create_msf_workspace()

      for i <- 1..10 do
        create_host(workspace, %{address: "10.0.0.#{i}"})
      end

      {:ok, result} = MsfData.list_hosts(workspace.name, %{offset: 0, limit: 3})

      assert result.count == 3
      assert result.total_count == 10
      assert length(result.hosts) == 3
    end

    test "offset skips the specified number of records" do
      workspace = create_msf_workspace()

      for i <- 1..5 do
        create_host(workspace, %{address: "10.0.0.#{i}"})
      end

      # Sort by address ascending for predictable order
      {:ok, page1} =
        MsfData.list_hosts(workspace.name, %{
          offset: 0,
          limit: 2,
          sort_by: :address,
          sort_dir: :asc
        })

      {:ok, page2} =
        MsfData.list_hosts(workspace.name, %{
          offset: 2,
          limit: 2,
          sort_by: :address,
          sort_dir: :asc
        })

      page1_addresses = Enum.map(page1.hosts, & &1.address)
      page2_addresses = Enum.map(page2.hosts, & &1.address)

      assert page1_addresses == ["10.0.0.1", "10.0.0.2"]
      assert page2_addresses == ["10.0.0.3", "10.0.0.4"]
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

    test "sorts by port ascending" do
      workspace = create_msf_workspace()
      host = create_host(workspace)
      _s1 = create_service(host, %{port: 443})
      _s2 = create_service(host, %{port: 22})
      _s3 = create_service(host, %{port: 80})

      {:ok, result} = MsfData.list_services(workspace.name, %{sort_by: :port, sort_dir: :asc})

      ports = Enum.map(result.services, & &1.port)
      assert ports == [22, 80, 443]
    end

    test "sorts by port descending" do
      workspace = create_msf_workspace()
      host = create_host(workspace)
      _s1 = create_service(host, %{port: 22})
      _s2 = create_service(host, %{port: 443})
      _s3 = create_service(host, %{port: 80})

      {:ok, result} = MsfData.list_services(workspace.name, %{sort_by: :port, sort_dir: :desc})

      ports = Enum.map(result.services, & &1.port)
      assert ports == [443, 80, 22]
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

  # ============================================================================
  # count_assets/1
  # ============================================================================

  describe "count_assets/1" do
    test "returns zero counts for empty workspace" do
      workspace = create_msf_workspace()

      {:ok, counts} = MsfData.count_assets(workspace.name)

      assert counts == %{
               hosts: 0,
               services: 0,
               vulns: 0,
               notes: 0,
               creds: 0,
               loots: 0,
               sessions: 0,
               total: 0
             }
    end

    test "returns correct counts for all asset types" do
      workspace = create_msf_workspace()

      # Create hosts
      host1 = create_host(workspace, %{address: "10.0.0.1"})
      host2 = create_host(workspace, %{address: "10.0.0.2"})

      # Create services
      service1 = create_service(host1, %{port: 22, name: "ssh"})
      service2 = create_service(host1, %{port: 80, name: "http"})
      _service3 = create_service(host2, %{port: 443, name: "https"})

      # Create vulns
      create_vuln(host1)
      create_vuln(host2)

      # Create notes
      create_note(workspace)
      create_note(workspace)
      create_note(workspace)

      # Create creds
      create_cred(service1)
      create_cred(service2)

      # Create loots
      create_loot(workspace, %{host_id: host1.id})

      # Create sessions
      create_session(host1)
      create_session(host2)

      {:ok, counts} = MsfData.count_assets(workspace.name)

      assert counts == %{
               hosts: 2,
               services: 3,
               vulns: 2,
               notes: 3,
               creds: 2,
               loots: 1,
               sessions: 2,
               total: 15
             }
    end

    test "counts are scoped to workspace" do
      workspace1 = create_msf_workspace()
      workspace2 = create_msf_workspace()

      # Create assets in workspace1
      host1 = create_host(workspace1, %{address: "10.0.0.1"})
      create_service(host1, %{port: 22})
      create_note(workspace1)

      # Create assets in workspace2
      host2 = create_host(workspace2, %{address: "10.0.0.2"})
      create_service(host2, %{port: 80})
      create_service(host2, %{port: 443})
      create_note(workspace2)
      create_note(workspace2)

      {:ok, counts1} = MsfData.count_assets(workspace1.name)
      {:ok, counts2} = MsfData.count_assets(workspace2.name)

      assert counts1.hosts == 1
      assert counts1.services == 1
      assert counts1.notes == 1

      assert counts2.hosts == 1
      assert counts2.services == 2
      assert counts2.notes == 2
    end

    test "returns error for non-existent workspace" do
      assert {:error, :workspace_not_found} == MsfData.count_assets("nonexistent")
    end
  end

  # ============================================================================
  # get_host/2
  # ============================================================================

  describe "get_host/2" do
    test "returns host with related counts" do
      workspace = create_msf_workspace()
      host = create_host(workspace, %{address: "10.0.0.5", name: "testhost"})
      service = create_service(host, %{port: 80})
      create_vuln(host)
      create_note(workspace, %{host_id: host.id})
      create_session(host)
      create_loot(workspace, %{host_id: host.id})
      create_cred(service)

      {:ok, result} = MsfData.get_host(workspace.name, host.id)

      assert result.id == host.id
      assert result.address == "10.0.0.5"
      assert result.name == "testhost"
      assert length(result.related_services) == 1
      assert length(result.related_vulns) == 1
      assert length(result.related_notes) == 1
      assert length(result.related_sessions) == 1
      assert length(result.related_loots) == 1
    end

    test "returns error for non-existent host" do
      workspace = create_msf_workspace()

      assert {:error, :not_found} == MsfData.get_host(workspace.name, 99_999)
    end

    test "returns error for non-existent workspace" do
      assert {:error, :workspace_not_found} == MsfData.get_host("nonexistent", 1)
    end
  end

  # ============================================================================
  # get_service/2
  # ============================================================================

  describe "get_service/2" do
    test "returns service with host info and related counts" do
      workspace = create_msf_workspace()
      host = create_host(workspace, %{address: "10.0.0.5", name: "testhost", os_name: "Linux"})
      service = create_service(host, %{port: 80, name: "http"})
      create_vuln(host, %{service_id: service.id})
      create_cred(service)
      create_note(workspace, %{host_id: host.id, service_id: service.id})

      {:ok, result} = MsfData.get_service(workspace.name, service.id)

      assert result.id == service.id
      assert result.port == 80
      assert result.host_address == "10.0.0.5"
      assert result.host_name == "testhost"
      assert result.host_os == "Linux"
      assert length(result.related_vulns) == 1
      assert length(result.related_creds) == 1
      assert length(result.related_notes) == 1
    end

    test "returns error for non-existent service" do
      workspace = create_msf_workspace()

      assert {:error, :not_found} == MsfData.get_service(workspace.name, 99_999)
    end
  end

  # ============================================================================
  # get_vuln/2
  # ============================================================================

  describe "get_vuln/2" do
    test "returns vuln with host and service info" do
      workspace = create_msf_workspace()
      host = create_host(workspace, %{address: "10.0.0.5", name: "testhost", os_name: "Windows"})
      service = create_service(host, %{port: 445, proto: "tcp", name: "smb"})
      vuln = create_vuln(host, %{service_id: service.id, name: "exploit/windows/smb/ms17_010"})

      {:ok, result} = MsfData.get_vuln(workspace.name, vuln.id)

      assert result.id == vuln.id
      assert result.name == "exploit/windows/smb/ms17_010"
      assert result.host_address == "10.0.0.5"
      assert result.host_name == "testhost"
      assert result.host_os == "Windows"
      assert result.service_port == 445
      assert result.service_proto == "tcp"
      assert result.service_name == "smb"
    end

    test "returns vuln without service info when no service" do
      workspace = create_msf_workspace()
      host = create_host(workspace, %{address: "10.0.0.5"})
      vuln = create_vuln(host, %{service_id: nil})

      {:ok, result} = MsfData.get_vuln(workspace.name, vuln.id)

      assert result.id == vuln.id
      assert result.host_address == "10.0.0.5"
      refute Map.has_key?(result, :service_port)
    end

    test "returns error for non-existent vuln" do
      workspace = create_msf_workspace()

      assert {:error, :not_found} == MsfData.get_vuln(workspace.name, 99_999)
    end
  end

  # ============================================================================
  # get_note/2
  # ============================================================================

  describe "get_note/2" do
    test "returns note with host and service info" do
      workspace = create_msf_workspace()
      host = create_host(workspace, %{address: "10.0.0.5", name: "testhost"})
      service = create_service(host, %{port: 80, proto: "tcp", name: "http"})
      note = create_note(workspace, %{host_id: host.id, service_id: service.id})

      {:ok, result} = MsfData.get_note(workspace.name, note.id)

      assert result.id == note.id
      assert result.host_address == "10.0.0.5"
      assert result.host_name == "testhost"
      assert result.service_port == 80
      assert result.service_name == "http"
    end

    test "returns note without host/service when not attached" do
      workspace = create_msf_workspace()
      note = create_note(workspace, %{host_id: nil, service_id: nil})

      {:ok, result} = MsfData.get_note(workspace.name, note.id)

      assert result.id == note.id
      assert result.host_address == nil
    end

    test "returns error for non-existent note" do
      workspace = create_msf_workspace()

      assert {:error, :not_found} == MsfData.get_note(workspace.name, 99_999)
    end

    test "returns is_serialized: true when data is Ruby Marshal encoded" do
      workspace = create_msf_workspace()
      # Real Marshal data: {:time => "Thu Nov 27 07:24:03 2025"}
      marshal_data = "BAh7BjoJdGltZSIdVGh1IE5vdiAyNyAwNzoyNDowMyAyMDI1"
      note = create_note(workspace, %{ntype: "host.last_boot", data: marshal_data})

      {:ok, result} = MsfData.get_note(workspace.name, note.id)

      assert result.is_serialized == true
      assert result.data == marshal_data
    end

    test "returns is_serialized: false when data is plain text" do
      workspace = create_msf_workspace()
      note = create_note(workspace, %{ntype: "agent.observation", data: "Plain text note"})

      {:ok, result} = MsfData.get_note(workspace.name, note.id)

      assert result.is_serialized == false
      assert result.data == "Plain text note"
    end
  end

  # ============================================================================
  # get_note/3 with RPC deserialization
  # ============================================================================

  describe "get_note/3 with RPC context" do
    setup do
      workspace = create_msf_workspace()
      host = create_host(workspace, %{address: "10.0.0.5"})
      {:ok, workspace: workspace, host: host}
    end

    test "deserializes Marshal data via RPC when context provided", %{
      workspace: workspace,
      host: host
    } do
      marshal_data = "BAh7BjoJdGltZSIdVGh1IE5vdiAyNyAwNzoyNDowMyAyMDI1"

      note =
        create_note(workspace, %{ntype: "host.last_boot", data: marshal_data, host_id: host.id})

      # Mock RPC client
      rpc_context = %{
        client: MsgrpcClientMock,
        endpoint: %{host: "localhost", port: 55_553},
        token: "test-token"
      }

      # Expect RPC call to db.notes and return deserialized data
      # Note: RPC uses "type" instead of "ntype" and doesn't include an "id" field
      expect(MsgrpcClientMock, :call, fn endpoint, token, "db.notes", [opts] ->
        assert endpoint == %{host: "localhost", port: 55_553}
        assert token == "test-token"
        assert opts["workspace"] == workspace.name

        {:ok,
         %{
           "notes" => [
             %{
               "type" => "host.last_boot",
               "data" => %{"time" => "Thu Nov 27 07:24:03 2025"},
               "host" => "10.0.0.5"
             }
           ]
         }}
      end)

      {:ok, result} = MsfData.get_note(workspace.name, note.id, rpc_context)

      assert result.data == %{"time" => "Thu Nov 27 07:24:03 2025"}
      assert result.deserialization_error == nil
      assert result.is_serialized == true
    end

    test "returns raw data with deserialization_error when RPC fails", %{workspace: workspace} do
      marshal_data = "BAh7BjoJdGltZSIdVGh1IE5vdiAyNyAwNzoyNDowMyAyMDI1"
      note = create_note(workspace, %{ntype: "host.last_boot", data: marshal_data})

      rpc_context = %{
        client: MsgrpcClientMock,
        endpoint: %{host: "localhost", port: 55_553},
        token: "test-token"
      }

      # RPC call fails
      expect(MsgrpcClientMock, :call, fn _endpoint, _token, "db.notes", _opts ->
        {:error, :connection_refused}
      end)

      {:ok, result} = MsfData.get_note(workspace.name, note.id, rpc_context)

      # Returns raw data with error
      assert result.data == marshal_data
      assert result.deserialization_error =~ "connection_refused"
      assert result.is_serialized == true
    end

    test "does not call RPC for plain text data", %{workspace: workspace} do
      note = create_note(workspace, %{ntype: "agent.observation", data: "Plain text"})

      rpc_context = %{
        client: MsgrpcClientMock,
        endpoint: %{host: "localhost", port: 55_553},
        token: "test-token"
      }

      # No RPC call expected - Mox will fail if call is made
      {:ok, result} = MsfData.get_note(workspace.name, note.id, rpc_context)

      assert result.data == "Plain text"
      assert result.is_serialized == false
      refute Map.has_key?(result, :deserialization_error)
    end

    test "returns raw data when note not found in RPC response", %{
      workspace: workspace,
      host: host
    } do
      marshal_data = "BAh7BjoJdGltZSIdVGh1IE5vdiAyNyAwNzoyNDowMyAyMDI1"

      note =
        create_note(workspace, %{ntype: "host.last_boot", data: marshal_data, host_id: host.id})

      rpc_context = %{
        client: MsgrpcClientMock,
        endpoint: %{host: "localhost", port: 55_553},
        token: "test-token"
      }

      # RPC returns notes but none match our type/host combination
      expect(MsgrpcClientMock, :call, fn _endpoint, _token, "db.notes", _opts ->
        {:ok,
         %{
           "notes" => [
             %{"type" => "other.type", "host" => "10.0.0.5", "data" => "something"}
           ]
         }}
      end)

      {:ok, result} = MsfData.get_note(workspace.name, note.id, rpc_context)

      assert result.data == marshal_data
      assert result.deserialization_error =~ "not found"
      assert result.is_serialized == true
    end

    test "handles RPC error response with error_message", %{workspace: workspace} do
      marshal_data = "BAh7BjoJdGltZSIdVGh1IE5vdiAyNyAwNzoyNDowMyAyMDI1"
      note = create_note(workspace, %{ntype: "host.last_boot", data: marshal_data})

      rpc_context = %{
        client: MsgrpcClientMock,
        endpoint: %{host: "localhost", port: 55_553},
        token: "invalid-token"
      }

      # RPC returns error response (as {:ok, %{"error" => true, ...}})
      expect(MsgrpcClientMock, :call, fn _endpoint, _token, "db.notes", _opts ->
        {:ok,
         %{
           "error" => true,
           "error_code" => 401,
           "error_message" => "Invalid Authentication Token"
         }}
      end)

      {:ok, result} = MsfData.get_note(workspace.name, note.id, rpc_context)

      assert result.data == marshal_data
      assert result.deserialization_error =~ "Invalid Authentication Token"
      assert result.is_serialized == true
    end

    test "matches note by type and host since RPC doesn't return IDs", %{
      workspace: workspace,
      host: host
    } do
      marshal_data = "BAh7BjoJdGltZSIdVGh1IE5vdiAyNyAwNzoyNDowMyAyMDI1"

      note =
        create_note(workspace, %{ntype: "host.last_boot", data: marshal_data, host_id: host.id})

      rpc_context = %{
        client: MsgrpcClientMock,
        endpoint: %{host: "localhost", port: 55_553},
        token: "test-token"
      }

      # RPC returns multiple notes - we should match by type and host
      expect(MsgrpcClientMock, :call, fn _endpoint, _token, "db.notes", _opts ->
        {:ok,
         %{
           "notes" => [
             %{"type" => "other.note", "host" => "10.0.0.5", "data" => "wrong"},
             %{
               "type" => "host.last_boot",
               "host" => "10.0.0.5",
               "data" => %{"time" => "Thu Nov 27 07:24:03 2025"}
             },
             %{"type" => "host.last_boot", "host" => "10.0.0.99", "data" => "wrong host"}
           ]
         }}
      end)

      {:ok, result} = MsfData.get_note(workspace.name, note.id, rpc_context)

      # Should match by type=host.last_boot and host=10.0.0.5
      assert result.data == %{"time" => "Thu Nov 27 07:24:03 2025"}
      assert result.deserialization_error == nil
    end
  end

  # ============================================================================
  # get_cred/2
  # ============================================================================

  describe "get_cred/2" do
    test "returns cred with host and service info" do
      workspace = create_msf_workspace()
      host = create_host(workspace, %{address: "10.0.0.5", name: "testhost", os_name: "Linux"})
      service = create_service(host, %{port: 22, proto: "tcp", name: "ssh", info: "OpenSSH"})
      cred = create_cred(service, %{user: "admin", pass: "secret123"})

      {:ok, result} = MsfData.get_cred(workspace.name, cred.id)

      assert result.id == cred.id
      assert result.user == "admin"
      assert result.pass == "secret123"
      assert result.host_id == host.id
      assert result.host_address == "10.0.0.5"
      assert result.host_name == "testhost"
      assert result.service_id == service.id
      assert result.service_port == 22
      assert result.service_proto == "tcp"
      assert result.service_info == "OpenSSH"
    end

    test "returns error for non-existent cred" do
      workspace = create_msf_workspace()

      assert {:error, :not_found} == MsfData.get_cred(workspace.name, 99_999)
    end
  end

  # ============================================================================
  # get_loot/2
  # ============================================================================

  describe "get_loot/2" do
    test "returns loot with host info and data" do
      workspace = create_msf_workspace()
      host = create_host(workspace, %{address: "10.0.0.5", name: "testhost", os_name: "Linux"})
      loot = create_loot(workspace, %{host_id: host.id, data: "secret content"})

      {:ok, result} = MsfData.get_loot(workspace.name, loot.id)

      assert result.id == loot.id
      assert result.host_address == "10.0.0.5"
      assert result.host_name == "testhost"
      assert result.host_os == "Linux"
      assert result.data == "secret content"
    end

    test "returns loot without host when not attached" do
      workspace = create_msf_workspace()
      loot = create_loot(workspace, %{host_id: nil})

      {:ok, result} = MsfData.get_loot(workspace.name, loot.id)

      assert result.id == loot.id
      assert result.host_address == nil
    end

    test "returns error for non-existent loot" do
      workspace = create_msf_workspace()

      assert {:error, :not_found} == MsfData.get_loot(workspace.name, 99_999)
    end
  end

  # ============================================================================
  # get_session/2
  # ============================================================================

  describe "get_session/2" do
    test "returns session with host info" do
      workspace = create_msf_workspace()
      host = create_host(workspace, %{address: "10.0.0.5", name: "testhost", os_name: "Windows"})

      session =
        create_session(host, %{
          stype: "meterpreter",
          via_exploit: "exploit/windows/smb/ms17_010"
        })

      {:ok, result} = MsfData.get_session(workspace.name, session.id)

      assert result.id == session.id
      assert result.stype == "meterpreter"
      assert result.host_address == "10.0.0.5"
      assert result.host_name == "testhost"
      assert result.host_os == "Windows"
    end

    test "returns error for non-existent session" do
      workspace = create_msf_workspace()

      assert {:error, :not_found} == MsfData.get_session(workspace.name, 99_999)
    end
  end

  # ============================================================================
  # is_marshaled_data?/1
  # ============================================================================

  describe "marshaled_data?/1" do
    test "returns true for base64-encoded Ruby Marshal hash" do
      # Real Marshal data: {:time => "Thu Nov 27 07:24:03 2025"}
      # Decodes to: <<0x04, 0x08, 0x7B, ...>> (Marshal v4.8 + Hash)
      marshal_data = "BAh7BjoJdGltZSIdVGh1IE5vdiAyNyAwNzoyNDowMyAyMDI1"

      assert MsfData.marshaled_data?(marshal_data)
    end

    test "returns false for plain text" do
      refute MsfData.marshaled_data?("Just some plain text")
      refute MsfData.marshaled_data?("Test note content")
    end

    test "returns false for nil" do
      refute MsfData.marshaled_data?(nil)
    end

    test "returns false for empty string" do
      refute MsfData.marshaled_data?("")
    end

    test "returns false for invalid base64" do
      refute MsfData.marshaled_data?("not-valid-base64!!!")
    end

    test "returns false for valid base64 that is not Marshal data" do
      # "Hello World" in base64
      refute MsfData.marshaled_data?("SGVsbG8gV29ybGQ=")
    end

    test "returns true when data has trailing whitespace (common in DB values)" do
      # Metasploit often stores data with trailing newlines
      marshal_data_with_newline = "BAh7BjoJdGltZSIdVGh1IE5vdiAyNyAwNzoyNDowMyAyMDI1\n"
      marshal_data_with_spaces = "BAh7BjoJdGltZSIdVGh1IE5vdiAyNyAwNzoyNDowMyAyMDI1  \n"

      assert MsfData.marshaled_data?(marshal_data_with_newline)
      assert MsfData.marshaled_data?(marshal_data_with_spaces)
    end
  end

  # ============================================================================
  # count_assets/2 (with search filter)
  # ============================================================================

  describe "count_assets/2" do
    test "filters counts by search term matching hostname" do
      workspace = create_msf_workspace()

      host1 = create_host(workspace, %{address: "10.0.0.1", name: "webserver"})
      host2 = create_host(workspace, %{address: "10.0.0.2", name: "database"})
      create_service(host1, %{port: 80, name: "http"})
      create_service(host2, %{port: 3306, name: "mysql"})

      {:ok, counts} = MsfData.count_assets(workspace.name, "webserver")

      assert counts.hosts == 1
      # Services don't match "webserver" in their fields
      assert counts.services == 0
    end

    test "filters counts by search term matching service name" do
      workspace = create_msf_workspace()

      host = create_host(workspace, %{address: "10.0.0.1", name: "server1"})
      create_service(host, %{port: 80, name: "http", info: "Apache HTTP Server"})
      create_service(host, %{port: 22, name: "ssh"})

      {:ok, counts} = MsfData.count_assets(workspace.name, "apache")

      assert counts.hosts == 0
      assert counts.services == 1
    end

    test "filters counts by search term matching vuln name" do
      workspace = create_msf_workspace()

      host = create_host(workspace, %{address: "10.0.0.1"})
      create_vuln(host, %{name: "exploit/windows/smb/ms17_010_eternalblue"})
      create_vuln(host, %{name: "exploit/linux/ssh/weak_keys"})

      {:ok, counts} = MsfData.count_assets(workspace.name, "eternalblue")

      assert counts.vulns == 1
    end

    test "search is case-insensitive" do
      workspace = create_msf_workspace()

      _host = create_host(workspace, %{address: "10.0.0.1", name: "WebServer"})

      {:ok, counts} = MsfData.count_assets(workspace.name, "webserver")

      assert counts.hosts == 1
    end

    test "empty search term returns all counts" do
      workspace = create_msf_workspace()

      host = create_host(workspace, %{address: "10.0.0.1"})
      create_service(host, %{port: 80})

      {:ok, counts_with_empty} = MsfData.count_assets(workspace.name, "")
      {:ok, counts_without} = MsfData.count_assets(workspace.name)

      assert counts_with_empty == counts_without
    end

    test "returns error for non-existent workspace" do
      assert {:error, :workspace_not_found} == MsfData.count_assets("nonexistent", "search")
    end
  end
end
