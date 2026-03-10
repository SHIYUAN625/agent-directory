# NATS JetStream Design for Autonomous Enterprise

This document describes the NATS JetStream configuration for durable task queues, event streaming, and inter-agent communication.

## Overview

NATS JetStream provides:
- **Durable task queues** - Tasks survive agent/VM failures
- **Event streaming** - Real-time observability
- **Reliable delivery** - Exactly-once semantics with ack/nak
- **Consumer groups** - Work distribution across agent instances

## Subject Hierarchy

```
autonomy.                           # Root namespace
├── tasks.                          # Task queues (JetStream streams)
│   ├── tasks.code-review           # Code review tasks
│   ├── tasks.analysis              # Analysis tasks
│   ├── tasks.coordination          # Coordinator tasks
│   ├── tasks.generic               # Generic worker tasks
│   └── tasks.{agent-type}          # Type-specific queues
│
├── events.                         # Real-time event streams
│   ├── events.agent.{id}           # Per-agent event stream
│   ├── events.all                  # Aggregated events (for dashboards)
│   └── events.audit                # Audit events (immutable log)
│
├── escalations.                    # Escalation routing
│   ├── escalations.team.engineering
│   ├── escalations.team.security
│   ├── escalations.department.product
│   └── escalations.human           # Final escalation to operators
│
├── results.                        # Task results
│   └── results.{task-id}           # Result for specific task
│
├── control.                        # Control plane
│   ├── control.agent.{id}.commands # Commands to specific agent
│   ├── control.broadcast           # Broadcast to all agents
│   └── control.shutdown            # Graceful shutdown signals
│
└── state.                          # Shared state (for coordinators)
    ├── state.missions.{id}         # Mission state
    └── state.workforce             # Workforce status
```

## JetStream Configuration

### Streams

#### Task Streams

```yaml
# tasks-code-review stream
name: TASKS_CODE_REVIEW
subjects:
  - "tasks.code-review"
  - "tasks.code-review.>"
storage: file
retention: workqueue           # Messages deleted after ack
max_msgs: 100000
max_bytes: 1073741824          # 1GB
max_age: 86400s                # 24 hours
max_msg_size: 1048576          # 1MB per message
duplicate_window: 120s         # 2 minutes dedup window
replicas: 3                    # HA across 3 nodes
```

```yaml
# tasks-analysis stream
name: TASKS_ANALYSIS
subjects:
  - "tasks.analysis"
  - "tasks.analysis.>"
storage: file
retention: workqueue
max_msgs: 50000
max_bytes: 536870912           # 512MB
max_age: 86400s
max_msg_size: 1048576
replicas: 3
```

```yaml
# tasks-coordination stream
name: TASKS_COORDINATION
subjects:
  - "tasks.coordination"
  - "tasks.coordination.>"
storage: file
retention: workqueue
max_msgs: 10000
max_bytes: 268435456           # 256MB
max_age: 172800s               # 48 hours (coordinators may take longer)
max_msg_size: 4194304          # 4MB (larger for mission context)
replicas: 3
```

```yaml
# tasks-generic stream
name: TASKS_GENERIC
subjects:
  - "tasks.generic"
  - "tasks.generic.>"
storage: file
retention: workqueue
max_msgs: 500000
max_bytes: 2147483648          # 2GB
max_age: 86400s
max_msg_size: 1048576
replicas: 3
```

#### Event Streams

```yaml
# events stream (all agent events)
name: EVENTS
subjects:
  - "events.>"
storage: file
retention: limits              # Keep events for analysis
max_msgs: 10000000
max_bytes: 10737418240         # 10GB
max_age: 604800s               # 7 days
max_msg_size: 65536            # 64KB per event
replicas: 3
```

```yaml
# audit stream (immutable audit log)
name: AUDIT
subjects:
  - "events.audit"
  - "events.audit.>"
storage: file
retention: limits
max_msgs: -1                   # No limit
max_bytes: -1                  # No limit
max_age: 0                     # Never expire
max_msg_size: 65536
replicas: 3
deny_delete: true              # Immutable
deny_purge: true               # Immutable
```

#### Escalation Streams

