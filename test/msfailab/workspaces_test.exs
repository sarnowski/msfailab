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

defmodule Msfailab.WorkspacesTest do
  use Msfailab.DataCase, async: true

  alias Msfailab.Workspaces
  alias Msfailab.Workspaces.Workspace

  @valid_attrs %{slug: "test-workspace", name: "Test Workspace", description: "A test workspace"}
  @update_attrs %{name: "Updated Name", description: "Updated description"}
  @invalid_attrs %{slug: nil, name: nil}

  describe "list_workspaces/0" do
    test "returns all active workspaces" do
      {:ok, workspace} = Workspaces.create_workspace(@valid_attrs)
      assert Workspaces.list_workspaces() == [workspace]
    end

    test "excludes archived workspaces" do
      {:ok, workspace} = Workspaces.create_workspace(@valid_attrs)
      {:ok, _archived} = Workspaces.archive_workspace(workspace)
      assert Workspaces.list_workspaces() == []
    end
  end

  describe "list_all_workspaces/0" do
    test "returns all workspaces including archived" do
      {:ok, workspace} = Workspaces.create_workspace(@valid_attrs)
      {:ok, archived} = Workspaces.archive_workspace(workspace)
      assert Workspaces.list_all_workspaces() == [archived]
    end
  end

  describe "get_workspace/1" do
    test "returns workspace by id" do
      {:ok, workspace} = Workspaces.create_workspace(@valid_attrs)
      assert Workspaces.get_workspace(workspace.id) == workspace
    end

    test "returns nil for non-existent workspace" do
      assert Workspaces.get_workspace(999) == nil
    end
  end

  describe "get_workspace!/1" do
    test "returns workspace by id" do
      {:ok, workspace} = Workspaces.create_workspace(@valid_attrs)
      assert Workspaces.get_workspace!(workspace.id) == workspace
    end

    test "raises for non-existent workspace" do
      assert_raise Ecto.NoResultsError, fn ->
        Workspaces.get_workspace!(999)
      end
    end
  end

  describe "get_workspace_by_slug/1" do
    test "returns workspace by slug" do
      {:ok, workspace} = Workspaces.create_workspace(@valid_attrs)
      assert Workspaces.get_workspace_by_slug("test-workspace") == workspace
    end

    test "returns nil for non-existent slug" do
      assert Workspaces.get_workspace_by_slug("non-existent") == nil
    end

    test "returns nil for archived workspace" do
      {:ok, workspace} = Workspaces.create_workspace(@valid_attrs)
      {:ok, _archived} = Workspaces.archive_workspace(workspace)
      assert Workspaces.get_workspace_by_slug("test-workspace") == nil
    end
  end

  describe "create_workspace/1" do
    test "creates a workspace with valid attrs" do
      assert {:ok, %Workspace{} = workspace} = Workspaces.create_workspace(@valid_attrs)
      assert workspace.slug == "test-workspace"
      assert workspace.name == "Test Workspace"
      assert workspace.description == "A test workspace"
      assert workspace.archived_at == nil
    end

    test "returns error changeset with invalid attrs" do
      assert {:error, %Ecto.Changeset{}} = Workspaces.create_workspace(@invalid_attrs)
    end

    test "enforces unique slug" do
      {:ok, _workspace} = Workspaces.create_workspace(@valid_attrs)
      assert {:error, changeset} = Workspaces.create_workspace(@valid_attrs)
      assert "has already been taken" in errors_on(changeset).slug
    end

    test "allows single character slug" do
      assert {:ok, %Workspace{}} =
               Workspaces.create_workspace(%{@valid_attrs | slug: "a", name: "A"})
    end
  end

  describe "create_workspace/1 slug validation" do
    test "rejects slug with uppercase" do
      assert {:error, changeset} = Workspaces.create_workspace(%{@valid_attrs | slug: "Test"})
      assert errors_on(changeset).slug != []
    end

    test "rejects slug with underscore" do
      assert {:error, changeset} =
               Workspaces.create_workspace(%{@valid_attrs | slug: "test_slug"})

      assert errors_on(changeset).slug != []
    end

    test "rejects slug starting with hyphen" do
      assert {:error, changeset} = Workspaces.create_workspace(%{@valid_attrs | slug: "-test"})
      assert errors_on(changeset).slug != []
    end

    test "rejects slug ending with hyphen" do
      assert {:error, changeset} = Workspaces.create_workspace(%{@valid_attrs | slug: "test-"})
      assert errors_on(changeset).slug != []
    end

    test "rejects slug starting with number" do
      assert {:error, changeset} = Workspaces.create_workspace(%{@valid_attrs | slug: "1test"})
      assert errors_on(changeset).slug != []
    end

    test "rejects slug with consecutive hyphens" do
      assert {:error, changeset} =
               Workspaces.create_workspace(%{@valid_attrs | slug: "test--name"})

      assert errors_on(changeset).slug != []
    end

    test "rejects slug exceeding 32 characters" do
      long_slug = "abcdefghijklmnopqrstuvwxyz1234567"

      assert {:error, changeset} =
               Workspaces.create_workspace(%{@valid_attrs | slug: long_slug})

      assert errors_on(changeset).slug != []
    end

    test "accepts slug at exactly 32 characters" do
      slug_32 = "abcdefghijklmnopqrstuvwxyz123456"

      assert {:ok, %Workspace{}} =
               Workspaces.create_workspace(%{@valid_attrs | slug: slug_32})
    end
  end

  describe "create_workspace/1 name validation" do
    test "rejects name with leading whitespace" do
      assert {:error, changeset} =
               Workspaces.create_workspace(%{@valid_attrs | name: "  Test"})

      assert errors_on(changeset).name != []
    end

    test "rejects name with trailing whitespace" do
      assert {:error, changeset} =
               Workspaces.create_workspace(%{@valid_attrs | name: "Test  "})

      assert errors_on(changeset).name != []
    end

    test "rejects name with consecutive spaces" do
      assert {:error, changeset} =
               Workspaces.create_workspace(%{@valid_attrs | name: "Test  Name"})

      assert errors_on(changeset).name != []
    end

    test "rejects name with special characters" do
      assert {:error, changeset} =
               Workspaces.create_workspace(%{@valid_attrs | name: "Test!"})

      assert errors_on(changeset).name != []
    end

    test "accepts name with hyphens" do
      assert {:ok, %Workspace{}} =
               Workspaces.create_workspace(%{@valid_attrs | slug: "red-team", name: "Red-Team"})
    end

    test "accepts name with numbers" do
      assert {:ok, %Workspace{}} =
               Workspaces.create_workspace(%{
                 @valid_attrs
                 | slug: "project",
                   name: "Project 2024"
               })
    end
  end

  describe "update_workspace/2" do
    test "updates workspace with valid attrs" do
      {:ok, workspace} = Workspaces.create_workspace(@valid_attrs)
      assert {:ok, %Workspace{} = updated} = Workspaces.update_workspace(workspace, @update_attrs)
      assert updated.name == "Updated Name"
      assert updated.description == "Updated description"
      assert updated.slug == "test-workspace"
    end

    test "does not allow updating slug" do
      {:ok, workspace} = Workspaces.create_workspace(@valid_attrs)
      {:ok, updated} = Workspaces.update_workspace(workspace, %{slug: "new-slug"})
      assert updated.slug == "test-workspace"
    end

    test "validates name on update" do
      {:ok, workspace} = Workspaces.create_workspace(@valid_attrs)
      assert {:error, changeset} = Workspaces.update_workspace(workspace, %{name: "  Invalid  "})
      assert errors_on(changeset).name != []
    end
  end

  describe "archive_workspace/1" do
    test "sets archived_at timestamp" do
      {:ok, workspace} = Workspaces.create_workspace(@valid_attrs)
      assert workspace.archived_at == nil
      {:ok, archived} = Workspaces.archive_workspace(workspace)
      assert archived.archived_at != nil
    end
  end

  describe "change_workspace/2" do
    test "returns a changeset" do
      {:ok, workspace} = Workspaces.create_workspace(@valid_attrs)
      assert %Ecto.Changeset{} = Workspaces.change_workspace(workspace)
    end
  end
end
