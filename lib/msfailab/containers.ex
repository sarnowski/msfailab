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

defmodule Msfailab.Containers do
  @moduledoc """
  Context for container and console management.

  This context provides a **unified public API** for all container and console
  operations. Callers interact only with this context—they have no knowledge
  of internal GenServers (Container, Console).

  ## Responsibilities

  - Container CRUD operations (database records)
  - Container GenServer lifecycle management
  - Querying container and console state (with live status)
  - Registering/unregistering consoles for tracks
  - Sending commands to consoles (Metasploit and bash)

  ## API Design Principles

  | Principle                          | Implementation                             |
  |------------------------------------|--------------------------------------------|
  | Flat lists, not nested structures  | `get_containers` and `get_consoles` return |
  |                                    | simple lists, not container→console maps   |
  | Consistent function signatures     | Console ops take `(container_id, track_id)`|
  | No cross-context dependencies      | `track_id` is opaque identifier            |
  | Live status from GenServers        | Status from GenServer state, not database  |
  | Subscribe-first pattern            | UI subscribes before querying state        |

  ### Why Flat Lists?

  **Decision:** `get_containers(workspace_id)` and `get_consoles(workspace_id)`
  return flat lists rather than nested structures.

  **Rationale:**
  - Easier to work with in Phoenix templates and LiveView
  - Aligns with typical Ecto context patterns
  - UI can easily index by ID: `Map.new(containers, &{&1.id, &1})`
  - Filtering and mapping are straightforward

  ### Why `track_id` is Opaque?

  **Decision:** Containers context doesn't query Track entities. It only uses
  `track_id` as an opaque identifier for console routing.

  **Rationale:**
  - Eliminates cyclic dependencies between contexts
  - Container manages infrastructure, not business logic
  - Simpler testing—Containers tests don't need Track fixtures

  ## Console Registration Model

  TrackServer **declares intent** to have a console, Container **owns lifecycle**.
  This separation ensures clean boundaries and simple implementations.

  ### From TrackServer's Perspective

  ```elixir
  # In TrackServer.init/1
  def init(opts) do
    container_id = Keyword.fetch!(opts, :container_id)
    track_id = Keyword.fetch!(opts, :track_id)

    # Subscribe to events FIRST
    Events.subscribe_to_workspace(workspace_id)

    # Then register console (always succeeds)
    Containers.register_console(container_id, track_id)

    # TrackServer is done—just listen to ConsoleUpdated events
    {:ok, state}
  end

  # In TrackServer.terminate/2
  def terminate(_reason, state) do
    Containers.unregister_console(state.container_id, state.track_id)
    :ok
  end
  ```

  ### Registration Guarantees

  | Function              | Return  | Behavior                                  |
  |-----------------------|---------|-------------------------------------------|
  | `register_console`    | `:ok`   | Always succeeds. If Container not running,|
  |                       |         | registration is stored for later.         |
  | `unregister_console`  | `:ok`   | Always succeeds. Cleans up if exists.     |

  ## State Access Pattern (Subscribe-First)

  To avoid race conditions between querying state and receiving events,
  **always subscribe before querying**:

  ```elixir
  def mount(%{"workspace" => slug}, _session, socket) do
    workspace = Workspaces.get_by_slug!(slug)

    # 1. Subscribe FIRST (before any queries)
    if connected?(socket) do
      Events.subscribe_to_workspace(workspace.id)
    end

    # 2. THEN query current state
    containers = Containers.get_containers(workspace.id)
    consoles = Containers.get_consoles(workspace.id)

    # 3. Index for easy lookup
    {:ok, assign(socket,
      workspace: workspace,
      containers: index_by_id(containers),
      consoles: index_by_track_id(consoles)
    )}
  end

  defp index_by_id(list), do: Map.new(list, &{&1.id, &1})
  defp index_by_track_id(list), do: Map.new(list, &{&1.track_id, &1})
  ```

  ### Why Subscribe First?

  If you query first, then subscribe, events that occur between the query
  and subscription are lost. By subscribing first:

  1. Events start queueing immediately
  2. Initial query gives you baseline state
  3. Events that arrive during/after query are correctly applied
  4. No gaps in the event stream

  ## LiveView Event Handling

  After mounting with subscribe-first pattern, handle events incrementally:

  ```elixir
  # Container status changes
  def handle_info(%ContainerUpdated{} = event, socket) do
    socket = update(socket, :containers, fn containers ->
      Map.update(containers, event.container_id, nil, fn container ->
        %{container | status: event.status, docker_container_id: event.docker_container_id}
      end)
    end)
    {:noreply, socket}
  end

  # Console status changes
  def handle_info(%ConsoleUpdated{} = event, socket) do
    socket = update(socket, :consoles, fn consoles ->
      Map.update(consoles, event.track_id, nil, fn console ->
        apply_console_event(console, event)
      end)
    end)
    {:noreply, socket}
  end

  defp apply_console_event(console, %ConsoleUpdated{status: :offline}) do
    %{console | status: :offline, prompt: ""}
  end

  defp apply_console_event(console, %ConsoleUpdated{status: :starting}) do
    %{console | status: :starting}
  end

  defp apply_console_event(console, %ConsoleUpdated{status: :ready, prompt: prompt}) do
    %{console | status: :ready, prompt: prompt}
  end

  defp apply_console_event(console, %ConsoleUpdated{status: :busy}) do
    %{console | status: :busy}
  end
  ```

  **Note:** Detailed output/history tracking is handled by TrackServer.
  LiveView typically just needs status and prompt for display. For full
  history, query TrackServer via `Tracks.get_track_state/1`.

  ## Command Execution

  ### Metasploit Commands

  Metasploit commands go through the Console GenServer (one at a time):

  ```elixir
  case Containers.send_metasploit_command(container_id, track_id, "db_status") do
    {:ok, command_id} ->
      # Command accepted, ConsoleUpdated(:busy) events will follow
      :ok

    {:error, :container_not_running} ->
      # No Container GenServer—container is offline
      show_error("Container is offline")

    {:error, :console_not_registered} ->
      # Track hasn't registered for a console
      show_error("Console not registered")

    {:error, :console_offline} ->
      # Console not spawned yet
      show_error("Console is offline")

    {:error, :console_starting} ->
      # Console still initializing
      show_error("Console is starting, please wait")

    {:error, :console_busy} ->
      # Another command is executing
      show_error("Console is busy")
  end
  ```

  ### Bash Commands

  Bash commands run as parallel, fire-and-forget tasks:

  ```elixir
  case Containers.send_bash_command(container_id, track_id, "ls -la") do
    {:ok, command_id} ->
      # Command started, CommandResult events will follow
      :ok

    {:error, :container_not_running} ->
      # No Container GenServer
      show_error("Container is offline")
  end
  ```

  ## Error Handling Philosophy

  ### No Persistent `:error` State

  **Decision:** Neither containers nor consoles have an `:error` state.
  Failures result in `:offline` + auto-recovery.

  **Rationale:**
  - `:error` provides no recovery path—users get stuck
  - Auto-recovery is more user-friendly
  - Unexpected errors should crash (let supervisor handle)

  ### Status Returns `:offline` for Missing GenServers

  **Decision:** Query functions return `:offline` status when GenServer
  doesn't exist, rather than returning an error or special value.

  **Rationale:**
  - Unified API regardless of GenServer existence
  - UI can treat "not started" same as "offline"
  - `:offline` accurately describes the situation

  ## Key Design Decisions

  ### Containers Context as Unified Public API

  **Decision:** All external interaction with containers and consoles goes
  through this context. Callers have no knowledge of internal GenServers.

  **Rationale:**
  - Encapsulation: Internal GenServer structure can change without affecting callers
  - Testability: Can mock the context for testing callers
  - Consistency: Single place for container/console logic

  ### Command Rejection (No Queuing)

  **Decision:** `send_metasploit_command` returns error if console not `:ready`.
  No command queuing.

  **Rationale:**
  - Simpler implementation
  - Clear feedback to user ("console is busy/offline")
  - Caller (UI) can decide how to handle (show error, disable button, etc.)
  """

  import Ecto.Query

  alias Msfailab.Containers.Container
  alias Msfailab.Containers.ContainerRecord
  alias Msfailab.Containers.DockerAdapter
  alias Msfailab.Containers.Msgrpc.Console
  alias Msfailab.Events
  alias Msfailab.Events.WorkspaceChanged
  alias Msfailab.Repo
  alias Msfailab.Workspaces.Workspace

  # ============================================================================
  # Types
  # ============================================================================

  @typedoc "Container with live status"
  @type container_info :: %{
          id: integer(),
          workspace_id: integer(),
          slug: String.t(),
          name: String.t(),
          docker_image: String.t(),
          status: :offline | :starting | :running,
          docker_container_id: String.t() | nil
        }

  @typedoc "Console with live status"
  @type console_info :: %{
          track_id: integer(),
          container_id: integer(),
          status: :offline | :starting | :ready | :busy,
          prompt: String.t()
        }

  @typedoc "Running bash command info"
  @type running_bash_command :: %{
          command_id: String.t(),
          track_id: integer(),
          container_id: integer(),
          command: String.t(),
          started_at: DateTime.t()
        }

  # ============================================================================
  # Container Record CRUD Operations
  # ============================================================================

  @doc """
  Returns all containers for a workspace.

  Accepts either a `%Workspace{}` struct or a workspace ID (integer).
  """
  @spec list_containers(Workspace.t() | integer()) :: [ContainerRecord.t()]
  def list_containers(workspace_or_id)

  def list_containers(%Workspace{} = workspace) do
    list_containers(workspace.id)
  end

  def list_containers(workspace_id) when is_integer(workspace_id) do
    ContainerRecord
    |> where([c], c.workspace_id == ^workspace_id)
    |> order_by([c], asc: c.name)
    |> Repo.all()
  end

  @doc """
  Returns all containers for a workspace with their tracks preloaded.

  Tracks are ordered by name. This is useful for UI display where you need
  to show containers with their associated tracks.
  """
  @spec list_containers_with_tracks(Workspace.t() | integer()) :: [ContainerRecord.t()]
  def list_containers_with_tracks(workspace_or_id)

  def list_containers_with_tracks(%Workspace{} = workspace) do
    list_containers_with_tracks(workspace.id)
  end

  def list_containers_with_tracks(workspace_id) when is_integer(workspace_id) do
    tracks_query = from(t in Msfailab.Tracks.Track, order_by: [asc: t.name])

    ContainerRecord
    |> where([c], c.workspace_id == ^workspace_id)
    |> order_by([c], asc: c.name)
    |> preload(tracks: ^tracks_query)
    |> Repo.all()
  end

  @doc """
  Returns all containers that have at least one active (non-archived) track.

  Used by the Reconciler to determine which containers need running GenServers.
  Preloads the workspace association required for container naming.
  """
  @spec list_active_containers() :: [ContainerRecord.t()]
  def list_active_containers do
    ContainerRecord
    |> join(:inner, [c], t in assoc(c, :tracks))
    |> where([c, t], is_nil(t.archived_at))
    |> distinct([c], c.id)
    |> preload(:workspace)
    |> Repo.all()
  end

  @doc """
  Gets a container by ID.

  Returns `nil` if the container does not exist.
  """
  @spec get_container(integer()) :: ContainerRecord.t() | nil
  def get_container(id), do: Repo.get(ContainerRecord, id)

  @doc """
  Gets a container by ID.

  Raises `Ecto.NoResultsError` if the container does not exist.
  """
  @spec get_container!(integer()) :: ContainerRecord.t()
  def get_container!(id), do: Repo.get!(ContainerRecord, id)

  @doc """
  Gets a container by workspace and slug.

  Accepts either a `%Workspace{}` struct or a workspace ID (integer).
  Returns `nil` if the container does not exist.
  """
  @spec get_container_by_slug(Workspace.t() | integer(), String.t()) :: ContainerRecord.t() | nil
  def get_container_by_slug(workspace_or_id, slug)

  def get_container_by_slug(%Workspace{} = workspace, slug) do
    get_container_by_slug(workspace.id, slug)
  end

  def get_container_by_slug(workspace_id, slug) when is_integer(workspace_id) do
    ContainerRecord
    |> where([c], c.workspace_id == ^workspace_id and c.slug == ^slug)
    |> Repo.one()
  end

  @doc """
  Checks if a container slug is already taken within a workspace.

  Returns `true` if the slug exists, `false` otherwise.
  """
  @spec slug_exists?(Workspace.t() | integer(), String.t()) :: boolean()
  def slug_exists?(workspace_or_id, slug)

  def slug_exists?(%Workspace{} = workspace, slug), do: slug_exists?(workspace.id, slug)

  def slug_exists?(workspace_id, slug)
      when is_integer(workspace_id) and is_binary(slug) and slug != "" do
    ContainerRecord
    |> where([c], c.workspace_id == ^workspace_id and c.slug == ^slug)
    |> Repo.exists?()
  end

  def slug_exists?(_, _), do: false

  @doc """
  Creates a new container within a workspace.

  Accepts either a `%Workspace{}` struct with attrs, or just attrs containing
  a `:workspace_id` key.
  """
  @spec create_container(Workspace.t() | map(), map() | nil) ::
          {:ok, ContainerRecord.t()} | {:error, Ecto.Changeset.t()}
  def create_container(workspace_or_attrs, attrs \\ nil)

  def create_container(%Workspace{} = workspace, attrs) do
    changeset =
      %ContainerRecord{workspace_id: workspace.id}
      |> ContainerRecord.create_changeset(attrs)

    with {:ok, container} <- Repo.insert(changeset) do
      Events.broadcast(WorkspaceChanged.new(container.workspace_id))
      {:ok, container}
    end
  end

  def create_container(attrs, nil) when is_map(attrs) do
    changeset =
      %ContainerRecord{}
      |> ContainerRecord.create_changeset(attrs)

    with {:ok, container} <- Repo.insert(changeset) do
      Events.broadcast(WorkspaceChanged.new(container.workspace_id))
      {:ok, container}
    end
  end

  @doc """
  Updates an existing container.
  """
  @spec update_container(ContainerRecord.t(), map()) ::
          {:ok, ContainerRecord.t()} | {:error, Ecto.Changeset.t()}
  def update_container(%ContainerRecord{} = container, attrs) do
    container
    |> ContainerRecord.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Returns a changeset for tracking container changes.
  """
  @spec change_container(ContainerRecord.t(), map()) :: Ecto.Changeset.t()
  def change_container(%ContainerRecord{} = container, attrs \\ %{}) do
    ContainerRecord.create_changeset(container, attrs)
  end

  # ============================================================================
  # Container GenServer Management
  # ============================================================================

  @doc """
  Starts a Container GenServer for a container record.

  Called when a container needs to be started (e.g., when a track is created).
  The container record must have its workspace association preloaded.

  Returns `{:ok, pid}` on success or `{:error, reason}` on failure.
  """
  @spec start_container(ContainerRecord.t()) :: {:ok, pid()} | {:error, term()}
  def start_container(%ContainerRecord{} = container) do
    opts = [
      container_record_id: container.id,
      workspace_id: container.workspace_id,
      workspace_slug: container.workspace.slug,
      container_slug: container.slug,
      container_name: container.name,
      docker_image: container.docker_image,
      # Auto-start since this is a runtime container start (not via Reconciler)
      auto_start: true
    ]

    DynamicSupervisor.start_child(
      Msfailab.Containers.ContainerSupervisor,
      {Container, opts}
    )
  end

  @doc """
  Stops a Container GenServer.

  Called when all tracks for a container are archived. The `Container` process
  `terminate/2` callback will handle stopping the Docker container.

  Returns `:ok` on success or `{:error, :not_found}` if no container
  process exists.
  """
  @spec stop_container(integer()) :: :ok | {:error, :not_found}
  def stop_container(container_record_id) do
    case Container.whereis(container_record_id) do
      nil ->
        {:error, :not_found}

      pid ->
        # Use GenServer.stop to allow the process to clean up via terminate/2
        # This ensures the Docker container is properly stopped
        GenServer.stop(pid, :normal)
        :ok
    end
  end

  # ============================================================================
  # State Query Functions
  # ============================================================================

  @doc """
  Returns all containers in a workspace with their live status.

  Status is derived from Container GenServer if running, otherwise :offline.

  ## Example

      Containers.get_containers(workspace_id)
      #=> [
      #     %{id: 1, name: "Main", slug: "main", status: :running, ...},
      #     %{id: 2, name: "Test", slug: "test", status: :offline, ...}
      #   ]
  """
  @spec get_containers(integer()) :: [container_info()]
  def get_containers(workspace_id) do
    records = list_containers(workspace_id)

    Enum.map(records, fn record ->
      {status, docker_container_id} = get_live_container_status(record.id)

      %{
        id: record.id,
        workspace_id: record.workspace_id,
        slug: record.slug,
        name: record.name,
        docker_image: record.docker_image,
        status: status,
        docker_container_id: docker_container_id
      }
    end)
  end

  @doc """
  Returns consoles with their live status.

  By default returns ALL consoles across all containers in the workspace.
  Use `container_id` option to filter to a specific container.

  Consoles are derived from registered_tracks in Container GenServers.
  Status is :offline if Container GenServer doesn't exist or console isn't
  registered/spawned yet.

  ## Options

  - `:container_id` - Filter to consoles in a specific container

  ## Examples

      # All consoles in workspace
      Containers.get_consoles(workspace_id)
      #=> [
      #     %{track_id: 42, container_id: 1, status: :ready, prompt: "msf6 > "},
      #     %{track_id: 43, container_id: 1, status: :busy, prompt: ""},
      #     %{track_id: 44, container_id: 2, status: :offline, prompt: ""}
      #   ]

      # Consoles in specific container
      Containers.get_consoles(workspace_id, container_id: 1)
      #=> [
      #     %{track_id: 42, container_id: 1, status: :ready, prompt: "msf6 > "},
      #     %{track_id: 43, container_id: 1, status: :busy, prompt: ""}
      #   ]
  """
  @spec get_consoles(integer(), keyword()) :: [console_info()]
  def get_consoles(workspace_id, opts \\ []) do
    filter_container_id = Keyword.get(opts, :container_id)

    records =
      if filter_container_id do
        [get_container(filter_container_id)] |> Enum.reject(&is_nil/1)
      else
        list_containers(workspace_id)
      end

    Enum.flat_map(records, fn record ->
      case Container.whereis(record.id) do
        nil ->
          []

        _pid ->
          try do
            snapshot = Container.get_state_snapshot(record.id)

            Enum.map(snapshot.consoles, fn {track_id, console_info} ->
              # Query the Console GenServer directly for status and prompt
              # since it owns that state (not the Container)
              {status, prompt} =
                case console_info.pid do
                  nil ->
                    {:offline, ""}

                  pid ->
                    try do
                      {Console.get_status(pid), Console.get_prompt(pid)}
                    catch
                      :exit, _ -> {:offline, ""}
                    end
                end

              %{
                track_id: track_id,
                container_id: record.id,
                status: status,
                prompt: prompt
              }
            end)
          catch
            :exit, _ -> []
          end
      end
    end)
  end

  # ============================================================================
  # Console Registration
  # ============================================================================

  @doc """
  Registers a console for a track in a container.

  Always succeeds immediately (returns :ok). The actual Console GenServer will
  be spawned by Container when it reaches :running state. If Container is already
  running, the console is spawned immediately.

  TrackServer should call this on init.

  ## Parameters

  - `container_id` - The container that will host the console
  - `track_id` - The track that wants a console (opaque identifier)

  ## Example

      # In TrackServer.init/1
      Containers.register_console(container_id, track_id)
      #=> :ok
  """
  @spec register_console(integer(), integer()) :: :ok
  def register_console(container_id, track_id) do
    case Container.whereis(container_id) do
      nil ->
        # Container not running, registration will happen when it starts
        :ok

      _pid ->
        Container.register_console(container_id, track_id)
    end
  end

  @doc """
  Unregisters a console for a track.

  Removes the track from registered_tracks and destroys the Console GenServer
  if one is running. TrackServer should call this on terminate.

  ## Parameters

  - `container_id` - The container hosting the console
  - `track_id` - The track to unregister

  ## Example

      # In TrackServer.terminate/2
      Containers.unregister_console(container_id, track_id)
      #=> :ok
  """
  @spec unregister_console(integer(), integer()) :: :ok
  def unregister_console(container_id, track_id) do
    case Container.whereis(container_id) do
      nil ->
        :ok

      _pid ->
        try do
          Container.unregister_console(container_id, track_id)
        catch
          :exit, _ -> :ok
        end
    end
  end

  # ============================================================================
  # Bash Command Query
  # ============================================================================

  @doc """
  Returns currently running bash commands.

  Use this to get the initial state for UI, then listen to CommandResult
  events for real-time updates. Commands are removed from this list when
  they finish (successfully or with error).

  ## Parameters

  - `container_id` - The container to query
  - `opts` - Options
    - `:track_id` - Optional. Filter to commands for a specific track.

  ## Examples

      # All running bash commands in container
      Containers.get_running_bash_commands(container_id)
      #=> [
      #     %{command_id: "abc123", track_id: 42, command: "nmap -sV ...", ...},
      #     %{command_id: "def456", track_id: 42, command: "ls -la", ...}
      #   ]

      # Running bash commands for specific track
      Containers.get_running_bash_commands(container_id, track_id: 42)
      #=> [%{command_id: "abc123", ...}, %{command_id: "def456", ...}]
  """
  @spec get_running_bash_commands(integer(), keyword()) :: [running_bash_command()]
  def get_running_bash_commands(container_id, opts \\ []) do
    filter_track_id = Keyword.get(opts, :track_id)

    case Container.whereis(container_id) do
      nil ->
        []

      _pid ->
        try do
          commands = Container.get_running_bash_commands(container_id)

          if filter_track_id do
            Enum.filter(commands, &(&1.track_id == filter_track_id))
          else
            commands
          end
        catch
          :exit, _ -> []
        end
    end
  end

  @doc """
  Gets the current status of a container's GenServer.

  Returns `{:ok, {status, docker_container_id}}` where status is one of:
  `:offline`, `:starting`, or `:running`.

  Returns `{:error, :not_found}` if no container process exists.
  """
  @spec get_status(integer()) :: {:ok, {atom(), String.t() | nil}} | {:error, :not_found}
  def get_status(container_record_id) do
    case Container.whereis(container_record_id) do
      nil ->
        {:error, :not_found}

      _pid ->
        try do
          {:ok, Container.get_status(container_record_id)}
        catch
          :exit, _ ->
            # Process died between lookup and call
            {:error, :not_found}
        end
    end
  end

  # Private helper for getting container status
  defp get_live_container_status(container_record_id) do
    case Container.whereis(container_record_id) do
      nil ->
        {:offline, nil}

      _pid ->
        try do
          Container.get_status(container_record_id)
        catch
          :exit, _ -> {:offline, nil}
        end
    end
  end

  # ============================================================================
  # Command Execution
  # ============================================================================

  @typedoc "Metasploit command error reasons"
  @type metasploit_command_error ::
          :container_not_running
          | :console_not_registered
          | :console_offline
          | :console_starting
          | :console_busy

  @doc """
  Sends a command to a track's Metasploit console.

  Console sessions are created on-demand when the first command is sent.
  This is an asynchronous operation that returns `{:ok, command_id}` immediately
  and broadcasts CommandIssued and CommandResult events via PubSub.

  ## Error reasons

  - `:container_not_running` - Container process is not running
  - `:console_not_registered` - Track is not registered with the container
  - `:console_offline` - Console process is not running (crashed or not started)
  - `:console_starting` - Console is still initializing
  - `:console_busy` - Console is executing another command
  """
  @spec send_metasploit_command(integer(), integer(), String.t()) ::
          {:ok, String.t()} | {:error, metasploit_command_error()}
  def send_metasploit_command(container_record_id, track_id, command) do
    case Container.whereis(container_record_id) do
      nil ->
        {:error, :container_not_running}

      _pid ->
        Container.send_metasploit_command(container_record_id, track_id, command)
    end
  end

  @doc """
  Sends a bash command to a container for a specific track.

  This is an asynchronous operation. Returns `{:ok, command_id}` immediately
  and broadcasts CommandIssued and CommandResult events via PubSub.

  Multiple bash commands can run in parallel. Events are tagged with the
  track_id for proper routing.

  Returns `{:error, :container_not_running}` only if no container process exists.
  """
  @spec send_bash_command(integer(), integer(), String.t()) ::
          {:ok, String.t()} | {:error, :container_not_running}
  def send_bash_command(container_record_id, track_id, command) do
    case Container.whereis(container_record_id) do
      nil ->
        {:error, :container_not_running}

      _pid ->
        Container.send_bash_command(container_record_id, track_id, command)
    end
  end

  # ============================================================================
  # RPC Endpoint Access
  # ============================================================================

  @doc """
  Gets the RPC endpoint for a container.

  Returns `{:ok, %{host: host, port: port}}` on success,
  or `{:error, reason}` on failure.

  ## Errors

  - `{:error, :not_running}` - No container process exists
  - `{:error, :not_available}` - Container exists but RPC endpoint not available yet
  """
  @spec get_rpc_endpoint(integer()) :: {:ok, map()} | {:error, term()}
  def get_rpc_endpoint(container_record_id) do
    case Container.whereis(container_record_id) do
      nil ->
        {:error, :not_running}

      _pid ->
        Container.get_rpc_endpoint(container_record_id)
    end
  end

  @doc """
  Gets the RPC context from any running container in a workspace.

  Searches for a running container with an active MSGRPC connection and
  returns its RPC context (client module, endpoint, and auth token).

  This is useful for making RPC calls to the Metasploit Framework when you
  don't need a specific container, such as deserializing Ruby Marshal data.

  ## Parameters

  - `workspace_id` - The workspace ID to search for containers

  ## Returns

  - `{:ok, rpc_context}` - RPC context with client, endpoint, and token
  - `{:error, :no_running_container}` - No container with active MSGRPC connection found
  """
  @spec get_rpc_context_for_workspace(integer()) ::
          {:ok, map()} | {:error, :no_running_container}
  def get_rpc_context_for_workspace(workspace_id) do
    workspace_id
    |> list_containers()
    |> Enum.find_value({:error, :no_running_container}, &try_get_container_rpc_context/1)
  end

  defp try_get_container_rpc_context(container) do
    # Only try to get context if the container process is running
    if Container.whereis(container.id) do
      # Wrap in try/catch - the Container GenServer may crash or be unavailable
      try do
        case Container.get_rpc_context(container.id) do
          {:ok, context} -> {:ok, context}
          {:error, _} -> nil
        end
      catch
        :exit, _ -> nil
      end
    else
      nil
    end
  end

  # ============================================================================
  # Utilities
  # ============================================================================

  @doc """
  Generates the Docker container name for a workspace and container slug combination.

  Format: `msfailab-{workspace_slug}-{container_slug}`
  """
  @spec container_name(String.t(), String.t()) :: String.t()
  def container_name(workspace_slug, container_slug) do
    "msfailab-#{workspace_slug}-#{container_slug}"
  end

  @doc """
  Returns the configured Docker adapter module.

  Used internally and by the Reconciler to interact with Docker.
  """
  @spec docker_adapter() :: module()
  def docker_adapter do
    Application.get_env(:msfailab, :docker_adapter, DockerAdapter.Cli)
  end
end
