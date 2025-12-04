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

defmodule Msfailab.Tools.MsfDataExecutorTest do
  use Msfailab.DataCase, async: true

  alias Msfailab.MsfData.{Cred, Host, Loot, MsfWorkspace, Note, Service, Session, Vuln}
  alias Msfailab.Repo
  alias Msfailab.Tools.MsfDataExecutor

  # ============================================================================
  # Test Helpers
  # ============================================================================

  defp create_msf_workspace(name) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %MsfWorkspace{}
    |> Ecto.Changeset.cast(
      %{
        name: name,
        boundary: "10.0.0.0/24",
        description: "Test workspace",
        created_at: now,
        updated_at: now
      },
      [:name, :boundary, :description, :created_at, :updated_at]
    )
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
      name: "exploit/test/vuln",
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

  defp create_cred(service, attrs \\ %{}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    default = %{
      user: "testuser",
      pass: "testpass",
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

  defp create_loot(workspace, attrs \\ %{}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    default = %{
      ltype: "host.files",
      name: "test_loot",
      info: "Test loot item",
      data: "Loot content here",
      workspace_id: workspace.id,
      created_at: now,
      updated_at: now
    }

    %Loot{}
    |> Ecto.Changeset.cast(Map.merge(default, attrs), [
      :ltype,
      :path,
      :data,
      :content_type,
      :name,
      :info,
      :workspace_id,
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

  # ============================================================================
  # handles_tool?/1
  # ============================================================================

  describe "handles_tool?/1" do
    test "returns true for all MSF data tools" do
      tools =
        ~w(list_hosts list_services list_vulns list_creds list_loots list_notes list_sessions retrieve_loot create_note)

      for tool <- tools do
        assert MsfDataExecutor.handles_tool?(tool), "Expected #{tool} to be handled"
      end
    end

    test "returns false for non-MSF data tools" do
      refute MsfDataExecutor.handles_tool?("msf_command")
      refute MsfDataExecutor.handles_tool?("bash_command")
      refute MsfDataExecutor.handles_tool?("unknown_tool")
    end
  end

  # ============================================================================
  # execute/3 - list_hosts
  # ============================================================================

  describe "execute list_hosts" do
    test "returns hosts for workspace" do
      workspace = create_msf_workspace("test-executor-hosts")
      host = create_host(workspace, %{address: "10.0.0.5"})

      {:ok, result} =
        MsfDataExecutor.execute("list_hosts", %{}, %{workspace_slug: workspace.name})

      assert result.count == 1
      assert hd(result.hosts).id == host.id
    end

    test "filters by address" do
      workspace = create_msf_workspace("test-executor-hosts-filter")
      host1 = create_host(workspace, %{address: "10.0.0.5"})
      _host2 = create_host(workspace, %{address: "10.0.0.6"})

      {:ok, result} =
        MsfDataExecutor.execute(
          "list_hosts",
          %{"address" => "10.0.0.5"},
          %{workspace_slug: workspace.name}
        )

      assert result.count == 1
      assert hd(result.hosts).id == host1.id
    end

    test "returns error for non-existent workspace" do
      {:error, :workspace_not_found} =
        MsfDataExecutor.execute("list_hosts", %{}, %{workspace_slug: "nonexistent"})
    end
  end

  # ============================================================================
  # execute/3 - list_services
  # ============================================================================

  describe "execute list_services" do
    test "returns services for workspace" do
      workspace = create_msf_workspace("test-executor-services")
      host = create_host(workspace)

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      service =
        %Msfailab.MsfData.Service{}
        |> Ecto.Changeset.cast(
          %{
            port: 80,
            proto: "tcp",
            state: "open",
            name: "http",
            host_id: host.id,
            created_at: now,
            updated_at: now
          },
          [:port, :proto, :state, :name, :host_id, :created_at, :updated_at]
        )
        |> Repo.insert!()

      {:ok, result} =
        MsfDataExecutor.execute("list_services", %{}, %{workspace_slug: workspace.name})

      assert result.count == 1
      assert hd(result.services).id == service.id
    end
  end

  # ============================================================================
  # execute/3 - list_vulns
  # ============================================================================

  describe "execute list_vulns" do
    test "returns vulns for workspace" do
      workspace = create_msf_workspace("test-executor-vulns")
      host = create_host(workspace)
      vuln = create_vuln(host)

      {:ok, result} =
        MsfDataExecutor.execute("list_vulns", %{}, %{workspace_slug: workspace.name})

      assert result.count == 1
      assert hd(result.vulns).id == vuln.id
    end

    test "filters by host address" do
      workspace = create_msf_workspace("test-executor-vulns-filter")
      host1 = create_host(workspace, %{address: "10.0.0.5"})
      host2 = create_host(workspace, %{address: "10.0.0.6"})
      vuln1 = create_vuln(host1)
      _vuln2 = create_vuln(host2)

      {:ok, result} =
        MsfDataExecutor.execute(
          "list_vulns",
          %{"host" => "10.0.0.5"},
          %{workspace_slug: workspace.name}
        )

      assert result.count == 1
      assert hd(result.vulns).id == vuln1.id
    end
  end

  # ============================================================================
  # execute/3 - list_creds
  # ============================================================================

  describe "execute list_creds" do
    test "returns creds for workspace" do
      workspace = create_msf_workspace("test-executor-creds")
      host = create_host(workspace)
      service = create_service(host, %{port: 22, name: "ssh"})
      cred = create_cred(service)

      {:ok, result} =
        MsfDataExecutor.execute("list_creds", %{}, %{workspace_slug: workspace.name})

      assert result.count == 1
      assert hd(result.creds).id == cred.id
    end

    test "filters by user" do
      workspace = create_msf_workspace("test-executor-creds-filter")
      host = create_host(workspace)
      service = create_service(host, %{port: 22})
      cred1 = create_cred(service, %{user: "admin"})
      _cred2 = create_cred(service, %{user: "guest"})

      {:ok, result} =
        MsfDataExecutor.execute(
          "list_creds",
          %{"user" => "admin"},
          %{workspace_slug: workspace.name}
        )

      assert result.count == 1
      assert hd(result.creds).id == cred1.id
    end
  end

  # ============================================================================
  # execute/3 - list_loots
  # ============================================================================

  describe "execute list_loots" do
    test "returns loots for workspace" do
      workspace = create_msf_workspace("test-executor-loots")
      loot = create_loot(workspace)

      {:ok, result} =
        MsfDataExecutor.execute("list_loots", %{}, %{workspace_slug: workspace.name})

      assert result.count == 1
      assert hd(result.loots).id == loot.id
    end

    test "filters by ltype" do
      workspace = create_msf_workspace("test-executor-loots-filter")
      loot1 = create_loot(workspace, %{ltype: "windows.hashes"})
      _loot2 = create_loot(workspace, %{ltype: "host.files"})

      {:ok, result} =
        MsfDataExecutor.execute(
          "list_loots",
          %{"ltype" => "windows.hashes"},
          %{workspace_slug: workspace.name}
        )

      assert result.count == 1
      assert hd(result.loots).id == loot1.id
    end
  end

  # ============================================================================
  # execute/3 - list_notes
  # ============================================================================

  describe "execute list_notes" do
    test "returns notes for workspace" do
      workspace = create_msf_workspace("test-executor-notes-list")
      note = create_note(workspace)

      {:ok, result} =
        MsfDataExecutor.execute("list_notes", %{}, %{workspace_slug: workspace.name})

      assert result.count == 1
      assert hd(result.notes).id == note.id
    end

    test "filters by ntype" do
      workspace = create_msf_workspace("test-executor-notes-filter")
      note1 = create_note(workspace, %{ntype: "agent.observation"})
      _note2 = create_note(workspace, %{ntype: "agent.finding"})

      {:ok, result} =
        MsfDataExecutor.execute(
          "list_notes",
          %{"ntype" => "agent.observation"},
          %{workspace_slug: workspace.name}
        )

      assert result.count == 1
      assert hd(result.notes).id == note1.id
    end
  end

  # ============================================================================
  # execute/3 - list_sessions
  # ============================================================================

  describe "execute list_sessions" do
    test "returns sessions for workspace" do
      workspace = create_msf_workspace("test-executor-sessions")
      host = create_host(workspace)
      session = create_session(host)

      {:ok, result} =
        MsfDataExecutor.execute("list_sessions", %{}, %{workspace_slug: workspace.name})

      assert result.count == 1
      assert hd(result.sessions).id == session.id
    end

    test "filters by session type" do
      workspace = create_msf_workspace("test-executor-sessions-filter")
      host = create_host(workspace)
      session1 = create_session(host, %{stype: "meterpreter"})
      _session2 = create_session(host, %{stype: "shell"})

      {:ok, result} =
        MsfDataExecutor.execute(
          "list_sessions",
          %{"stype" => "meterpreter"},
          %{workspace_slug: workspace.name}
        )

      assert result.count == 1
      assert hd(result.sessions).id == session1.id
    end
  end

  # ============================================================================
  # execute/3 - retrieve_loot
  # ============================================================================

  describe "execute retrieve_loot" do
    test "retrieves loot content" do
      workspace = create_msf_workspace("test-executor-retrieve-loot")
      loot = create_loot(workspace, %{data: "Secret data content"})

      {:ok, result} =
        MsfDataExecutor.execute(
          "retrieve_loot",
          %{"loot_id" => loot.id},
          %{workspace_slug: workspace.name}
        )

      assert result.content == "Secret data content"
      assert result.loot_id == loot.id
      assert result.truncated == false
    end

    test "returns error for non-existent loot" do
      workspace = create_msf_workspace("test-executor-retrieve-loot-notfound")

      {:error, :loot_not_found} =
        MsfDataExecutor.execute(
          "retrieve_loot",
          %{"loot_id" => 99_999},
          %{workspace_slug: workspace.name}
        )
    end
  end

  # ============================================================================
  # execute/3 - create_note
  # ============================================================================

  describe "execute create_note" do
    test "creates note in workspace" do
      workspace = create_msf_workspace("test-executor-notes")

      {:ok, result} =
        MsfDataExecutor.execute(
          "create_note",
          %{
            "ntype" => "agent.observation",
            "content" => "Test observation"
          },
          %{workspace_slug: workspace.name}
        )

      assert result.created == true
      assert result.ntype == "agent.observation"
    end

    test "returns error for invalid ntype" do
      workspace = create_msf_workspace("test-executor-notes-invalid")

      {:error, {:validation_error, errors}} =
        MsfDataExecutor.execute(
          "create_note",
          %{
            "ntype" => "invalid",
            "content" => "Test"
          },
          %{workspace_slug: workspace.name}
        )

      assert errors[:ntype] != nil
    end

    test "returns error for non-existent workspace" do
      {:error, :workspace_not_found} =
        MsfDataExecutor.execute(
          "create_note",
          %{
            "ntype" => "agent.test",
            "content" => "Test"
          },
          %{workspace_slug: "nonexistent"}
        )
    end
  end

  # ============================================================================
  # execute/3 - unknown tool
  # ============================================================================

  describe "execute unknown tool" do
    test "returns error for unknown tool" do
      {:error, {:unknown_tool, "unknown"}} =
        MsfDataExecutor.execute("unknown", %{}, %{workspace_slug: "test"})
    end
  end
end
