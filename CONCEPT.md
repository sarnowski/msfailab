# Metasploit Framework AI Lab - Technical Concept

## 1. Vision

msfailab is a collaborative security research platform that augments penetration testing workflows with AI assistance. Built on Elixir/OTP/Phoenix with LiveView, it enables teams of security researchers to work together in real-time while leveraging AI agents that can observe, advise, and execute within Metasploit environments.

---

## 2. Core Architecture

### Technology Foundation

- **Elixir/OTP**: Provides fault-tolerant, concurrent process management ideal for handling multiple long-running research sessions
- **Phoenix Framework**: Web application layer with robust WebSocket support
- **LiveView**: Enables real-time UI updates without custom JavaScript, allowing researchers to see console output, AI responses, and collaborator actions instantly
- **Docker**: Isolated container environments for each research track

### Design Principles

- **Real-time by default**: All state changes propagate immediately to connected users
- **Process isolation**: Each track runs in its own supervised process tree and container
- **Shared knowledge, isolated execution**: Teams share intelligence while maintaining separate execution environments

---

## 3. Organizational Model

### Workspaces

A **workspace** is the top-level organizational unit representing a distinct engagement, project, or client.

| Aspect | Description |
|--------|-------------|
| **Isolation** | Complete data separation between workspaces; no cross-workspace data access |
| **URL Pattern** | `/<workspace-name>` |

#### Workspace Knowledge Base

Each workspace maintains its own persistent knowledge store:

- **Hosts**: Discovered systems, IP addresses, hostnames, OS fingerprints
- **Services**: Running services, ports, versions
- **Vulnerabilities**: Identified vulnerabilities linked to hosts/services
- **Credentials**: Captured or known credentials
- **Notes & Documentation**: Researcher observations, methodology notes, findings

This knowledge is synchronized from Metasploit databases across all tracks and enriched by researcher annotations.

---

### Tracks

A **track** is the primary interaction unit—an active research session where a researcher (or team) engages with Metasploit, shell environments, and an AI assistant.

| Aspect | Description |
|--------|-------------|
| **Purpose** | Focused investigation stream (e.g., "initial recon", "pivot to internal", "AD exploitation") |
| **Parallelism** | Multiple tracks can run simultaneously within a workspace |
| **URL Pattern** | `/<workspace-name>/<track-name>` |

Tracks enable researchers to pursue multiple attack paths concurrently while maintaining clear separation of context and history.

---

## 4. Track Environment

Each track operates within a dedicated, persistent Docker container that provides:

### Container Lifecycle

- **Long-running**: Containers persist for the track's lifetime (potentially weeks/months)
- **Restartable**: Containers can restart or update while preserving configuration and state
- **Metasploit Console**: `msfconsole` runs continuously within the container

### Execution Interfaces

| Interface | Description |
|-----------|-------------|
| **Metasploit Console** | Interactive `msfconsole` session with full command history |
| **Bash Shell** | General-purpose shell for auxiliary tools (`msfvenom`, `nmap`, custom scripts) |

Both interfaces are accessible to the user directly and to the AI assistant (subject to permission controls).

### File System Architecture

```
/home/                          # Workspace shared directory (read-only to tracks)
├── track-alpha/                # Track-specific directory (read-write for track-alpha)
└── track-bravo/                # Track-specific directory (read-write for track-bravo)

/workspace/                     # Mounted workspace data
├── loot/                       # Captured artifacts
└── uploads/                    # User-uploaded files
```

- Each track has read-write access to its own `/home/<track-name>` directory
- Each track has read-only access to all other track directories
- Enables sharing artifacts between tracks while preventing accidental overwrites

### File Operations

- **Upload to AI**: Attach images, documents, or data files to AI conversations for analysis
- **Upload to Container**: Transfer tools, payloads, or resources directly into the track's file system
- **File Browser**: Navigate container file system and download artifacts (loot, screenshots, exports)

---

## 5. AI Integration

### Multi-Provider Support

The platform integrates with multiple AI providers through a unified interface:

| Provider | Configuration |
|----------|---------------|
| **Ollama** | Local/self-hosted models |
| **OpenAI** | GPT-4, GPT-4o, etc. |
| **Anthropic** | Claude models |

- API keys and provider settings configured via environment variables
- Admin designates a default provider/model for new tracks
- Tracks can switch models at any time without losing conversation history

### AI Capabilities

The AI assistant within each track can:

1. **Observe**: See all console output and user prompts in real-time
2. **Respond**: Provide guidance, explanations, and suggestions to the researcher
3. **Execute**: Send commands to the Metasploit console or bash shell
4. **Access Knowledge**: Query and contribute to the workspace knowledge base
5. **Analyze Files**: Process uploaded images, documents, and data files

### Execution Control Modes

Users maintain control over AI autonomy:

| Mode | Behavior |
|------|----------|
| **Approval Required** | AI proposes commands; user approves or rejects before execution |
| **Autonomous** | AI executes commands directly (with configurable restrictions) |

Mode can be changed at any time during a track session.

### Context Window Management

Long-running tracks will accumulate history exceeding AI context limits. The platform implements intelligent context management:

- **Sliding window**: Recent conversation and console output always included
- **Knowledge extraction**: Key findings automatically extracted to workspace knowledge base
- **Summarization**: Older conversation segments compressed into summaries
- **Selective retrieval**: Relevant historical context pulled in based on current task
- **Session checkpoints**: Periodic state snapshots enabling context reconstruction

---

## 6. Real-Time Collaboration

### LiveView Architecture

Phoenix LiveView enables seamless real-time updates:

- Console output streams to all connected viewers instantly
- AI responses appear character-by-character as generated
- Multiple researchers can observe and interact with the same track
- Track status indicators show activity across the workspace

### Multi-Track Workflow

Researchers can:

- **Monitor multiple tracks**: Dashboard view showing activity across all workspace tracks
- **Quick switch**: Fluid navigation between tracks within a single LiveView; URLs pushed to browser history for proper back/forward navigation and deep linking
- **Notifications**: Alerts when significant events occur in background tracks
- **Concurrent AI sessions**: Run multiple AI-assisted investigations in parallel

---

## 7. URL Structure

Clean, hierarchical URLs reflecting the organizational model:

```
/                                   # Landing / workspace selection
/<workspace>                        # Workspace dashboard & knowledge base
/<workspace>/<track>                # Track interface (console + AI + files)
```

---

## 8. Security Considerations

### Isolation Boundaries

- **Workspace isolation**: No data leakage between workspaces at application and database level
- **Container isolation**: Each track runs in a separate Docker container with network policies
- **Anonymous by default**: No built-in authentication; operators can add access control via reverse proxy if needed

### AI Safety

- **Command approval**: Configurable gates before AI-initiated execution
- **Audit logging**: All AI commands logged with full context
- **Scope restrictions**: AI actions bounded to track's container and workspace knowledge

