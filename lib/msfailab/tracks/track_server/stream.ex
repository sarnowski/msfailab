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

defmodule Msfailab.Tracks.TrackServer.Stream do
  @moduledoc """
  Pure functions for LLM streaming content handling.

  This module handles the accumulation and rendering of LLM streaming content.
  It manages the mapping from LLM content block indices to chat entry positions
  and uses MDEx for incremental markdown rendering.

  ## Content Block Lifecycle

  ```
  ContentBlockStart ──► ContentDelta (multiple) ──► ContentBlockStop
         │                      │                          │
         ▼                      ▼                          ▼
    Allocate position    Append content,           Mark streaming=false,
    Create ChatEntry     render markdown           persist to DB
  ```

  ## Design

  All functions are pure - they take stream state and chat entries, returning
  new state, updated entries, and actions for the shell to execute.
  """

  alias Msfailab.Markdown
  alias Msfailab.Tracks.ChatEntry
  alias Msfailab.Tracks.TrackServer.State.Stream, as: StreamState

  @type action ::
          {:persist_message, pos_integer(), String.t() | nil, pos_integer(), map()}
          | :broadcast_chat_state

  @doc """
  Handles a content block start event.

  Allocates a position for the new block, creates a streaming ChatEntry,
  and initializes a streaming MDEx document.

  ## Parameters

  - `stream` - Current stream state
  - `entries` - Current chat entries
  - `index` - The LLM content block index
  - `type` - The content type (:thinking or :text)

  ## Returns

  `{new_stream, new_entries, actions}`
  """
  @spec block_start(StreamState.t(), [ChatEntry.t()], non_neg_integer(), :thinking | :text) ::
          {StreamState.t(), [ChatEntry.t()], [action()]}
  def block_start(%StreamState{} = stream, entries, index, type) do
    position = stream.next_position

    # Map type to message_type
    message_type =
      case type do
        :thinking -> :thinking
        :text -> :response
      end

    # Create streaming MDEx document for markdown rendering
    document = Markdown.new_streaming_document()

    # Create streaming entry with empty rendered HTML (not yet persisted)
    entry =
      case message_type do
        :thinking -> ChatEntry.assistant_thinking(Ecto.UUID.generate(), position, "", "", true)
        :response -> ChatEntry.assistant_response(Ecto.UUID.generate(), position, "", "", true)
      end

    # Update stream state
    new_stream = %StreamState{
      stream
      | blocks: Map.put(stream.blocks, index, position),
        documents: Map.put(stream.documents, position, document),
        next_position: position + 1
    }

    # Add entry to chat entries
    new_entries = entries ++ [entry]

    {new_stream, new_entries, [:broadcast_chat_state]}
  end

  @doc """
  Handles a content delta event.

  Appends the delta to the appropriate entry's content and re-renders markdown.

  ## Parameters

  - `stream` - Current stream state
  - `entries` - Current chat entries
  - `index` - The LLM content block index
  - `delta` - The content delta string

  ## Returns

  `{new_stream, new_entries, actions}`
  """
  @spec apply_delta(StreamState.t(), [ChatEntry.t()], non_neg_integer(), String.t()) ::
          {StreamState.t(), [ChatEntry.t()], [action()]}
  def apply_delta(%StreamState{} = stream, entries, index, delta) do
    case Map.get(stream.blocks, index) do
      nil ->
        # Unknown block, ignore
        {stream, entries, []}

      position ->
        # Get the streaming document for this position
        document = Map.get(stream.documents, position)

        if document do
          # Render markdown with the new delta
          {html, updated_document} = Markdown.put_and_render(document, delta)

          # Update stream state with new document
          new_stream = %StreamState{
            stream
            | documents: Map.put(stream.documents, position, updated_document)
          }

          # Update entry content and rendered HTML
          new_entries = append_delta_to_entry(entries, position, delta, html)

          {new_stream, new_entries, [:broadcast_chat_state]}
        else
          # Fallback: just append content without markdown rendering
          new_entries = append_delta_to_entry(entries, position, delta, nil)
          {stream, new_entries, [:broadcast_chat_state]}
        end
    end
  end

  @doc """
  Handles a content block stop event.

  Marks the entry as not streaming and returns an action to persist it.

  ## Parameters

  - `stream` - Current stream state
  - `entries` - Current chat entries
  - `index` - The LLM content block index
  - `track_id` - Track ID for persistence
  - `turn_id` - Current turn ID for persistence

  ## Returns

  `{new_stream, new_entries, actions}`
  """
  @spec block_stop(
          StreamState.t(),
          [ChatEntry.t()],
          non_neg_integer(),
          pos_integer(),
          String.t() | nil
        ) ::
          {StreamState.t(), [ChatEntry.t()], [action()]}
  def block_stop(%StreamState{} = stream, entries, index, track_id, turn_id) do
    case Map.get(stream.blocks, index) do
      nil ->
        # Unknown block, ignore
        {stream, entries, []}

      position ->
        # Find the entry and mark as not streaming
        {new_entries, persist_actions} =
          finish_streaming_entry(entries, position, track_id, turn_id)

        # Clean up the streaming document for this position
        new_stream = %StreamState{
          stream
          | documents: Map.delete(stream.documents, position)
        }

        {new_stream, new_entries, persist_actions ++ [:broadcast_chat_state]}
    end
  end

  @doc """
  Finalizes all streaming entries.

  Called when stream completes - marks all remaining streaming entries
  as not streaming and returns actions to persist them.

  ## Parameters

  - `stream` - Current stream state
  - `entries` - Current chat entries
  - `track_id` - Track ID for persistence
  - `turn_id` - Current turn ID for persistence

  ## Returns

  `{new_stream, new_entries, actions}`
  """
  @spec finalize(StreamState.t(), [ChatEntry.t()], pos_integer(), String.t() | nil) ::
          {StreamState.t(), [ChatEntry.t()], [action()]}
  def finalize(%StreamState{} = stream, entries, track_id, turn_id) do
    {new_entries, actions} =
      Enum.map_reduce(entries, [], fn entry, acc ->
        if entry.streaming and ChatEntry.message?(entry) do
          persist_action = build_persist_action(entry, track_id, turn_id)
          {%{entry | streaming: false}, [persist_action | acc]}
        else
          {entry, acc}
        end
      end)

    # Reset stream state
    new_stream = StreamState.reset(stream)

    {new_stream, new_entries, Enum.reverse(actions) ++ [:broadcast_chat_state]}
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp append_delta_to_entry(entries, position, delta, rendered_html) do
    Enum.map(entries, &maybe_append_delta(&1, position, delta, rendered_html))
  end

  defp maybe_append_delta(entry, position, delta, rendered_html) do
    if entry.position == position do
      do_append_delta(entry, delta, rendered_html)
    else
      entry
    end
  end

  defp do_append_delta(entry, delta, nil) do
    %{entry | content: (entry.content || "") <> delta}
  end

  defp do_append_delta(entry, delta, rendered_html) do
    %{entry | content: (entry.content || "") <> delta, rendered_html: rendered_html}
  end

  defp finish_streaming_entry(entries, position, track_id, turn_id) do
    Enum.map_reduce(entries, [], fn entry, acc ->
      if entry.position == position and ChatEntry.message?(entry) do
        persist_action = build_persist_action(entry, track_id, turn_id)
        {%{entry | streaming: false}, [persist_action | acc]}
      else
        {entry, acc}
      end
    end)
  end

  defp build_persist_action(entry, track_id, turn_id) do
    message_type_str = Atom.to_string(entry.message_type)
    role_str = Atom.to_string(entry.role)

    {:persist_message, track_id, turn_id, entry.position,
     %{role: role_str, message_type: message_type_str, content: entry.content}}
  end
end
