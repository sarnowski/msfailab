# Compaction Strategy

This document describes the advanced compaction strategy for managing long-running conversations in msfailab. It enables the impression of an endless, uninterrupted conversation across research sessions that may span months.

## Goals

1. **Seamless experience**: Users never notice compaction happening
2. **No workflow interruption**: Compaction runs in the background
3. **Cache efficiency**: Maximize LLM cache hits to reduce costs and latency
4. **No information loss for findings**: Critical discoveries are preserved
5. **Dynamic adaptation**: Scale to any context window size (32k to 1M+)
6. **Semantic relevance**: Old information surfaces when contextually relevant

## Memory Hierarchy

The system uses a tiered memory architecture where each tier has different persistence characteristics and cache behavior.

```
┌─────────────────────────────────────────────────────────────────┐
│                        MEMORY TIERS                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  TIER 1: STRUCTURED LONG-TERM MEMORY                            │
│  ════════════════════════════════════                           │
│  Source: Metasploit database                                     │
│  Contents: Hosts, services, vulnerabilities, credentials,        │
│            loots, notes, sessions                                │
│  Access: Via tool calls (msf_query_hosts, msf_query_services)   │
│  Cache impact: None (not in context, queried on demand)          │
│  Persistence: Permanent, survives across tracks                  │
│                                                                  │
│  TIER 2: WORKING MEMORY                                          │
│  ══════════════════════                                          │
│  Source: Track-level state                                       │
│  Contents: Current objectives, next steps, blockers, notes       │
│  Access: Included in system prompt or via tool                   │
│  Cache impact: Minimal (small, changes infrequently)             │
│  Persistence: Track lifetime                                     │
│                                                                  │
│  TIER 3: COMPACTED HISTORY                                       │
│  ═════════════════════════                                       │
│  Source: Background compaction of old conversation blocks        │
│  Contents: Summarized findings, actions, and outcomes            │
│  Access: Directly in conversation history                        │
│  Cache impact: Stable once created (part of cached prefix)       │
│  Persistence: Track lifetime (original blocks retained)          │
│                                                                  │
│  TIER 4: RECENT CONVERSATION                                     │
│  ═════════════════════════════                                   │
│  Source: Recent conversation blocks                              │
│  Contents: Full detail of recent turns                           │
│  Access: Directly in conversation history                        │
│  Cache impact: Append-only (excellent cache behavior)            │
│  Persistence: Track lifetime, becomes Tier 3 via compaction      │
│                                                                  │
│  TIER 5: RETRIEVED CONTEXT (RAG)                                 │
│  ═══════════════════════════════                                 │
│  Source: Vector similarity search on all historical blocks       │
│  Contents: Semantically relevant old blocks                      │
│  Access: Dynamically injected based on current query             │
│  Cache impact: None (appended fresh each request)                │
│  Persistence: N/A (retrieval, not storage)                       │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Cache-Friendly Context Assembly

LLM caching (Anthropic prompt caching, OpenAI automatic caching, Ollama context) works on **prefix matching**. To maximize cache hits, we structure messages as a stable prefix plus a dynamic suffix.

### The Cache Principle

```
REQUEST N:
┌────────────────────────────────────────┐
│ [System prompt]                        │ ◄─┐
│ [Compaction block 1]                   │   │
│ [Conversation blocks 1-50]             │   │ STABLE PREFIX
│ [Last user message from turn N-1]      │   │ (cached)
│ [Last assistant response from N-1]     │ ◄─┘
│ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─  │
│ [Retrieved context via RAG]            │ ◄─┐
│ [Unsynced console context]             │   │ DYNAMIC SUFFIX
│ [New user prompt]                      │ ◄─┘ (fresh)
└────────────────────────────────────────┘

REQUEST N+1:
┌────────────────────────────────────────┐
│ [System prompt]                        │ ◄─┐
│ [Compaction block 1]                   │   │
│ [Conversation blocks 1-50]             │   │
│ [Last user message from turn N-1]      │   │ CACHED
│ [Last assistant response from N-1]     │   │ (same as before)
│ [User prompt from turn N]              │   │ ◄── now part of prefix
│ [Assistant response from turn N]       │ ◄─┘
│ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─  │
│ [New retrieved context]                │ ◄─┐
│ [New user prompt]                      │ ◄─┘ FRESH
└────────────────────────────────────────┘
```

### What Goes Where

| Content Type | Position | Cache Behavior | Rationale |
|--------------|----------|----------------|-----------|
| System prompt | Start | Stable | Rarely changes |
| Compaction blocks | After system | Stable once created | Summarizes old history |
| Conversation blocks | Middle | Append-only | Each turn appends |
| Retrieved context (RAG) | Before new prompt | Fresh each request | Query-specific |
| Console context (unsynced) | Before new prompt | Fresh until synced | User activity between turns |
| New user prompt | End | Always fresh | Current input |

### Why Dynamic Content Goes at the End

If we inject dynamic content (RAG results, fresh MSF state) into the middle of the context, we break the cache for everything after it:

```
BAD: Dynamic content in middle
┌────────────────────────────────────────┐
│ [System prompt]                        │ ◄── cached
│ [MSF inventory: 5 hosts]               │ ◄── CHANGED! Cache broken
│ [Conversation blocks 1-50]             │ ◄── NOT cached (prefix changed)
│ [New user prompt]                      │
└────────────────────────────────────────┘

