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

defmodule Msfailab.Repo.Migrations.CreateTracks do
  use Ecto.Migration

  def change do
    create table(:msfailab_tracks) do
      add :slug, :string, null: false
      add :name, :string, null: false
      add :current_model, :string
      add :autonomous, :boolean, null: false, default: false
      add :archived_at, :utc_datetime
      add :container_id, references(:msfailab_containers, on_delete: :restrict), null: false

      timestamps()
    end

    create index(:msfailab_tracks, [:container_id])
    create unique_index(:msfailab_tracks, [:container_id, :slug])

    # Console history blocks - persisted Metasploit console output
    execute(
      "CREATE TYPE msfailab_console_history_block_type AS ENUM ('startup', 'command')",
      "DROP TYPE msfailab_console_history_block_type"
    )

    create table(:msfailab_track_console_history_blocks) do
      add :type, :msfailab_console_history_block_type, null: false
      add :output, :text, null: false, default: ""
      add :prompt, :string, null: false, default: ""
      add :command, :text
      add :started_at, :utc_datetime_usec, null: false
      add :finished_at, :utc_datetime_usec, null: false
      add :track_id, references(:msfailab_tracks, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:msfailab_track_console_history_blocks, [:track_id])

    # =========================================================================
    # Chat History Schema
    # =========================================================================
    #
    # The chat feature enables AI-assisted security research within tracks.
    # See CHAT_SCHEMA.md for full documentation of the design.
    #
    # Key concepts:
    # - Track is the conversation: No separate conversation entity
    # - Turns represent agentic loops: One complete user-to-agent cycle
    # - Entries are the timeline: Immutable, position-ordered records
    # - Content tables provide type safety: Each entry type has its own table
    # - Compactions are separate entities: Summaries that replace older content
    # =========================================================================

    # Turns - agentic loop cycles (user prompt → LLM responses → tools → done)
    create table(:msfailab_track_chat_history_turns) do
      add :track_id, references(:msfailab_tracks, on_delete: :delete_all), null: false

      add :position, :integer, null: false

      # What started this turn
      add :trigger, :string, null: false
      # Values: "user_prompt", (future: "scheduled_prompt", "script_triggered")

      # Cyclical state machine (see CHAT_SCHEMA.md for diagram)
      add :status, :string, null: false, default: "pending"
      # Values: "pending", "streaming", "pending_approval", "executing_tools",
      #         "finished", "error", "interrupted"

      # Snapshot at turn creation (allows model changes mid-conversation)
      add :model, :string, null: false
      add :tool_approval_mode, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:msfailab_track_chat_history_turns, [:track_id])
    create index(:msfailab_track_chat_history_turns, [:track_id, :position])
    create index(:msfailab_track_chat_history_turns, [:track_id, :status])

    # LLM Responses - individual API calls within a turn
    create table(:msfailab_track_chat_history_llm_responses) do
      add :track_id, references(:msfailab_tracks, on_delete: :delete_all), null: false

      add :turn_id,
          references(:msfailab_track_chat_history_turns, on_delete: :delete_all),
          null: false

      add :model, :string, null: false

      # Normalized token metrics (provider-agnostic)
      add :input_tokens, :integer, null: false
      add :output_tokens, :integer, null: false
      add :cached_input_tokens, :integer
      add :cache_creation_tokens, :integer

      # Provider-specific cache context (e.g., Ollama's context token array)
      add :cache_context, :map

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:msfailab_track_chat_history_llm_responses, [:track_id])
    create index(:msfailab_track_chat_history_llm_responses, [:turn_id])

    # Entries - the conversation timeline (position-ordered)
    create table(:msfailab_track_chat_history_entries) do
      add :track_id, references(:msfailab_tracks, on_delete: :delete_all), null: false

      # Turn-scoped entries have turn_id; console_context doesn't
      add :turn_id,
          references(:msfailab_track_chat_history_turns, on_delete: :delete_all)

      # LLM-generated entries have llm_response_id
      add :llm_response_id,
          references(:msfailab_track_chat_history_llm_responses, on_delete: :nilify_all)

      # Chronological ordering - monotonic, immutable, track-scoped
      add :position, :integer, null: false

      # Type discriminator determines which content table holds payload
      add :entry_type, :string, null: false
      # Values: "message", "tool_invocation", "console_context"

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:msfailab_track_chat_history_entries, [:track_id, :position])
    create index(:msfailab_track_chat_history_entries, [:turn_id])
    create index(:msfailab_track_chat_history_entries, [:llm_response_id])
    create index(:msfailab_track_chat_history_entries, [:entry_type])

    # Messages - content for user prompts, AI thinking, AI responses
    create table(:msfailab_track_chat_messages, primary_key: false) do
      # Shared identity with Entry (1:1 relationship)
      add :entry_id,
          references(:msfailab_track_chat_history_entries, on_delete: :delete_all),
          primary_key: true

      add :role, :string, null: false
      # Values: "user", "assistant"

      add :message_type, :string, null: false
      # Values: "prompt", "thinking", "response"
      # Valid combinations: user+prompt, assistant+thinking, assistant+response

      add :content, :text, null: false, default: ""
    end

    # Tool Invocations - combined call + result for tool executions
    create table(:msfailab_track_chat_tool_invocations, primary_key: false) do
      add :entry_id,
          references(:msfailab_track_chat_history_entries, on_delete: :delete_all),
          primary_key: true

      # Call info (from LLM response)
      add :tool_call_id, :string, null: false
      add :tool_name, :string, null: false
      add :arguments, :map, null: false, default: %{}

      # Console prompt at time of tool call creation (for UI display)
      add :console_prompt, :string, null: false, default: ""

      # Lifecycle status
      add :status, :string, null: false, default: "pending"
      # Values: "pending", "approved", "denied", "executing", "success", "error", "timeout"

      # Result info (populated when execution completes)
      add :result_content, :text
      add :duration_ms, :integer
      add :error_message, :text
      add :denied_reason, :text
    end

    create index(:msfailab_track_chat_tool_invocations, [:tool_call_id])
    create index(:msfailab_track_chat_tool_invocations, [:status])

    # Console Contexts - user-initiated MSF console activity injected into conversation
    create table(:msfailab_track_chat_console_contexts, primary_key: false) do
      add :entry_id,
          references(:msfailab_track_chat_history_entries, on_delete: :delete_all),
          primary_key: true

      add :content, :text, null: false

      # Reference to source MSF console activity (ConsoleHistoryBlock uses integer IDs)
      add :console_history_block_id, :bigint
    end

    # Compactions - summaries that replace older conversation content
    create table(:msfailab_track_chat_compactions) do
      add :track_id, references(:msfailab_tracks, on_delete: :delete_all), null: false

      # The summary content
      add :content, :text, null: false

      # Entries with position <= this value are summarized by this compaction
      add :summarized_up_to_position, :integer, null: false

      # Audit chain - links to previous compaction for history
      add :previous_compaction_id,
          references(:msfailab_track_chat_compactions, on_delete: :nilify_all)

      # Metrics
      add :entries_summarized_count, :integer, null: false
      add :input_tokens_before, :integer, null: false
      add :input_tokens_after, :integer, null: false
      add :compaction_model, :string, null: false
      add :compaction_duration_ms, :integer

      timestamps(type: :utc_datetime_usec)
    end

    create index(:msfailab_track_chat_compactions, [:track_id])
    create index(:msfailab_track_chat_compactions, [:track_id, :inserted_at])
  end
end
