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

defmodule Msfailab.Tracks do
  @moduledoc """
  Context module for managing tracks.

  Tracks are active research sessions within containers, each with its own
  dedicated Metasploit console session and AI assistant. Multiple tracks
  can share the same container, collaborating on the same engagement while
  maintaining independent console contexts.

  ## Track Lifecycle

  When a track is created:
  1. The track database record is created
  2. The container GenServer is started if not already running

  Console sessions are created on-demand when the first command is sent
  for a track, not when the track is created.

  When a track is archived:
  1. Any existing console session is closed (if container is running)
  2. If no more active tracks exist for the container, the Container GenServer stops

  ## Relationships

  - Tracks belong to Containers (which provide the Docker environment)
  - Workspace is accessed via Container: Track -> Container -> Workspace
  """
  import Ecto.Query

  alias Msfailab.Containers
  alias Msfailab.Containers.ContainerRecord
  alias Msfailab.Events
  alias Msfailab.Events.WorkspaceChanged
  alias Msfailab.Repo
  alias Msfailab.Tracks.ChatContext
  alias Msfailab.Tracks.ChatState
  alias Msfailab.Tracks.ConsoleHistoryBlock
  alias Msfailab.Tracks.Track
  alias Msfailab.Tracks.TrackServer
  alias Msfailab.Workspaces.Workspace

  # ============================================================================
  # Query Functions
  # ============================================================================

  @doc """
  Returns all active (non-archived) tracks for a workspace.

  Accepts either a `%Workspace{}` struct or a workspace ID (integer).
  Joins through containers to find tracks in the workspace.
  """
  @spec list_tracks(Workspace.t() | integer()) :: [Track.t()]
  def list_tracks(workspace_or_id)

  def list_tracks(%Workspace{} = workspace) do
    list_tracks(workspace.id)
  end

  def list_tracks(workspace_id) when is_integer(workspace_id) do
    Track
    |> join(:inner, [t], c in assoc(t, :container))
    |> where([t, c], c.workspace_id == ^workspace_id and is_nil(t.archived_at))
    |> order_by([t], asc: t.name)
    |> Repo.all()
  end

  @doc """
  Returns all active (non-archived) tracks for a container.

  Accepts either a `%ContainerRecord{}` struct or a container ID (integer).
  """
  @spec list_tracks_by_container(ContainerRecord.t() | integer()) :: [Track.t()]
  def list_tracks_by_container(container_or_id)

  def list_tracks_by_container(%ContainerRecord{} = container) do
    list_tracks_by_container(container.id)
  end

  def list_tracks_by_container(container_id) when is_integer(container_id) do
    Track
    |> where([t], t.container_id == ^container_id and is_nil(t.archived_at))
    |> order_by([t], asc: t.name)
    |> Repo.all()
  end

  @doc """
  Returns all tracks for a workspace including archived ones.
  """
  @spec list_all_tracks(Workspace.t()) :: [Track.t()]
  def list_all_tracks(%Workspace{} = workspace) do
    Track
    |> join(:inner, [t], c in assoc(t, :container))
    |> where([t, c], c.workspace_id == ^workspace.id)
    |> order_by([t], asc: t.name)
    |> Repo.all()
  end

  @doc """
  Gets a track by ID.

  Returns `nil` if the track does not exist.
  """
  @spec get_track(integer()) :: Track.t() | nil
  def get_track(id), do: Repo.get(Track, id)

  @doc """
  Gets a track by ID.

  Raises `Ecto.NoResultsError` if the track does not exist.
  """
  @spec get_track!(integer()) :: Track.t()
  def get_track!(id), do: Repo.get!(Track, id)

  @doc """
  Gets a track by ID with container and workspace preloaded.

  Returns `nil` if the track does not exist.
  """
  @spec get_track_with_context(integer()) :: Track.t() | nil
  def get_track_with_context(id) do
    Track
    |> where([t], t.id == ^id)
    |> preload(container: :workspace)
    |> Repo.one()
  end

  @doc """
  Gets an active track by workspace and slug.

  Accepts either a `%Workspace{}` struct or a workspace ID (integer).
  Returns `nil` if the track does not exist or is archived.

  Note: This finds a track within a workspace by looking through all
  containers in that workspace. If you know the container, use
  `get_track_by_container_and_slug/2` instead for better performance.
  """
  @spec get_track_by_slug(Workspace.t() | integer(), String.t()) :: Track.t() | nil
  def get_track_by_slug(workspace_or_id, slug)

  def get_track_by_slug(%Workspace{} = workspace, slug) do
    get_track_by_slug(workspace.id, slug)
  end

  def get_track_by_slug(workspace_id, slug) when is_integer(workspace_id) do
    Track
    |> join(:inner, [t], c in assoc(t, :container))
    |> where(
      [t, c],
      c.workspace_id == ^workspace_id and t.slug == ^slug and is_nil(t.archived_at)
    )
    |> Repo.one()
  end

  @doc """
  Gets an active track by container and slug.

  Accepts either a `%ContainerRecord{}` struct or a container ID (integer).
  Returns `nil` if the track does not exist or is archived.
  """
  @spec get_track_by_container_and_slug(ContainerRecord.t() | integer(), String.t()) ::
          Track.t() | nil
  def get_track_by_container_and_slug(container_or_id, slug)

  def get_track_by_container_and_slug(%ContainerRecord{} = container, slug) do
    get_track_by_container_and_slug(container.id, slug)
  end

  def get_track_by_container_and_slug(container_id, slug) when is_integer(container_id) do
    Track
    |> where([t], t.container_id == ^container_id and t.slug == ^slug and is_nil(t.archived_at))
    |> Repo.one()
  end

  @doc """
  Checks if a track slug is already taken within a container.

  Returns `true` if the slug exists, `false` otherwise.
  """
  @spec slug_exists?(ContainerRecord.t() | integer(), String.t()) :: boolean()
  def slug_exists?(container_or_id, slug)

  def slug_exists?(%ContainerRecord{} = container, slug), do: slug_exists?(container.id, slug)

  def slug_exists?(container_id, slug)
      when is_integer(container_id) and is_binary(slug) and slug != "" do
    Track
    |> where([t], t.container_id == ^container_id and t.slug == ^slug)
    |> Repo.exists?()
  end

  def slug_exists?(_, _), do: false

  # ============================================================================
  # Create/Update/Archive Operations
  # ============================================================================

  @doc """
  Creates a new track within a container.

  Accepts either a `%ContainerRecord{}` struct with attrs, or just attrs containing
  a `:container_id` key.

  After successful creation, ensures the Container GenServer is running.
  Console sessions are created on-demand when commands are sent.
  """
  @spec create_track(ContainerRecord.t() | map(), map() | nil) ::
          {:ok, Track.t()} | {:error, Ecto.Changeset.t()}
  def create_track(container_or_attrs, attrs \\ nil)

  def create_track(%ContainerRecord{} = container, attrs) do
    changeset =
      %Track{container_id: container.id}
      |> Track.create_changeset(attrs)

    with {:ok, track} <- Repo.insert(changeset) do
      # Need container with workspace_id for events and container startup
      container_with_workspace = Repo.preload(container, :workspace)
      track_with_context = %{track | container: container_with_workspace}

      Events.broadcast(WorkspaceChanged.new(container_with_workspace.workspace_id))
      maybe_start_container(track_with_context)
      maybe_start_track_server(track_with_context)
      {:ok, track}
    end
  end

  def create_track(attrs, nil) when is_map(attrs) do
    changeset =
      %Track{}
      |> Track.create_changeset(attrs)

    with {:ok, track} <- Repo.insert(changeset) do
      # Preload container and workspace for events and startup
      track_with_context = Repo.preload(track, container: :workspace)

      Events.broadcast(WorkspaceChanged.new(track_with_context.container.workspace_id))
      maybe_start_container(track_with_context)
      maybe_start_track_server(track_with_context)
      {:ok, track}
    end
  end

  @doc """
  Updates an existing track.
  """
  @spec update_track(Track.t(), map()) :: {:ok, Track.t()} | {:error, Ecto.Changeset.t()}
  def update_track(%Track{} = track, attrs) do
    with {:ok, updated_track} <- track |> Track.update_changeset(attrs) |> Repo.update() do
      # Preload container with workspace for event
      track_with_context = Repo.preload(updated_track, container: :workspace)
      Events.broadcast(WorkspaceChanged.new(track_with_context.container.workspace_id))
      {:ok, updated_track}
    end
  end

  @doc """
  Archives a track.

  Archived tracks are not listed by default and cannot be accessed via slug.
  After successful archival, closes any console session for this track and,
  if no more active tracks exist for the container, stops the Container GenServer.
  """
  @spec archive_track(Track.t()) :: {:ok, Track.t()} | {:error, Ecto.Changeset.t()}
  def archive_track(%Track{} = track) do
    with {:ok, archived_track} <- track |> Track.archive_changeset() |> Repo.update() do
      # Preload container with workspace for event
      track_with_context = Repo.preload(archived_track, container: :workspace)
      Events.broadcast(WorkspaceChanged.new(track_with_context.container.workspace_id))

      # Stop the TrackServer for this track (which unregisters the console)
      stop_track_server(archived_track.id)

      # Check if this was the last active track for the container
      maybe_stop_container(archived_track.container_id)

      {:ok, archived_track}
    end
  end

  @doc """
  Returns a changeset for tracking track changes.
  """
  @spec change_track(Track.t(), map()) :: Ecto.Changeset.t()
  def change_track(%Track{} = track, attrs \\ %{}) do
    Track.create_changeset(track, attrs)
  end

  # ============================================================================
  # TrackServer Management
  # ============================================================================

  @doc """
  Starts a TrackServer GenServer for a track.

  Called when a track is created. The track must have its container association
  preloaded to get the workspace_id.

  Returns `{:ok, pid}` on success or `{:error, reason}` on failure.
  """
  @spec start_track_server(Track.t()) :: {:ok, pid()} | {:error, term()}
  def start_track_server(%Track{} = track) do
    opts = [
      track_id: track.id,
      workspace_id: track.container.workspace_id,
      container_id: track.container_id
    ]

    DynamicSupervisor.start_child(
      Msfailab.Tracks.TrackSupervisor,
      {TrackServer, opts}
    )
  end

  @doc """
  Stops a TrackServer GenServer.

  Called when a track is archived. Uses GenServer.stop to allow the process
  to clean up gracefully.

  Returns `:ok` on success or `{:error, :not_found}` if no TrackServer exists.
  """
  @spec stop_track_server(integer()) :: :ok | {:error, :not_found}
  def stop_track_server(track_id) do
    # Only stop track server if the registry is running
    # (it's disabled in test mode for most tests)
    case Process.whereis(Msfailab.Tracks.Registry) do
      nil ->
        # Registry not running, nothing to stop
        :ok

      _registry_pid ->
        case TrackServer.whereis(track_id) do
          nil ->
            {:error, :not_found}

          pid ->
            GenServer.stop(pid, :normal)
            :ok
        end
    end
  end

  @doc """
  Gets the console history for a track from the running TrackServer.

  Returns a list of `ConsoleHistoryBlock` structs in chronological order (oldest first).
  This includes both persisted (finished) blocks and any in-flight (running) block.

  Returns `{:ok, blocks}` on success or `{:error, :not_found}` if no
  TrackServer exists for the track.
  """
  @spec get_console_history(integer()) ::
          {:ok, [ConsoleHistoryBlock.t()]} | {:error, :not_found}
  def get_console_history(track_id) do
    # Only query if the registry is running (it's disabled in test mode for most tests)
    case Process.whereis(Msfailab.Tracks.Registry) do
      nil ->
        {:error, :not_found}

      _registry_pid ->
        case TrackServer.whereis(track_id) do
          nil ->
            {:error, :not_found}

          _pid ->
            try do
              {:ok, TrackServer.get_console_history(track_id)}
            catch
              :exit, _ ->
                # Process died between lookup and call
                {:error, :not_found}
            end
        end
    end
  end

  @doc """
  Gets the full track state from the running TrackServer.

  Returns a map with `:console_status`, `:current_prompt`, and `:console_history`.

  Returns `{:ok, state}` on success or `{:error, :not_found}` if no
  TrackServer exists for the track.
  """
  @spec get_track_state(integer()) ::
          {:ok,
           %{
             console_status: TrackServer.console_status(),
             current_prompt: String.t(),
             console_history: [ConsoleHistoryBlock.t()]
           }}
          | {:error, :not_found}
  def get_track_state(track_id) do
    # Only query if the registry is running (it's disabled in test mode for most tests)
    case Process.whereis(Msfailab.Tracks.Registry) do
      nil ->
        {:error, :not_found}

      _registry_pid ->
        case TrackServer.whereis(track_id) do
          nil ->
            {:error, :not_found}

          _pid ->
            try do
              {:ok, TrackServer.get_state(track_id)}
            catch
              :exit, _ ->
                # Process died between lookup and call
                {:error, :not_found}
            end
        end
    end
  end

  # ============================================================================
  # Chat State Operations
  # ============================================================================

  # coveralls-ignore-start
  # Reason: TrackServer runtime integration. These thin wrappers delegate to
  # TrackServer which is tested at 91.0% coverage. Testing requires full runtime infrastructure.

  @doc """
  Starts a new chat turn with the given user prompt.

  Creates a new turn, persists the user prompt, builds conversation context,
  and starts streaming from the LLM.

  ## Parameters

  - `track_id` - The track to start the turn in
  - `user_prompt` - The user's message
  - `model` - The model to use for this turn

  ## Returns

  - `{:ok, turn_id}` - The turn was started successfully
  - `{:error, reason}` - Failed to start the turn
  """
  @spec start_chat_turn(integer(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, term()}
  def start_chat_turn(track_id, user_prompt, model) do
    case Process.whereis(Msfailab.Tracks.Registry) do
      nil ->
        {:error, :not_found}

      _registry_pid ->
        case TrackServer.whereis(track_id) do
          nil ->
            {:error, :not_found}

          _pid ->
            try do
              TrackServer.start_chat_turn(track_id, user_prompt, model)
            catch
              :exit, _ ->
                {:error, :not_found}
            end
        end
    end
  end

  @doc """
  Gets the current chat state for a track from the running TrackServer.

  Returns a `ChatState` struct with entries and turn status.

  ## Returns

  - `{:ok, chat_state}` - The chat state

  Note: This function always succeeds by falling back to loading from the database
  when the TrackServer is unavailable. This ensures the UI shows persisted chat
  history even during transient failures (TrackServer crash, restart, etc.).
  """
  @spec get_chat_state(integer()) :: {:ok, ChatState.t()}
  def get_chat_state(track_id) do
    case Process.whereis(Msfailab.Tracks.Registry) do
      nil ->
        # Registry not available, fall back to database
        load_chat_state_from_db(track_id)

      _registry_pid ->
        case TrackServer.whereis(track_id) do
          nil ->
            # TrackServer not running, fall back to database
            load_chat_state_from_db(track_id)

          _pid ->
            try do
              {:ok, TrackServer.get_chat_state(track_id)}
            catch
              :exit, _ ->
                # TrackServer crashed during call, fall back to database
                load_chat_state_from_db(track_id)
            end
        end
    end
  end

  # Falls back to loading chat state directly from the database when TrackServer
  # is unavailable (crashed, restarting, or not yet started). This ensures the UI
  # shows persisted chat history even during transient failures.
  defp load_chat_state_from_db(track_id) do
    persisted_entries = ChatContext.load_entries(track_id)
    chat_entries = ChatContext.entries_to_chat_entries(persisted_entries)

    # Determine turn status from entries - if there are pending/approved tools,
    # show appropriate status; otherwise idle
    turn_status = infer_turn_status_from_entries(persisted_entries)

    {:ok, ChatState.new(chat_entries, turn_status, nil)}
  end

  defp infer_turn_status_from_entries(entries) do
    has_pending_tools =
      Enum.any?(entries, fn entry ->
        entry.entry_type == "tool_invocation" and
          entry.tool_invocation != nil and
          entry.tool_invocation.status == "pending"
      end)

    has_approved_tools =
      Enum.any?(entries, fn entry ->
        entry.entry_type == "tool_invocation" and
          entry.tool_invocation != nil and
          entry.tool_invocation.status == "approved"
      end)

    cond do
      has_pending_tools -> :pending_approval
      has_approved_tools -> :executing_tools
      true -> :idle
    end
  end

  @doc """
  Approves a pending tool invocation.

  When a tool invocation is approved, the TrackServer's reconciliation engine
  will check if the tool can be executed (e.g., console is ready for sequential
  tools) and start execution if possible.

  ## Parameters

  - `track_id` - The ID of the track
  - `entry_id` - The ID of the tool invocation entry to approve

  ## Returns

  - `:ok` - Tool was approved successfully
  - `{:error, :not_found}` - No TrackServer exists for the track
  - `{:error, :invalid_status}` - Tool is not in pending status
  """
  @spec approve_tool(integer(), String.t()) :: :ok | {:error, term()}
  def approve_tool(track_id, entry_id) do
    case Process.whereis(Msfailab.Tracks.Registry) do
      nil ->
        {:error, :not_found}

      _registry_pid ->
        case TrackServer.whereis(track_id) do
          nil ->
            {:error, :not_found}

          _pid ->
            try do
              TrackServer.approve_tool(track_id, entry_id)
            catch
              :exit, _ ->
                {:error, :not_found}
            end
        end
    end
  end

  @doc """
  Denies a pending tool invocation with a reason.

  When a tool invocation is denied, the TrackServer's reconciliation engine
  will check if all tools are now in terminal states and potentially continue
  the LLM turn with the denial information.

  ## Parameters

  - `track_id` - The ID of the track
  - `entry_id` - The ID of the tool invocation entry to deny
  - `reason` - The reason for denying the tool

  ## Returns

  - `:ok` - Tool was denied successfully
  - `{:error, :not_found}` - No TrackServer exists for the track
  - `{:error, :invalid_status}` - Tool is not in pending status
  """
  @spec deny_tool(integer(), String.t(), String.t()) :: :ok | {:error, term()}
  def deny_tool(track_id, entry_id, reason) do
    case Process.whereis(Msfailab.Tracks.Registry) do
      nil ->
        {:error, :not_found}

      _registry_pid ->
        case TrackServer.whereis(track_id) do
          nil ->
            {:error, :not_found}

          _pid ->
            try do
              TrackServer.deny_tool(track_id, entry_id, reason)
            catch
              :exit, _ ->
                {:error, :not_found}
            end
        end
    end
  end

  @doc """
  Sets the autonomous mode for a track.

  When autonomous mode is enabled, tool invocations are automatically approved
  without waiting for user confirmation. Updates both the database and the
  running TrackServer (if any).

  ## Parameters

  - `track_id` - The ID of the track
  - `autonomous` - Whether autonomous mode should be enabled

  ## Returns

  - `{:ok, track}` - The track was updated successfully
  - `{:error, changeset}` - Failed to update the track
  """
  @spec set_autonomous(integer(), boolean()) :: {:ok, Track.t()} | {:error, Ecto.Changeset.t()}
  def set_autonomous(track_id, autonomous) do
    track = get_track!(track_id)

    with {:ok, updated_track} <- update_track(track, %{autonomous: autonomous}) do
      # Notify running TrackServer if any
      case Process.whereis(Msfailab.Tracks.Registry) do
        nil ->
          :ok

        _registry_pid ->
          case TrackServer.whereis(track_id) do
            nil ->
              :ok

            _pid ->
              try do
                TrackServer.set_autonomous(track_id, autonomous)
              catch
                :exit, _ -> :ok
              end
          end
      end

      {:ok, updated_track}
    end
  end

  # coveralls-ignore-stop

  # ============================================================================
  # Console History Block Persistence
  # ============================================================================

  @doc """
  Lists all persisted console history blocks for a track.

  Returns blocks in chronological order (oldest first) based on insertion time.
  All returned blocks have status `:finished` (set on load since only finished
  blocks are persisted).
  """
  @spec list_console_history_blocks(integer()) :: [ConsoleHistoryBlock.t()]
  def list_console_history_blocks(track_id) do
    ConsoleHistoryBlock
    |> where([b], b.track_id == ^track_id)
    |> order_by([b], asc: b.inserted_at)
    |> Repo.all()
    |> Enum.map(&%{&1 | status: :finished})
  end

  @doc """
  Persists a finished console history block to the database.

  Only blocks with status `:finished` can be persisted. Returns `{:error, changeset}`
  if the block is not finished or validation fails.
  """
  @spec create_console_history_block(ConsoleHistoryBlock.t()) ::
          {:ok, ConsoleHistoryBlock.t()} | {:error, Ecto.Changeset.t()}
  def create_console_history_block(%ConsoleHistoryBlock{} = block) do
    case Repo.insert(ConsoleHistoryBlock.persist_changeset(block)) do
      {:ok, persisted} ->
        # Set status to :finished on the returned struct (virtual field)
        {:ok, %{persisted | status: :finished}}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  # coveralls-ignore-start
  # Reason: Runtime lifecycle coordination requiring Container/Track supervisors.
  # These functions check for running supervisors and delegate to tested modules.

  defp maybe_start_container(track) do
    # Only start container if the supervisor is running
    # (it's disabled in test mode for most tests)
    if Process.whereis(Msfailab.Containers.ContainerSupervisor) do
      ensure_container_started(track.container)
    end
  end

  defp ensure_container_started(%ContainerRecord{} = container) do
    # Check if container GenServer is already running
    case Containers.get_status(container.id) do
      {:ok, _status} ->
        # Already running
        :ok

      {:error, :not_found} ->
        # Need to start it - ensure workspace is preloaded
        container_with_workspace = Repo.preload(container, :workspace)
        Containers.start_container(container_with_workspace)
    end
  end

  defp maybe_stop_container(container_id) do
    # Only stop container if the supervisor is running
    if Process.whereis(Msfailab.Containers.ContainerSupervisor) do
      # Check if there are any remaining active tracks for this container
      remaining_tracks =
        Track
        |> where([t], t.container_id == ^container_id and is_nil(t.archived_at))
        |> Repo.exists?()

      unless remaining_tracks do
        # No more active tracks, stop the container
        Containers.stop_container(container_id)
      end
    end
  end

  defp maybe_start_track_server(track) do
    # Only start track server if the supervisor is running
    # (it's disabled in test mode for most tests)
    if Process.whereis(Msfailab.Tracks.TrackSupervisor) do
      start_track_server(track)
    end
  end

  # coveralls-ignore-stop
end
