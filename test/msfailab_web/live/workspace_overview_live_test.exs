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

defmodule MsfailabWeb.WorkspaceOverviewLiveTest do
  use MsfailabWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Msfailab.Workspaces

  describe "mount/3" do
    test "loads page with workspaces list", %{conn: conn} do
      # Create a workspace first
      {:ok, workspace} =
        Workspaces.create_workspace(%{name: "Test Workspace", slug: "test-workspace-mount"})

      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Metasploit AI Lab"
      assert html =~ "Your Workspaces"
      assert html =~ workspace.name
    end

    test "shows empty state when no workspaces", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Your Workspaces"
      assert html =~ "New Workspace"
    end

    test "modal is initially hidden", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Modal should not be visible initially
      refute has_element?(view, "#create-workspace-modal[open]")
    end
  end

  describe "open_create_modal event" do
    test "opens the create workspace modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Click the new workspace button
      view
      |> element("[phx-click*='open_create_modal']", "New Workspace")
      |> render_click()

      html = render(view)
      assert html =~ "Create New Workspace"
    end
  end

  describe "close_create_modal event" do
    test "closes the modal when cancel button clicked", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Open modal first
      view
      |> element("[phx-click*='open_create_modal']", "New Workspace")
      |> render_click()

      # Click cancel
      view
      |> element("button[phx-click='close_create_modal']", "Cancel")
      |> render_click()

      # Modal content should not be visible
      html = render(view)
      # The modal might still be in DOM but should be hidden
      refute html =~ ~r/<dialog[^>]*open[^>]*>/
    end
  end

  describe "validate event" do
    test "auto-generates slug from name", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Open modal
      view
      |> element("[phx-click*='open_create_modal']", "New Workspace")
      |> render_click()

      # Type a name
      html =
        view
        |> form("#create-workspace-modal form", workspace: %{name: "My Test Workspace"})
        |> render_change()

      # Slug should be auto-generated
      assert html =~ "my-test-workspace"
    end

    test "preserves custom slug when user edits it without changing name", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Open modal
      view
      |> element("[phx-click*='open_create_modal']", "New Workspace")
      |> render_click()

      # First set name to get auto-slug
      view
      |> form("#create-workspace-modal form", workspace: %{name: "Original Name"})
      |> render_change()

      # Now change only slug (keeping name the same - simulating user editing the slug)
      html =
        view
        |> form("#create-workspace-modal form",
          workspace: %{name: "Original Name", slug: "custom-slug"}
        )
        |> render_change()

      # Custom slug should be preserved since name didn't change
      assert html =~ "custom-slug"
      refute html =~ "original-name"
    end

    test "regenerates slug when name changes after custom slug edit", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Open modal
      view
      |> element("[phx-click*='open_create_modal']", "New Workspace")
      |> render_click()

      # First set name to get auto-slug
      view
      |> form("#create-workspace-modal form", workspace: %{name: "Original Name"})
      |> render_change()

      # Edit slug without changing name
      view
      |> form("#create-workspace-modal form",
        workspace: %{name: "Original Name", slug: "custom-slug"}
      )
      |> render_change()

      # Now change the name - slug should regenerate
      html =
        view
        |> form("#create-workspace-modal form",
          workspace: %{name: "Changed Name", slug: "custom-slug"}
        )
        |> render_change()

      # Slug should be regenerated from new name, not preserved
      assert html =~ "changed-name"
      refute html =~ "custom-slug"
    end

    test "shows validation error for duplicate slug", %{conn: conn} do
      # Create existing workspace
      {:ok, _workspace} =
        Workspaces.create_workspace(%{name: "Existing", slug: "existing-workspace"})

      {:ok, view, _html} = live(conn, ~p"/")

      # Open modal
      view
      |> element("[phx-click*='open_create_modal']", "New Workspace")
      |> render_click()

      # First set a name (slug auto-generates)
      view
      |> form("#create-workspace-modal form",
        workspace: %{name: "New Workspace"}
      )
      |> render_change()

      # Now try to use existing slug (keeping name the same so it doesn't regenerate)
      html =
        view
        |> form("#create-workspace-modal form",
          workspace: %{name: "New Workspace", slug: "existing-workspace"}
        )
        |> render_change()

      assert html =~ "is already taken"
    end

    test "shows validation error for empty name", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Open modal
      view
      |> element("[phx-click*='open_create_modal']", "New Workspace")
      |> render_click()

      # Submit with empty name
      html =
        view
        |> form("#create-workspace-modal form", workspace: %{name: ""})
        |> render_change()

      assert html =~ "can&#39;t be blank" or html =~ "can't be blank"
    end
  end

  describe "create_workspace event" do
    test "creates workspace and navigates to it", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Open modal
      view
      |> element("[phx-click*='open_create_modal']", "New Workspace")
      |> render_click()

      # Fill and submit form
      view
      |> form("#create-workspace-modal form",
        workspace: %{
          name: "Brand New Workspace",
          slug: "brand-new-workspace",
          description: "Test description"
        }
      )
      |> render_submit()

      # Should navigate to the new workspace
      assert_redirect(view, ~p"/brand-new-workspace")

      # Verify workspace was created
      assert Workspaces.get_workspace_by_slug("brand-new-workspace")
    end

    test "shows error when creation fails due to validation", %{conn: conn} do
      # Create workspace with slug we'll try to duplicate
      {:ok, _workspace} =
        Workspaces.create_workspace(%{name: "Existing", slug: "duplicate-test"})

      {:ok, view, _html} = live(conn, ~p"/")

      # Open modal
      view
      |> element("[phx-click*='open_create_modal']", "New Workspace")
      |> render_click()

      # Try to submit with duplicate slug
      html =
        view
        |> form("#create-workspace-modal form",
          workspace: %{name: "New", slug: "duplicate-test"}
        )
        |> render_submit()

      # Should show error and stay on page
      assert html =~ "has already been taken" or html =~ "already taken"
    end
  end
end
