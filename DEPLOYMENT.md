# Deployment Guide

This guide helps system administrators choose and configure the right msfailab deployment for their environment.

## Quick Recommendation

For production security research, deploy **Linux Release** on a **dedicated host**:

```bash
# Download configuration template
curl -o msfailab.conf https://raw.githubusercontent.com/sarnowski/msfailab/main/msfailab.conf.example

# Configure at least one AI backend
nano msfailab.conf

# Start msfailab (runs in background)
set -a && source msfailab.conf && set +a
docker compose -f oci://ghcr.io/sarnowski/msfailab-linux:latest up -d

# Stop msfailab
docker compose -f oci://ghcr.io/sarnowski/msfailab-linux:latest down
```

Read on to understand all deployment options and their trade-offs.

## Deployment Matrix

msfailab offers six deployment configurations across two dimensions:

### Dimension 1: Image Source

| Type | Description | Use Case |
|------|-------------|----------|
| **Release** | Pre-built images from GitHub Container Registry | Production, quick setup |
| **Local** | Build images from source code | Test modifications, contribute |
| **Dev** | App runs on host, only postgres in container | Active development |

### Dimension 2: Operating System / Network Mode

| OS | Network Mode | Limitations |
|----|--------------|-------------|
| **Linux** | Host network | None - full functionality |
| **macOS** | Bridge network | No inbound ports (reverse shells), no LAN binding |
| **WSL2** | Host network (Linux variant) | No inbound ports from Windows LAN |

### Configuration Files

| File | OS | Type | Description |
|------|-----|------|-------------|
| `compose.linux.release.yaml` | Linux/WSL | Release | **Recommended for production** |
| `compose.linux.local.yaml` | Linux/WSL | Local | Production setup, built from source |
| `compose.linux.dev.yaml` | Linux/WSL | Dev | Development with app on host |
| `compose.macos.release.yaml` | macOS | Release | Pre-built images for macOS |
| `compose.macos.local.yaml` | macOS | Local | Build from source on macOS |
| `compose.macos.dev.yaml` | macOS | Dev | Development on macOS |

## Choosing a Deployment

### Production Deployments

#### Linux Release (Recommended)

**Best for**: Security research teams, production pentesting engagements

```bash
# Start
docker compose -f oci://ghcr.io/sarnowski/msfailab-linux:latest up -d

# Stop
docker compose -f oci://ghcr.io/sarnowski/msfailab-linux:latest down
```

**Advantages:**
- Full network functionality (reverse shells, LAN binding)
- Pre-built images - no build tools required
- Tested, versioned releases
- Simplest setup

**Requirements:**
- Linux host (dedicated machine, VM, Raspberry Pi, cloud instance)
- Docker installed

#### Linux Local

**Best for**: Testing modifications before contributing, running unreleased features

```bash
git clone https://github.com/sarnowski/msfailab.git
cd msfailab

# Start
docker compose -f compose.linux.local.yaml up --build -d

# Stop
docker compose -f compose.linux.local.yaml down
```

**Advantages:**
- Full network functionality
- Run modified or bleeding-edge code
- Test changes in production-like environment

**Disadvantages:**
- Requires source checkout
- Requires build tools (longer initial startup)
- May contain unstable code

#### macOS Release

**Best for**: Individual researchers on Mac who don't need reverse shells

```bash
# Start
docker compose -f oci://ghcr.io/sarnowski/msfailab-macos:latest up -d

# Stop
docker compose -f oci://ghcr.io/sarnowski/msfailab-macos:latest down
```

**Advantages:**
- Works on macOS without Linux VM
- Pre-built images

