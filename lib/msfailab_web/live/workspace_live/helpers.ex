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

defmodule MsfailabWeb.WorkspaceLive.Helpers do
  @moduledoc """
  Pure helper functions for WorkspaceLive.

  These functions contain conditional logic extracted from the LiveView
  to enable comprehensive unit testing without process setup.
  """

  alias Ecto.Changeset
  alias Msfailab.Containers
  alias Msfailab.Tracks
  alias Msfailab.Tracks.ConsoleHistoryBlock

  # ===========================================================================
  # Page Title
  # ===========================================================================

  @doc """
  Generates the page title based on workspace and current track.

  ## Examples

      iex> workspace = %{name: "ACME Pentest"}
      iex> Helpers.page_title(workspace, nil)
      "ACME Pentest - Asset Library"

      iex> workspace = %{name: "ACME Pentest"}
      iex> track = %{name: "Reconnaissance"}
      iex> Helpers.page_title(workspace, track)
      "Reconnaissance - ACME Pentest"
  """
  @spec page_title(map(), map() | nil) :: String.t()
  def page_title(workspace, nil), do: "#{workspace.name} - Asset Library"
  def page_title(workspace, track), do: "#{track.name} - #{workspace.name}"

  # ===========================================================================
  # Console History Rendering
  # ===========================================================================

  @typedoc """
  A segment for rendering console history in the terminal view.

  - `{:output, text}` - ANSI text to render (startup output, command output)
  - `{:command_line, prompt, command}` - A command line with prompt and command (styled differently)
  - `:restart_separator` - Visual separator indicating console restart
  """
  @type console_segment ::
          {:output, String.t()}
          | {:command_line, prompt :: String.t(), command :: String.t()}
          | :restart_separator

  @doc """
  Transforms console history blocks into render segments for the terminal view.

  This function converts domain data (ConsoleHistoryBlock structs) into view data
  (render segments) that the template can iterate and render with appropriate styling.

  ## Segment Types

  - `{:output, text}` - Plain ANSI text (startup banners, command output)
  - `{:command_line, prompt, command}` - Command line with prompt (highlighted differently)
  - `:restart_separator` - Red divider indicating console restart

  ## Examples

      iex> blocks = [
      ...>   %ConsoleHistoryBlock{type: :startup, output: "Banner\\n", prompt: "msf6 > "},
      ...>   %ConsoleHistoryBlock{type: :command, command: "help", output: "Help text\\n", prompt: "msf6 > "}
      ...> ]
      iex> Helpers.blocks_to_segments(blocks)
      [{:output, "Banner\\n"}, {:command_line, "msf6 > ", "help"}, {:output, "Help text\\n"}]

      iex> Helpers.blocks_to_segments([])
      []
  """
  @spec blocks_to_segments([ConsoleHistoryBlock.t()]) :: [console_segment()]
  def blocks_to_segments([]), do: []

  def blocks_to_segments(blocks) do
    blocks
    |> Enum.with_index()
    |> Enum.flat_map(fn {block, index} ->
      block_to_segments(block, index, blocks)
    end)
  end

  defp block_to_segments(%ConsoleHistoryBlock{type: :startup} = block, 0, _blocks) do
    # First startup block - just output
    [{:output, block.output}]
  end

  defp block_to_segments(%ConsoleHistoryBlock{type: :startup} = block, _index, _blocks) do
    # Non-first startup block - console restarted
    [:restart_separator, {:output, block.output}]
  end

  defp block_to_segments(%ConsoleHistoryBlock{type: :command} = block, index, blocks) do
    # Command block - get previous block's prompt for the command line
    previous_prompt = get_previous_prompt(blocks, index)

    segments = [{:command_line, previous_prompt, block.command}]

    # Add output if present
    if block.output != "" do
      segments ++ [{:output, block.output}]
    else
      segments
    end
  end

  defp get_previous_prompt(blocks, index) when index > 0 do
    case Enum.at(blocks, index - 1) do
      nil -> ""
      prev_block -> prev_block.prompt
    end
  end

  defp get_previous_prompt(_blocks, _index), do: ""

  # ===========================================================================
  # Track Form Helpers
  # ===========================================================================

  @doc """
  Validates that a track slug is unique within a container.

  ## Examples

      iex> changeset = Ecto.Changeset.change(%Track{}, %{slug: "unique-slug"})
      iex> container = %{id: 1}
      iex> # Assuming slug doesn't exist
      iex> result = Helpers.validate_track_slug_uniqueness(changeset, container)
      iex> result.errors
      []
  """
  @spec validate_track_slug_uniqueness(Changeset.t(), map() | nil) :: Changeset.t()
  def validate_track_slug_uniqueness(changeset, nil), do: changeset

  def validate_track_slug_uniqueness(changeset, container) do
    slug = Changeset.get_field(changeset, :slug)

    if slug && Tracks.slug_exists?(container, slug) do
      Changeset.add_error(changeset, :slug, "is already taken")
    else
      changeset
    end
  end

  @doc """
  Generates helper text for the track slug field showing the full URL.

  ## Examples

      iex> field = %{value: "my-track", errors: []}
      iex> Helpers.track_slug_helper(field, "test-workspace", "https://example.com")
      "https://example.com/test-workspace/my-track"

      iex> field = %{value: "", errors: []}
      iex> Helpers.track_slug_helper(field, "test-workspace", "https://example.com")
      "https://example.com/test-workspace/your-slug"
  """
  @spec track_slug_helper(map(), String.t(), String.t()) :: String.t()
  def track_slug_helper(field, workspace_slug, base_url) do
    slug = field.value
    has_errors = field.errors != []

    if slug && slug != "" && !has_errors do
      "#{base_url}/#{workspace_slug}/#{slug}"
    else
      "#{base_url}/#{workspace_slug}/your-slug"
    end
  end

  # ===========================================================================
  # Container Form Helpers
  # ===========================================================================

  @doc """
  Validates that a container slug is unique within a workspace.

  ## Examples

      iex> changeset = Ecto.Changeset.change(%ContainerRecord{}, %{slug: "unique-slug"})
      iex> workspace = %{id: 1}
      iex> # Assuming slug doesn't exist
      iex> result = Helpers.validate_container_slug_uniqueness(changeset, workspace)
      iex> result.errors
      []
  """
  @spec validate_container_slug_uniqueness(Changeset.t(), map()) :: Changeset.t()
  def validate_container_slug_uniqueness(changeset, workspace) do
    slug = Changeset.get_field(changeset, :slug)

    if slug && Containers.slug_exists?(workspace, slug) do
      Changeset.add_error(changeset, :slug, "is already taken")
    else
      changeset
    end
  end

  @doc """
  Generates helper text for the container slug field showing the Docker container name.

  ## Examples

      iex> field = %{value: "my-container", errors: []}
      iex> Helpers.container_slug_helper(field, "test-workspace")
      "Docker container: msfailab-test-workspace-my-container"

      iex> field = %{value: "", errors: []}
      iex> Helpers.container_slug_helper(field, "test-workspace")
      "Docker container: msfailab-test-workspace-your-slug"
  """
  @spec container_slug_helper(map(), String.t()) :: String.t()
  def container_slug_helper(field, workspace_slug) do
    slug = field.value
    has_errors = field.errors != []

    if slug && slug != "" && !has_errors do
      "Docker container: msfailab-#{workspace_slug}-#{slug}"
    else
      "Docker container: msfailab-#{workspace_slug}-your-slug"
    end
  end

  # ===========================================================================
  # Container Lookup
  # ===========================================================================

  @doc """
  Finds a container by ID in a list of containers.

  ## Examples

      iex> containers = [%{id: 1, name: "First"}, %{id: 2, name: "Second"}]
      iex> Helpers.find_container(containers, 2)
      %{id: 2, name: "Second"}

      iex> Helpers.find_container([], 1)
      nil
  """
  @spec find_container([map()], integer()) :: map() | nil
  def find_container(containers, container_id) do
    Enum.find(containers, &(&1.id == container_id))
  end
end