```yaml
# escalations stream
name: ESCALATIONS
subjects:
  - "escalations.>"
storage: file
retention: workqueue
max_msgs: 10000
max_bytes: 268435456           # 256MB
max_age: 172800s               # 48 hours
max_msg_size: 4194304          # 4MB (includes trajectory)
replicas: 3
```

### Consumers

#### Task Queue Consumers

Each agent type has a durable consumer for its task queue:

```yaml
# Consumer for code-review agents
name: code-reviewer
stream: TASKS_CODE_REVIEW
durable: code-reviewer
deliver_policy: all
ack_policy: explicit
ack_wait: 300s                 # 5 min timeout
max_deliver: 3                 # Max retries
filter_subject: "tasks.code-review"
max_ack_pending: 10            # Concurrent tasks per consumer
```

```yaml
# Consumer for analysis agents
name: analyst
stream: TASKS_ANALYSIS
durable: analyst
deliver_policy: all
ack_policy: explicit
ack_wait: 600s                 # 10 min timeout
max_deliver: 3
filter_subject: "tasks.analysis"
max_ack_pending: 5
```

```yaml
# Consumer for coordinator agents
name: coordinator
stream: TASKS_COORDINATION
durable: coordinator
deliver_policy: all
ack_policy: explicit
ack_wait: 1800s                # 30 min timeout
max_deliver: 2                 # Fewer retries for complex tasks
filter_subject: "tasks.coordination"
max_ack_pending: 3
```

#### Event Consumers

```yaml
# Dashboard consumer (all events)
name: dashboard
stream: EVENTS
durable: dashboard
deliver_policy: new            # Only new events
ack_policy: none               # No ack needed for streaming
replay_policy: instant
filter_subject: "events.all"
```

```yaml
# Per-agent consumer (for agent's own events)
name: agent-{id}
stream: EVENTS
durable: agent-{id}
deliver_policy: last           # Resume from last position
ack_policy: none
filter_subject: "events.agent.{id}"
```

## Message Formats

### Task Message

```json
{
  "id": "task-uuid-here",
  "type": "code-review",
  "priority": 100,
  "created_at": "2024-01-15T10:30:00Z",
  "expires_at": "2024-01-15T22:30:00Z",
  "source": {
    "agent_id": "coordinator-001",
    "mission_id": "mission-uuid"
  },
  "payload": {
    "repository": "org/repo",
    "pull_request": 123,
    "files": ["src/main.py", "tests/test_main.py"],
    "context": "Review for security issues and code quality"
  },
  "requirements": {
    "min_trust_level": 2,
    "required_capabilities": ["urn:agent:capability:code:review"],
    "required_tools": ["git.cli", "filesystem.read"]
  },
  "reply_to": "results.task-uuid-here",
  "checkpoint_id": null
}
```

### Event Message

```json
{
  "id": "event-uuid",
  "timestamp": "2024-01-15T10:30:05Z",
  "agent_id": "worker-001",
  "task_id": "task-uuid",
  "type": "tool_execution",
  "data": {
    "tool": "git.cli",
    "arguments": ["diff", "HEAD~1"],
    "duration_ms": 1234,
    "exit_code": 0
  },
  "metrics": {
    "memory_mb": 512,
    "cpu_percent": 25
  }
}
```

### Escalation Message

```json
{
  "id": "escalation-uuid",
  "timestamp": "2024-01-15T10:35:00Z",
  "source_agent": "worker-001",
  "task": {
    "id": "task-uuid",
    "type": "code-review",
    "payload": {}
  },
  "reason": "blocked",
  "error": "Cannot access repository: permission denied",
  "trajectory": {
    "session_id": "session-uuid",
    "steps": [],
    "usage": {"input_tokens": 5000, "output_tokens": 1000}
  },
  "attempted_resolutions": [
    "Retry with different credentials",
    "Request elevated permissions"
  ]
}
```

### Result Message

```json
{
  "task_id": "task-uuid",
  "agent_id": "worker-001",
  "completed_at": "2024-01-15T10:45:00Z",
  "status": "success",
  "result": {
    "review_status": "approved",
    "comments": [
      {"file": "src/main.py", "line": 42, "message": "Consider error handling"}
    ],
    "overall_score": 0.85
  },
  "trajectory_id": "trajectory-uuid",
  "usage": {
    "input_tokens": 15000,
    "output_tokens": 2000,
    "duration_seconds": 120
  }
}
```

