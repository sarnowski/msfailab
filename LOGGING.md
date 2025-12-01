# Logging Strategy

This document defines the logging approach for msfailab. Logs serve application operators and developers—not end users, who receive feedback through the UI.

## Architecture Overview

The application has two distinct logging systems:

1. **Application Logs** - Standard Logger output for operational visibility
2. **Trace Logs** - Development-only file dumps for debugging external system interactions

## Log Destinations by Environment

| Environment | Application Logs | Trace Logs |
|-------------|------------------|------------|
| `:prod` | stdout (12-factor) | disabled |
| `:dev` | stdout + `log/app.log` | `log/*.log` files |
| `:test` | silent (suppressed) | disabled |

In development, `app.log` is truncated on application start to keep it relevant to the current session.

## Application Log Levels

### error

Unrecoverable unexpected situations. The application cannot fix this automatically.

```elixir
Logger.error("Container failed to start after retries", container_id: id, attempts: 5)
Logger.error("Database connection lost", error: inspect(reason))
```

### warning

Recoverable unexpected situations. The application handles this automatically.

```elixir
Logger.warning("Console process crashed, restarting", console_id: id)
Logger.warning("MSGRPC connection lost, reconnecting", container_id: id)
```

### info

Runtime state changes. Use for lifecycle events of primary entities and ecosystem components.

**Log these:**
- Workspace/track/container lifecycle (created, started, stopped, deleted)
- External connections (Docker container started, MSGRPC connected)
- Knowledge base changes (host discovered, credential added, note created)

**Don't log these:**
- User interactions within a track (prompts, commands executed)
- Routine polling or heartbeat activity
- User input validation failures (UI handles feedback)

```elixir
Logger.info("Workspace created", workspace_id: id, name: name)
Logger.info("Container started", container_id: id, image: image)
Logger.info("Host discovered", host: ip, workspace_id: workspace_id)
```

### debug

Data flow tracing for development. Filtered out in production.

Use debug to trace function calls, state transitions, and data transformations. Include relevant parameters to understand the flow.

```elixir
Logger.debug("Processing console output", console_id: id, bytes: byte_size(data))
Logger.debug("State transition", from: old_state, to: new_state, reason: reason)
```

**Important:** Do not use debug for content that belongs in trace logs. Full command outputs and HTTP responses go to trace files, not the application log.

## Metadata

All log messages must include context metadata. Set metadata at the process level so all subsequent logs inherit it.

### Standard Metadata Keys

| Key | Description |
|-----|-------------|
| `workspace_id` | Current workspace UUID |
| `workspace_name` | Current workspace name |
| `track_id` | Current track UUID |
| `track_name` | Current track name |
| `container_id` | Container UUID |

### Setting Context

Set metadata early in process lifecycle:

```elixir
# In LiveView mount
def mount(%{"workspace" => workspace_name}, _session, socket) do
  Logger.metadata(workspace_id: workspace.id, workspace_name: workspace.name)
  # ...
end

# In GenServer init
def init(%{track: track}) do
  Logger.metadata(track_id: track.id, track_name: track.name)
  # ...
end
```

## Trace Logs (Development Only)

Trace logs capture full request/response data for debugging external system interactions. They are completely separate from the Logger system.

| File | Content |
|------|---------|
| `log/metasploit.log` | Console commands with prompt, command, and full output |
| `log/bash.log` | Shell commands with command, output, and exit code |
| `log/ollama.log` | Full HTTP request and response bodies |
| `log/openai.log` | Full HTTP request and response bodies |
| `log/anthropic.log` | Full HTTP request and response bodies |

Use the `Msfailab.Trace` module:

```elixir
# After a Metasploit command completes
Trace.metasploit(prompt, command, output)

# After a bash command completes
Trace.bash(command, output, exit_code)

# After an LLM API call completes
Trace.http(:ollama, request, response)
```

Trace functions are no-ops outside of `:dev`. Never duplicate trace content to Logger—trace files are the authoritative source for full dumps.

## Production Log Guidelines

Since production logs may be aggregated and searched, follow these guidelines:

1. **No sensitive data** - Never log credentials, tokens, API keys, or session identifiers at error/warning/info levels
2. **Structured metadata** - Use metadata keywords rather than interpolating values into message strings
3. **Actionable messages** - Error and warning messages should help operators understand what happened and what to do

```elixir
# Good - structured, actionable
Logger.error("Failed to connect to MSGRPC", container_id: id, reason: inspect(reason))

# Bad - unstructured, unhelpful
Logger.error("Something went wrong: #{inspect(error)}")
```