GOOD: Dynamic content at end
┌────────────────────────────────────────┐
│ [System prompt]                        │ ◄── cached
│ [Conversation blocks 1-50]             │ ◄── cached (prefix unchanged)
│ [MSF inventory: 5 hosts]               │ ◄── fresh (small)
│ [New user prompt]                      │ ◄── fresh
└────────────────────────────────────────┘
```

## Structured Memory via Tools

Instead of injecting Metasploit inventory into every request (which would break cache on every change), the AI queries it via tools when needed.

### System Prompt Approach

```
You are a security research assistant working with Metasploit Framework.

## Available Tools

### Metasploit Database Queries
- `msf_query_hosts`: List discovered hosts with OS and status
- `msf_query_services`: List services on a host or all hosts
- `msf_query_vulns`: List known vulnerabilities
- `msf_query_creds`: List captured credentials
- `msf_query_loots`: List collected loot files

### Command Execution
- `msf_command`: Execute Metasploit console command
- `bash_command`: Execute shell command

## Important Guidelines

Query the Metasploit database for current inventory when needed. The database
is the authoritative source for discovered assets and may have been updated
by other processes or manual user activity.

Do not rely solely on conversation history for inventory details—always
verify with a fresh query when accuracy matters.
```

### Benefits

1. **No cache invalidation**: MSF inventory changes don't affect conversation cache
2. **Fresh data**: AI always gets current state when it queries
3. **Selective retrieval**: AI only fetches what's relevant to the current task
4. **Audit trail**: Queries become part of conversation history

### Example Flow

```
User: "What SSH services did we find?"

AI thinks: I should query the database for current SSH services

AI: [tool_call] msf_query_services(port: 22)

System: [tool_result]
  - 192.168.1.10:22 SSH OpenSSH 7.4
  - 192.168.1.15:22 SSH OpenSSH 8.2
  - 192.168.1.20:22 SSH Dropbear

AI: "We've discovered SSH services on three hosts: ..."
```

The tool result is now part of the conversation and will be cached for future requests.

## RAG: Retrieval-Augmented Generation

RAG enables semantic search over all historical conversation blocks, surfacing relevant old information without keeping everything in context.

### How RAG Works

```
┌─────────────────────────────────────────────────────────────────┐
│                         INDEXING PHASE                          │
│                    (after each block is persisted)              │
└─────────────────────────────────────────────────────────────────┘

New block persisted:
  "Discovered SSH on 192.168.1.10, banner shows OpenSSH 7.4"
                    │
                    ▼
            ┌───────────────┐
            │ Embedding     │  (e.g., text-embedding-3-small)
            │ Model         │
            └───────┬───────┘
                    │
                    ▼
    [0.023, -0.156, 0.891, ..., 0.042]  ← Vector (1536 dimensions)
                    │
                    ▼
            ┌───────────────┐
            │ Vector DB     │  (pgvector in PostgreSQL)
            │ INSERT        │
            └───────────────┘


┌─────────────────────────────────────────────────────────────────┐
│                         RETRIEVAL PHASE                         │
│                    (before each LLM request)                    │
└─────────────────────────────────────────────────────────────────┘

User prompt: "What vulnerabilities affect the SSH services?"
                    │
                    ▼
            ┌───────────────┐
            │ Embedding     │
            │ Model         │
            └───────┬───────┘
                    │
                    ▼
    [0.019, -0.148, 0.902, ..., 0.038]  ← Query vector
                    │
                    ▼
            ┌───────────────┐
            │ Vector DB     │  Cosine similarity search
            │ SELECT        │  ORDER BY embedding <=> query_vector
            │ TOP K         │  LIMIT 5
            └───────┬───────┘
                    │
                    ▼
    Retrieved blocks (most similar first):

    1. "OpenSSH 7.4 vulnerable to CVE-2018-15473 user enumeration"
       Similarity: 0.92

    2. "Discovered SSH on 192.168.1.10, banner shows OpenSSH 7.4"
       Similarity: 0.87

    3. "SSH authentication bypass attempt on 192.168.1.10 failed"
       Similarity: 0.81
