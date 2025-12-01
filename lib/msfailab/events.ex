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

  ## Event Categories

  Events are divided into two distinct categories based on what they represent:

  ### Entity Events

  Represent changes to domain model entities (CRUD operations, metadata changes).
  These events are broadcast by **context modules** (Containers, Tracks) and
  represent "what exists" and its properties.

  - **Source of truth**: Database
  - **Broadcast by**: Context modules
  - **Used for**: Header menus, navigation, entity listings
  - **Events**: ContainerCreated, ContainerUpdated, TrackCreated, TrackUpdated

  ### State Events

  Represent changes to runtime session state within entities. These events are
  broadcast by **GenServers** (Container, TrackServer) and represent "what's
  happening" within those entities.

  - **Source of truth**: GenServer (cached in memory, persisted to DB)
  - **Broadcast by**: GenServers
  - **Used for**: Terminal pane, chat pane, activity indicators
  - **Events**: TrackStateUpdated, CommandIssued, CommandResult

  The key distinction:
  - **Entity events**: "A track was created/renamed/archived"
  - **State events**: "Something happened in this track's session"

  ## Self-Healing Event Pattern

  All events in this system follow a **self-healing pattern**: subsequent events
  in an event chain carry all information from previous events plus additional
  fields. This enables state reconstruction if earlier events are missed.

  ### Event Chains

  **Container Events (Entity):**
  - `ContainerCreated` (base): id, slug, name, docker_image
  - `ContainerUpdated` (extends): + status, reason

  **Track Events (Entity):**
  - `TrackCreated` (base): id, slug, name, container_id
  - `TrackUpdated` (extends): + archived_at

  **Command Events (State):**
  - `CommandIssued` (base): id, type, command
  - `CommandResult` (extends): + output, status, exit_code, error

  **Track State Events (State):**
  - `TrackStateUpdated` - Notification only, query TrackServer for full state

  ### Example: Self-Healing in Action

  If a subscriber joins mid-session and misses `ContainerCreated`, the next
  `ContainerUpdated` event contains all entity fields (slug, name, docker_image),
  allowing the subscriber to reconstruct the container's existence and current state.

  Similarly, if `CommandIssued` is missed, `CommandResult` includes the command
  type and text, so the subscriber can still display meaningful output.

  ### Design Principle

  When adding new events, ensure:
  1. Subsequent events include ALL fields from previous events in the chain
  2. Each event can independently describe the entity's current state
  3. Field names remain consistent across the event chain

  ## Topics

  - `workspace:<workspace_id>` - All events for a workspace (containers, tracks, commands)

  ## Event Types

  ### Entity Events (from context modules)
  - `Msfailab.Events.ContainerCreated` - New container created
  - `Msfailab.Events.ContainerUpdated` - Container updated or status changed
  - `Msfailab.Events.TrackCreated` - New track created
  - `Msfailab.Events.TrackUpdated` - Track updated or archived

  ### State Events (from GenServers)
  - `Msfailab.Events.TrackStateUpdated` - Track session state changed (query for full state)
  - `Msfailab.Events.CommandIssued` - Command submitted for execution
  - `Msfailab.Events.CommandResult` - Command execution result (running/finished/error)

  ## Event Context

  All events include full context for routing and filtering:
  - `workspace_id` - Used for PubSub topic routing
  - `container_id` - Identifies the container
  - `track_id` - Identifies the track (for track and command events)

  ## Usage

      # Broadcasting (from contexts and GenServers)
      Events.broadcast(ContainerCreated.new(container))
      Events.broadcast(ContainerUpdated.new(container, :running))

      # Subscribing (from LiveViews)
      Events.subscribe_to_workspace(workspace_id)

      # Handling (in LiveView handle_info)
      def handle_info(%Events.ContainerCreated{} = event, socket) do
        # Add container to menu
      end

      def handle_info(%Events.ContainerUpdated{} = event, socket) do
        # Update container status indicator
      end

      def handle_info(%Events.TrackCreated{} = event, socket) do
        # Add track to menu
      end

      def handle_info(%Events.CommandResult{} = event, socket) do
        # Display command output
      end
  """

  alias Msfailab.Events.ChatStateUpdated
  alias Msfailab.Events.CommandIssued
  alias Msfailab.Events.CommandResult
  alias Msfailab.Events.ConsoleUpdated
  alias Msfailab.Events.ContainerCreated
  alias Msfailab.Events.ContainerUpdated
  alias Msfailab.Events.TrackCreated
  alias Msfailab.Events.TrackStateUpdated
  alias Msfailab.Events.TrackUpdated
  alias Msfailab.Trace

  @pubsub Msfailab.PubSub

  # Topic builders

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

  The topic is derived from the event's workspace_id field.
  All events must include a workspace_id to enable routing.
  """
  @spec broadcast(struct()) :: :ok | {:error, term()}
  def broadcast(%ContainerCreated{workspace_id: workspace_id} = event) do
    Trace.event(event)
    Phoenix.PubSub.broadcast(@pubsub, workspace_topic(workspace_id), event)
  end

  def broadcast(%ContainerUpdated{workspace_id: workspace_id} = event) do
    Trace.event(event)
    Phoenix.PubSub.broadcast(@pubsub, workspace_topic(workspace_id), event)
  end

  def broadcast(%TrackCreated{workspace_id: workspace_id} = event) do
    Trace.event(event)
    Phoenix.PubSub.broadcast(@pubsub, workspace_topic(workspace_id), event)
  end

  def broadcast(%TrackUpdated{workspace_id: workspace_id} = event) do
    Trace.event(event)
    Phoenix.PubSub.broadcast(@pubsub, workspace_topic(workspace_id), event)
  end

  def broadcast(%TrackStateUpdated{workspace_id: workspace_id} = event) do
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

  def broadcast(%ChatStateUpdated{workspace_id: workspace_id} = event) do
    Trace.event(event)
    Phoenix.PubSub.broadcast(@pubsub, workspace_topic(workspace_id), event)
  end

  @doc """
  Broadcast an event locally (only to subscribers on this node).

  Useful for testing or when cross-node distribution isn't needed.
  """
  @spec broadcast_local(struct()) :: :ok | {:error, term()}
  def broadcast_local(%ContainerCreated{workspace_id: workspace_id} = event) do
    Trace.event(event)
    Phoenix.PubSub.local_broadcast(@pubsub, workspace_topic(workspace_id), event)
  end

  def broadcast_local(%ContainerUpdated{workspace_id: workspace_id} = event) do
    Trace.event(event)
    Phoenix.PubSub.local_broadcast(@pubsub, workspace_topic(workspace_id), event)
  end

  def broadcast_local(%TrackCreated{workspace_id: workspace_id} = event) do
    Trace.event(event)
    Phoenix.PubSub.local_broadcast(@pubsub, workspace_topic(workspace_id), event)
  end

  def broadcast_local(%TrackUpdated{workspace_id: workspace_id} = event) do
    Trace.event(event)
    Phoenix.PubSub.local_broadcast(@pubsub, workspace_topic(workspace_id), event)
  end

  def broadcast_local(%TrackStateUpdated{workspace_id: workspace_id} = event) do
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

  def broadcast_local(%ChatStateUpdated{workspace_id: workspace_id} = event) do
    Trace.event(event)
    Phoenix.PubSub.local_broadcast(@pubsub, workspace_topic(workspace_id), event)
  end
end
