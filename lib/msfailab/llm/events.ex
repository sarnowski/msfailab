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

defmodule Msfailab.LLM.Events do
  @moduledoc """
  Events emitted during LLM streaming responses.

  All events are sent to the caller as `{:llm, ref, event}` tuples, where:
  - `ref` is the reference returned by `LLM.chat/2`
  - `event` is one of the structs defined in this module

  ## Event Sequence

  A typical successful stream follows this sequence:

      StreamStarted
      ContentBlockStart (index: 0, type: :thinking)
      ContentDelta (index: 0, delta: "Let me...")
      ContentDelta (index: 0, delta: " analyze...")
      ContentBlockStop (index: 0)
      ContentBlockStart (index: 1, type: :text)
      ContentDelta (index: 1, delta: "Based on...")
      ContentBlockStop (index: 1)
      StreamComplete

  When tool calls are present:

      StreamStarted
      ContentBlockStart (index: 0, type: :text)
      ContentDelta (index: 0, delta: "I'll search...")
      ContentBlockStop (index: 0)
      ContentBlockStart (index: 1, type: :tool_call)
      ToolCall (index: 1, id: "call_1", name: "msf_command", arguments: %{...})
      ContentBlockStop (index: 1)
      StreamComplete (stop_reason: :tool_use)

  ## Error Handling

  If an error occurs during streaming, a `StreamError` event is sent instead
  of `StreamComplete`. The stream may have partial content blocks that were
  already emitted.

  ## Content Block Indices

  Each content block has a zero-based `index` that identifies it throughout
  its lifecycle (start, deltas, stop). Use this index to track accumulated
  content for each block separately.
  """

  defmodule StreamStarted do
    @moduledoc """
    Emitted when the LLM stream begins.

    This is always the first event in a stream sequence.
    """

    @type t :: %__MODULE__{
            model: String.t()
          }

    defstruct [:model]
  end

  defmodule ContentBlockStart do
    @moduledoc """
    Emitted when a new content block begins.

    Content blocks represent distinct pieces of output:
    - `:thinking` - Extended thinking/reasoning (may be hidden from users)
    - `:text` - Regular response text
    - `:tool_call` - Tool invocation (arguments streamed, then ToolCall emitted)

    The `index` is used to correlate subsequent `ContentDelta` and
    `ContentBlockStop` events with this block.
    """

    @type block_type :: :thinking | :text | :tool_call

    @type t :: %__MODULE__{
            index: non_neg_integer(),
            type: block_type()
          }

    defstruct [:index, :type]
  end

  defmodule ContentDelta do
    @moduledoc """
    Emitted when new content is available for a block.

    The `delta` contains the incremental text chunk. Accumulate deltas
    to build the complete content for a block.

    For `:tool_call` blocks, deltas contain the JSON arguments string
    which should be accumulated and parsed when the block completes.
    """

    @type t :: %__MODULE__{
            index: non_neg_integer(),
            delta: String.t()
          }

    defstruct [:index, :delta]
  end

  defmodule ContentBlockStop do
    @moduledoc """
    Emitted when a content block is complete.

    After this event, no more `ContentDelta` events will be emitted
    for this `index`. The accumulated content is now final.
    """

    @type t :: %__MODULE__{
            index: non_neg_integer()
          }

    defstruct [:index]
  end

  defmodule ToolCall do
    @moduledoc """
    Emitted when a tool call has been fully parsed.

    This event is emitted after the tool call's arguments have been
    completely streamed and parsed. It provides the structured data
    needed to execute the tool.

    The `index` corresponds to the content block that contained this
    tool call.
    """

    @type t :: %__MODULE__{
            index: non_neg_integer(),
            id: String.t(),
            name: String.t(),
            arguments: map()
          }

    defstruct [:index, :id, :name, :arguments]
  end

  defmodule StreamComplete do
    @moduledoc """
    Emitted when the stream completes successfully.

    This is the final event in a successful stream. It contains
    token usage metrics and the reason the model stopped.

    ## Stop Reasons

    - `:end_turn` - Model finished its response naturally
    - `:tool_use` - Model wants to execute tool calls
    - `:max_tokens` - Response was truncated due to token limit

    ## Token Metrics

    All token counts are normalized across providers:

    - `input_tokens` - Tokens in the request (prompt + messages)
    - `output_tokens` - Tokens generated by the model
    - `cached_input_tokens` - Input tokens served from cache (cost savings)
    - `cache_creation_tokens` - Tokens written to cache this request

    ## Cache Context

    The `cache_context` field contains provider-specific data that should
    be passed back in the next request's `cache_context` field to enable
    caching optimizations. This field is opaque - don't inspect or modify it.
    """

    @type stop_reason :: :end_turn | :tool_use | :max_tokens

    @type t :: %__MODULE__{
            input_tokens: non_neg_integer(),
            output_tokens: non_neg_integer(),
            cached_input_tokens: non_neg_integer() | nil,
            cache_creation_tokens: non_neg_integer() | nil,
            cache_context: term() | nil,
            stop_reason: stop_reason()
          }

    defstruct [
      :input_tokens,
      :output_tokens,
      :cached_input_tokens,
      :cache_creation_tokens,
      :cache_context,
      :stop_reason
    ]
  end

  defmodule StreamError do
    @moduledoc """
    Emitted when an error occurs during streaming.

    This event terminates the stream. Any content blocks that were
    already emitted may contain partial data.

    ## Recoverable Errors

    When `recoverable` is `true`, the error may be transient (e.g., rate
    limiting, network timeout) and retrying the request might succeed.

    When `recoverable` is `false`, the error is permanent (e.g., invalid
    API key, malformed request) and retrying won't help.
    """

    @type t :: %__MODULE__{
            reason: term(),
            recoverable: boolean()
          }

    defstruct [:reason, recoverable: false]
  end

  @type t ::
          StreamStarted.t()
          | ContentBlockStart.t()
          | ContentDelta.t()
          | ContentBlockStop.t()
          | ToolCall.t()
          | StreamComplete.t()
          | StreamError.t()
end