## Agent Integration

### Agent Boot Sequence

```python
import nats
from nats.js import JetStreamContext

async def agent_boot(agent_config):
    # 1. Connect to NATS
    nc = await nats.connect(
        servers=["nats://nats.autonomy.local:4222"],
        user=agent_config.nats_user,
        password=agent_config.nats_password,
    )
    js = nc.jetstream()

    # 2. Get durable consumer for agent type
    consumer_name = f"agent-{agent_config.agent_type}"
    stream_name = f"TASKS_{agent_config.agent_type.upper()}"

    # 3. Subscribe to task queue
    sub = await js.pull_subscribe(
        subject=f"tasks.{agent_config.agent_type}",
        durable=consumer_name,
        stream=stream_name,
    )

    # 4. Subscribe to control commands
    await nc.subscribe(
        f"control.agent.{agent_config.agent_id}.commands",
        cb=handle_control_command
    )

    # 5. Subscribe to broadcast commands
    await nc.subscribe(
        "control.broadcast",
        cb=handle_control_command
    )

    return nc, js, sub
```

### Task Processing Loop

```python
async def process_tasks(sub: JetStreamContext, agent: Agent):
    while agent.running:
        try:
            # Fetch task with timeout
            msgs = await sub.fetch(batch=1, timeout=30)

            for msg in msgs:
                task = Task.from_json(msg.data)

                # Check if resuming from checkpoint
                if task.checkpoint_id:
                    trajectory = await load_checkpoint(task.checkpoint_id)
                else:
                    trajectory = Trajectory()

                try:
                    # Process task
                    result = await agent.execute(task, trajectory)

                    # Publish result
                    await nc.publish(
                        task.reply_to,
                        result.to_json()
                    )

                    # Ack task
                    await msg.ack()

                except Retry as e:
                    # Retry with backoff
                    await msg.nak(delay=e.backoff_seconds)

                except Fail as e:
                    # Escalate to coordinator
                    await escalate(task, e, trajectory)
                    await msg.ack()  # Don't redeliver

                except Exception as e:
                    # Unexpected error - let NATS redeliver
                    await msg.nak()

        except TimeoutError:
            # No tasks, continue polling
            continue
```

### Event Publishing

```python
async def publish_event(nc, agent_id: str, event_type: str, data: dict):
    event = {
        "id": str(uuid4()),
        "timestamp": datetime.utcnow().isoformat(),
        "agent_id": agent_id,
        "type": event_type,
        "data": data,
    }

    # Publish to per-agent stream
    await nc.publish(
        f"events.agent.{agent_id}",
        json.dumps(event).encode()
    )

    # Also publish to aggregated stream
    await nc.publish(
        "events.all",
        json.dumps(event).encode()
    )
```

## Monitoring

### Key Metrics

- **Stream depth**: Messages waiting in each task queue
- **Consumer lag**: Difference between stream position and consumer position
- **Ack latency**: Time from message delivery to acknowledgment
- **Redelivery rate**: Rate of nak'd messages
- **Error rate**: Messages that exceed max_deliver

### Example Prometheus Queries

```promql
# Task queue depth
nats_jetstream_stream_messages{stream="TASKS_CODE_REVIEW"}

# Consumer lag
nats_jetstream_consumer_pending{consumer="code-reviewer"}

# Processing latency (p99)
histogram_quantile(0.99, sum(rate(agent_task_duration_seconds_bucket[5m])) by (le, agent_type))

# Escalation rate
sum(rate(nats_jetstream_stream_messages{stream="ESCALATIONS"}[5m]))
```

## Deployment Configuration

### NATS Server Config

