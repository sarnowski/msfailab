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

defmodule Msfailab.Events do
  @moduledoc """
  Central catalog and dispatcher for all application events.

  This module provides a structured approach to PubSub events, ensuring:
  - All events are well-defined structs with clear semantics
  - Topics are derived from events, not scattered as string literals
  - Subscription helpers make it easy to listen to relevant events

  ## Event Philosophy: Lightweight Notifications

  All events in this system are **lightweight notifications**. They signal that
  something changed, but do NOT carry the full state payload. The UI should
  always fetch fresh state from the appropriate context after receiving an event.

  This "notification + fetch" pattern:

  - **Eliminates accumulation bugs** - No race conditions from appending/updating
    local state while the database also changes (e.g., via `push_patch` reload)
  - **Ensures consistency** - UI always gets complete, coherent state from the
    single source of truth (database or GenServer)
  - **Handles missed events** - If a subscriber misses an event, the next one
    still triggers a full refresh
  - **Keeps events minimal** - Only identifiers needed to know what to refresh
  - **Simplifies LiveView handlers** - No transformation logic, just fetch and assign

  ## Event-to-UI Region Mapping

  Each UI notification event corresponds to a specific region that should re-render:

  | Event | Topic | UI Region | Data Source |
  |-------|-------|-----------|-------------|
  | `WorkspacesChanged` | `application` | Workspace list (home, selector) | `Workspaces.list_workspaces/0` |
  | `WorkspaceChanged` | `workspace:<id>` | Header menu (containers, tracks) | `Containers.list_containers_with_tracks/1` |
  | `ConsoleChanged` | `workspace:<id>` | Terminal pane | `Tracks.get_console_state/1` |
  | `ChatChanged` | `workspace:<id>` | AI chat pane | `Tracks.get_chat_state/1` |

  ## When to Broadcast Each Event

  ### WorkspacesChanged

  Broadcast when the **list** of workspaces changes:
  - Workspace created
  - Workspace renamed (slug/name change)
  - Workspace deleted

  ### WorkspaceChanged

  Broadcast when **entities within** a workspace change:
  - Container created or updated (name, status)
  - Track created, renamed, or archived
  - Any change affecting the header menu structure

  ### ConsoleChanged

  Broadcast when the **terminal pane** needs to update:
  - Console status changed (offline → starting → ready)
  - Command output received
  - History block completed

  ### ChatChanged

  Broadcast when the **AI chat pane** needs to update:
  - New chat entry added
  - Streaming content updated
  - Tool invocation status changed

  ## Command Events (Activity Indicators)

  These events are for real-time activity feedback, not UI region refreshes:

  - `CommandIssued` - Command submitted (show "executing" indicator)
  - `CommandResult` - Command completed (show result, clear indicator)
  - `ConsoleUpdated` - Raw console output (internal, triggers ConsoleChanged)

  ## Topics

  - `application` - Application-wide events (WorkspacesChanged only)
  - `workspace:<workspace_id>` - All events scoped to a specific workspace

  ## Complete LiveView Integration Example

      defmodule MyAppWeb.WorkspaceLive do
        use Phoenix.LiveView

        alias MyApp.Containers
        alias MyApp.Events
        alias MyApp.Events.{WorkspaceChanged, ConsoleChanged, ChatChanged}
        alias MyApp.Tracks

        def mount(_params, _session, socket) do
          if connected?(socket) do
            Events.subscribe_to_workspace(socket.assigns.workspace.id)
          end
          {:ok, socket}
        end

        # WorkspaceChanged: refresh header menu (containers + tracks)
        def handle_info(%WorkspaceChanged{}, socket) do
          containers = Containers.list_containers_with_tracks(socket.assigns.workspace)
          {:noreply, assign(socket, :containers, containers)}
        end

        # ConsoleChanged: refresh terminal pane (only if viewing this track)
        def handle_info(%ConsoleChanged{track_id: track_id}, socket) do
          if socket.assigns.current_track?.id == track_id do
            {status, prompt, segments} = Tracks.get_console_state(track_id)
            socket =
              socket
              |> assign(:console_status, status)
              |> assign(:current_prompt, prompt)
              |> assign(:console_segments, segments)
            {:noreply, socket}
          else
            {:noreply, socket}
          end
        end

        # ChatChanged: refresh chat pane (only if viewing this track)
        def handle_info(%ChatChanged{track_id: track_id}, socket) do
          if socket.assigns.current_track?.id == track_id do
            {:ok, chat_state} = Tracks.get_chat_state(track_id)
            {:noreply, assign(socket, :chat_state, chat_state)}
          else
            {:noreply, socket}
          end
        end
      end

  ## Anti-Pattern: Payload Accumulation

  **Do NOT** carry full entity data in events and accumulate it in the UI:

      # ❌ BAD: Event carries payload, UI accumulates
      def handle_info(%TrackCreated{} = event, socket) do
        new_track = %Track{id: event.track_id, name: event.name, ...}
        containers = update_in(socket.assigns.containers, ...)
        {:noreply, assign(socket, :containers, containers)}
      end

  This pattern causes bugs when:
  - `push_patch` triggers `handle_params` which reloads from database
  - Multiple events arrive for the same entity
  - Events are missed and state diverges

  **Instead**, use lightweight notifications:

      # ✅ GOOD: Event notifies, UI fetches fresh state
      def handle_info(%WorkspaceChanged{}, socket) do
        containers = Containers.list_containers_with_tracks(socket.assigns.workspace)
        {:noreply, assign(socket, :containers, containers)}
      end

  ## Broadcasting Events

      # From context modules (e.g., Tracks.create_track/2)
      def create_track(container, attrs) do
        with {:ok, track} <- Repo.insert(changeset) do
          Events.broadcast(WorkspaceChanged.new(container.workspace_id))
          {:ok, track}
        end
      end

      # From GenServers (e.g., TrackServer after console update)
      def handle_info(%ConsoleUpdated{} = event, state) do
        new_state = process_console_update(state, event)
        Events.broadcast(ConsoleChanged.new(state.workspace_id, state.track_id))
        {:noreply, new_state}
      end
  """

  alias Msfailab.Events.ChatChanged
  alias Msfailab.Events.CommandIssued
  alias Msfailab.Events.CommandResult
  alias Msfailab.Events.ConsoleChanged
  alias Msfailab.Events.ConsoleUpdated
  alias Msfailab.Events.WorkspaceChanged
  alias Msfailab.Events.WorkspacesChanged
  alias Msfailab.Trace

  @pubsub Msfailab.PubSub
  @application_topic "application"

  # Topic builders

  @doc """
  Returns the PubSub topic for application-wide events.

  Events like WorkspacesChanged are broadcast to this topic.
  """
  @spec application_topic() :: String.t()
  def application_topic, do: @application_topic

  @doc """
  Returns the PubSub topic for a workspace.

  All container, track, and command events for this workspace
  are broadcast to this topic.
  """
  @spec workspace_topic(integer()) :: String.t()
  def workspace_topic(workspace_id) when is_integer(workspace_id) do
    "workspace:#{workspace_id}"
  end

  # Subscription functions

  @doc """
  Subscribe the current process to application-wide events.

  This includes workspace list changes (create, rename, delete).
  """
  @spec subscribe_to_application() :: :ok | {:error, term()}
  def subscribe_to_application do
    Phoenix.PubSub.subscribe(@pubsub, @application_topic)
  end

  @doc """
  Unsubscribe the current process from application-wide events.
  """
  @spec unsubscribe_from_application() :: :ok
  def unsubscribe_from_application do
    Phoenix.PubSub.unsubscribe(@pubsub, @application_topic)
  end

  @doc """
  Subscribe the current process to all events for a workspace.

  This includes container lifecycle, track changes, and command events
  for all tracks within the workspace.
  """
  @spec subscribe_to_workspace(integer()) :: :ok | {:error, term()}
  def subscribe_to_workspace(workspace_id) when is_integer(workspace_id) do
    Phoenix.PubSub.subscribe(@pubsub, workspace_topic(workspace_id))
  end

  @doc """
  Unsubscribe the current process from workspace events.
  """
  @spec unsubscribe_from_workspace(integer()) :: :ok
  def unsubscribe_from_workspace(workspace_id) when is_integer(workspace_id) do
    Phoenix.PubSub.unsubscribe(@pubsub, workspace_topic(workspace_id))
  end

  # Broadcast functions - pattern match on event types

  @doc """
  Broadcast an event to its appropriate topic.

  The topic is derived from the event type:
  - WorkspacesChanged -> application topic
  - All others -> workspace topic (from workspace_id field)
  """
  @spec broadcast(struct()) :: :ok | {:error, term()}
  def broadcast(%WorkspacesChanged{} = event) do
    Trace.event(event)
    Phoenix.PubSub.broadcast(@pubsub, @application_topic, event)
  end

  def broadcast(%WorkspaceChanged{workspace_id: workspace_id} = event) do
    Trace.event(event)
    Phoenix.PubSub.broadcast(@pubsub, workspace_topic(workspace_id), event)
  end

  def broadcast(%ConsoleChanged{workspace_id: workspace_id} = event) do
    Trace.event(event)
    Phoenix.PubSub.broadcast(@pubsub, workspace_topic(workspace_id), event)
  end

  def broadcast(%ChatChanged{workspace_id: workspace_id} = event) do
    Trace.event(event)
    Phoenix.PubSub.broadcast(@pubsub, workspace_topic(workspace_id), event)
  end

  def broadcast(%CommandIssued{workspace_id: workspace_id} = event) do
    Trace.event(event)
    Phoenix.PubSub.broadcast(@pubsub, workspace_topic(workspace_id), event)
  end

  def broadcast(%CommandResult{workspace_id: workspace_id} = event) do
    Trace.event(event)
    Phoenix.PubSub.broadcast(@pubsub, workspace_topic(workspace_id), event)
  end

  def broadcast(%ConsoleUpdated{workspace_id: workspace_id} = event) do
    Trace.event(event)
    Phoenix.PubSub.broadcast(@pubsub, workspace_topic(workspace_id), event)
  end

  @doc """
  Broadcast an event locally (only to subscribers on this node).

  Useful for testing or when cross-node distribution isn't needed.
  """
  @spec broadcast_local(struct()) :: :ok | {:error, term()}
  def broadcast_local(%WorkspacesChanged{} = event) do
    Trace.event(event)
    Phoenix.PubSub.local_broadcast(@pubsub, @application_topic, event)
  end

  def broadcast_local(%WorkspaceChanged{workspace_id: workspace_id} = event) do
    Trace.event(event)
    Phoenix.PubSub.local_broadcast(@pubsub, workspace_topic(workspace_id), event)
  end

  def broadcast_local(%ConsoleChanged{workspace_id: workspace_id} = event) do
    Trace.event(event)
    Phoenix.PubSub.local_broadcast(@pubsub, workspace_topic(workspace_id), event)
  end

  def broadcast_local(%ChatChanged{workspace_id: workspace_id} = event) do
    Trace.event(event)
    Phoenix.PubSub.local_broadcast(@pubsub, workspace_topic(workspace_id), event)
  end

  def broadcast_local(%CommandIssued{workspace_id: workspace_id} = event) do
    Trace.event(event)
    Phoenix.PubSub.local_broadcast(@pubsub, workspace_topic(workspace_id), event)
  end

  def broadcast_local(%CommandResult{workspace_id: workspace_id} = event) do
    Trace.event(event)
    Phoenix.PubSub.local_broadcast(@pubsub, workspace_topic(workspace_id), event)
  end

  def broadcast_local(%ConsoleUpdated{workspace_id: workspace_id} = event) do
    Trace.event(event)
    Phoenix.PubSub.local_broadcast(@pubsub, workspace_topic(workspace_id), event)
  end
end