```

### Semantic vs Keyword Search

| Query | Keyword Search | Semantic Search (RAG) |
|-------|---------------|----------------------|
| "SSH vulnerabilities" | Finds "SSH" AND "vulnerabilities" | Finds related concepts |
| | ✓ "SSH vulnerability found" | ✓ "SSH vulnerability found" |
| | ✗ "OpenSSH CVE-2018-15473" | ✓ "OpenSSH CVE-2018-15473" |
| | ✗ "remote shell exploit" | ✓ "remote shell exploit" |

### When to Use RAG

RAG is most valuable when:
- Conversation history is large (many compactions have occurred)
- User asks about topics from long ago
- Current query relates to earlier work semantically

RAG is not needed when:
- Conversation is short (everything fits in context)
- Query is about recent activity (already in recent window)
- Query is about structured data (use MSF database instead)

### RAG Configuration

```elixir
# Per-track RAG settings
%{
  enabled: true,
  max_retrieved_blocks: 5,
  min_similarity_score: 0.75,
  exclude_recent_positions: 20,  # Don't retrieve what's already in context
  block_types_to_index: [:user_prompt, :response, :tool_result]
}
```

### Injecting Retrieved Context

Retrieved blocks are formatted and injected before the new user prompt:

```
[...conversation history...]

[system] Relevant context from earlier in this research session:

> Earlier discussion about SSH:
> "Discovered SSH on 192.168.1.10, banner shows OpenSSH 7.4"
> "OpenSSH 7.4 is vulnerable to CVE-2018-15473 (user enumeration)"

[user] What vulnerabilities affect the SSH services?
```

## Background Compaction

Compaction runs asynchronously, never interrupting the user's workflow.

### Compaction Lifecycle

```
┌─────────────────────────────────────────────────────────────────┐
│                   COMPACTION STATE MACHINE                       │
└─────────────────────────────────────────────────────────────────┘

                         MONITORING
                            │
              ┌─────────────┼─────────────┐
              │             │             │
              ▼             ▼             ▼
         Count tokens   Check model   Identify
         in context     thresholds    candidates
              │             │             │
              └─────────────┼─────────────┘
                            │
                            ▼
                    ┌───────────────┐
                    │ Threshold     │
                    │ exceeded?     │
                    └───────┬───────┘
                            │
                   No ──────┼────── Yes
                   │        │        │
                   ▼        │        ▼
                 IDLE       │    SCHEDULED
                   ▲        │        │
                   │        │        ▼
                   │        │    ┌───────────────┐
                   │        │    │ Start async   │
                   │        │    │ compaction    │
                   │        │    │ job           │
                   │        │    └───────┬───────┘
                   │        │            │
                   │        │            ▼
                   │        │      IN_PROGRESS
                   │        │            │
                   │        │      ┌─────┴─────┐
                   │        │      │           │
                   │        │      ▼           ▼
                   │        │   Success     Failure
                   │        │      │           │
                   │        │      ▼           ▼
                   │        │   COMPLETED   FAILED
                   │        │      │           │
                   └────────┴──────┴───────────┘
                            │
                            ▼
                    Track continues
                    normally throughout
```

### Threshold Configuration

Thresholds are dynamic based on model context window:

```elixir
def compaction_thresholds(model) do
  context_window = LLM.get_model(model).context_window

  %{
    # Start preparing compaction candidates
    prepare_threshold: floor(context_window * 0.60),

    # Trigger background compaction
    trigger_threshold: floor(context_window * 0.70),

    # Hard limit - must wait for compaction if exceeded
    hard_limit: floor(context_window * 0.80),

    # Protected recent window (never compact)
    recent_window: floor(context_window * 0.30)
  }
end

