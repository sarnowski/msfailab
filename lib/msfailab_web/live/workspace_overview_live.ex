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

defmodule MsfailabWeb.WorkspaceOverviewLive do
  @moduledoc """
  Landing page LiveView displaying all available workspaces.

  Users can browse existing workspaces and create new ones through a modal dialog.
  """
  use MsfailabWeb, :live_view

  alias Msfailab.Slug
  alias Msfailab.Workspaces
  alias Msfailab.Workspaces.Workspace
  alias MsfailabWeb.WorkspaceOverviewLive.Helpers

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Workspaces")
      |> stream(:workspaces, Workspaces.list_workspaces())
      |> assign(:show_create_modal, false)
      |> assign(:previous_name, "")
      |> assign_form(Workspaces.change_workspace(%Workspace{}))

    {:ok, socket}
  end

  # coveralls-ignore-start
  # Reason: Logic-free template - all conditional logic tested via event handlers
  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <!-- Main container - full viewport height, centered content -->
      <div class="min-h-screen flex flex-col">
        <!-- Hero section - product branding -->
        <section class="py-16 text-center">
          <!-- Product name -->
          <h1 class="text-5xl font-bold text-base-content mb-4">
            Metasploit AI Lab
          </h1>
          <!-- Tagline/slogan -->
          <p class="text-xl text-base-content/70 max-w-2xl mx-auto">
            Collaborative security research with AI agents as first-class research partners
          </p>
        </section>
        
    <!-- Workspaces section -->
        <section class="flex-1 px-6 pb-12">
          <!-- Section header -->
          <div class="max-w-7xl mx-auto mb-6">
            <h2 class="text-2xl font-semibold text-base-content">
              Your Workspaces
            </h2>
            <p class="text-base-content/60 mt-1">
              Select a workspace to continue your research or create a new one
            </p>
          </div>
          
    <!-- Workspace cards grid - max 5 per row -->
          <div class="max-w-7xl mx-auto">
            <div class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 gap-4">
              <!-- Existing workspace cards (stream container uses contents to flatten into parent grid) -->
              <div id="workspaces" phx-update="stream" class="contents">
                <.workspace_card
                  :for={{dom_id, workspace} <- @streams.workspaces}
                  id={dom_id}
                  name={workspace.name}
                  description={workspace.description || ""}
                  slug={workspace.slug}
                />
              </div>
              <!-- Create new workspace card -->
              <.new_item_card on_click={JS.push("open_create_modal")} label="New Workspace" />
            </div>
          </div>
        </section>
        
    <!-- Footer with minimal info -->
        <footer class="py-6 text-center text-base-content/50 text-sm border-t border-base-300">
          <p>Metasploit Framework AI Lab</p>
        </footer>
      </div>
      
    <!-- Create workspace modal -->
      <.modal
        id="create-workspace-modal"
        show={@show_create_modal}
        on_cancel={JS.push("close_create_modal")}
      >
        <:title>Create New Workspace</:title>

        <.form for={@form} phx-change="validate" phx-submit="create_workspace" class="space-y-4">
          <!-- Workspace name input -->
          <.form_field
            label="Name"
            field={@form[:name]}
            placeholder="e.g., ACME Corp Pentest"
            autofocus
          />
          
    <!-- Workspace description input -->
          <.textarea_field
            label="Description"
            field={@form[:description]}
            placeholder="Brief description of this workspace's purpose"
          />
          
    <!-- Workspace slug input (auto-generated but editable) -->
          <.form_field
            label="URL Slug"
            field={@form[:slug]}
            placeholder="acme-corp-pentest"
            helper={Helpers.slug_helper(@form[:slug], MsfailabWeb.Endpoint.url())}
          />

          <div class="modal-action">
            <button type="button" class="btn btn-ghost" phx-click="close_create_modal">
              Cancel
            </button>
            <button type="submit" class="btn btn-primary" disabled={not @form.source.valid?}>
              Create Workspace
            </button>
          </div>
        </.form>
      </.modal>
    </Layouts.app>
    """
  end

  # coveralls-ignore-stop

  # ===========================================================================
  # Event Handlers
  # ===========================================================================

  @impl true
  def handle_event("open_create_modal", _params, socket) do
    socket =
      socket
      |> assign(:show_create_modal, true)
      |> assign(:previous_name, "")
      |> assign_form(Workspaces.change_workspace(%Workspace{}))

    {:noreply, socket}
  end

  @impl true
  def handle_event("close_create_modal", _params, socket) do
    {:noreply, assign(socket, :show_create_modal, false)}
  end

  @impl true
  def handle_event("validate", %{"workspace" => params}, socket) do
    current_name = params["name"] || ""
    current_slug = params["slug"] || ""
    previous_name = socket.assigns.previous_name

    # Auto-generate slug if:
    # - slug is empty (initial state), OR
    # - name changed from previous (user typed in name field)
    # This allows the slug to update as the user types the name.
    # Custom slugs are preserved only while the name stays unchanged.
    params =
      if current_slug == "" || current_name != previous_name do
        Map.put(params, "slug", Slug.generate(current_name))
      else
        params
      end

    changeset =
      %Workspace{}
      |> Workspaces.change_workspace(params)
      |> Helpers.validate_slug_uniqueness()
      |> Map.put(:action, :validate)

    socket =
      socket
      |> assign(:previous_name, current_name)
      |> assign_form(changeset)

    {:noreply, socket}
  end

  @impl true
  def handle_event("create_workspace", %{"workspace" => params}, socket) do
    case Workspaces.create_workspace(params) do
      {:ok, workspace} ->
        socket =
          socket
          |> put_flash(:info, "Workspace '#{workspace.name}' created successfully!")
          |> push_navigate(to: ~p"/#{workspace.slug}")

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  # ===========================================================================
  # Helper Functions
  # ===========================================================================

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: "workspace"))
  end
end
