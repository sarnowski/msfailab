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

defmodule MsfailabWeb.WorkspaceLive do
  @moduledoc """
  Main workspace LiveView handling both Asset Library and Track views.

  Routes:
  - /<workspace-slug> - Asset Library view (knowledge base)
  - /<workspace-slug>/<track-slug> - Track view (console + AI)
  """
  use MsfailabWeb, :live_view

  alias Msfailab.Containers
  alias Msfailab.Containers.ContainerRecord
  alias Msfailab.Events
  alias Msfailab.Events.ChatChanged
  alias Msfailab.Events.ConsoleChanged
  alias Msfailab.Events.DatabaseUpdated
  alias Msfailab.Events.WorkspaceChanged
  alias Msfailab.LLM
  alias Msfailab.MsfData
  alias Msfailab.Slug
  alias Msfailab.Tracks
  alias Msfailab.Tracks.ChatState
  alias Msfailab.Tracks.Memory
  alias Msfailab.Tracks.Track
  alias Msfailab.Workspaces
  alias MsfailabWeb.WorkspaceLive.CommandHandler
  alias MsfailabWeb.WorkspaceLive.Helpers
  alias MsfailabWeb.WorkspaceLive.ModelSelector

  @impl true
  def mount(_params, _session, socket) do
    # Fetch available models once at mount (static during runtime)
    available_models = LLM.list_models()

    socket =
      socket
      # Track modal state
      |> assign(:show_create_track_modal, false)
      |> assign(:selected_container_id, nil)
      |> assign(:previous_track_name, "")
      # Container modal state
      |> assign(:show_create_container_modal, false)
      |> assign(:previous_container_name, "")
      # Track input state
      |> assign(:input_text, "")
      |> assign(:input_mode, "ai")
      |> assign(:selected_model, nil)
      |> assign(:autonomous_mode, false)
      |> assign(:show_input_menu, false)
      |> assign(:available_models, available_models)
      # Chat and terminal state
      |> assign(:chat_state, ChatState.empty())
      |> assign(:console_segments, [])
      |> assign(:console_status, :offline)
      |> assign(:current_prompt, "")
      |> assign(:memory, Memory.new())
      # Event subscription tracking
      |> assign(:subscribed_workspace_id, nil)
      # Database browser state
      |> assign(:show_database_modal, false)
      |> assign(:asset_counts, empty_asset_counts())
      |> assign(:database_active_tab, :hosts)
      |> assign(:database_search_term, "")
      |> assign(:database_assets, [])
      |> assign(:database_sort_field, :address)
      |> assign(:database_sort_dir, :asc)
      |> assign(:database_page, 1)
      |> assign(:database_page_size, 25)
      |> assign(:database_total_count, 0)
      # Detail view state
      |> assign(:database_detail_asset, nil)
      |> assign(:database_detail_type, nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    workspace_slug = params["workspace_slug"]
    track_slug = params["track_slug"]

    case Workspaces.get_workspace_by_slug(workspace_slug) do
      nil ->
        socket =
          socket
          |> put_flash(:error, "Workspace not found")
          |> push_navigate(to: ~p"/")

        {:noreply, socket}

      workspace ->
        # Subscribe to workspace events (handles unsubscribe from previous workspace)
        socket = maybe_subscribe_to_workspace(socket, workspace.id)

        # Load containers with their tracks preloaded for the header
        containers = Containers.list_containers_with_tracks(workspace)

        # Load asset counts for the database button badge
        asset_counts = load_asset_counts(workspace)

        current_track =
          if track_slug do
            Tracks.get_track_by_slug(workspace, track_slug)
          else
            nil
          end

        # Handle track not found
        socket =
          if track_slug && is_nil(current_track) do
            socket
            |> put_flash(:error, "Track not found")
            |> push_navigate(to: ~p"/#{workspace.slug}")
          else
            # Load console state and memory for current track
            {console_status, current_prompt, console_segments, memory} =
              load_console_state(current_track)

            # Load chat state for current track
            chat_state = load_chat_state(current_track)

            socket
            |> assign(:workspace, workspace)
            |> assign(:containers, containers)
            |> assign(:current_track, current_track)
            |> assign(:console_segments, console_segments)
            |> assign(:console_status, console_status)
            |> assign(:current_prompt, current_prompt)
            |> assign(:chat_state, chat_state)
            |> assign(:memory, memory)
            |> assign(:asset_counts, asset_counts)
            |> assign(:page_title, Helpers.page_title(workspace, current_track))
            |> maybe_assign_selected_model(current_track)
            |> maybe_assign_autonomous_mode(current_track)
            |> assign_container_form(
              Containers.change_container(%ContainerRecord{
                workspace_id: workspace.id,
                docker_image: default_docker_image()
              })
            )
          end

        {:noreply, socket}
    end
  end

  # coveralls-ignore-start
  # Reason: Logic-free template - all conditional logic tested via event handlers
  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <!-- Main workspace container - fixed viewport height for track, scrollable for asset library -->
      <div class={[
        "flex flex-col bg-base-200",
        @current_track && "h-screen overflow-hidden",
        !@current_track && "min-h-screen"
      ]}>
        <!-- Workspace header with navigation tabs -->
        <.workspace_header
          workspace_slug={@workspace.slug}
          current_track={@current_track}
          containers={@containers}
          on_new_container={JS.push("open_create_container_modal")}
        />
        
    <!-- Content area - either Asset Library or Track view -->
        <%= if @current_track do %>
          <.track_content
            track={@current_track}
            chat_state={@chat_state}
            memory={@memory}
            console_segments={@console_segments}
            console_status={@console_status}
            current_prompt={@current_prompt}
            input_text={@input_text}
            input_mode={@input_mode}
            selected_model={@selected_model}
            autonomous_mode={@autonomous_mode}
            show_input_menu={@show_input_menu}
            available_models={@available_models}
            asset_counts={@asset_counts}
            on_open_database={JS.push("open_database_modal")}
          />
        <% else %>
          <.asset_library />
        <% end %>
      </div>
      
    <!-- Create track modal -->
      <.modal
        :if={@show_create_track_modal}
        id="create-track-modal"
        show={@show_create_track_modal}
        on_cancel={JS.push("close_create_track_modal")}
      >
        <:title>Create New Track</:title>

        <.form
          for={@track_form}
          phx-change="validate_track"
          phx-submit="create_track"
          class="space-y-4"
        >
          <!-- Track name input -->
          <.form_field
            label="Track Name"
            field={@track_form[:name]}
            placeholder="e.g., Initial Reconnaissance"
            autofocus
          />
          
    <!-- Track slug input (auto-generated but editable) -->
          <.form_field
            label="URL Slug"
            field={@track_form[:slug]}
            placeholder="initial-reconnaissance"
            helper={
              Helpers.track_slug_helper(
                @track_form[:slug],
                @workspace.slug,
                MsfailabWeb.Endpoint.url()
              )
            }
          />
          
    <!-- AI Model selection -->
          <.model_select field={@track_form[:current_model]} models={@available_models} />

          <div class="modal-action">
            <button type="button" class="btn btn-ghost" phx-click="close_create_track_modal">
              Cancel
            </button>
            <button type="submit" class="btn btn-primary" disabled={not @track_form.source.valid?}>
              Create Track
            </button>
          </div>
        </.form>
      </.modal>
      
    <!-- Create container modal -->
      <.modal
        id="create-container-modal"
        show={@show_create_container_modal}
        on_cancel={JS.push("close_create_container_modal")}
      >
        <:title>Create New Container</:title>

        <.form
          for={@container_form}
          phx-change="validate_container"
          phx-submit="create_container"
          class="space-y-4"
        >
          <!-- Container name input -->
          <.form_field
            label="Container Name"
            field={@container_form[:name]}
            placeholder="e.g., Metasploit Main"
            autofocus
          />
          
    <!-- Container slug input (auto-generated but editable) -->
          <.form_field
            label="URL Slug"
            field={@container_form[:slug]}
            placeholder="metasploit-main"
            helper={Helpers.container_slug_helper(@container_form[:slug], @workspace.slug)}
          />
          
    <!-- Docker image input -->
          <.form_field
            label="Docker Image"
            field={@container_form[:docker_image]}
            placeholder="msfailab-msfconsole"
          />

          <div class="modal-action">
            <button type="button" class="btn btn-ghost" phx-click="close_create_container_modal">
              Cancel
            </button>
            <button
              type="submit"
              class="btn btn-primary"
              disabled={not @container_form.source.valid?}
            >
              Create Container
            </button>
          </div>
        </.form>
      </.modal>
      
    <!-- Database browser modal -->
      <.database_browser
        show={@show_database_modal}
        on_close={JS.push("close_database_modal")}
        asset_counts={@asset_counts}
        active_tab={@database_active_tab}
        search_term={@database_search_term}
        detail_asset={@database_detail_asset}
        detail_type={@database_detail_type}
      >
        <:table_content>
          <%= if @database_assets != [] do %>
            <%= case @database_active_tab do %>
              <% :hosts -> %>
                <.hosts_table
                  hosts={@database_assets}
                  sort_field={@database_sort_field}
                  sort_dir={@database_sort_dir}
                  search_term={@database_search_term}
                />
              <% :services -> %>
                <.services_table
                  services={@database_assets}
                  sort_field={@database_sort_field}
                  sort_dir={@database_sort_dir}
                  search_term={@database_search_term}
                />
              <% :vulns -> %>
                <.vulns_table
                  vulns={@database_assets}
                  sort_field={@database_sort_field}
                  sort_dir={@database_sort_dir}
                  search_term={@database_search_term}
                />
              <% :notes -> %>
                <.notes_table
                  notes={@database_assets}
                  sort_field={@database_sort_field}
                  sort_dir={@database_sort_dir}
                  search_term={@database_search_term}
                />
              <% :creds -> %>
                <.creds_table
                  creds={@database_assets}
                  sort_field={@database_sort_field}
                  sort_dir={@database_sort_dir}
                  search_term={@database_search_term}
                />
              <% :loots -> %>
                <.loots_table
                  loots={@database_assets}
                  sort_field={@database_sort_field}
                  sort_dir={@database_sort_dir}
                  search_term={@database_search_term}
                />
              <% :sessions -> %>
                <.sessions_table
                  sessions={@database_assets}
                  sort_field={@database_sort_field}
                  sort_dir={@database_sort_dir}
                  search_term={@database_search_term}
                />
              <% _ -> %>
            <% end %>
            <.pagination
              page={@database_page}
              total_pages={ceil(@database_total_count / @database_page_size)}
              total_count={@database_total_count}
              page_size={@database_page_size}
            />
          <% end %>
        </:table_content>
      </.database_browser>
    </Layouts.app>
    """
  end

  # coveralls-ignore-stop

  # ===========================================================================
  # Event Handlers
  # ===========================================================================

  # ---------------------------------------------------------------------------
  # Track Modal Event Handlers
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("open_create_track_modal", %{"container_id" => container_id}, socket) do
    container_id = String.to_integer(container_id)
    default_model = LLM.get_default_model()

    socket =
      socket
      |> assign(:show_create_track_modal, true)
      |> assign(:selected_container_id, container_id)
      |> assign(:previous_track_name, "")
      |> assign_track_form(
        Tracks.change_track(%Track{container_id: container_id, current_model: default_model})
      )

    {:noreply, socket}
  end

  @impl true
  def handle_event("close_create_track_modal", _params, socket) do
    {:noreply, assign(socket, :show_create_track_modal, false)}
  end

  @impl true
  def handle_event("validate_track", %{"track" => params}, socket) do
    current_name = params["name"] || ""
    current_slug = params["slug"] || ""
    previous_name = socket.assigns.previous_track_name
    container_id = socket.assigns.selected_container_id

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

    container = Helpers.find_container(socket.assigns.containers, container_id)

    changeset =
      %Track{container_id: container_id}
      |> Tracks.change_track(params)
      |> Helpers.validate_track_slug_uniqueness(container)
      |> Map.put(:action, :validate)

    socket =
      socket
      |> assign(:previous_track_name, current_name)
      |> assign_track_form(changeset)

    {:noreply, socket}
  end

  @impl true
  def handle_event("create_track", %{"track" => params}, socket) do
    workspace = socket.assigns.workspace
    container_id = socket.assigns.selected_container_id
    container = Helpers.find_container(socket.assigns.containers, container_id)

    if is_nil(container) do
      socket =
        socket
        |> put_flash(:error, "Container not found.")

      {:noreply, socket}
    else
      case Tracks.create_track(container, params) do
        {:ok, track} ->
          socket =
            socket
            |> assign(:show_create_track_modal, false)
            |> put_flash(:info, "Track '#{track.name}' created!")
            |> push_patch(to: ~p"/#{workspace.slug}/#{track.slug}")

          {:noreply, socket}

        {:error, changeset} ->
          {:noreply, assign_track_form(socket, changeset)}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Container Modal Event Handlers
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("open_create_container_modal", _params, socket) do
    workspace = socket.assigns.workspace

    socket =
      socket
      |> assign(:show_create_container_modal, true)
      |> assign(:previous_container_name, "")
      |> assign_container_form(
        Containers.change_container(%ContainerRecord{
          workspace_id: workspace.id,
          docker_image: default_docker_image()
        })
      )

    {:noreply, socket}
  end

  @impl true
  def handle_event("close_create_container_modal", _params, socket) do
    {:noreply, assign(socket, :show_create_container_modal, false)}
  end

  @impl true
  def handle_event("validate_container", %{"container_record" => params}, socket) do
    current_name = params["name"] || ""
    current_slug = params["slug"] || ""
    previous_name = socket.assigns.previous_container_name
    workspace = socket.assigns.workspace

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
      %ContainerRecord{workspace_id: workspace.id, docker_image: default_docker_image()}
      |> Containers.change_container(params)
      |> Helpers.validate_container_slug_uniqueness(workspace)
      |> Map.put(:action, :validate)

    socket =
      socket
      |> assign(:previous_container_name, current_name)
      |> assign_container_form(changeset)

    {:noreply, socket}
  end

  @impl true
  def handle_event("create_container", %{"container_record" => params}, socket) do
    workspace = socket.assigns.workspace

    case Containers.create_container(workspace, params) do
      {:ok, container} ->
        socket =
          socket
          |> assign(:show_create_container_modal, false)
          |> put_flash(:info, "Container '#{container.name}' created!")

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign_container_form(socket, changeset)}
    end
  end

  # ---------------------------------------------------------------------------
  # Database Browser Modal Event Handlers
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("open_database_modal", _params, socket) do
    # Load data for the initial tab when opening modal
    socket =
      socket
      |> assign(:show_database_modal, true)
      |> assign(:database_page, 1)
      |> load_database_assets()

    {:noreply, socket}
  end

  @impl true
  def handle_event("close_database_modal", _params, socket) do
    {:noreply, assign(socket, :show_database_modal, false)}
  end

  @impl true
  def handle_event("database_tab_change", %{"tab" => tab}, socket) do
    tab_atom = String.to_existing_atom(tab)
    default_sort = default_sort_for_tab(tab_atom)

    socket =
      socket
      |> assign(:database_active_tab, tab_atom)
      |> assign(:database_sort_field, default_sort.field)
      |> assign(:database_sort_dir, default_sort.dir)
      |> assign(:database_page, 1)
      |> load_database_assets()

    {:noreply, socket}
  end

  @impl true
  def handle_event("database_search", %{"value" => search_term}, socket) do
    socket =
      socket
      |> assign(:database_search_term, search_term)
      |> assign(:database_page, 1)
      |> load_database_assets()

    {:noreply, socket}
  end

  def handle_event("database_search", %{"search" => search_term}, socket) do
    socket =
      socket
      |> assign(:database_search_term, search_term)
      |> assign(:database_page, 1)
      |> load_database_assets()

    {:noreply, socket}
  end

  @impl true
  def handle_event("database_sort", %{"field" => field}, socket) do
    field_atom = String.to_existing_atom(field)
    current_field = socket.assigns.database_sort_field
    current_dir = socket.assigns.database_sort_dir

    # Toggle direction if same field, otherwise default to :asc
    new_dir =
      if field_atom == current_field do
        if current_dir == :asc, do: :desc, else: :asc
      else
        :asc
      end

    socket =
      socket
      |> assign(:database_sort_field, field_atom)
      |> assign(:database_sort_dir, new_dir)
      |> load_database_assets()

    {:noreply, socket}
  end

  @impl true
  def handle_event("database_page", %{"page" => page}, socket) do
    page_num = String.to_integer(page)

    socket =
      socket
      |> assign(:database_page, page_num)
      |> load_database_assets()

    {:noreply, socket}
  end

  @impl true
  def handle_event("database_select", %{"type" => type, "id" => id}, socket) do
    asset_id = String.to_integer(id)
    workspace = socket.assigns.workspace

    case fetch_asset_detail_with_rpc(workspace, type, asset_id) do
      {:ok, asset} ->
        socket =
          socket
          |> assign(:database_detail_asset, asset)
          |> assign(:database_detail_type, String.to_existing_atom(type))

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Asset not found")}
    end
  end

  @impl true
  def handle_event("database_back", _params, socket) do
    socket =
      socket
      |> assign(:database_detail_asset, nil)
      |> assign(:database_detail_type, nil)

    {:noreply, socket}
  end

  @impl true
  def handle_event("database_navigate", %{"type" => type, "id" => id}, socket) do
    # Navigate to a related asset from detail view
    asset_id = String.to_integer(id)
    workspace = socket.assigns.workspace

    case fetch_asset_detail_with_rpc(workspace, type, asset_id) do
      {:ok, asset} ->
        socket =
          socket
          |> assign(:database_detail_asset, asset)
          |> assign(:database_detail_type, String.to_existing_atom(type))

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Asset not found")}
    end
  end

  # ---------------------------------------------------------------------------
  # Track Input Event Handlers
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("toggle_input_menu", _params, socket) do
    {:noreply, assign(socket, :show_input_menu, !socket.assigns.show_input_menu)}
  end

  @impl true
  def handle_event("select_input_mode", %{"mode" => mode}, socket) do
    socket =
      socket
      |> assign(:input_mode, mode)
      |> assign(:show_input_menu, false)

    {:noreply, socket}
  end

  @impl true
  def handle_event("select_model", %{"model" => model}, socket) do
    # Persist model selection to database if we have a track
    if socket.assigns.current_track do
      Tracks.update_track(socket.assigns.current_track, %{current_model: model})
    end

    socket =
      socket
      |> assign(:selected_model, model)
      |> assign(:show_input_menu, false)

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_autonomous", _params, socket) do
    track = socket.assigns.current_track

    if track do
      new_value = !socket.assigns.autonomous_mode

      case Tracks.set_autonomous(track.id, new_value) do
        {:ok, _} ->
          {:noreply, assign(socket, :autonomous_mode, new_value)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to update autonomous mode")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_input", %{"input" => text}, socket) do
    {:noreply, assign(socket, :input_text, text)}
  end

  @impl true
  def handle_event("send_input", %{"input" => text}, socket) do
    input_text = String.trim(text)

    socket =
      if input_text == "" do
        socket
      else
        handle_send_command(socket, socket.assigns.input_mode, input_text)
      end

    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # Tool Approval Event Handlers
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("approve_tool", %{"entry-id" => entry_id}, socket) do
    track = socket.assigns.current_track

    if track do
      case Tracks.approve_tool(track.id, entry_id) do
        :ok ->
          {:noreply, socket}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed to approve: #{inspect(reason)}")}
      end
    else
      {:noreply, put_flash(socket, :error, "No track selected")}
    end
  end

  @impl true
  def handle_event("deny_tool", %{"entry-id" => entry_id}, socket) do
    track = socket.assigns.current_track

    if track do
      case Tracks.deny_tool(track.id, entry_id, "User denied") do
        :ok ->
          {:noreply, socket}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed to deny: #{inspect(reason)}")}
      end
    else
      {:noreply, put_flash(socket, :error, "No track selected")}
    end
  end

  # ---------------------------------------------------------------------------
  # Keyboard Shortcut Event Handlers
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("toggle_input_mode", _params, socket) do
    new_mode = if socket.assigns.input_mode == "ai", do: "msf", else: "ai"
    {:noreply, assign(socket, :input_mode, new_mode)}
  end

  # ===========================================================================
  # PubSub Event Handlers
  # ===========================================================================

  # ---------------------------------------------------------------------------
  # WorkspaceChanged Event (for header menu updates)
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info(%WorkspaceChanged{}, socket) do
    # Re-fetch containers with tracks from database
    containers = Containers.list_containers_with_tracks(socket.assigns.workspace)
    {:noreply, assign(socket, :containers, containers)}
  end

  # ---------------------------------------------------------------------------
  # Console/Chat Changed Events (for pane updates)
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info(%ConsoleChanged{track_id: track_id}, socket) do
    current_track = socket.assigns.current_track

    socket =
      if current_track && current_track.id == track_id do
        # Fetch updated console state and re-render terminal
        {console_status, current_prompt, console_segments, memory} =
          load_console_state(current_track)

        socket
        |> assign(:console_segments, console_segments)
        |> assign(:console_status, console_status)
        |> assign(:current_prompt, current_prompt)
        |> assign(:memory, memory)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info(%ChatChanged{track_id: track_id}, socket) do
    current_track = socket.assigns.current_track

    socket =
      if current_track && current_track.id == track_id do
        # Fetch updated chat state and memory, then re-render chat panel
        chat_state = load_chat_state(current_track)
        {_, _, _, memory} = load_console_state(current_track)

        socket
        |> assign(:chat_state, chat_state)
        |> assign(:memory, memory)
      else
        socket
      end

    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # DatabaseUpdated Event (for asset count badge updates)
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info(%DatabaseUpdated{} = event, socket) do
    # Update asset counts from event payload and optionally show flash
    socket =
      socket
      |> assign(:asset_counts, event.totals)
      |> maybe_show_database_flash(event.changes)

    {:noreply, socket}
  end

  # Ignore other PubSub events (CommandIssued, CommandResult handled by TrackServer)
  @impl true
  def handle_info(_event, socket) do
    {:noreply, socket}
  end

  # ===========================================================================
  # Command Handling
  # ===========================================================================

  defp handle_send_command(socket, "msf", command) do
    track = socket.assigns.current_track

    if track do
      case Containers.send_metasploit_command(track.container_id, track.id, command) do
        {:ok, _command_id} ->
          assign(socket, :input_text, "")

        {:error, reason} ->
          put_flash(socket, :error, CommandHandler.format_msf_error(reason))
      end
    else
      put_flash(socket, :error, CommandHandler.no_track_error())
    end
  end

  defp handle_send_command(socket, "ai", prompt) do
    track = socket.assigns.current_track
    model = socket.assigns.selected_model

    if track do
      do_start_chat_turn(socket, track.id, prompt, model)
    else
      put_flash(socket, :error, CommandHandler.no_track_error())
    end
  end

  defp handle_send_command(socket, _mode, _command) do
    socket
  end

  defp do_start_chat_turn(socket, track_id, prompt, model) do
    case Tracks.start_chat_turn(track_id, prompt, model) do
      {:ok, _turn_id} ->
        assign(socket, :input_text, "")

      {:error, reason} ->
        put_flash(socket, :error, CommandHandler.format_chat_error(reason))
    end
  end

  # ===========================================================================
  # Helper Functions
  # ===========================================================================

  # ---------------------------------------------------------------------------
  # Event Subscription Helpers
  # ---------------------------------------------------------------------------

  defp maybe_subscribe_to_workspace(socket, workspace_id) do
    if connected?(socket) do
      # Unsubscribe from previous workspace if different
      previous_id = socket.assigns.subscribed_workspace_id

      if previous_id && previous_id != workspace_id do
        Events.unsubscribe_from_workspace(previous_id)
      end

      # Subscribe to new workspace if not already subscribed
      if previous_id != workspace_id do
        Events.subscribe_to_workspace(workspace_id)
      end

      assign(socket, :subscribed_workspace_id, workspace_id)
    else
      socket
    end
  end

  # ---------------------------------------------------------------------------
  # Console State Helpers
  # ---------------------------------------------------------------------------

  @typep console_state ::
           {Tracks.TrackServer.console_status(), String.t(), [Helpers.console_segment()],
            Memory.t()}

  @spec load_console_state(map() | nil) :: console_state()
  defp load_console_state(nil), do: {:offline, "", [], Memory.new()}

  defp load_console_state(track) do
    case Tracks.get_track_state(track.id) do
      {:ok, state} ->
        segments = Helpers.blocks_to_segments(state.console_history)
        {state.console_status, state.current_prompt, segments, state.memory}

      # TrackServer not running or other error
      _error ->
        {:offline, "", [], Memory.new()}
    end
  end

  # ---------------------------------------------------------------------------
  # Chat State Helpers
  # ---------------------------------------------------------------------------

  @spec load_chat_state(map() | nil) :: ChatState.t()
  defp load_chat_state(nil), do: ChatState.empty()

  defp load_chat_state(track) do
    # Tracks.get_chat_state always succeeds by falling back to DB when TrackServer
    # is unavailable, so we don't need error handling here
    {:ok, chat_state} = Tracks.get_chat_state(track.id)
    chat_state
  end

  # ---------------------------------------------------------------------------
  # Form Helpers
  # ---------------------------------------------------------------------------

  defp assign_track_form(socket, changeset) do
    assign(socket, :track_form, to_form(changeset, as: "track"))
  end

  defp assign_container_form(socket, changeset) do
    assign(socket, :container_form, to_form(changeset, as: "container_record"))
  end

  defp default_docker_image do
    Application.get_env(:msfailab, :docker_image, "msfailab-msfconsole")
  end

  # ---------------------------------------------------------------------------
  # Model Selection Helpers
  # ---------------------------------------------------------------------------

  # Assigns selected_model from track's current_model, or defaults to first available model
  defp maybe_assign_selected_model(socket, nil), do: socket

  defp maybe_assign_selected_model(socket, track) do
    selected_model = ModelSelector.select_model_for_track(track, socket.assigns.available_models)
    assign(socket, :selected_model, selected_model)
  end

  # ---------------------------------------------------------------------------
  # Autonomous Mode Helpers
  # ---------------------------------------------------------------------------

  # Assigns autonomous_mode from track's autonomous field
  defp maybe_assign_autonomous_mode(socket, nil), do: socket

  defp maybe_assign_autonomous_mode(socket, track) do
    assign(socket, :autonomous_mode, track.autonomous)
  end

  # ---------------------------------------------------------------------------
  # Asset Count Helpers
  # ---------------------------------------------------------------------------

  defp empty_asset_counts do
    %{
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

  defp load_asset_counts(workspace) do
    case MsfData.count_assets(workspace.slug) do
      {:ok, counts} -> counts
      {:error, _} -> empty_asset_counts()
    end
  end

  defp load_asset_counts_with_search(workspace, "") do
    load_asset_counts(workspace)
  end

  defp load_asset_counts_with_search(workspace, search_term) do
    case MsfData.count_assets(workspace.slug, search_term) do
      {:ok, counts} -> counts
      {:error, _} -> empty_asset_counts()
    end
  end

  # Shows a flash message when new assets are discovered
  defp maybe_show_database_flash(socket, changes) do
    case DatabaseUpdated.format_changes(changes) do
      nil -> socket
      message -> put_flash(socket, :info, message)
    end
  end

  # ---------------------------------------------------------------------------
  # Database Browser Helpers
  # ---------------------------------------------------------------------------

  # Default sort configuration for each asset type
  defp default_sort_for_tab(:hosts), do: %{field: :address, dir: :asc}
  defp default_sort_for_tab(:services), do: %{field: :port, dir: :asc}
  defp default_sort_for_tab(:vulns), do: %{field: :name, dir: :asc}
  defp default_sort_for_tab(:notes), do: %{field: :created_at, dir: :desc}
  defp default_sort_for_tab(:creds), do: %{field: :user, dir: :asc}
  defp default_sort_for_tab(:loots), do: %{field: :created_at, dir: :desc}
  defp default_sort_for_tab(:sessions), do: %{field: :opened_at, dir: :desc}
  defp default_sort_for_tab(_), do: %{field: :id, dir: :asc}

  # Loads assets for the current tab with sorting and pagination
  defp load_database_assets(socket) do
    workspace = socket.assigns.workspace
    tab = socket.assigns.database_active_tab
    sort_field = socket.assigns.database_sort_field
    sort_dir = socket.assigns.database_sort_dir
    page = socket.assigns.database_page
    page_size = socket.assigns.database_page_size
    search_term = socket.assigns.database_search_term

    offset = (page - 1) * page_size

    # MsfData list functions expect a map with atom keys
    filters = %{
      sort_by: sort_field,
      sort_dir: sort_dir,
      limit: page_size,
      offset: offset
    }

    # Add search filter if provided
    filters = if search_term != "", do: Map.put(filters, :search, search_term), else: filters

    {assets, total_count} = fetch_assets_for_tab(workspace.slug, tab, filters)

    # Update asset counts based on search term
    asset_counts = load_asset_counts_with_search(workspace, search_term)

    socket
    |> assign(:database_assets, assets)
    |> assign(:database_total_count, total_count)
    |> assign(:asset_counts, asset_counts)
  end

  # Fetches assets and count for the given tab
  # MsfData list functions return {:ok, %{hosts: [...], count: n, total_count: n}}
  defp fetch_assets_for_tab(workspace_slug, :hosts, filters) do
    case MsfData.list_hosts(workspace_slug, filters) do
      {:ok, %{hosts: hosts, total_count: total}} -> {hosts, total}
      {:error, _} -> {[], 0}
    end
  end

  defp fetch_assets_for_tab(workspace_slug, :services, filters) do
    case MsfData.list_services(workspace_slug, filters) do
      {:ok, %{services: services, total_count: total}} -> {services, total}
      {:error, _} -> {[], 0}
    end
  end

  defp fetch_assets_for_tab(workspace_slug, :vulns, filters) do
    case MsfData.list_vulns(workspace_slug, filters) do
      {:ok, %{vulns: vulns, total_count: total}} -> {vulns, total}
      {:error, _} -> {[], 0}
    end
  end

  defp fetch_assets_for_tab(workspace_slug, :notes, filters) do
    case MsfData.list_notes(workspace_slug, filters) do
      {:ok, %{notes: notes, total_count: total}} -> {notes, total}
      {:error, _} -> {[], 0}
    end
  end

  defp fetch_assets_for_tab(workspace_slug, :creds, filters) do
    case MsfData.list_creds(workspace_slug, filters) do
      {:ok, %{creds: creds, total_count: total}} -> {creds, total}
      {:error, _} -> {[], 0}
    end
  end

  defp fetch_assets_for_tab(workspace_slug, :loots, filters) do
    case MsfData.list_loots(workspace_slug, filters) do
      {:ok, %{loots: loots, total_count: total}} -> {loots, total}
      {:error, _} -> {[], 0}
    end
  end

  defp fetch_assets_for_tab(workspace_slug, :sessions, filters) do
    case MsfData.list_sessions(workspace_slug, filters) do
      {:ok, %{sessions: sessions, total_count: total}} -> {sessions, total}
      {:error, _} -> {[], 0}
    end
  end

  defp fetch_assets_for_tab(_workspace_slug, _tab, _filters), do: {[], 0}

  # Fetches a single asset for detail view
  defp fetch_asset_detail(workspace_slug, "host", id) do
    MsfData.get_host(workspace_slug, id)
  end

  defp fetch_asset_detail(workspace_slug, "service", id) do
    MsfData.get_service(workspace_slug, id)
  end

  defp fetch_asset_detail(workspace_slug, "vuln", id) do
    MsfData.get_vuln(workspace_slug, id)
  end

  defp fetch_asset_detail(workspace_slug, "note", id) do
    MsfData.get_note(workspace_slug, id)
  end

  defp fetch_asset_detail(workspace_slug, "cred", id) do
    MsfData.get_cred(workspace_slug, id)
  end

  defp fetch_asset_detail(workspace_slug, "loot", id) do
    MsfData.get_loot(workspace_slug, id)
  end

  defp fetch_asset_detail(workspace_slug, "session", id) do
    MsfData.get_session(workspace_slug, id)
  end

  defp fetch_asset_detail(_workspace_slug, _type, _id), do: {:error, :unknown_type}

  # RPC-aware asset fetching for notes with Ruby Marshal data
  defp fetch_asset_detail_with_rpc(workspace, "note", id) do
    # Try to get RPC context for deserializing Ruby Marshal data
    rpc_context =
      case Containers.get_rpc_context_for_workspace(workspace.id) do
        {:ok, ctx} -> ctx
        {:error, _} -> nil
      end

    MsfData.get_note(workspace.slug, id, rpc_context)
  end

  defp fetch_asset_detail_with_rpc(workspace, type, id) do
    # Other asset types don't need RPC context
    fetch_asset_detail(workspace.slug, type, id)
  end
end