# Examples by model size:
#
# 32k model (small Ollama):
#   prepare: 19k, trigger: 22k, hard: 25k, recent: 9k
#
# 128k model (GPT-4, Claude):
#   prepare: 76k, trigger: 89k, hard: 102k, recent: 38k
#
# 200k model (Claude):
#   prepare: 120k, trigger: 140k, hard: 160k, recent: 60k
```

### Selecting Blocks to Compact

Not all blocks are eligible for compaction:

```elixir
def select_compactable_blocks(track_id, opts) do
  thresholds = compaction_thresholds(opts[:model])

  # Get all non-compacted, synced blocks
  all_blocks =
    from(b in Block,
      where: b.track_id == ^track_id,
      where: is_nil(b.compacted_by_block_id),
      where: b.ai_synced == true,
      order_by: b.position
    )
    |> Repo.all()

  # Calculate token counts
  total_tokens = estimate_tokens(all_blocks)

  if total_tokens < thresholds.trigger_threshold do
    {:skip, :below_threshold}
  else
    # Find the split point: protect recent_window tokens
    {older, recent} = split_at_token_budget(all_blocks, thresholds.recent_window)

    if length(older) < 10 do
      {:skip, :insufficient_blocks}
    else
      {:ok, older, recent}
    end
  end
end

defp split_at_token_budget(blocks, budget) do
  # Work backwards from end, accumulating until budget reached
  {recent, older} =
    blocks
    |> Enum.reverse()
    |> Enum.reduce_while({[], 0}, fn block, {recent, tokens} ->
      block_tokens = estimate_tokens(block)
      new_total = tokens + block_tokens

      if new_total <= budget do
        {:cont, {[block | recent], new_total}}
      else
        {:halt, {recent, tokens}}
      end
    end)

  older = blocks -- recent
  {older, recent}
end
```

### Compaction Job

The compaction runs as an async job (Oban or Task):

```elixir
defmodule Msfailab.Tracks.CompactionWorker do
  use Oban.Worker, queue: :compaction, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"track_id" => track_id, "block_ids" => block_ids}}) do
    # 1. Load blocks to compact
    blocks = load_blocks(block_ids)

    # 2. Build summarization prompt
    prompt = build_compaction_prompt(blocks)

    # 3. Call LLM (can use cheaper model)
    {:ok, summary} = LLM.complete(
      model: "gpt-4o-mini",  # Cheaper model for summarization
      messages: [%{role: :user, content: prompt}],
      max_tokens: 4000
    )

    # 4. Create compaction block and mark originals
    {:ok, compaction_block} = create_compaction_block(track_id, blocks, summary)
    mark_blocks_compacted(block_ids, compaction_block.id)

    # 5. Notify TrackServer
    TrackServer.compaction_complete(track_id, compaction_block.id)

    :ok
  end
end
```

### Compaction Prompt

The prompt instructs the LLM to preserve critical information:

```elixir
def build_compaction_prompt(blocks) do
  formatted_blocks = format_blocks_for_summary(blocks)

  """
  You are summarizing a segment of a security research conversation for
  future context. The summary will replace the original messages in the
  AI's context window.

  ## Requirements

  PRESERVE with exact details:
  - IP addresses, hostnames, ports
  - Discovered services and versions
  - CVE identifiers and vulnerability names
  - Credentials (usernames, password hints - not full passwords)
  - File paths and loot locations
  - Key commands that produced important results
  - Failed attempts and why they failed
  - Decisions made and their rationale

  OMIT:
  - Verbose tool output (keep conclusions only)
  - Thinking/reasoning that led to obvious conclusions
  - Repeated information
  - Small talk or acknowledgments

  ## Output Format

  Structure the summary as:

  ### Findings
  Concrete discoveries with specific details.

  ### Actions Taken
  What was done, including successful and failed attempts.

  ### Current State
  Where things stand at the end of this segment.

  ### Open Questions
  Unresolved items or next steps mentioned.

  ---

  ## Conversation Segment to Summarize

  #{formatted_blocks}
  """
end
```

### Transparency to User

The user never sees compaction happening:

```
USER EXPERIENCE:

10:00 AM - User working normally
           [Background: Token count at 65%]

10:15 AM - User sends prompt, gets response
           [Background: Token count at 72%, compaction triggered]

10:16 AM - User sends another prompt
           [Background: Compaction running on blocks 1-200]
           [Foreground: Request uses blocks 1-500 as normal]

10:17 AM - User gets response
           [Background: Compaction complete]

10:18 AM - User sends prompt
           [Context now: compaction_block + blocks 201-520]
           [User notices nothing different]
```

### Handling Concurrent Requests

If a user sends a request while compaction is in progress:

```elixir
def build_llm_context(track_id) do
  case get_compaction_status(track_id) do
    :idle ->
      # Normal: use current blocks
      build_context_from_blocks(track_id)

    :in_progress ->
      # Compaction running: use current blocks (not yet compacted)
      # The compaction will apply to next request after it completes
      build_context_from_blocks(track_id)

    :completed_pending_swap ->
      # Compaction done but not yet applied: apply it now
      apply_pending_compaction(track_id)
      build_context_from_blocks(track_id)
  end
