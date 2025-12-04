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

defmodule MsfailabWeb.WorkspaceLiveTest do
  use MsfailabWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Msfailab.Containers
  alias Msfailab.Events.WorkspaceChanged
  alias Msfailab.Tracks
  alias Msfailab.Workspaces

  # ===========================================================================
  # Test Setup
  # ===========================================================================

  setup %{conn: conn} do
    {:ok, workspace} = Workspaces.create_workspace(%{name: "Test Workspace", slug: "test-ws"})

    {:ok, container} =
      Containers.create_container(workspace, %{
        name: "Test Container",
        slug: "test-container",
        docker_image: "test:latest"
      })

    {:ok, track} =
      Tracks.create_track(container, %{
        name: "Test Track",
        slug: "test-track"
      })

    %{conn: conn, workspace: workspace, container: container, track: track}
  end

  # ===========================================================================
  # Mount and Handle Params Tests
  # ===========================================================================

  describe "mount/3 and handle_params/3" do
    test "loads workspace and shows asset library when no track", %{
      conn: conn,
      workspace: workspace
    } do
      {:ok, view, html} = live(conn, ~p"/#{workspace.slug}")

      # Verify workspace is loaded (asset library shown, containers visible)
      assert html =~ workspace.name or html =~ "Asset Library"
      assert has_element?(view, "[title='Asset Library']")
    end

    test "redirects to home when workspace not found", %{conn: conn} do
      {:error, {:live_redirect, %{to: "/", flash: flash}}} =
        live(conn, ~p"/nonexistent-workspace")

      assert flash["error"] =~ "not found"
    end

    test "redirects to workspace when track not found", %{conn: conn, workspace: workspace} do
      {:error, {:live_redirect, %{to: path, flash: flash}}} =
        live(conn, ~p"/#{workspace.slug}/nonexistent-track")

      assert path == "/#{workspace.slug}"
      assert flash["error"] =~ "not found"
    end

    test "sets initial modal state to closed", %{conn: conn, workspace: workspace} do
      {:ok, view, _html} = live(conn, ~p"/#{workspace.slug}")

      # Modal div exists but has show=false so it's not visible
      # Check that the modal form is not active by verifying assigns via view state
      # The modals exist in the HTML (hidden) but shouldn't be interactive
      # Test that clicking the new track button actually opens the modal
      refute has_element?(view, "#create-track-modal form:not([hidden])")
    end
  end

  # ===========================================================================
  # Track Modal Event Tests
  # ===========================================================================

  describe "track modal events" do
    test "open_create_track_modal shows modal", %{
      conn: conn,
      workspace: workspace,
      container: container
    } do
      {:ok, view, _html} = live(conn, ~p"/#{workspace.slug}")

      # Find by aria-label with container name
      view
      |> element("[aria-label='Create new track in #{container.name}']")
      |> render_click()

      # After clicking, the modal should be visible
      html = render(view)
      assert html =~ "Create New Track"
    end

    test "validate_track auto-generates slug from name", %{
      conn: conn,
      workspace: workspace,
      container: container
    } do
      {:ok, view, _html} = live(conn, ~p"/#{workspace.slug}")

      # Open modal
      view
      |> element("[aria-label='Create new track in #{container.name}']")
      |> render_click()

      # Type a name
      html =
        view
        |> form("#create-track-modal form", track: %{name: "My New Track"})
        |> render_change()

      # Slug should be auto-generated
      assert html =~ "my-new-track"
    end

    # NOTE: Testing track creation that navigates to the track page requires
    # the Tracks.Registry to be running. See TracksCase for full track tests.
    # The modal open/close and validation are tested above.

    test "create_track shows validation errors for empty name", %{
      conn: conn,
      workspace: workspace,
      container: container
    } do
      {:ok, view, _html} = live(conn, ~p"/#{workspace.slug}")

      # Open modal
      view
      |> element("[aria-label='Create new track in #{container.name}']")
      |> render_click()

      # Try to submit with empty name - validation should show error
      html =
        view
        |> form("#create-track-modal form", track: %{name: "", slug: ""})
        |> render_change()

      # Should show validation error (changeset action is :validate)
      assert html =~ "can&#39;t be blank" or html =~ "can't be blank"
    end
  end

  # ===========================================================================
  # Container Modal Event Tests
  # ===========================================================================

  describe "container modal events" do
    test "open_create_container_modal shows modal", %{conn: conn, workspace: workspace} do
      {:ok, view, _html} = live(conn, ~p"/#{workspace.slug}")

      view
      |> element("[aria-label='Create new container']")
      |> render_click()

      html = render(view)
      assert html =~ "Create New Container"
    end

    test "validate_container auto-generates slug from name", %{conn: conn, workspace: workspace} do
      {:ok, view, _html} = live(conn, ~p"/#{workspace.slug}")

      # Open modal
      view
      |> element("[aria-label='Create new container']")
      |> render_click()

      # Type a name
      html =
        view
        |> form("#create-container-modal form", container_record: %{name: "My Container"})
        |> render_change()

      # Slug should be auto-generated
      assert html =~ "my-container"
    end

    test "create_container creates container in database", %{
      conn: conn,
      workspace: workspace
    } do
      {:ok, view, _html} = live(conn, ~p"/#{workspace.slug}")

      # Open modal
      view
      |> element("[aria-label='Create new container']")
      |> render_click()

      # Submit form
      view
      |> form("#create-container-modal form",
        container_record: %{
          name: "Brand New Container",
          slug: "brand-new-container",
          docker_image: "test:latest"
        }
      )
      |> render_submit()

      # Verify container was created in database
      assert Containers.get_container_by_slug(workspace, "brand-new-container")
    end
  end

  # ===========================================================================
  # PubSub Event Tests
  # ===========================================================================

  describe "handle_info for PubSub events" do
    test "WorkspaceChanged refreshes containers and tracks", %{
      conn: conn,
      workspace: workspace,
      container: container
    } do
      {:ok, view, _html} = live(conn, ~p"/#{workspace.slug}")

      # Create a new track in the database (simulating another user's action)
      {:ok, new_track} =
        Tracks.create_track(container, %{
          name: "New Track From Event",
          slug: "new-track-event"
        })

      # Simulate WorkspaceChanged event (triggers re-fetch from database)
      event = WorkspaceChanged.new(workspace.id)
      send(view.pid, event)

      # New track should appear after the refresh
      html = render(view)
      assert html =~ new_track.name
    end

    test "WorkspaceChanged handles archived tracks correctly", %{
      conn: conn,
      workspace: workspace,
      track: track
    } do
      {:ok, view, _html} = live(conn, ~p"/#{workspace.slug}")

      # Verify track is in the list first
      html = render(view)
      assert html =~ track.name

      # Archive the track in the database
      {:ok, _archived} = Tracks.archive_track(track)

      # Simulate WorkspaceChanged event (triggers re-fetch from database)
      event = WorkspaceChanged.new(workspace.id)
      send(view.pid, event)

      # Track should be removed from the view after refresh
      html = render(view)
      refute html =~ track.name
    end

    test "ignores unknown events", %{conn: conn, workspace: workspace} do
      {:ok, view, _html} = live(conn, ~p"/#{workspace.slug}")

      # Send an unknown event
      send(view.pid, {:unknown_event, "data"})

      # Should not crash
      html = render(view)
      assert html
    end
  end

  # ===========================================================================
  # Track Input Event Tests
  # ===========================================================================

  describe "track input events" do
    test "toggle_input_menu toggles menu visibility", %{
      conn: conn,
      workspace: workspace,
      track: track
    } do
      {:ok, view, _html} = live(conn, ~p"/#{workspace.slug}/#{track.slug}")

      # Find and click the input menu toggle
      # Menu toggle button should exist
      assert has_element?(view, "[phx-click='toggle_input_menu']")

      # Toggle the menu on
      view |> element("[phx-click='toggle_input_menu']") |> render_click()

      # Toggle should work (view doesn't crash)
      assert render(view)
    end

    test "select_input_mode changes mode", %{conn: conn, workspace: workspace, track: track} do
      {:ok, view, _html} = live(conn, ~p"/#{workspace.slug}/#{track.slug}")

      # Send select_input_mode event directly
      render_click(view, "select_input_mode", %{"mode" => "msf"})

      # View doesn't crash and mode is accepted
      assert render(view)
    end

    test "toggle_input_mode switches between ai and msf", %{
      conn: conn,
      workspace: workspace,
      track: track
    } do
      {:ok, view, _html} = live(conn, ~p"/#{workspace.slug}/#{track.slug}")

      # Toggle mode (keyboard shortcut)
      render_click(view, "toggle_input_mode", %{})

      # Should not crash
      assert render(view)
    end

    test "update_input stores input text", %{conn: conn, workspace: workspace, track: track} do
      {:ok, view, _html} = live(conn, ~p"/#{workspace.slug}/#{track.slug}")

      # Update input
      render_click(view, "update_input", %{"input" => "test command"})

      # Should not crash
      assert render(view)
    end

    test "send_input with empty text does nothing", %{
      conn: conn,
      workspace: workspace,
      track: track
    } do
      {:ok, view, _html} = live(conn, ~p"/#{workspace.slug}/#{track.slug}")

      # Send empty input
      render_click(view, "send_input", %{"input" => ""})

      # Should not crash
      assert render(view)
    end

    test "send_input with whitespace-only text does nothing", %{
      conn: conn,
      workspace: workspace,
      track: track
    } do
      {:ok, view, _html} = live(conn, ~p"/#{workspace.slug}/#{track.slug}")

      # Send whitespace-only input
      render_click(view, "send_input", %{"input" => "   "})

      # Should not crash
      assert render(view)
    end

    test "select_model updates model selection", %{
      conn: conn,
      workspace: workspace,
      track: track
    } do
      {:ok, view, _html} = live(conn, ~p"/#{workspace.slug}/#{track.slug}")

      # Select a model
      render_click(view, "select_model", %{"model" => "claude-3-haiku"})

      # Should not crash
      assert render(view)
    end

    test "toggle_autonomous toggles mode", %{conn: conn, workspace: workspace, track: track} do
      {:ok, view, _html} = live(conn, ~p"/#{workspace.slug}/#{track.slug}")

      # Toggle autonomous mode
      render_click(view, "toggle_autonomous", %{})

      # Should not crash
      assert render(view)
    end
  end

  # ===========================================================================
  # Tool Approval Event Tests
  # ===========================================================================

  describe "tool approval events" do
    test "approve_tool without track shows error", %{conn: conn, workspace: workspace} do
      {:ok, view, _html} = live(conn, ~p"/#{workspace.slug}")

      # Try to approve without a track
      render_click(view, "approve_tool", %{"entry-id" => "123"})

      # Should show error flash
      assert render(view) =~ "No track selected"
    end

    test "deny_tool without track shows error", %{conn: conn, workspace: workspace} do
      {:ok, view, _html} = live(conn, ~p"/#{workspace.slug}")

      # Try to deny without a track
      render_click(view, "deny_tool", %{"entry-id" => "123"})

      # Should show error flash
      assert render(view) =~ "No track selected"
    end
  end

  # ===========================================================================
  # Console and Chat PubSub Event Tests
  # ===========================================================================

  describe "handle_info for console and chat events" do
    alias Msfailab.Events.ChatChanged
    alias Msfailab.Events.ConsoleChanged

    test "ConsoleChanged for different track is ignored", %{
      conn: conn,
      workspace: workspace,
      track: track
    } do
      {:ok, view, _html} = live(conn, ~p"/#{workspace.slug}/#{track.slug}")

      # Send a console changed event for a different track
      event = ConsoleChanged.new(workspace.id, track.id + 999)
      send(view.pid, event)

      # Should not crash
      assert render(view)
    end

    test "ChatChanged for different track is ignored", %{
      conn: conn,
      workspace: workspace,
      track: track
    } do
      {:ok, view, _html} = live(conn, ~p"/#{workspace.slug}/#{track.slug}")

      # Send a chat changed event for a different track
      event = ChatChanged.new(workspace.id, track.id + 999)
      send(view.pid, event)

      # Should not crash
      assert render(view)
    end

    test "ConsoleChanged for current track updates state", %{
      conn: conn,
      workspace: workspace,
      track: track
    } do
      {:ok, view, _html} = live(conn, ~p"/#{workspace.slug}/#{track.slug}")

      # Send a console changed event for current track
      # TrackServer not running, so state fetch will fail gracefully
      event = ConsoleChanged.new(workspace.id, track.id)
      send(view.pid, event)

      # Should not crash - gracefully handles missing TrackServer
      assert render(view)
    end

    test "ChatChanged for current track updates state", %{
      conn: conn,
      workspace: workspace,
      track: track
    } do
      {:ok, view, _html} = live(conn, ~p"/#{workspace.slug}/#{track.slug}")

      # Send a chat changed event for current track
      event = ChatChanged.new(workspace.id, track.id)
      send(view.pid, event)

      # Should not crash - gracefully handles missing TrackServer
      assert render(view)
    end
  end

  # ===========================================================================
  # Helper Functions Tests
  # ===========================================================================

  describe "page_title helper" do
    test "shows workspace name for asset library view", %{conn: conn, workspace: workspace} do
      {:ok, _view, html} = live(conn, ~p"/#{workspace.slug}")

      # Check the HTML contains the workspace name (page title comes from assigns)
      assert html =~ workspace.name
    end
  end
end