**Limitations:**
- No inbound connections (reverse shells don't work)
- Web UI only accessible via localhost, not from LAN
- Bridge networking adds complexity

#### macOS Local

**Best for**: macOS users who need to modify code

```bash
git clone https://github.com/sarnowski/msfailab.git
cd msfailab

# Start
docker compose -f compose.macos.local.yaml up --build -d

# Stop
docker compose -f compose.macos.local.yaml down
```

Same limitations as macOS Release, plus requires build tools.

### Development Deployments

#### Linux Dev

**Best for**: Active development on Linux

```bash
# Start postgres and build msfconsole image
docker compose -f compose.linux.dev.yaml up --build -d

# First-time setup
mix setup

# Run app
mix phx.server

# Stop postgres
docker compose -f compose.linux.dev.yaml down
```

**Advantages:**
- Hot code reload
- Direct debugger access
- Full network functionality for msfconsole testing

#### macOS Dev

**Best for**: Active development on macOS

```bash
# Start postgres and build msfconsole image
docker compose -f compose.macos.dev.yaml up --build -d

# First-time setup
mix setup

# Run app
mix phx.server

# Stop postgres
docker compose -f compose.macos.dev.yaml down
```

**Advantages:**
- Hot code reload
- Direct debugger access
- Native macOS development experience

**Limitations:**
- msfconsole containers have limited network functionality

### WSL2 Users

WSL2 users should use the **Linux variants** (`compose.linux.*.yaml`). Docker runs natively in WSL2's Linux environment, and host networking works correctly within WSL2.

**Limitations:**
- Ports bound in WSL2 are accessible from Windows via `localhost`
- Ports are NOT accessible from other machines on the LAN
- Reverse shells from LAN targets will not reach msfconsole

**Workaround for LAN access:**
Configure Windows firewall port forwarding to route specific ports into WSL2. This requires manual Windows configuration and is outside the scope of this guide.

## Network Architecture

### Linux: Host Network Mode

All containers share the host's network namespace. Services control their exposure through bind address:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                              HOST NETWORK                                    │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐ │
│  │                        127.0.0.1 (private)                              │ │
│  │                                                                         │ │
│  │   ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐             │ │
│  │   │ postgres │   │   app    │   │ msf-1    │   │ msf-2    │             │ │
│  │   │  :5432   │◀─▶│  :4000   │◀─▶│  :55553  │   │  :55554  │  ...        │ │
│  │   └──────────┘   └──────────┘   └──────────┘   └──────────┘             │ │
│  │                                                                         │ │
│  │   Private services: postgres, MSGRPC (one port per msfconsole)          │ │
│  └─────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐ │
│  │                        0.0.0.0 (network-accessible)                     │ │
│  │                                                                         │ │
│  │   ┌──────────┐   ┌──────────┐   ┌──────────┐                            │ │
│  │   │   app    │   │  msf-1   │   │  msf-2   │                            │ │
│  │   │  :4000   │   │  :4444   │   │  :4445   │  reverse shells            │ │
│  │   │(optional)│   │   ...    │   │   ...    │  (dynamic, any port)       │ │
│  │   └──────────┘   └──────────┘   └──────────┘                            │ │
│  └─────────────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────────────┘
                                      │
                    ┌─────────────────┴─────────────────┐
                    ▼                                   ▼
           ┌─────────────────┐                ┌──────────────────┐
           │    Internet     │                │  Local Network   │
           │   (AI APIs)     │                │ (targets, shells)│
           └─────────────────┘                └──────────────────┘
```

**Key points:**
- `127.0.0.1` binding = private (only accessible from host)
- `0.0.0.0` binding = public (accessible from network)
- Each msfconsole gets a unique MSGRPC port (55553, 55554, ...)
- msfconsole can bind any port dynamically for reverse shells

### macOS: Bridge Network Mode

Containers run in an isolated Docker network. Port publishing forwards specific ports to the host:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              macOS HOST                                     │
│                                                                             │
│   localhost:4000 ─────────────────────────────────┐                         │
│   localhost:5432 ──────────────────────┐          │                         │
│                                        │          │                         │
│   ┌────────────────────────────────────┼──────────┼─────────────────────┐   │
│   │           Docker Desktop VM        │          │                     │   │
│   │                                    ▼          ▼                     │   │
│   │   ┌─────────────────────────────────────────────────────────────┐   │   │
│   │   │              Bridge Network                                 │   │   │
│   │   │                                                             │   │   │
│   │   │        ┌──────────┐   ┌──────────┐   ┌──────────┐           │   │   │
│   │   │        │ postgres │◀─▶│   app    │◀─▶│  msf-1   │           │   │   │
│   │   │        │  :5432   │   │  :4000   │   │  :55553  │           │   │   │
│   │   │        └──────────┘   └──────────┘   └──────────┘           │   │   │
│   │   │             ▲              ▲                                │   │   │
│   │   │             │              │                                │   │   │
│   │   └─────────────┼──────────────┼────────────────────────────────┘   │   │
│   │                 │              │                                    │   │
│   │           -p 5432:5432    -p 4000:4000                              │   │
│   │            (published)     (published)                              │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│   ❌ No inbound from LAN (reverse shells don't work)                        │
│   ❌ Web UI not accessible from LAN (only localhost)                        │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Key points:**
- Port publishing required for any port accessible from macOS host
- msfconsole containers can reach internet/LAN (outbound works)
- No inbound connections from LAN (Docker Desktop limitation)
- MSGRPC accessible via internal Docker network (no publishing needed)

## Security Considerations

### Dedicated Host Recommendation

We strongly recommend deploying msfailab on a **dedicated host** - a machine used exclusively for msfailab. This provides:

1. **Blast radius containment**: msfconsole containers receive reverse shells from potentially compromised targets. If an attacker pivots through a reverse connection, only the msfailab host is at risk.

2. **Port freedom**: msfailab dynamically binds ports for MSGRPC and reverse shells. A dedicated host eliminates port conflicts with other services.

3. **Simplified security**: Firewall rules can be tailored specifically for pentesting traffic.

**Suitable dedicated hosts:**
- Raspberry Pi or similar SBC
- Old laptop or desktop
- Cloud VM (AWS, GCP, Azure, DigitalOcean, etc.)
- Proxmox/VMware/Hyper-V virtual machine
- Dedicated server

### Shared Host Considerations

Running msfailab on a shared host (your daily workstation, a server with other services) is possible but introduces risks:

- Other services may be affected if msfailab is compromised
- Port conflicts may occur
- Firewall configuration becomes more complex

If you must share, consider running msfailab in a VM on that host.

### Port Security

| Service | Port | Bind Address | Security |
|---------|------|--------------|----------|
| SSH | 22 | 0.0.0.0 | Key-based auth only |
| PostgreSQL | 5432 | 127.0.0.1 | Never expose to network |
| Web UI | 4000 | Configurable | Auth proxy recommended for LAN |
| MSGRPC | 55553+ | 127.0.0.1 | Never expose to network |
| Reverse shells | Dynamic | 0.0.0.0 | Required for pentesting |

**Important:** MSGRPC uses simple password authentication not suitable for network exposure. Always bind to `127.0.0.1`.

### Firewall Configuration

Example `ufw` configuration for a dedicated Linux host:

```bash
# Default policies
ufw default deny incoming
ufw default allow outgoing

# SSH for administration
ufw allow 22/tcp

# Web UI (optional - omit for localhost-only)
ufw allow 4000/tcp

# Reverse shell port range (adjust as needed)
ufw allow 4444:5000/tcp
ufw allow 8080:8090/tcp

# Enable
ufw enable
```

## Configuration

### Environment Variables

All deployments use environment variables for configuration. Create a `msfailab.conf` file:

```bash
# AI Backend (at least one required)
MSFAILAB_OLLAMA_HOST=http://localhost:11434
# MSFAILAB_OPENAI_API_KEY=sk-...
# MSFAILAB_ANTHROPIC_API_KEY=sk-ant-...

# Web UI binding
# localhost only (default):
MSFAILAB_PORT=127.0.0.1:4000
# Or network accessible:
# MSFAILAB_PORT=0.0.0.0:4000

# Security (REQUIRED for production)
MSFAILAB_SECRET_KEY_BASE=<generate with: openssl rand -base64 48>
```

Load before running:
```bash
set -a && source msfailab.conf && set +a
docker compose -f <compose-file> up -d
```

See `msfailab.conf.example` for all available options.

### Model Filtering

Control which AI models are available:

```bash
# Default filters (restrictive)
MSFAILAB_OLLAMA_MODEL_FILTER=*                           # All Ollama models
MSFAILAB_OPENAI_MODEL_FILTER=gpt-5*                      # GPT-5 models only
MSFAILAB_ANTHROPIC_MODEL_FILTER=claude-opus-4*,claude-sonnet-4*  # Claude 4 only

# Example: Allow all models from all providers
MSFAILAB_OLLAMA_MODEL_FILTER=*
MSFAILAB_OPENAI_MODEL_FILTER=*
MSFAILAB_ANTHROPIC_MODEL_FILTER=*
```

## Troubleshooting

### All LLM Providers Return No Models

If you see:
```
provider=openai [warning] Provider returned no models
provider=anthropic [warning] Provider returned no models
```

Check:
1. **API keys are set** in environment before running docker compose
2. **Network connectivity** from container to API endpoints
3. **Model filters** aren't excluding all models (see Model Filtering above)

### Cannot Access Web UI

**Linux:** Check `MSFAILAB_PORT` binding and firewall rules.

**macOS:** Web UI is only accessible via `localhost:4000`, not from other machines on the LAN. This is a Docker Desktop limitation.

**WSL2:** Access via `localhost:4000` from Windows. Not accessible from other LAN machines without Windows port forwarding.

### Reverse Shells Not Working

**Linux:** Should work. Check firewall allows the port.

**macOS/WSL2:** Inbound connections from LAN don't reach containers. Workarounds:
- Use bind shells instead (msfconsole connects to target)
- Deploy to Linux for full functionality

### msfconsole Cannot Reach Targets

Check:
1. **Outbound connectivity** - can the container reach the internet?
2. **DNS resolution** - try IP addresses if hostnames fail
3. **Firewall** on target or intermediate networks

## Upgrading

### Release Deployments

Pull latest images and restart:

```bash
docker compose -f <compose-file> pull
docker compose -f <compose-file> up -d
```

### Local Deployments

Pull latest code and rebuild:

```bash
git pull
docker compose -f <compose-file> up --build -d
```

### Database Migrations

Migrations run automatically on startup via the `migrate` service. No manual intervention required for standard upgrades.

## Architecture Reference

### Services

| Service | Purpose | Managed By |
|---------|---------|------------|
| postgres | Database | Docker Compose |
| migrate | Run database migrations | Docker Compose (exits after completion) |
| server | msfailab web application | Docker Compose |
| msfconsole-image | Ensure msfconsole image exists | Docker Compose (exits after pull/build) |
| msfconsole-* | Metasploit containers | msfailab app (dynamic) |

### Volumes

| Volume | Purpose |
|--------|---------|
| postgres_data | PostgreSQL database files |

### Networks

| Config | Network | Purpose |
|--------|---------|---------|
| Linux | Host | All services share host network namespace |
| macOS | msfailab (bridge) | Isolated network with port publishing |