end
```

## Context Budget Allocation

The context window is divided into budgets for each tier:

```
┌────────────────────────────────────────────────────────────────┐
│                    CONTEXT BUDGET (128k example)               │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  ┌──────────────────────────────────────┐                      │
│  │ System prompt + tool definitions     │  ~5k tokens          │
│  │ (fixed)                              │                      │
│  └──────────────────────────────────────┘                      │
│                                                                │
│  ┌──────────────────────────────────────┐                      │
│  │ Working memory                       │  ~2k tokens          │
│  │ (objectives, notes)                  │                      │
│  └──────────────────────────────────────┘                      │
│                                                                │
│  ┌──────────────────────────────────────┐                      │
│  │ Compaction summaries                 │  ~15k tokens         │
│  │ (grows slowly over months)           │  (can have multiple) │
│  └──────────────────────────────────────┘                      │
│                                                                │
│  ┌──────────────────────────────────────┐                      │
│  │ Recent conversation                  │  ~55k tokens         │
│  │ (protected window, full detail)      │                      │
│  └──────────────────────────────────────┘                      │
│                                                                │
│  ┌──────────────────────────────────────┐                      │
│  │ RAG retrieved context                │  ~5k tokens          │
│  │ (0-5 blocks, query-specific)         │                      │
│  └──────────────────────────────────────┘                      │
│                                                                │
│  ┌──────────────────────────────────────┐                      │
│  │ New user prompt                      │  ~1k tokens          │
│  └──────────────────────────────────────┘                      │
│                                                                │
│  ════════════════════════════════════════                      │
│  TOTAL USED: ~83k (65%)                                        │
│  RESERVED FOR RESPONSE: ~25k (20%)                             │
│  BUFFER: ~20k (15%)                                            │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

### Dynamic Scaling by Model

```elixir
def allocate_context_budget(model) do
  context_window = LLM.get_model(model).context_window

  # Fixed allocations
  fixed = %{
    system_prompt: 5_000,
    working_memory: 2_000,
    new_prompt_estimate: 1_000
  }

  # Percentage-based allocations
  usable = context_window - fixed.system_prompt - fixed.working_memory - fixed.new_prompt_estimate

  %{
    system_prompt: fixed.system_prompt,
    working_memory: fixed.working_memory,
    compaction: min(floor(usable * 0.15), 30_000),
    recent_conversation: floor(usable * 0.55),
    rag_retrieved: min(floor(usable * 0.10), 10_000),
    response_reserve: floor(context_window * 0.20)
  }
end

# Results by model size:
#
# 32k model:
#   compaction: 3k, recent: 13k, rag: 2k, reserve: 6k
#
# 128k model:
#   compaction: 15k, recent: 55k, rag: 10k, reserve: 25k
#
# 200k model:
#   compaction: 25k, recent: 90k, rag: 10k, reserve: 40k
```

## Complete Message Assembly

Here's the full algorithm for building an LLM request:

