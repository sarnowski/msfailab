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

defmodule MsfailabWeb.WorkspaceComponents do
  @moduledoc """
  Provides reusable UI components for workspace-related views.

  These components follow daisyUI conventions and use semantic theme colors
  to ensure consistent styling across the application.
  """
  use Phoenix.Component

  import MsfailabWeb.CoreComponents, only: [icon: 1]

  # Import verified routes for ~p sigil
  use Phoenix.VerifiedRoutes,
    endpoint: MsfailabWeb.Endpoint,
    router: MsfailabWeb.Router,
    statics: MsfailabWeb.static_paths()

  alias Msfailab.Tracks.ChatState
  alias Phoenix.LiveView.JS

  # MSF data tools (database query/mutation tools)
  @msf_data_tools ~w(list_hosts list_services list_vulns list_creds list_loots list_notes list_sessions retrieve_loot create_note)

  # coveralls-ignore-start
  # Reason: Pure presentation components - UI templates without business logic

  # ===========================================================================
  # Modal Components
  # ===========================================================================

  @doc """
  Renders a modal dialog using daisyUI's modal component.

  The modal is controlled via the `show` attribute and can be closed by
  clicking the backdrop or the close button.

  ## Examples

      <.modal id="create-workspace" show={@show_modal} on_cancel={JS.push("close_modal")}>
        <:title>Create Workspace</:title>
        <p>Modal content here</p>
        <:actions>
          <button class="btn">Cancel</button>
          <button class="btn btn-primary">Create</button>
        </:actions>
      </.modal>
  """
  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :on_cancel, JS, default: %JS{}

  slot :title, required: true
  slot :inner_block, required: true
  slot :actions

  def modal(assigns) do
    ~H"""
    <!-- Modal container -->
    <div
      id={@id}
      class={["modal", @show && "modal-open"]}
      phx-mounted={@show && JS.focus_first(to: "##{@id} .modal-box")}
    >
      <!-- Modal backdrop - clicking closes the modal -->
      <div class="modal-backdrop bg-base-300/80" phx-click={@on_cancel} />
      
    <!-- Modal content box -->
      <div class="modal-box bg-base-100 border-2 border-base-300">
        <!-- Modal header with title and close button -->
        <header class="flex items-center justify-between mb-4">
          <h3 class="text-lg font-bold">{render_slot(@title)}</h3>
          <button
            type="button"
            class="btn btn-sm btn-circle btn-ghost"
            phx-click={@on_cancel}
            aria-label="Close"
          >
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </header>
        
    <!-- Modal body -->
        <div class="py-2">
          {render_slot(@inner_block)}
        </div>
        
    <!-- Modal actions/footer -->
        <div :if={@actions != []} class="modal-action">
          {render_slot(@actions)}
        </div>
      </div>
    </div>
    """
  end

  # ===========================================================================
  # Card Components
  # ===========================================================================

  @doc """
  Renders a workspace card for the overview grid.

  Each card is clickable and navigates to the workspace.

  ## Examples

      <.workspace_card
        id="workspace-1"
        name="ACME Corp Pentest"
        description="Annual penetration testing engagement"
        slug="acme-corp"
      />
  """
  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :description, :string, required: true
  attr :slug, :string, required: true

  def workspace_card(assigns) do
    ~H"""
    <!-- Workspace card - clickable, navigates to workspace -->
    <.link
      id={@id}
      navigate={~p"/#{@slug}"}
      class="card bg-base-100 border-2 border-base-300 hover:bg-primary hover:border-primary hover:shadow-lg transition-all cursor-pointer group"
    >
      <div class="card-body">
        <!-- Workspace name -->
        <h2 class="card-title text-base-content group-hover:text-primary-content transition-colors">
          {@name}
        </h2>
        <!-- Workspace description -->
        <p class="text-base-content/70 group-hover:text-primary-content/80 text-sm line-clamp-3">
          {@description}
        </p>
      </div>
    </.link>
    """
  end

  @doc """
  Renders a "create new" card with a prominent plus icon.

  Used as the last item in workspace/track grids to allow creating new items.

  ## Examples

      <.new_item_card on_click={JS.push("open_create_modal")} label="Create Workspace" />
  """
  attr :on_click, JS, required: true
  attr :label, :string, default: "Create new"

  def new_item_card(assigns) do
    ~H"""
    <!-- New item card - dashed border, plus icon -->
    <button
      type="button"
      class="card border-2 border-dashed border-base-300 hover:border-primary hover:bg-base-100 transition-all cursor-pointer group min-h-[140px] flex items-center justify-center"
      phx-click={@on_click}
      aria-label={@label}
    >
      <div class="card-body items-center justify-center">
        <.icon
          name="hero-plus"
          class="size-12 text-base-content/40 group-hover:text-primary transition-colors"
        />
        <span class="text-base-content/60 group-hover:text-primary text-sm font-medium">
          {@label}
        </span>
      </div>
    </button>
    """
  end

  # ===========================================================================
  # Header/Navigation Components
  # ===========================================================================

  @doc """
  Renders the workspace header with tabs for containers and their tracks.

  Containers are displayed as groups, each containing:
  - Container name tab
  - Track tabs for that container
  - New track button for that container

  ## Examples

      <.workspace_header
        workspace_slug="acme-corp"
        current_track={@current_track}
        containers={@containers}
        on_new_container={JS.push("open_create_container_modal")}
      />
  """
  attr :workspace_slug, :string, required: true
  attr :current_track, :map, default: nil
  attr :containers, :list, required: true
  attr :on_new_container, JS, required: true

  def workspace_header(assigns) do
    ~H"""
    <!-- Workspace header - single line navigation bar with tab-style containers -->
    <header class="relative bg-base-100">
      <!-- Border line rendered behind tabs -->
      <div class="absolute bottom-0 left-0 right-0 h-[2px] bg-base-300" />
      <nav class="relative flex items-end h-12 px-2">
        <!-- Left section: Asset Library tab + Container tabs + New container button -->
        <div class="flex items-end flex-1 overflow-x-auto">
          <!-- Asset Library tab (icon only) -->
          <.header_tab
            icon="hero-building-library"
            active={is_nil(@current_track)}
            href={~p"/#{@workspace_slug}"}
            tooltip="Asset Library"
          />
          
    <!-- Container tabs -->
          <.container_group
            :for={container <- @containers}
            container={container}
            workspace_slug={@workspace_slug}
            current_track={@current_track}
          />
          
    <!-- New container button -->
          <button
            type="button"
            class="btn btn-ghost btn-sm px-2 ml-2 mb-1"
            phx-click={@on_new_container}
            aria-label="Create new container"
          >
            <.icon name="hero-plus" class="size-4" />
            <.icon name="hero-server-stack" class="size-4" />
          </button>
        </div>
        
    <!-- Right section: Overflow menu + Close button -->
        <div class="flex items-center gap-1 pl-2 h-full border-l border-base-300">
          <!-- Overflow/archived tracks menu -->
          <div class="dropdown dropdown-end">
            <button
              type="button"
              tabindex="0"
              class="btn btn-ghost btn-sm px-2"
              aria-label="More tracks"
            >
              <.icon name="hero-bars-3" class="size-5" />
            </button>
            <ul
              tabindex="0"
              class="dropdown-content menu bg-base-100 border-2 border-base-300 rounded-box w-52 p-2 shadow-lg z-50"
            >
              <li class="menu-title">
                <span>Archived Tracks</span>
              </li>
              <li>
                <span class="text-base-content/50 text-sm">No archived tracks</span>
              </li>
            </ul>
          </div>
          
    <!-- Close button - returns to workspace overview -->
          <.link
            navigate={~p"/"}
            class="btn btn-ghost btn-sm px-2"
            aria-label="Close workspace"
          >
            <.icon name="hero-x-mark" class="size-5" />
          </.link>
        </div>
      </nav>
    </header>
    """
  end

  @doc """
  Renders a container group with its tracks as a unified tab.

  The entire container is treated as a single tab that gets highlighted
  when any of its tracks is currently selected. Inside the tab:
  - Container name with icon
  - Track links
  - New track button
  """
  attr :container, :map, required: true
  attr :workspace_slug, :string, required: true
  attr :current_track, :map, default: nil

  def container_group(assigns) do
    # Filter to only non-archived tracks
    tracks = Enum.filter(assigns.container.tracks, &is_nil(&1.archived_at))

    # Check if any track in this container is currently selected
    is_active =
      assigns.current_track != nil &&
        Enum.any?(tracks, &(&1.slug == assigns.current_track.slug))

    assigns =
      assigns
      |> assign(:tracks, tracks)
      |> assign(:is_active, is_active)

    ~H"""
    <!-- Container tab - the whole container is treated as a single tab -->
    <div class={[
      "flex items-center gap-0.5 ml-1 px-1 rounded-t-lg border-2 border-b-0",
      @is_active && "bg-base-200 border-base-300 h-10 pb-[2px]",
      !@is_active && "bg-base-100 border-base-300/50 hover:border-base-300 h-9 mb-[2px]"
    ]}>
      <!-- Container label -->
      <div class={[
        "flex items-center gap-1 px-2 text-xs font-medium",
        @is_active && "text-base-content",
        !@is_active && "text-base-content/60"
      ]}>
        <.icon name="hero-server-stack" class="size-3" />
        <span class="max-w-[80px] truncate">{@container.name}</span>
      </div>
      
    <!-- Track links for this container -->
      <.link
        :for={track <- @tracks}
        navigate={~p"/#{@workspace_slug}/#{track.slug}"}
        class={[
          "btn btn-xs h-7",
          @current_track && @current_track.slug == track.slug && "btn-primary",
          !(@current_track && @current_track.slug == track.slug) && "btn-ghost"
        ]}
      >
        <span class="max-w-[100px] truncate">{track.name}</span>
      </.link>
      
    <!-- New track button for this container -->
      <button
        type="button"
        class="btn btn-ghost btn-xs px-1.5 h-7"
        phx-click="open_create_track_modal"
        phx-value-container_id={@container.id}
        aria-label={"Create new track in #{@container.name}"}
      >
        <.icon name="hero-plus" class="size-3" />
      </button>
    </div>
    """
  end

  @doc """
  Renders an individual tab in the header navigation.

  Can display either an icon-only tab or a labeled tab. Uses the same
  tab styling as container groups for visual consistency.

  ## Examples

      <.header_tab icon="hero-home" active={true} href="/" />
      <.header_tab label="Track 1" active={false} href="/workspace/track-1" />
  """
  attr :label, :string, default: nil
  attr :icon, :string, default: nil
  attr :active, :boolean, default: false
  attr :href, :string, required: true
  attr :tooltip, :string, default: nil

  def header_tab(assigns) do
    ~H"""
    <!-- Header tab - styled as a tab that aligns with container tabs -->
    <.link
      navigate={@href}
      class={[
        "flex items-center gap-1 px-3 rounded-t-lg border-2 border-b-0",
        @active && "bg-base-200 border-base-300 text-base-content h-10 pb-[2px]",
        !@active &&
          "bg-base-100 border-base-300/50 text-base-content/60 hover:border-base-300 h-9 mb-[2px]"
      ]}
      title={@tooltip}
    >
      <.icon :if={@icon} name={@icon} class="size-4" />
      <span :if={@label} class="max-w-[120px] truncate text-sm font-medium">{@label}</span>
    </.link>
    """
  end

  # ===========================================================================
  # Content Area Components
  # ===========================================================================

  @doc """
  Renders the Asset Library content area with a search box.

  ## Examples

      <.asset_library />
  """
  def asset_library(assigns) do
    ~H"""
    <!-- Asset Library content area -->
    <div class="flex-1 flex flex-col">
      <!-- Search section - centered prominently -->
      <div class="flex justify-center py-8">
        <div class="form-control w-full max-w-xl">
          <div class="input-group">
            <label class="input input-bordered flex items-center gap-2 w-full bg-base-100 border-2 border-base-300 focus-within:border-primary">
              <.icon name="hero-magnifying-glass" class="size-5 text-base-content/50" />
              <input
                type="text"
                placeholder="Search assets (hosts, services, vulnerabilities, credentials...)"
                class="grow bg-transparent focus:outline-none"
              />
            </label>
          </div>
        </div>
      </div>
      
    <!-- Asset content placeholder -->
      <div class="flex-1 px-6 pb-6">
        <div class="bg-base-100 border-2 border-base-300 rounded-box p-6 min-h-[300px]">
          <!-- Asset categories placeholder -->
          <div class="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
            <.asset_stat_card icon="hero-server" label="Hosts" count={0} />
            <.asset_stat_card icon="hero-globe-alt" label="Services" count={0} />
            <.asset_stat_card icon="hero-shield-exclamation" label="Vulnerabilities" count={0} />
            <.asset_stat_card icon="hero-key" label="Credentials" count={0} />
          </div>
          
    <!-- Empty state message -->
          <div class="text-center py-12 text-base-content/50">
            <.icon name="hero-inbox" class="size-16 mx-auto mb-4" />
            <p class="text-lg font-medium">No assets discovered yet</p>
            <p class="text-sm">Start a track to begin discovering assets</p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a stat card for the asset library.
  """
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :count, :integer, required: true

  def asset_stat_card(assigns) do
    ~H"""
    <!-- Asset stat card -->
    <div class="stat bg-base-200 rounded-box border border-base-300">
      <div class="stat-figure text-primary">
        <.icon name={@icon} class="size-8" />
      </div>
      <div class="stat-title text-xs">{@label}</div>
      <div class="stat-value text-2xl">{@count}</div>
    </div>
    """
  end

  @doc """
  Renders the Track content area with AI chat and terminal split view.

  ## Examples

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
      />
  """
  attr :track, :map, required: true
  attr :chat_state, Msfailab.Tracks.ChatState, required: true
  attr :console_segments, :list, default: []
  attr :console_status, :atom, default: :offline
  attr :current_prompt, :string, default: ""
  attr :input_text, :string, default: ""
  attr :input_mode, :string, default: "ai"
  attr :selected_model, :string, default: "gpt-5.1"
  attr :autonomous_mode, :boolean, default: false
  attr :show_input_menu, :boolean, default: false
  attr :available_models, :list, default: []

  def track_content(assigns) do
    ~H"""
    <!-- Track content area - split view with floating input -->
    <div class="flex-1 flex flex-col relative overflow-hidden">
      <!-- Main content: AI Chat (left) + Divider + Terminal (right) -->
      <div
        id="resizable-panes"
        phx-hook="ResizablePanes"
        class="flex-1 grid p-4 pb-20 overflow-hidden"
        style="grid-template-columns: var(--left-pane-width, 50%) 8px 1fr;"
      >
        <!-- AI Chat Side -->
        <div data-pane-left class="flex flex-col overflow-hidden min-w-0">
          <.chat_panel chat_state={@chat_state} />
        </div>
        <!-- Draggable divider -->
        <div
          data-pane-divider
          class="flex items-center justify-center cursor-col-resize group hover:bg-primary/10 rounded transition-colors"
        >
          <div class="w-1 h-12 bg-base-300 rounded-full group-hover:bg-primary transition-colors" />
        </div>
        <!-- Terminal Side -->
        <div data-pane-right class="flex flex-col overflow-hidden min-w-0">
          <.terminal_panel
            segments={@console_segments}
            console_status={@console_status}
            current_prompt={@current_prompt}
          />
        </div>
      </div>
      
    <!-- Floating Input Bar -->
      <.input_bar
        input_text={@input_text}
        input_mode={@input_mode}
        console_status={@console_status}
        turn_status={@chat_state.turn_status}
        selected_model={@selected_model}
        autonomous_mode={@autonomous_mode}
        show_menu={@show_input_menu}
        available_models={@available_models}
      />
    </div>
    """
  end

  # ===========================================================================
  # Track Content Sub-Components
  # ===========================================================================

  @doc """
  Renders the AI chat panel with message bubbles.
  """
  attr :chat_state, Msfailab.Tracks.ChatState, required: true

  def chat_panel(assigns) do
    ~H"""
    <!-- AI Chat Panel -->
    <div class="flex-1 flex flex-col bg-base-100 rounded-box border-2 border-base-300 overflow-hidden">
      <!-- Chat header with status indicator -->
      <div class="flex items-center justify-between px-3 py-2 border-b border-base-300 bg-base-200/50">
        <div class="flex items-center gap-2">
          <.icon name="hero-chat-bubble-left-right" class="size-4 text-base-content/60" />
          <span class="text-xs font-medium text-base-content/60">Security Research Assistant</span>
        </div>
        <.chat_status_badge status={@chat_state.turn_status} />
      </div>
      <!-- Chat messages wrapper (relative for scroll button positioning) -->
      <div class="flex-1 relative overflow-hidden">
        <!-- Chat messages container -->
        <div
          id="chat-scroll-container"
          phx-hook="AutoScroll"
          class="absolute inset-0 overflow-y-auto p-4 space-y-4"
        >
          <%= if @chat_state.entries == [] do %>
            <!-- Empty state with responsible use warning -->
            <div class="flex-1 flex items-center justify-center h-full">
              <div class="alert alert-warning max-w-lg shadow-lg">
                <.icon name="hero-exclamation-triangle" class="size-6" />
                <div>
                  <h3 class="font-semibold">Responsible Use Notice</h3>
                  <p class="mt-2 text-sm">
                    This tool can execute exploits, access sensitive data, and cause system damage.
                    You must only use it against systems that you <strong>own</strong>
                    or have <strong>explicit written authorization</strong>
                    to test.
                  </p>
                  <p class="mt-2 text-sm">
                    Unauthorized use may result in criminal liability, unintended data exposure,
                    or disruption of critical services.
                  </p>
                  <p class="mt-2 text-xs opacity-75">
                    This program is distributed WITHOUT ANY WARRANTY; without even the implied
                    warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
                    See the GNU Affero General Public License for more details.
                  </p>
                </div>
              </div>
            </div>
          <% else %>
            <!-- Message list -->
            <.chat_entry :for={entry <- @chat_state.entries} entry={entry} />
          <% end %>
        </div>
        <!-- Scroll to bottom button (visibility controlled by AutoScroll hook) -->
        <button
          type="button"
          id="chat-scroll-button"
          phx-update="ignore"
          data-scroll-button
          class="hidden absolute bottom-3 right-3 btn btn-circle btn-sm btn-neutral shadow-lg"
          aria-label="Scroll to bottom"
        >
          <.icon name="hero-arrow-down" class="size-4" />
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders a chat status badge indicating the turn status.

  Turn statuses:
  - `:idle` / `:finished` - No badge
  - `:pending` - Waiting for LLM response
  - `:streaming` - LLM is responding
  - `:pending_approval` - Tools awaiting user approval
  - `:executing_tools` - Tools are executing
  - `:error` - Error occurred
  """
  attr :status, :atom, required: true

  def chat_status_badge(assigns) do
    ~H"""
    <%= case @status do %>
      <% :pending -> %>
        <span class="badge badge-info badge-sm gap-1">
          <span class="loading loading-spinner loading-xs" /> Waiting...
        </span>
      <% :streaming -> %>
        <span class="badge badge-info badge-sm gap-1">
          <span class="loading loading-spinner loading-xs" /> Responding...
        </span>
      <% :pending_approval -> %>
        <span class="badge badge-warning badge-sm gap-1">
          <.icon name="hero-clock-mini" class="size-3" /> Awaiting Approval
        </span>
      <% :executing_tools -> %>
        <span class="badge badge-info badge-sm gap-1">
          <span class="loading loading-spinner loading-xs" /> Executing...
        </span>
      <% :error -> %>
        <span class="badge badge-error badge-sm gap-1">
          <.icon name="hero-exclamation-triangle-mini" class="size-3" /> Error
        </span>
      <% _ -> %>
        <!-- No badge for :idle, :finished -->
    <% end %>
    """
  end

  @doc """
  Renders a single chat entry.

  Dispatches to the appropriate sub-component based on entry type:
  - `:message` - User prompts, assistant thinking, assistant responses
  - `:tool_invocation` - LLM tool calls with approval flow

  Uses ChatEntry struct from Msfailab.Tracks.ChatEntry.
  """
  attr :entry, Msfailab.Tracks.ChatEntry, required: true

  def chat_entry(assigns) do
    ~H"""
    <%= case @entry.entry_type do %>
      <% :message -> %>
        <.message_entry entry={@entry} />
      <% :tool_invocation -> %>
        <.tool_entry entry={@entry} />
    <% end %>
    """
  end

  # Renders a message entry (user prompt, assistant thinking, or response).
  defp message_entry(assigns) do
    ~H"""
    <%= case {@entry.role, @entry.message_type} do %>
      <% {:user, :prompt} -> %>
        <!-- User prompt - left aligned -->
        <div class="flex justify-start">
          <div class="max-w-[90%] bg-secondary rounded-box p-3 border border-secondary">
            <div class="flex items-center gap-2 mb-1">
              <.icon name="hero-user" class="size-4 text-secondary-content" />
              <span class="text-xs font-medium text-secondary-content">You</span>
              <span class="text-xs text-secondary-content/50">
                <.entry_timestamp timestamp={@entry.timestamp} />
              </span>
            </div>
            <p class="text-sm text-secondary-content whitespace-pre-wrap">{@entry.content}</p>
          </div>
        </div>
      <% {:assistant, :thinking} -> %>
        <!-- Assistant thinking block -->
        <div class="flex justify-end">
          <%= if @entry.streaming do %>
            <!-- Streaming: fully visible -->
            <div class="w-[90%] bg-base-200/50 rounded-box p-3 border border-base-300/50">
              <div class="flex items-center gap-2 mb-1">
                <.icon name="hero-light-bulb" class="size-4 text-base-content/50" />
                <span class="text-xs font-medium text-base-content/50">Thinking</span>
                <span class="text-xs text-base-content/40">
                  <.entry_timestamp timestamp={@entry.timestamp} />
                </span>
                <span class="loading loading-dots loading-xs" />
              </div>
              <div
                id={"streaming-thinking-#{@entry.id}"}
                phx-hook="StreamingCursor"
                class="text-sm prose prose-sm max-w-none text-base-content/70"
              >
                {Phoenix.HTML.raw(@entry.rendered_html)}
              </div>
            </div>
          <% else %>
            <!-- Finished: collapsible -->
            <details class="w-[90%] bg-base-200/50 rounded-box border border-base-300/50 group">
              <summary class="flex items-center gap-2 p-3 cursor-pointer select-none list-none [&::-webkit-details-marker]:hidden">
                <.icon name="hero-light-bulb" class="size-4 text-base-content/50" />
                <span class="text-xs font-medium text-base-content/50">Thinking</span>
                <span class="text-xs text-base-content/40">
                  <.entry_timestamp timestamp={@entry.timestamp} />
                </span>
                <.icon
                  name="hero-chevron-down"
                  class="size-3 text-base-content/40 transition-transform group-open:rotate-180 ml-auto"
                />
              </summary>
              <div class="px-3 pb-3 text-sm prose prose-sm max-w-none text-base-content/70">
                {Phoenix.HTML.raw(@entry.rendered_html || @entry.content)}
              </div>
            </details>
          <% end %>
        </div>
      <% {:assistant, :response} -> %>
        <!-- Assistant response - right aligned -->
        <div class="flex justify-end">
          <div class="w-[90%] bg-base-200 rounded-box p-3 border border-base-300">
            <div class="flex items-center gap-2 mb-1">
              <.icon name="hero-sparkles" class="size-4 text-base-content/60" />
              <span class="text-xs font-medium text-base-content/60">
                Security Research Assistant
              </span>
              <span class="text-xs text-base-content/40">
                <.entry_timestamp timestamp={@entry.timestamp} />
              </span>
            </div>
            <%= if @entry.streaming do %>
              <div
                id={"streaming-response-#{@entry.id}"}
                phx-hook="StreamingCursor"
                class="text-sm prose prose-sm max-w-none"
              >
                {Phoenix.HTML.raw(@entry.rendered_html)}
              </div>
            <% else %>
              <div class="text-sm prose prose-sm max-w-none">
                {Phoenix.HTML.raw(@entry.rendered_html || @entry.content)}
              </div>
            <% end %>
          </div>
        </div>
      <% _ -> %>
        <!-- Fallback for unknown message types -->
        <div class="text-sm text-base-content/50">{@entry.content}</div>
    <% end %>
    """
  end

  # ===========================================================================
  # Tool Entry Components - Pluggable UI System
  # ===========================================================================
  #
  # This section implements a pluggable rendering system for tool invocations.
  # Each tool can define custom rendering for different states while sharing
  # common building blocks.
  #
  # Data Flow:
  #   @chat_state.entries → :for loop → chat_entry(entry) → tool_entry(entry)
  #                                                              │
  #                                           dispatch by entry.tool_status
  #                                                              │
  #     ├── :pending   → tool_pending_box (common)
  #     ├── :declined  → tool_declined_box (common)
  #     ├── :executing → tool_executing_box (per-tool dispatch)
  #     ├── :success   → tool_finished_box (per-tool dispatch)
  #     └── :error     → tool_error_box (default + per-tool override)

  # Main router - dispatches by tool_status
  defp tool_entry(assigns) do
    ~H"""
    <%= case @entry.tool_status do %>
      <% :pending -> %>
        <.tool_pending_box entry={@entry} />
      <% :declined -> %>
        <.tool_declined_box entry={@entry} />
      <% :executing -> %>
        <.tool_executing_box entry={@entry} />
      <% :success -> %>
        <.tool_finished_box entry={@entry} />
      <% status when status in [:error, :timeout] -> %>
        <.tool_error_box entry={@entry} />
      <% _ -> %>
        <!-- Fallback for unknown status -->
        <.tool_pending_box entry={@entry} />
    <% end %>
    """
  end

  # ---------------------------------------------------------------------------
  # Shared Helpers (Building Blocks)
  # ---------------------------------------------------------------------------

  # Container component with icon, tool name, timestamp, status badge, and inner content.
  # This provides the common "box" structure used by pending/declined states.
  attr :entry, Msfailab.Tracks.ChatEntry, required: true
  attr :status_override, :atom, default: nil
  slot :inner_block, required: true

  defp tool_box(assigns) do
    status = assigns.status_override || assigns.entry.tool_status
    # Use warning border for pending state to draw attention
    border_class = if status == :pending, do: "border-warning", else: "border-base-300"

    assigns = assigns |> assign(:status, status) |> assign(:border_class, border_class)

    ~H"""
    <!-- Tool box container - right aligned -->
    <div class="flex justify-end">
      <div class={["min-w-[60%] max-w-[90%] bg-base-200 rounded-box p-3 border", @border_class]}>
        <!-- Header with tool name and status -->
        <div class="flex items-center gap-2 mb-2">
          <.icon name="hero-command-line" class="size-4 text-base-content" />
          <span class="text-xs font-medium text-base-content">
            {tool_display_name(@entry.tool_name)}
          </span>
          <span class="text-xs text-base-content/60">
            <.entry_timestamp timestamp={@entry.timestamp} />
          </span>
          <div class="ml-auto">
            <.tool_status_badge status={@status} />
          </div>
        </div>
        <!-- Tool-specific content -->
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  # Terminal-style box mimicking the main terminal panel design.
  # Used by executing states and finished bash commands.
  attr :title, :string, required: true
  attr :timestamp, DateTime, required: true
  attr :status, :atom, default: nil
  slot :inner_block, required: true

  defp terminal_box(assigns) do
    ~H"""
    <div class="flex justify-end">
      <div class="min-w-[60%] max-w-[90%] bg-neutral rounded-box border border-base-300 overflow-hidden">
        <!-- Terminal header -->
        <div class="flex items-center justify-between px-3 py-1.5 bg-neutral-focus border-b border-base-300">
          <div class="flex items-center gap-2">
            <div class="flex gap-1.5">
              <div class="size-2.5 rounded-full bg-error/80" />
              <div class="size-2.5 rounded-full bg-warning/80" />
              <div class="size-2.5 rounded-full bg-success/80" />
            </div>
            <span class="text-xs font-mono text-neutral-content/60 ml-2">{@title}</span>
          </div>
          <div class="flex items-center gap-2">
            <!-- Badge before time when executing -->
            <.tool_status_badge :if={@status} status={@status} />
            <span class="text-xs text-neutral-content/40">
              <.entry_timestamp timestamp={@timestamp} />
            </span>
          </div>
        </div>
        <!-- Terminal content -->
        <div class="p-3 font-mono text-sm text-neutral-content">
          {render_slot(@inner_block)}
        </div>
      </div>
    </div>
    """
  end

  # Renders a command with prompt in a monospace box.
  # Used by pending and declined states.
  attr :prompt, :string, required: true
  attr :command, :string, required: true

  defp command_display(assigns) do
    ~H"""
    <div class="bg-neutral rounded px-3 py-2 font-mono text-sm text-neutral-content">
      <span :if={@prompt != ""} class="text-success">{@prompt}</span><strong>{@command}</strong>
    </div>
    """
  end

  # Renders terminal-style output (raw pre-formatted text).
  # Used inside terminal_box for finished commands.
  attr :output, :string, required: true
  attr :class, :string, default: ""

  defp terminal_output(assigns) do
    ~H"""
    <pre class={["whitespace-pre-wrap overflow-x-auto max-h-48 overflow-y-auto", @class]}>{@output}</pre>
    """
  end

  # ---------------------------------------------------------------------------
  # Common Status Renderers
  # ---------------------------------------------------------------------------

  # Pending state for msf_command - uses Console helper for proper prompt styling
  defp tool_pending_box(%{entry: %{tool_name: "msf_command"}} = assigns) do
    prompt = assigns.entry.console_prompt || "msf6 > "
    command = get_tool_command(assigns.entry.tool_arguments)
    assigns = assigns |> assign(:prompt, prompt) |> assign(:command, command)

    ~H"""
    <.tool_box entry={@entry}>
      <div class="bg-neutral rounded px-3 py-2 font-mono text-sm text-neutral-content">
        {MsfailabWeb.Console.render_console_command(@prompt, @command)}
      </div>
      <.approval_buttons entry_id={@entry.id} />
    </.tool_box>
    """
  end

  # Pending state for bash_command - uses Console helper for proper prompt styling
  defp tool_pending_box(%{entry: %{tool_name: "bash_command"}} = assigns) do
    command = get_tool_command(assigns.entry.tool_arguments)
    assigns = assign(assigns, :command, command)

    ~H"""
    <.tool_box entry={@entry}>
      <div class="bg-neutral rounded px-3 py-2 font-mono text-sm text-neutral-content">
        {MsfailabWeb.Console.render_bash_command(@command)}
      </div>
      <.approval_buttons entry_id={@entry.id} />
    </.tool_box>
    """
  end

  # Default pending state for unknown tools
  defp tool_pending_box(assigns) do
    prompt = get_tool_prompt(assigns.entry)
    command = get_tool_command(assigns.entry.tool_arguments)
    assigns = assigns |> assign(:prompt, prompt) |> assign(:command, command)

    ~H"""
    <.tool_box entry={@entry}>
      <.command_display prompt={@prompt} command={@command} />
      <.approval_buttons entry_id={@entry.id} />
    </.tool_box>
    """
  end

  # Shared approval buttons component
  attr :entry_id, :any, required: true

  defp approval_buttons(assigns) do
    ~H"""
    <div class="flex gap-2 justify-end mt-2">
      <button
        type="button"
        phx-click="deny_tool"
        phx-value-entry-id={@entry_id}
        class="btn btn-sm btn-error btn-outline"
      >
        <.icon name="hero-x-mark" class="size-4" /> Deny
      </button>
      <button
        type="button"
        phx-click="approve_tool"
        phx-value-entry-id={@entry_id}
        class="btn btn-sm btn-secondary"
      >
        <.icon name="hero-check" class="size-4" /> Approve
      </button>
    </div>
    """
  end

  # Declined state for msf_command
  defp tool_declined_box(%{entry: %{tool_name: "msf_command"}} = assigns) do
    prompt = assigns.entry.console_prompt || "msf6 > "
    command = get_tool_command(assigns.entry.tool_arguments)
    assigns = assigns |> assign(:prompt, prompt) |> assign(:command, command)

    ~H"""
    <.tool_box entry={@entry} status_override={:declined}>
      <div class="bg-neutral rounded px-3 py-2 font-mono text-sm text-neutral-content">
        {MsfailabWeb.Console.render_console_command(@prompt, @command)}
      </div>
    </.tool_box>
    """
  end

  # Declined state for bash_command
  defp tool_declined_box(%{entry: %{tool_name: "bash_command"}} = assigns) do
    command = get_tool_command(assigns.entry.tool_arguments)
    assigns = assign(assigns, :command, command)

    ~H"""
    <.tool_box entry={@entry} status_override={:declined}>
      <div class="bg-neutral rounded px-3 py-2 font-mono text-sm text-neutral-content">
        {MsfailabWeb.Console.render_bash_command(@command)}
      </div>
    </.tool_box>
    """
  end

  # Default declined state for unknown tools
  defp tool_declined_box(assigns) do
    prompt = get_tool_prompt(assigns.entry)
    command = get_tool_command(assigns.entry.tool_arguments)
    assigns = assigns |> assign(:prompt, prompt) |> assign(:command, command)

    ~H"""
    <.tool_box entry={@entry} status_override={:declined}>
      <.command_display prompt={@prompt} command={@command} />
    </.tool_box>
    """
  end

  # ---------------------------------------------------------------------------
  # Per-Tool Executing Renderers
  # ---------------------------------------------------------------------------

  # Executing state for msf_command - terminal style with blinking cursor
  defp tool_executing_box(%{entry: %{tool_name: "msf_command"}} = assigns) do
    prompt = assigns.entry.console_prompt || "msf6 > "
    command = get_tool_command(assigns.entry.tool_arguments)
    assigns = assigns |> assign(:prompt, prompt) |> assign(:command, command)

    ~H"""
    <.terminal_box title="msfconsole" timestamp={@entry.timestamp} status={:executing}>
      <div>{MsfailabWeb.Console.render_console_command(@prompt, @command)}</div>
      <div class="mt-1"><span class="terminal-cursor"></span></div>
    </.terminal_box>
    """
  end

  # Executing state for bash_command - terminal style with blinking cursor
  defp tool_executing_box(%{entry: %{tool_name: "bash_command"}} = assigns) do
    command = get_tool_command(assigns.entry.tool_arguments)
    assigns = assign(assigns, :command, command)

    ~H"""
    <.terminal_box title="bash" timestamp={@entry.timestamp} status={:executing}>
      <div>{MsfailabWeb.Console.render_bash_command(@command)}</div>
      <div class="mt-1"><span class="terminal-cursor"></span></div>
    </.terminal_box>
    """
  end

  # Executing state for MSF data tools - simple box with active label and status badge
  defp tool_executing_box(%{entry: %{tool_name: tool_name}} = assigns)
       when tool_name in @msf_data_tools do
    assigns = assign(assigns, :label, msf_data_active_label(tool_name))

    ~H"""
    <div class="flex justify-end">
      <div class="min-w-[40%] max-w-[70%] bg-base-200 rounded-box px-4 py-2 border border-base-300 flex items-center justify-between gap-4">
        <span class="text-sm text-base-content">{@label}</span>
        <.tool_status_badge status={:executing} />
      </div>
    </div>
    """
  end

  # Default executing state for unknown tools
  defp tool_executing_box(assigns) do
    prompt = get_tool_prompt(assigns.entry)
    command = get_tool_command(assigns.entry.tool_arguments)
    assigns = assigns |> assign(:prompt, prompt) |> assign(:command, command)

    ~H"""
    <.tool_box entry={@entry}>
      <.command_display prompt={@prompt} command={@command} />
    </.tool_box>
    """
  end

  # ---------------------------------------------------------------------------
  # Per-Tool Finished Renderers (Main Differentiation)
  # ---------------------------------------------------------------------------

  # Finished state for msf_command - collapsed one-liner, expand to terminal box
  # MSF output is visible in the console panel, so we show a minimal collapsed view.
  defp tool_finished_box(%{entry: %{tool_name: "msf_command"}} = assigns) do
    prompt = assigns.entry.console_prompt || "msf6 > "
    command = get_tool_command(assigns.entry.tool_arguments)
    output = assigns.entry.result_content || ""

    assigns =
      assigns |> assign(:prompt, prompt) |> assign(:command, command) |> assign(:output, output)

    ~H"""
    <div class="flex justify-end">
      <details class="min-w-[60%] max-w-[90%] bg-neutral/70 rounded-box border border-base-300/30 group">
        <summary class="flex items-center gap-2 px-3 py-2 cursor-pointer select-none list-none [&::-webkit-details-marker]:hidden">
          <code class="text-xs text-neutral-content/80">
            {MsfailabWeb.Console.render_console_command(@prompt, @command)}
          </code>
          <.icon
            name="hero-chevron-down"
            class="size-3 text-neutral-content/50 transition-transform group-open:rotate-180 ml-auto"
          />
        </summary>
        <!-- Expanded: terminal box style -->
        <div class="mx-2 mb-2 bg-neutral rounded-box border border-base-300 overflow-hidden">
          <div class="flex items-center justify-between px-3 py-1.5 bg-neutral-focus border-b border-base-300">
            <div class="flex items-center gap-2">
              <div class="flex gap-1.5">
                <div class="size-2.5 rounded-full bg-error/80" />
                <div class="size-2.5 rounded-full bg-warning/80" />
                <div class="size-2.5 rounded-full bg-success/80" />
              </div>
              <span class="text-xs font-mono text-neutral-content/60 ml-2">msfconsole</span>
            </div>
            <span class="text-xs text-neutral-content/40">
              <.entry_timestamp timestamp={@entry.timestamp} />
            </span>
          </div>
          <div class="p-3 font-mono text-sm text-neutral-content">
            {MsfailabWeb.Console.render_console_output(@prompt, @command, @output)}
          </div>
        </div>
      </details>
    </div>
    """
  end

  # Finished state for bash_command - terminal box with output
  # Bash output is NOT visible elsewhere, so we prominently display it.
  defp tool_finished_box(%{entry: %{tool_name: "bash_command"}} = assigns) do
    command = get_tool_command(assigns.entry.tool_arguments)
    output = assigns.entry.result_content || ""

    assigns = assigns |> assign(:command, command) |> assign(:output, output)

    ~H"""
    <.terminal_box title="bash" timestamp={@entry.timestamp}>
      {MsfailabWeb.Console.render_bash_output(@command, @output)}
    </.terminal_box>
    """
  end

  # Finished state for MSF data tools - hidden (result is consumed by LLM, not shown to user)
  defp tool_finished_box(%{entry: %{tool_name: tool_name}} = assigns)
       when tool_name in @msf_data_tools do
    ~H"""
    """
  end

  # Default finished state for unknown tools
  defp tool_finished_box(assigns) do
    prompt = get_tool_prompt(assigns.entry)
    command = get_tool_command(assigns.entry.tool_arguments)
    output = assigns.entry.result_content || ""

    assigns =
      assigns |> assign(:prompt, prompt) |> assign(:command, command) |> assign(:output, output)

    ~H"""
    <.tool_box entry={@entry}>
      <.command_display prompt={@prompt} command={@command} />
      <div
        :if={@output != ""}
        class="mt-2 bg-neutral rounded px-2 py-1.5 font-mono text-xs text-neutral-content overflow-x-auto max-h-48 overflow-y-auto"
      >
        <.terminal_output output={@output} />
      </div>
    </.tool_box>
    """
  end

  # ---------------------------------------------------------------------------
  # Error Renderers
  # ---------------------------------------------------------------------------

  # Error/timeout state - shows command and error message.
  # Can be overridden per-tool if needed.
  defp tool_error_box(assigns) do
    prompt = get_tool_prompt(assigns.entry)
    command = get_tool_command(assigns.entry.tool_arguments)
    error = assigns.entry.result_content || "An error occurred"

    assigns =
      assigns |> assign(:prompt, prompt) |> assign(:command, command) |> assign(:error, error)

    ~H"""
    <.tool_box entry={@entry}>
      <.command_display prompt={@prompt} command={@command} />
      <div class="mt-2 bg-error/10 rounded px-2 py-1.5 border border-error/30">
        <code class="text-xs text-error break-all">{@error}</code>
      </div>
    </.tool_box>
    """
  end

  # Renders a status badge for tool invocations.
  defp tool_status_badge(assigns) do
    ~H"""
    <%= case @status do %>
      <% :pending -> %>
        <span class="badge badge-warning badge-sm gap-1">
          <.icon name="hero-clock" class="size-3" /> Awaiting approval
        </span>
      <% :approved -> %>
        <span class="badge badge-info badge-sm gap-1">
          <.icon name="hero-check" class="size-3" /> Approved
        </span>
      <% :executing -> %>
        <span class="badge badge-info badge-sm gap-1">
          <span class="loading loading-spinner loading-xs" /> Running...
        </span>
      <% :success -> %>
        <!-- No badge when complete -->
      <% :error -> %>
        <span class="badge badge-error badge-sm gap-1">
          <.icon name="hero-exclamation-circle" class="size-3" /> Failed
        </span>
      <% :timeout -> %>
        <span class="badge badge-error badge-sm gap-1">
          <.icon name="hero-clock" class="size-3" /> Timed out
        </span>
      <% :denied -> %>
        <span class="badge badge-error badge-sm gap-1">
          <.icon name="hero-x-circle" class="size-3" /> Denied
        </span>
    <% end %>
    """
  end

  # Helper function to get display name for tools
  defp tool_display_name("msf_command"), do: "Metasploit Command"
  defp tool_display_name("bash_command"), do: "Bash Command"
  defp tool_display_name("list_hosts"), do: "List Hosts"
  defp tool_display_name("list_services"), do: "List Services"
  defp tool_display_name("list_vulns"), do: "List Vulnerabilities"
  defp tool_display_name("list_creds"), do: "List Credentials"
  defp tool_display_name("list_loots"), do: "List Loot"
  defp tool_display_name("list_notes"), do: "List Notes"
  defp tool_display_name("list_sessions"), do: "List Sessions"
  defp tool_display_name("retrieve_loot"), do: "Retrieve Loot"
  defp tool_display_name("create_note"), do: "Create Note"
  defp tool_display_name(name), do: name

  # Helper function to extract command from tool arguments
  defp get_tool_command(arguments) when is_map(arguments) do
    Map.get(arguments, "command", inspect(arguments))
  end

  defp get_tool_command(_), do: ""

  # Helper function to get prompt for a tool entry.
  # MSF commands use the dynamic console_prompt, bash commands use hardcoded "# ".
  defp get_tool_prompt(%{tool_name: "msf_command"} = entry) do
    entry.console_prompt || ""
  end

  defp get_tool_prompt(%{tool_name: "bash_command"}) do
    "# "
  end

  defp get_tool_prompt(_entry), do: ""

  @doc """
  Returns true if the tool is an MSF data tool (database query/mutation tools).
  """
  @spec msf_data_tool?(String.t()) :: boolean()
  def msf_data_tool?(tool_name) when tool_name in @msf_data_tools, do: true
  def msf_data_tool?(_tool_name), do: false

  @doc """
  Returns the active label for an MSF data tool (e.g., "Listing hosts...").
  """
  @spec msf_data_active_label(String.t()) :: String.t()
  def msf_data_active_label("list_hosts"), do: "Listing hosts..."
  def msf_data_active_label("list_services"), do: "Listing services..."
  def msf_data_active_label("list_vulns"), do: "Listing vulnerabilities..."
  def msf_data_active_label("list_creds"), do: "Listing credentials..."
  def msf_data_active_label("list_loots"), do: "Listing loot..."
  def msf_data_active_label("list_notes"), do: "Listing notes..."
  def msf_data_active_label("list_sessions"), do: "Listing sessions..."
  def msf_data_active_label("retrieve_loot"), do: "Retrieving loot..."
  def msf_data_active_label("create_note"), do: "Creating note..."
  def msf_data_active_label(_tool_name), do: ""

  @doc """
  Formats a timestamp for display in chat entries.

  Shows HH:MM for same-day messages, YYYY-MM-DD HH:MM for older messages.
  """
  attr :timestamp, DateTime, required: true

  def entry_timestamp(assigns) do
    formatted = format_entry_timestamp(assigns.timestamp)
    assigns = assign(assigns, :formatted, formatted)

    ~H"""
    {@formatted}
    """
  end

  defp format_entry_timestamp(%DateTime{} = timestamp) do
    today = Date.utc_today()
    entry_date = DateTime.to_date(timestamp)

    if entry_date == today do
      Calendar.strftime(timestamp, "%H:%M")
    else
      Calendar.strftime(timestamp, "%Y-%m-%d %H:%M")
    end
  end

  @doc """
  Renders the terminal panel simulating msfconsole.

  Displays console history as segments with appropriate styling:
  - Output segments: Plain ANSI-colored text
  - Command lines: Highlighted with different background, command in bold
  - Restart separators: Red divider line indicating console restart

  Shows status footer when console is not ready:
  - :ready - Shows current prompt with cursor
  - :starting - "Console is starting..."
  - :busy - "Running command..."
  - :offline - "The console is currently offline."
  """
  attr :segments, :list, default: []
  attr :console_status, :atom, default: :offline
  attr :current_prompt, :string, default: ""

  def terminal_panel(assigns) do
    ~H"""
    <!-- Terminal Panel -->
    <div class="flex-1 flex flex-col bg-neutral rounded-box border-2 border-base-300 overflow-hidden">
      <!-- Terminal header -->
      <div class="flex items-center justify-between px-3 py-2 bg-neutral-focus border-b border-base-300">
        <div class="flex items-center gap-2">
          <div class="flex gap-1.5">
            <div class="size-3 rounded-full bg-error/80" />
            <div class="size-3 rounded-full bg-warning/80" />
            <div class="size-3 rounded-full bg-success/80" />
          </div>
          <span class="text-xs font-mono text-neutral-content/60 ml-2">msfconsole</span>
        </div>
        <.console_status_badge status={@console_status} />
      </div>
      <!-- Terminal content wrapper (relative for scroll button positioning) -->
      <div class="flex-1 relative overflow-hidden">
        <!-- Terminal content -->
        <div
          id="terminal-scroll-container"
          phx-hook="AutoScroll"
          class="absolute inset-0 overflow-y-auto p-3 font-mono text-sm text-neutral-content"
        >
          <%= if @segments == [] and @console_status == :offline do %>
            <!-- Empty state -->
            <div class="text-neutral-content/50">
              <p>Metasploit Framework Console</p>
              <p class="mt-2">Waiting for console...</p>
            </div>
          <% else %>
            <!-- Console history segments -->
            <%= for segment <- @segments do %>
              <.console_segment segment={segment} />
            <% end %>
            <!-- Current prompt or status footer -->
            <.console_status_footer
              status={@console_status}
              prompt={@current_prompt}
            />
          <% end %>
        </div>
        <!-- Scroll to bottom button (visibility controlled by AutoScroll hook) -->
        <button
          type="button"
          id="terminal-scroll-button"
          phx-update="ignore"
          data-scroll-button
          class="hidden absolute bottom-3 right-3 btn btn-circle btn-sm btn-primary shadow-lg"
          aria-label="Scroll to bottom"
        >
          <.icon name="hero-arrow-down" class="size-4" />
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders a single console segment.
  """
  attr :segment, :any, required: true

  def console_segment(assigns) do
    ~H"""
    <%= case @segment do %>
      <% {:output, text} -> %>
        <div class="whitespace-pre-wrap">{MsfailabWeb.Console.to_html(text)}</div>
      <% {:command_line, prompt, command} -> %>
        <div class="bg-base-content/5 -mx-3 px-3">
          {MsfailabWeb.Console.render_console_command(prompt, command)}
        </div>
      <% :restart_separator -> %>
        <div class="border-t border-error/50 my-2 relative">
          <span class="absolute left-1/2 -translate-x-1/2 -top-2 bg-neutral px-2 text-xs text-error/70">
            console restarted
          </span>
        </div>
    <% end %>
    """
  end

  @doc """
  Renders a status badge in the terminal header.

  Only shown when console is not ready:
  - :starting - Warning badge with spinner
  - :busy - Info badge with spinner
  - :offline - Error badge with warning icon
  - :ready - No badge (empty)
  """
  attr :status, :atom, required: true

  def console_status_badge(assigns) do
    ~H"""
    <%= case @status do %>
      <% :starting -> %>
        <span class="badge badge-info badge-sm gap-1">
          <span class="loading loading-spinner loading-xs" /> Starting...
        </span>
      <% :busy -> %>
        <span class="badge badge-info badge-sm gap-1">
          <span class="loading loading-spinner loading-xs" /> Working...
        </span>
      <% :offline -> %>
        <span class="badge badge-error badge-sm gap-1">
          <.icon name="hero-exclamation-triangle-mini" class="size-3" /> Offline
        </span>
      <% :ready -> %>
        <!-- No badge when ready -->
    <% end %>
    """
  end

  @doc """
  Renders the console status footer based on current status.

  Only shows the prompt with cursor when console is ready.
  Other statuses are displayed in the header badge instead.
  """
  attr :status, :atom, required: true
  attr :prompt, :string, required: true

  def console_status_footer(assigns) do
    ~H"""
    <%= if @status == :ready do %>
      <!-- Show current prompt with cursor -->
      <div>
        {MsfailabWeb.Console.format_prompt(@prompt)}<span class="terminal-cursor"></span>
      </div>
    <% end %>
    """
  end

  @doc """
  Renders the floating input bar at the bottom of the track view.

  The send button is disabled independently per mode:
  - MSF mode: disabled when console_status is not :ready
  - AI mode: disabled when turn_status is :streaming
  """
  attr :input_text, :string, required: true
  attr :input_mode, :string, required: true
  attr :console_status, :atom, required: true
  attr :turn_status, :atom, required: true
  attr :selected_model, :string, required: true
  attr :autonomous_mode, :boolean, required: true
  attr :show_menu, :boolean, required: true
  attr :available_models, :list, default: []

  def input_bar(assigns) do
    # Calculate if send should be disabled based on current mode
    # - MSF mode: disabled when console is not ready
    # - AI mode: disabled when chat is busy (pending, streaming, awaiting approval, executing)
    send_disabled =
      case assigns.input_mode do
        "msf" -> assigns.console_status != :ready
        "ai" -> ChatState.busy?(assigns.turn_status)
        _ -> false
      end

    # Group models by provider for the submenu, sorted by provider priority
    # Models within each group are already sorted descending from Registry.list_models/0
    models_by_provider =
      assigns.available_models
      |> Enum.group_by(& &1.provider)
      |> Enum.sort_by(fn {provider, _} -> provider_sort_order(provider) end)

    assigns =
      assigns
      |> assign(:send_disabled, send_disabled)
      |> assign(:models_by_provider, models_by_provider)

    ~H"""
    <!-- Floating Input Bar -->
    <div class="absolute bottom-0 left-0 right-0 p-4 pointer-events-none">
      <div class="max-w-4xl mx-auto flex items-end gap-2 pointer-events-auto">
        <!-- Mode button with dropup menu -->
        <div class="relative">
          <!-- Dropup menu -->
          <div
            :if={@show_menu}
            class="absolute bottom-full left-0 mb-2 w-56 bg-base-100 rounded-box border-2 border-base-300 shadow-xl z-50"
          >
            <!-- AI Model selector -->
            <div class="group relative">
              <button class="w-full flex items-center justify-between px-4 py-2 hover:bg-base-200 text-sm">
                <span>{model_display_name(@selected_model)}</span>
                <.icon name="hero-chevron-right" class="size-4" />
              </button>
              <!-- Model submenu -->
              <div class="hidden group-hover:block absolute left-full bottom-0 ml-1 w-48 bg-base-100 rounded-box border-2 border-base-300 shadow-xl overflow-hidden max-h-80 overflow-y-auto">
                <%= for {provider, models} <- @models_by_provider do %>
                  <div class="px-3 py-1.5 text-xs font-semibold text-base-content/50 bg-base-200">
                    {provider_display_name(provider)}
                  </div>
                  <.model_option
                    :for={model <- models}
                    model={model.name}
                    selected={@selected_model}
                    label={model.name}
                  />
                <% end %>
              </div>
            </div>
            
    <!-- Autonomous toggle -->
            <label
              class="flex items-center gap-2 px-4 py-2 hover:bg-base-200 cursor-pointer"
              title="The assistant will execute tools without asking for permission"
            >
              <input
                type="checkbox"
                class="checkbox checkbox-sm checkbox-primary"
                checked={@autonomous_mode}
                phx-click="toggle_autonomous"
              />
              <span class="text-sm">Run Autonomous</span>
              <.icon
                :if={@autonomous_mode}
                name="hero-exclamation-triangle"
                class="size-4 text-warning"
              />
            </label>

            <div class="divider my-0" />
            
    <!-- Mode options -->
            <.mode_option
              mode="ai"
              current={@input_mode}
              icon="hero-sparkles"
              label="AI Prompt"
            />
            <.mode_option
              mode="msf"
              current={@input_mode}
              icon="hero-command-line"
              label="Metasploit"
            />
          </div>
          
    <!-- Mode button -->
          <button
            type="button"
            class={[
              "btn btn-square border-2",
              @input_mode == "ai" && "bg-base-100 border-base-300 hover:border-primary",
              @input_mode == "msf" && "bg-neutral text-neutral-content border-neutral"
            ]}
            phx-click="toggle_input_menu"
          >
            <.icon
              name={if @input_mode == "ai", do: "hero-sparkles", else: "hero-command-line"}
              class="size-5"
            />
          </button>
        </div>
        
    <!-- Input form -->
        <form phx-submit="send_input" phx-change="update_input" class="flex-1 flex items-end gap-2">
          <div class={[
            "flex-1 rounded-box border-2",
            @input_mode == "ai" && "bg-base-100 border-base-300 focus-within:border-primary",
            @input_mode == "msf" && "bg-neutral text-neutral-content border-neutral"
          ]}>
            <textarea
              name="input"
              placeholder={input_placeholder(@input_mode)}
              rows="1"
              class={[
                "block w-full bg-transparent px-4 py-2 text-sm resize-none focus:outline-none",
                @input_mode == "msf" && "placeholder-neutral-content/50"
              ]}
              style="max-height: 240px;"
              phx-hook="AutoResizeTextarea"
              id="track-input"
            >{@input_text}</textarea>
          </div>
          
    <!-- Send button -->
          <button
            type="submit"
            class={["btn btn-square", (@send_disabled && "btn-disabled") || "btn-primary"]}
            disabled={@send_disabled}
          >
            <.icon name="hero-paper-airplane" class="size-5" />
          </button>
        </form>
      </div>
    </div>
    """
  end

  defp input_placeholder("ai"), do: "Ask the AI assistant... (Ctrl+M to switch to Metasploit)"
  defp input_placeholder("msf"), do: "Enter Metasploit command... (Ctrl+M to switch to AI)"
  defp input_placeholder(_), do: "Type a message..."

  defp model_display_name(model), do: model

  defp provider_display_name(:ollama), do: "Ollama"
  defp provider_display_name(:openai), do: "OpenAI"
  defp provider_display_name(:anthropic), do: "Anthropic"
  defp provider_display_name(provider), do: provider |> to_string() |> String.capitalize()

  defp provider_sort_order(:anthropic), do: 0
  defp provider_sort_order(:openai), do: 1
  defp provider_sort_order(:ollama), do: 2
  defp provider_sort_order(_), do: 3

  @doc """
  Renders a model option in the dropdown.
  """
  attr :model, :string, required: true
  attr :selected, :string, required: true
  attr :label, :string, required: true

  def model_option(assigns) do
    ~H"""
    <button
      type="button"
      class={[
        "w-full flex items-center gap-2 px-4 py-2 text-sm text-left hover:bg-base-200",
        @model == @selected && "bg-primary/10 text-primary"
      ]}
      phx-click="select_model"
      phx-value-model={@model}
    >
      <.icon
        name={if @model == @selected, do: "hero-check-circle-solid", else: "hero-circle"}
        class="size-4"
      />
      <span>{@label}</span>
    </button>
    """
  end

  @doc """
  Renders a model select dropdown for forms.

  Groups models by provider and pre-selects the specified model.

  ## Examples

      <.model_select
        field={@form[:current_model]}
        models={@available_models}
      />
  """
  attr :field, Phoenix.HTML.FormField, required: true
  attr :models, :list, required: true

  def model_select(assigns) do
    # Group models by provider for optgroups
    models_by_provider =
      assigns.models
      |> Enum.group_by(& &1.provider)
      |> Enum.sort_by(fn {provider, _} -> provider_sort_order(provider) end)

    assigns =
      assigns
      |> assign(:models_by_provider, models_by_provider)
      |> assign(:name, assigns.field.name)
      |> assign(:value, assigns.field.value || "")
      |> assign(:id, assigns.field.id)

    ~H"""
    <div class="form-control w-full">
      <label class="label" for={@id}>
        <span class="label-text font-medium">AI Model</span>
      </label>
      <select
        id={@id}
        name={@name}
        class="select select-bordered w-full bg-base-100 border-2 border-base-300 focus:border-primary focus:outline-none"
      >
        <%= for {provider, models} <- @models_by_provider do %>
          <optgroup label={provider_display_name(provider)}>
            <%= for model <- models do %>
              <option value={model.name} selected={model.name == @value}>
                {model.name}
              </option>
            <% end %>
          </optgroup>
        <% end %>
      </select>
      <label class="label">
        <span class="label-text-alt text-base-content/60">
          Select the AI model for this track's research assistant
        </span>
      </label>
    </div>
    """
  end

  @doc """
  Renders a mode option in the dropdown.
  """
  attr :mode, :string, required: true
  attr :current, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true

  def mode_option(assigns) do
    ~H"""
    <button
      type="button"
      class={[
        "w-full flex items-center gap-2 px-4 py-2 text-sm text-left hover:bg-base-200",
        @mode == @current && "bg-primary/10 text-primary"
      ]}
      phx-click="select_input_mode"
      phx-value-mode={@mode}
    >
      <.icon name={@icon} class={["size-4", @mode == @current && "text-primary"]} />
      <span>{@label}</span>
    </button>
    """
  end

  # ===========================================================================
  # Form Components
  # ===========================================================================

  @doc """
  Renders a form field with label, input, optional helper text, and error display.

  Uses daisyUI form styling conventions. Accepts either a Phoenix form field
  or manual name/value attributes.

  ## Examples

      # With Phoenix form field
      <.form_field
        label="Workspace Name"
        field={@form[:name]}
        placeholder="Enter workspace name"
      />

      # With manual attributes
      <.form_field
        label="Workspace Name"
        name="name"
        value={@name}
        placeholder="Enter workspace name"
        phx-keyup="update_name"
      />
  """
  attr :label, :string, required: true
  attr :field, Phoenix.HTML.FormField, default: nil
  attr :name, :string, default: nil
  attr :value, :string, default: ""
  attr :placeholder, :string, default: ""
  attr :helper, :string, default: nil
  attr :type, :string, default: "text"
  attr :readonly, :boolean, default: false

  attr :rest, :global,
    include: ~w(phx-keyup phx-change phx-blur phx-focus autofocus phx-value-field)

  def form_field(assigns) do
    # Extract name, value, and errors from field if provided
    assigns =
      if assigns.field do
        assigns
        |> assign(:name, assigns.field.name)
        |> assign(:value, assigns.field.value || "")
        |> assign(:errors, Enum.map(assigns.field.errors, &translate_error/1))
        |> assign(:id, assigns.field.id)
      else
        assigns
        |> assign(:errors, [])
        |> assign_new(:id, fn -> assigns.name end)
      end

    ~H"""
    <!-- Form field with label -->
    <div class="form-control w-full">
      <label class="label" for={@id}>
        <span class="label-text font-medium">{@label}</span>
      </label>
      <input
        type={@type}
        id={@id}
        name={@name}
        value={@value}
        placeholder={@placeholder}
        readonly={@readonly}
        class={[
          "input input-bordered w-full bg-base-100 border-2",
          @errors == [] && "border-base-300 focus:border-primary",
          @errors != [] && "border-error focus:border-error",
          "focus:outline-none",
          @readonly && "bg-base-200 cursor-not-allowed"
        ]}
        {@rest}
      />
      <label :if={@helper && @errors == []} class="label">
        <span class="label-text-alt text-base-content/60">{@helper}</span>
      </label>
      <label :for={error <- @errors} class="label py-1">
        <span class="label-text-alt text-error break-words whitespace-normal">{error}</span>
      </label>
    </div>
    """
  end

  @doc """
  Renders a textarea form field with optional error display.

  ## Examples

      # With Phoenix form field
      <.textarea_field
        label="Description"
        field={@form[:description]}
        placeholder="Enter description"
      />

      # With manual attributes
      <.textarea_field
        label="Description"
        name="description"
        value={@description}
        placeholder="Enter description"
      />
  """
  attr :label, :string, required: true
  attr :field, Phoenix.HTML.FormField, default: nil
  attr :name, :string, default: nil
  attr :value, :string, default: ""
  attr :placeholder, :string, default: ""
  attr :rows, :integer, default: 3
  attr :rest, :global, include: ~w(phx-keyup phx-change phx-blur)

  def textarea_field(assigns) do
    # Extract name, value, and errors from field if provided
    assigns =
      if assigns.field do
        assigns
        |> assign(:name, assigns.field.name)
        |> assign(:value, assigns.field.value || "")
        |> assign(:errors, Enum.map(assigns.field.errors, &translate_error/1))
        |> assign(:id, assigns.field.id)
      else
        assigns
        |> assign(:errors, [])
        |> assign_new(:id, fn -> assigns.name end)
      end

    ~H"""
    <!-- Textarea form field -->
    <div class="form-control w-full">
      <label class="label" for={@id}>
        <span class="label-text font-medium">{@label}</span>
      </label>
      <textarea
        id={@id}
        name={@name}
        placeholder={@placeholder}
        rows={@rows}
        class={[
          "textarea textarea-bordered w-full bg-base-100 border-2",
          @errors == [] && "border-base-300 focus:border-primary",
          @errors != [] && "border-error focus:border-error",
          "focus:outline-none"
        ]}
        {@rest}
      >{@value}</textarea>
      <label :for={error <- @errors} class="label py-1">
        <span class="label-text-alt text-error break-words whitespace-normal">{error}</span>
      </label>
    </div>
    """
  end

  # coveralls-ignore-stop

  # Translates an error tuple to a human-readable string
  defp translate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", fn _ -> to_string(value) end)
    end)
  end
end
