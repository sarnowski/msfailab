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
  alias Msfailab.Events.ChatStateUpdated
  alias Msfailab.Events.ContainerCreated
  alias Msfailab.Events.ContainerUpdated
  alias Msfailab.Events.TrackCreated
  alias Msfailab.Events.TrackStateUpdated
  alias Msfailab.Events.TrackUpdated
  alias Msfailab.LLM
  alias Msfailab.Slug
  alias Msfailab.Tracks
  alias Msfailab.Tracks.ChatState
  alias Msfailab.Tracks.Track
  alias Msfailab.Workspaces
  alias MsfailabWeb.WorkspaceLive.Helpers

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
      # Event subscription tracking
      |> assign(:subscribed_workspace_id, nil)

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
            # Load console state for current track
            {console_status, current_prompt, console_segments} =
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
            console_segments={@console_segments}
            console_status={@console_status}
            current_prompt={@current_prompt}
            input_text={@input_text}
            input_mode={@input_mode}
            selected_model={@selected_model}
            autonomous_mode={@autonomous_mode}
            show_input_menu={@show_input_menu}
            available_models={@available_models}
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
  # Entity Events (for header menu updates)
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info(%ContainerCreated{} = event, socket) do
    # Add new container to the list with empty tracks
    new_container = %ContainerRecord{
      id: event.container_id,
      workspace_id: event.workspace_id,
      slug: event.slug,
      name: event.name,
      docker_image: event.docker_image,
      tracks: []
    }

    containers = socket.assigns.containers ++ [new_container]
    {:noreply, assign(socket, :containers, containers)}
  end

  @impl true
  def handle_info(%ContainerUpdated{} = event, socket) do
    # Update container in the list (name changes, etc.)
    containers =
      Enum.map(socket.assigns.containers, fn container ->
        if container.id == event.container_id do
          %{container | name: event.name, slug: event.slug}
        else
          container
        end
      end)

    {:noreply, assign(socket, :containers, containers)}
  end

  @impl true
  def handle_info(%TrackCreated{} = event, socket) do
    # Add new track to the appropriate container
    new_track = %Track{
      id: event.track_id,
      container_id: event.container_id,
      slug: event.slug,
      name: event.name,
      archived_at: nil
    }

    containers =
      Enum.map(socket.assigns.containers, fn container ->
        if container.id == event.container_id do
          %{container | tracks: container.tracks ++ [new_track]}
        else
          container
        end
      end)

    {:noreply, assign(socket, :containers, containers)}
  end

  @impl true
  def handle_info(%TrackUpdated{} = event, socket) do
    # Update track in the appropriate container (or remove if archived)
    containers =
      Enum.map(socket.assigns.containers, fn container ->
        if container.id == event.container_id do
          %{container | tracks: Helpers.update_tracks_list(container.tracks, event)}
        else
          container
        end
      end)

    {:noreply, assign(socket, :containers, containers)}
  end

  # ---------------------------------------------------------------------------
  # State Events (for terminal pane updates)
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info(%TrackStateUpdated{track_id: track_id}, socket) do
    current_track = socket.assigns.current_track

    socket =
      if current_track && current_track.id == track_id do
        # Fetch updated console state and re-render terminal
        {console_status, current_prompt, console_segments} =
          load_console_state(current_track)

        socket
        |> assign(:console_segments, console_segments)
        |> assign(:console_status, console_status)
        |> assign(:current_prompt, current_prompt)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info(%ChatStateUpdated{track_id: track_id}, socket) do
    current_track = socket.assigns.current_track

    socket =
      if current_track && current_track.id == track_id do
        # Fetch updated chat state and re-render chat panel
        chat_state = load_chat_state(current_track)
        assign(socket, :chat_state, chat_state)
      else
        socket
      end

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
          socket
          |> assign(:input_text, "")

        {:error, :container_not_running} ->
          socket
          |> put_flash(:error, "Container is not running")

        {:error, :console_starting} ->
          socket
          |> put_flash(:error, "Console is still starting up, please wait")

        {:error, :console_busy} ->
          socket
          |> put_flash(:error, "Console is busy processing a command")

        {:error, :console_offline} ->
          socket
          |> put_flash(:error, "Console is offline")

        {:error, :console_not_registered} ->
          socket
          |> put_flash(:error, "Console is not registered for this track")
      end
    else
      socket
      |> put_flash(:error, "No track selected")
    end
  end

  defp handle_send_command(socket, "ai", prompt) do
    track = socket.assigns.current_track
    model = socket.assigns.selected_model

    if track do
      case Tracks.start_chat_turn(track.id, prompt, model) do
        {:ok, _turn_id} ->
          socket
          |> assign(:input_text, "")

        {:error, :not_found} ->
          socket
          |> put_flash(:error, "Track server not found")

        {:error, reason} ->
          socket
          |> put_flash(:error, "Failed to send message: #{inspect(reason)}")
      end
    else
      socket
      |> put_flash(:error, "No track selected")
    end
  end

  defp handle_send_command(socket, _mode, _command) do
    socket
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
           {Tracks.TrackServer.console_status(), String.t(), [Helpers.console_segment()]}

  @spec load_console_state(map() | nil) :: console_state()
  defp load_console_state(nil), do: {:offline, "", []}

  defp load_console_state(track) do
    case Tracks.get_track_state(track.id) do
      {:ok, state} ->
        segments = Helpers.blocks_to_segments(state.console_history)
        {state.console_status, state.current_prompt, segments}

      {:error, :not_found} ->
        {:offline, "", []}
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
    selected_model =
      case track.current_model do
        nil ->
          case List.first(socket.assigns.available_models) do
            nil -> nil
            model -> model.name
          end

        model ->
          model
      end

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
end