```elixir
defmodule Msfailab.Tracks.ContextBuilder do
  @moduledoc """
  Assembles LLM context with cache-friendly structure.
  """

  def build_messages(track_id, user_prompt, opts \\ []) do
    track = Tracks.get_track!(track_id)
    budget = allocate_context_budget(track.current_model)

    # ══════════════════════════════════════════════════════════
    # SECTION 1: STABLE PREFIX (cacheable)
    # ══════════════════════════════════════════════════════════

    # 1a. System message
    system_message = build_system_message(track, budget)

    # 1b. Compaction blocks (if any)
    compaction_blocks = get_compaction_blocks(track_id)

    # 1c. Conversation history (synced blocks only)
    conversation_blocks =
      from(b in Block,
        where: b.track_id == ^track_id,
        where: is_nil(b.compacted_by_block_id),
        where: b.ai_synced == true,
        where: b.type != "compaction",  # Handled separately
        order_by: b.position
      )
      |> Repo.all()

    # Combine into cached prefix
    cached_prefix =
      [system_message] ++
      blocks_to_messages(compaction_blocks) ++
      blocks_to_messages(conversation_blocks)

    # ══════════════════════════════════════════════════════════
    # SECTION 2: DYNAMIC SUFFIX (fresh each request)
    # ══════════════════════════════════════════════════════════

    dynamic_suffix = []

    # 2a. RAG retrieval (if enabled and beneficial)
    if opts[:enable_rag] && should_use_rag?(track_id, user_prompt) do
      retrieved = retrieve_relevant_blocks(
        track_id,
        user_prompt,
        limit: 5,
        min_score: 0.75,
        exclude_positions: recent_positions(conversation_blocks, 20)
      )

      if retrieved != [] do
        dynamic_suffix = dynamic_suffix ++ [
          format_retrieved_context(retrieved)
        ]
      end
    end

    # 2b. Unsynced console context (user MSF activity)
    unsynced_console =
      from(b in Block,
        where: b.track_id == ^track_id,
        where: b.ai_synced == false,
        where: b.type == "console_context",
        order_by: b.position
      )
      |> Repo.all()

    if unsynced_console != [] do
      dynamic_suffix = dynamic_suffix ++ blocks_to_messages(unsynced_console)
    end

    # 2c. New user prompt
    dynamic_suffix = dynamic_suffix ++ [
      %{role: :user, content: user_prompt}
    ]

    # ══════════════════════════════════════════════════════════
    # COMBINE AND RETURN
    # ══════════════════════════════════════════════════════════

    all_messages = cached_prefix ++ dynamic_suffix

    # Track IDs to mark as synced after successful LLM call
    unsynced_block_ids =
      unsynced_console
      |> Enum.map(& &1.id)

    %{
      messages: all_messages,
      unsynced_block_ids: unsynced_block_ids,
      token_estimate: estimate_tokens(all_messages),
      cache_prefix_tokens: estimate_tokens(cached_prefix)
    }
  end

  defp format_retrieved_context(blocks) do
    formatted =
      blocks
      |> Enum.map(fn {block, score} ->
        "> #{block.type}: #{String.slice(block.content, 0, 500)}"
      end)
      |> Enum.join("\n\n")

    %{
      role: :user,
      content: """
      [CONTEXT] Relevant information from earlier in this research session:

      #{formatted}

      [END CONTEXT]
      """
    }
  end
end
```

## Concrete Examples

### Example 1: Fresh Conversation (No Compaction Yet)

Turn 3 of a new track:

```
┌─────────────────────────────────────────────────────────────────┐
│ LLM REQUEST - Turn 3                                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│ ═══ SYSTEM MESSAGE ═════════════════════════════════════════    │
│                                                                 │
│ You are a security research assistant...                        │
│ [tool definitions]                                              │
│                                                                 │
│ Current objectives: (none set)                                  │
│                                                                 │
│ ═══ CONVERSATION HISTORY ═══════════════════════════════════    │
│                                                                 │
│ [user] Let's scan 192.168.1.0/24                                │
│                                                                 │
│ [assistant] I'll run a comprehensive scan...                    │
│ [tool_call] msf_command("db_nmap -sV 192.168.1.0/24")           │
│                                                                 │
│ [tool_result] Nmap scan report...                               │
│ Discovered 5 hosts, 23 services...                              │
│                                                                 │
│ [assistant] The scan found 5 active hosts. Here's the summary:  │
│ - 192.168.1.1: Router (SSH, HTTP)                               │
│ - 192.168.1.10: Linux server (SSH, HTTP, MySQL)                 │
│ ...                                                             │
│                                                                 │
│ [user] Focus on .10, what services are there?                   │
│                                                                 │
│ [assistant] Let me get the details...                           │
│ [tool_call] msf_query_services(host: "192.168.1.10")            │
│                                                                 │
│ [tool_result] Services on 192.168.1.10:                         │
│ - 22/tcp: SSH OpenSSH 7.4                                       │
│ - 80/tcp: HTTP Apache 2.4.6                                     │
│ - 3306/tcp: MySQL 5.7.32                                        │
│                                                                 │
│ [assistant] Host 192.168.1.10 has three services exposed...     │
│                                                                 │
│ ─── NEW (this request) ─────────────────────────────────────    │
│                                                                 │
│ [user] Any known vulnerabilities for these services?            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

Token breakdown:
  System: 2,000
  History: 1,500
  New prompt: 50
  Total: 3,550

Cache status:
  All of system + history is now cached for next request
```

### Example 2: After First Compaction

Turn 25, after compaction of turns 1-15:

```
┌─────────────────────────────────────────────────────────────────┐
│ LLM REQUEST - Turn 25                                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│ ═══ SYSTEM MESSAGE ═════════════════════════════════════════    │
│                                                                 │
│ You are a security research assistant...                        │
│ [tool definitions]                                              │
│                                                                 │
│ Current objectives:                                             │
│ 1. Escalate privileges on 192.168.1.10                          │
│ 2. Find lateral movement opportunities                          │
│                                                                 │
│ ═══ COMPACTED HISTORY ══════════════════════════════════════    │
│                                                                 │
│ [compaction] ## Session Summary (Turns 1-15)                    │
│                                                                 │
│ ### Findings                                                    │
│ - Network 192.168.1.0/24 scanned, 5 hosts discovered            │
│ - Primary target: 192.168.1.10 (Linux, SSH/HTTP/MySQL)          │
│ - SSH version: OpenSSH 7.4 (CVE-2018-15473 confirmed)           │
│ - Valid SSH credentials: admin:admin123                         │
│ - MySQL accessible with default root credentials                │
│ - Web app at /admin has SQL injection in login                  │
│                                                                 │
│ ### Actions Taken                                               │
│ - Network reconnaissance completed                              │
│ - SSH user enumeration via CVE-2018-15473                       │
│ - SSH brute force successful                                    │
│ - Initial shell obtained as 'admin' user                        │
│                                                                 │
│ ### Current State                                               │
│ - Have SSH access as admin (non-root)                           │
│ - Need privilege escalation                                     │
│                                                                 │
│ ═══ RECENT CONVERSATION (Turns 16-24) ══════════════════════    │
│                                                                 │
│ [user] Check for SUID binaries                                  │
│                                                                 │
│ [assistant] I'll search for SUID binaries...                    │
│ [tool_call] bash_command("find / -perm -4000 2>/dev/null")      │
│                                                                 │
│ [tool_result] /usr/bin/sudo                                     │
│ /usr/bin/passwd                                                 │
│ /usr/local/bin/backup                                           │
│ ...                                                             │
│                                                                 │
│ [assistant] Found an interesting SUID binary: /usr/local/bin/   │
│ backup. This is non-standard and worth investigating.           │
│                                                                 │
│ [user] Analyze that backup binary                               │
│ ...                                                             │
│ [8 more turns of recent conversation]                           │
│ ...                                                             │
│                                                                 │
│ ─── NEW ────────────────────────────────────────────────────    │
│                                                                 │
│ [user] Can we exploit the backup binary?                        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

Token breakdown:
  System: 2,200
  Compaction: 800
  Recent (turns 16-24): 5,000
  New prompt: 50
  Total: 8,050

Cache status:
  System + compaction + recent = all cached
  Next request appends to this prefix
```

### Example 3: With RAG Retrieval

Turn 50, user asks about something from early in the session:

```
┌─────────────────────────────────────────────────────────────────┐
│ LLM REQUEST - Turn 50                                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│ ═══ SYSTEM MESSAGE ═════════════════════════════════════════    │
│ (cached)                                                        │
│                                                                 │
│ ═══ COMPACTED HISTORY ══════════════════════════════════════    │
│                                                                 │
│ [compaction] ## Summary (Turns 1-15)                            │
│ (cached - same as before)                                       │
│                                                                 │
│ [compaction] ## Summary (Turns 16-35)                           │
│ ### Findings                                                    │
│ - Privilege escalation via backup SUID binary successful        │
│ - Root access obtained on 192.168.1.10                          │
│ - Found /etc/shadow hashes                                      │
│ - Discovered internal network 10.0.0.0/24                       │
│ - Pivoting configured via SSH tunnel                            │
│ ...                                                             │
│ (cached)                                                        │
│                                                                 │
│ ═══ RECENT CONVERSATION (Turns 36-49) ══════════════════════    │
│ [14 turns of internal network exploration]                      │
│ (cached)                                                        │
│                                                                 │
│ ─── DYNAMIC SECTION (fresh) ────────────────────────────────    │
│                                                                 │
│ [context] Relevant information from earlier:                    │
│                                                                 │
│ > Turn 8 (response): "The SQL injection in /admin login         │
│ > allows authentication bypass. Payload: ' OR '1'='1"           │
│ >                                                               │
│ > Turn 12 (tool_result): "MySQL query returned user table:      │
│ > id=1, username=admin, password_hash=5f4dcc3b..."              │
│                                                                 │
│ [user] What was that SQL injection we found on the web app?     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

Token breakdown:
  System: 2,200
  Compaction 1: 800
  Compaction 2: 1,200
  Recent: 12,000
  RAG retrieved: 400
  New prompt: 50
  Total: 16,650

Cache breakdown:
  Cached prefix: 16,200 tokens (everything before RAG)
  Fresh: 450 tokens (RAG + prompt)
  Cache hit rate: 97%
```

### Example 4: Console Context Injection

User ran MSF commands while AI was executing tools:

