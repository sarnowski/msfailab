---
name: debugging
description: "STOP guessing. Investigate systematically. Use when: user reports an issue or bug, says 'doesn't work'/'broken'/'error'/'failed', investigating test failures, analyzing unexpected behavior, tracking down root causes, verifying fixes. Covers: logs, Docker, database, and debugging strategy."
---

# Debugging

Systematic investigation beats code inspection. This skill equips you to find root causes efficiently.

## Debugging Strategy

Before diving into tools, establish the facts:

1. **Reproduce** - Can you trigger the issue? What are the exact steps?
2. **Isolate** - When did it last work? What changed?
3. **Observe** - What does the system actually do vs. what's expected?
4. **Hypothesize** - Form a theory, then test it with evidence

### Common Investigation Patterns

| Symptom | Start Here |
|---------|------------|
| "It doesn't work" | Ask user for exact error/behavior, check `log/app.log` |
| Test failure | Read the failure message, check test setup, run with `PRINT_LOGS=true` |
| UI not updating | Check `log/events.log` for PubSub events, verify backend state |
| Container issues | `docker ps`, `docker logs`, check container state |
| Data looks wrong | Query database directly, trace the write path in logs |
| Intermittent failure | Look for race conditions, check timing, add logging |

## Observation Tools

### Application Logs

All logs are in `/log/` and are truncated on app restart:

| File | Content |
|------|---------|
| `app.log` | Application Logger output (info/warning/error) |
| `events.log` | All PubSub events with full payload |
| `ollama.log` | Ollama HTTP requests/responses |
| `openai.log` | OpenAI HTTP requests/responses |
| `anthropic.log` | Anthropic HTTP requests/responses |

```bash
# Tail logs in real-time
tail -f log/app.log
tail -f log/events.log

# Search for specific patterns
grep -i error log/app.log
grep "container_id" log/events.log
```

### Docker Containers

```bash
# List running containers
docker ps

# Container naming:
#   msfailab-postgres     - PostgreSQL database
#   msfailab-msfconsole-* - Metasploit containers (1:1 with app containers)

# View container logs
docker logs msfailab-postgres
docker logs -f msfailab-msfconsole-<id>  # Follow mode

# Inspect container state
docker inspect <container>

# Execute commands inside container
docker exec -it msfailab-msfconsole-<id> /bin/bash
```

### Database

Query PostgreSQL directly using `psql`:

```bash
psql -h localhost -U postgres -d msfailab_dev
```

Read migrations in `/priv/repo/migrations/` to understand the schema before querying.

```sql
-- Example queries
\dt                           -- List tables
\d table_name                 -- Describe table
SELECT * FROM workspaces;
SELECT * FROM tracks WHERE workspace_id = '...';
```

## Investigation Checklist

1. **Check logs first** - Most issues leave traces in `app.log` or `events.log`
2. **Verify container state** - Use `docker ps` to confirm expected containers are running
3. **Query database** - Verify data state matches expectations
4. **Ask user to reproduce** - If above methods don't reveal the issue, ask the user to trigger it while you watch logs

## When to Ask the User

If logs and inspection don't show the issue:
- Ask the user to reproduce the problem
- Ask them to describe exact steps and expected vs actual behavior
- Watch `tail -f log/app.log log/events.log` while they reproduce

## After Finding the Bug: STOP

**This skill is for investigation only, not implementation.**

Once you've identified the root cause:

1. **Do NOT write the fix yet**
2. **Invoke the `development` skill**
3. Follow the Bug Fix workflow: write a failing test FIRST, then fix

The correct flow is:
```
debugging (find the bug) → development (test + fix) → finishing-work (verify)
```

Common mistake: Jumping straight from "I found it!" to writing the fix. This skips the regression test that prevents the bug from recurring.

**Exception:** If the fix is purely adding/modifying log statements with no behavioral changes, you can skip the development skill and go directly to finishing-work.

**WARNING: The logging exception is NOT a gateway.** If you start with logging but then find yourself:
- Adding or modifying functions
- Changing return types or error handling
- Fixing environment variable handling
- Refactoring any code path

**STOP immediately.** The scope has expanded beyond logging. Invoke the `development` skill before continuing. This is a common trap—don't rationalize "I already started" as permission to skip TDD.