```conf
# nats-server.conf
listen: 0.0.0.0:4222
server_name: nats-1

jetstream {
    store_dir: /data/jetstream
    max_memory_store: 4GB
    max_file_store: 100GB
}

cluster {
    name: agent-cluster
    listen: 0.0.0.0:6222
    routes: [
        nats://nats-2:6222
        nats://nats-3:6222
    ]
}

authorization {
    users: [
        # Provisioning service (admin)
        {user: provisioner, password: "$2a$...", permissions: {publish: ">", subscribe: ">"}}

        # Coordinator agents
        {user: coordinator, password: "$2a$...", permissions: {
            publish: ["tasks.>", "events.>", "results.>", "escalations.>", "state.>"],
            subscribe: ["tasks.coordination", "control.>", "escalations.>", "state.>"]
        }}

        # Worker agents
        {user: worker, password: "$2a$...", permissions: {
            publish: ["events.>", "results.>", "escalations.>"],
            subscribe: ["tasks.generic", "tasks.code-review", "tasks.analysis", "control.>"]
        }}

        # Dashboard (read-only)
        {user: dashboard, password: "$2a$...", permissions: {
            subscribe: ["events.>", "state.>"]
        }}
    ]
}
```

### Stream Creation Script

```bash
#!/bin/bash
# create-streams.sh

NATS_URL="nats://nats.autonomy.local:4222"

# Create task streams
nats stream add TASKS_CODE_REVIEW \
    --subjects "tasks.code-review,tasks.code-review.>" \
    --storage file \
    --retention workqueue \
    --max-msgs 100000 \
    --max-bytes 1GB \
    --max-age 24h \
    --max-msg-size 1MB \
    --replicas 3 \
    --server "$NATS_URL"

nats stream add TASKS_ANALYSIS \
    --subjects "tasks.analysis,tasks.analysis.>" \
    --storage file \
    --retention workqueue \
    --max-msgs 50000 \
    --max-bytes 512MB \
    --max-age 24h \
    --replicas 3 \
    --server "$NATS_URL"

nats stream add TASKS_COORDINATION \
    --subjects "tasks.coordination,tasks.coordination.>" \
    --storage file \
    --retention workqueue \
    --max-msgs 10000 \
    --max-bytes 256MB \
    --max-age 48h \
    --max-msg-size 4MB \
    --replicas 3 \
    --server "$NATS_URL"

nats stream add TASKS_GENERIC \
    --subjects "tasks.generic,tasks.generic.>" \
    --storage file \
    --retention workqueue \
    --max-msgs 500000 \
    --max-bytes 2GB \
    --max-age 24h \
    --replicas 3 \
    --server "$NATS_URL"

# Create event stream
nats stream add EVENTS \
    --subjects "events.>" \
    --storage file \
    --retention limits \
    --max-msgs 10000000 \
    --max-bytes 10GB \
    --max-age 7d \
    --max-msg-size 64KB \
    --replicas 3 \
    --server "$NATS_URL"

# Create audit stream (immutable)
nats stream add AUDIT \
    --subjects "events.audit,events.audit.>" \
    --storage file \
    --retention limits \
    --max-msgs=-1 \
    --max-bytes=-1 \
    --replicas 3 \
    --deny-delete \
    --deny-purge \
    --server "$NATS_URL"

# Create escalation stream
nats stream add ESCALATIONS \
    --subjects "escalations.>" \
    --storage file \
    --retention workqueue \
    --max-msgs 10000 \
    --max-bytes 256MB \
    --max-age 48h \
    --max-msg-size 4MB \
    --replicas 3 \
    --server "$NATS_URL"

echo "Streams created successfully"
```

## Durable Execution Pattern

### Checkpoint to PostgreSQL

```python
async def checkpoint_trajectory(
    task_id: str,
    trajectory: Trajectory,
    db: AsyncSession
):
    """Save trajectory checkpoint for crash recovery."""
    checkpoint = TrajectoryCheckpoint(
        task_id=task_id,
        agent_id=trajectory.agent_id,
        session_id=trajectory.session_id,
        events=trajectory.to_dict(),
        usage=trajectory.usage,
        created_at=datetime.utcnow(),
    )
    db.add(checkpoint)
    await db.commit()

    return checkpoint.id
```

### Resume from Checkpoint

```python
async def resume_task(
    task: Task,
    db: AsyncSession
) -> Trajectory:
    """Resume task from last checkpoint if exists."""
    checkpoint = await db.query(TrajectoryCheckpoint).filter(
        TrajectoryCheckpoint.task_id == task.id
    ).order_by(
        TrajectoryCheckpoint.created_at.desc()
    ).first()

    if checkpoint:
        return Trajectory.from_dict(checkpoint.events)

    return Trajectory()
```

This design provides durable, scalable task execution with automatic failover and resume capabilities.