```
┌─────────────────────────────────────────────────────────────────┐
│ LLM REQUEST - Turn 28                                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│ ═══ SYSTEM + COMPACTED + RECENT HISTORY ════════════════════    │
│ (cached prefix from previous request)                           │
│                                                                 │
│ [assistant] I'll run the exploit now...                         │
│ [tool_call] msf_command("exploit -j")                           │ ◄─ CACHED
│                                                                 │
│ ─── DYNAMIC SECTION ────────────────────────────────────────    │
│                                                                 │
│ [console_context]                                               │
│ While AI was working, user ran:                                 │ ◄─ FRESH
│ msf6 > services -p 445                                          │   (unsynced
│ Services                                                        │    console
│ ========                                                        │    activity)
│ host          port  proto  name  state  info                    │
│ ----          ----  -----  ----  -----  ----                    │
│ 192.168.1.20  445   tcp    smb   open   Windows Server 2016     │
│                                                                 │
│ [tool_result]                                                   │ ◄─ FRESH
│ Exploit completed. Session 1 opened.                            │    (tool
│ Meterpreter session 1 opened (192.168.1.5:4444 ->               │    result)
│ 192.168.1.10:49721)                                             │
│                                                                 │
│ [user] Great! I also found SMB on .20, can we pivot there?      │ ◄─ NEW
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

The AI now sees:
1. Its tool call (cached)
2. User's MSF activity during execution (injected)
3. The tool result (fresh)
4. User's new prompt referencing both

This provides full context for a coherent response.
```

## Schema Requirements

### Database Tables

See SCHEMA.md for full schema. Key additions for compaction:

```elixir
# Track-level compaction state
alter table(:msfailab_tracks) do
  add :compaction_status, :string, default: "idle"
  # Values: "idle", "scheduled", "in_progress", "completed_pending_swap"

  add :last_compaction_at, :utc_datetime_usec
  add :compaction_job_id, :string  # Oban job reference
end

# Block embeddings for RAG (optional, requires pgvector)
create table(:msfailab_track_chat_history_block_embeddings) do
  add :block_id, references(:msfailab_track_chat_history_blocks,
                            type: :binary_id, on_delete: :delete_all),
      null: false

  add :embedding, :vector, size: 1536  # OpenAI embedding dimension
  add :model, :string, null: false     # Embedding model used

  timestamps(type: :utc_datetime_usec, updated_at: false)
end

create unique_index(:msfailab_track_chat_history_block_embeddings, [:block_id])
```

### Compaction Block Metadata

```elixir
# Enhanced metadata for compaction blocks
%{
  "blocks_summarized_count" => 45,
  "input_tokens_before" => 85000,
  "input_tokens_after" => 4000,
  "compression_ratio" => 0.047,  # 4000/85000

  "block_range" => %{
    "first_position" => 1,
    "last_position" => 145,
    "first_id" => "uuid-1",
    "last_id" => "uuid-145"
  },

  "time_range" => %{
    "first_timestamp" => "2025-01-15T10:00:00Z",
    "last_timestamp" => "2025-01-15T14:30:00Z"
  },

  "turns_summarized" => [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],

  "compaction_model" => "gpt-4o-mini",
  "compaction_duration_ms" => 3500
}
```

## Process Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      PROCESS OVERVIEW                           │
└─────────────────────────────────────────────────────────────────┘

Msfailab.Supervisor
│
├── Tracks.Supervisor
│   └── TrackServer (per track)
│       ├── Monitors token usage
│       ├── Triggers compaction when threshold reached
│       ├── Receives compaction completion notification
│       └── Builds LLM context with ContextBuilder
│
├── Compaction.Supervisor
│   └── Oban (job processor)
│       └── CompactionWorker
│           ├── Runs asynchronously
│           ├── Uses separate LLM call
│           └── Notifies TrackServer on completion
│
└── RAG.Supervisor (optional)
    ├── EmbeddingWorker
    │   └── Generates embeddings for new blocks
    └── VectorStore
        └── Manages pgvector queries
```

## Summary

This compaction strategy provides:

| Feature | Benefit |
|---------|---------|
| **Memory tiers** | Right storage for right data (MSF DB, working memory, conversation) |
| **Cache-friendly structure** | Stable prefix + dynamic suffix maximizes cache hits |
| **Background compaction** | Never interrupts user workflow |
| **RAG retrieval** | Old relevant details surface when needed |
| **Dynamic scaling** | Adapts to any context window (32k to 1M+) |
| **Tool-based inventory** | MSF state queried fresh, not cached stale |
| **Seamless experience** | User perceives infinite, uninterrupted conversation |

The key principles:

1. **Append-only conversation history** for cache efficiency
2. **Compact old blocks** to make room for new ones
3. **Query structured data** via tools, not context injection
4. **Retrieve semantically** when user asks about old topics
5. **Run compaction in background** to avoid workflow interruption
