"""
Metrics collection for autonomous enterprise monitoring.
"""

from dataclasses import dataclass, field
from datetime import datetime, timedelta
from typing import Any, Dict, List, Optional
from collections import defaultdict
import asyncio
import json
import logging

logger = logging.getLogger(__name__)


@dataclass
class AgentMetrics:
    """Metrics for a single agent."""
    agent_id: str
    agent_type: str
    trust_level: int = 2

    # Task metrics
    tasks_processed: int = 0
    tasks_completed: int = 0
    tasks_failed: int = 0
    tasks_escalated: int = 0

    # Performance metrics
    avg_task_duration_ms: float = 0
    total_llm_tokens: int = 0
    total_tool_calls: int = 0

    # Current state
    current_task: Optional[str] = None
    state: str = "idle"
    last_heartbeat: datetime = field(default_factory=datetime.utcnow)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "agent_id": self.agent_id,
            "agent_type": self.agent_type,
            "trust_level": self.trust_level,
            "tasks_processed": self.tasks_processed,
            "tasks_completed": self.tasks_completed,
            "tasks_failed": self.tasks_failed,
            "tasks_escalated": self.tasks_escalated,
            "avg_task_duration_ms": self.avg_task_duration_ms,
            "total_llm_tokens": self.total_llm_tokens,
            "total_tool_calls": self.total_tool_calls,
            "current_task": self.current_task,
            "state": self.state,
            "last_heartbeat": self.last_heartbeat.isoformat(),
        }


@dataclass
class QueueMetrics:
    """Metrics for a task queue."""
    queue_name: str
    depth: int = 0
    in_flight: int = 0
    completed_last_hour: int = 0
    failed_last_hour: int = 0
    avg_wait_time_ms: float = 0
    avg_processing_time_ms: float = 0

    def to_dict(self) -> Dict[str, Any]:
        return {
            "queue_name": self.queue_name,
            "depth": self.depth,
            "in_flight": self.in_flight,
            "completed_last_hour": self.completed_last_hour,
            "failed_last_hour": self.failed_last_hour,
            "avg_wait_time_ms": self.avg_wait_time_ms,
            "avg_processing_time_ms": self.avg_processing_time_ms,
        }


@dataclass
class SystemMetrics:
    """System-wide metrics."""
    timestamp: datetime = field(default_factory=datetime.utcnow)

    # Agent counts
    total_agents: int = 0
    agents_idle: int = 0
    agents_working: int = 0
    agents_blocked: int = 0
    agents_offline: int = 0

    # Task counts
    total_tasks_pending: int = 0
    total_tasks_in_progress: int = 0
    tasks_completed_today: int = 0
    tasks_failed_today: int = 0

    # Queue depths
    queue_depths: Dict[str, int] = field(default_factory=dict)

    # Escalations
    pending_escalations: int = 0
    escalations_today: int = 0

    # Resource usage
    total_llm_tokens_today: int = 0
    total_tool_executions_today: int = 0

    def to_dict(self) -> Dict[str, Any]:
        return {
            "timestamp": self.timestamp.isoformat(),
            "agents": {
                "total": self.total_agents,
                "idle": self.agents_idle,
                "working": self.agents_working,
                "blocked": self.agents_blocked,
                "offline": self.agents_offline,
            },
            "tasks": {
                "pending": self.total_tasks_pending,
                "in_progress": self.total_tasks_in_progress,
                "completed_today": self.tasks_completed_today,
                "failed_today": self.tasks_failed_today,
            },
            "queues": self.queue_depths,
            "escalations": {
                "pending": self.pending_escalations,
                "today": self.escalations_today,
            },
            "resources": {
                "llm_tokens_today": self.total_llm_tokens_today,
                "tool_executions_today": self.total_tool_executions_today,
            },
        }


class MetricsCollector:
    """
    Collects and aggregates metrics from agent events.

    Subscribes to NATS event streams and maintains current state.
    """

    def __init__(self, nats_client: Any = None):
        """
        Initialize metrics collector.

        Args:
            nats_client: Connected NATS client
        """
        self.nc = nats_client

        # Per-agent metrics
        self.agents: Dict[str, AgentMetrics] = {}

        # Queue metrics
        self.queues: Dict[str, QueueMetrics] = {}

        # Time-series data (last 24 hours, 1-minute resolution)
        self.timeseries: Dict[str, List[Dict[str, Any]]] = defaultdict(list)

        # Event counts for rate calculation
        self.event_counts: Dict[str, int] = defaultdict(int)

        self._running = False
        self._collector_task = None

    async def start(self):
        """Start collecting metrics."""
        self._running = True

        if self.nc:
            # Subscribe to all agent events
            await self.nc.subscribe(
                "events.>",
                cb=self._handle_event,
            )

        # Start aggregation task
        self._collector_task = asyncio.create_task(self._aggregate_loop())

        logger.info("Metrics collector started")

    async def stop(self):
        """Stop collecting metrics."""
        self._running = False
        if self._collector_task:
            self._collector_task.cancel()
            try:
                await self._collector_task
            except asyncio.CancelledError:
                pass

    async def _handle_event(self, msg):
        """Handle incoming event from NATS."""
        try:
            data = json.loads(msg.data.decode('utf-8'))
            event_type = data.get("_type", "")
            agent_id = data.get("agent_id", "")

            # Update agent metrics
            if agent_id:
                if agent_id not in self.agents:
                    self.agents[agent_id] = AgentMetrics(
                        agent_id=agent_id,
                        agent_type=data.get("agent_type", "unknown"),
                    )

                agent = self.agents[agent_id]
                agent.last_heartbeat = datetime.utcnow()

                if event_type == "AgentStart":
                    agent.state = "working"
                    agent.current_task = data.get("task_id")
                    agent.tasks_processed += 1

                elif event_type == "AgentEnd":
                    agent.state = "idle"
                    agent.current_task = None
                    if data.get("stop_reason") == "finished":
                        agent.tasks_completed += 1
                    elif data.get("stop_reason") == "error":
                        agent.tasks_failed += 1

                    # Update token usage
                    usage = data.get("usage", {})
                    agent.total_llm_tokens += usage.get("total_tokens", 0)

                elif event_type == "ToolStep":
                    agent.total_tool_calls += 1

                elif event_type == "EscalationEvent":
                    agent.tasks_escalated += 1

            # Track event counts
            self.event_counts[event_type] += 1

        except Exception as e:
            logger.warning(f"Error handling event: {e}")

    async def _aggregate_loop(self):
        """Periodically aggregate metrics."""
        while self._running:
            try:
                metrics = self.get_system_metrics()

                # Add to time series
                self.timeseries["system"].append(metrics.to_dict())

                # Keep only last 24 hours
                cutoff = datetime.utcnow() - timedelta(hours=24)
                for key in self.timeseries:
                    self.timeseries[key] = [
                        m for m in self.timeseries[key]
                        if datetime.fromisoformat(m.get("timestamp", "2000-01-01")) > cutoff
                    ]

                # Prune stale agents
                stale_cutoff = datetime.utcnow() - timedelta(minutes=5)
                for agent_id, agent in list(self.agents.items()):
                    if agent.last_heartbeat < stale_cutoff:
                        agent.state = "offline"

            except Exception as e:
                logger.error(f"Aggregation error: {e}")

            await asyncio.sleep(60)  # Aggregate every minute

    def get_system_metrics(self) -> SystemMetrics:
        """Get current system-wide metrics."""
        metrics = SystemMetrics()

        # Aggregate agent states
        for agent in self.agents.values():
            metrics.total_agents += 1
            if agent.state == "idle":
                metrics.agents_idle += 1
            elif agent.state == "working":
                metrics.agents_working += 1
            elif agent.state == "blocked":
                metrics.agents_blocked += 1
            elif agent.state == "offline":
                metrics.agents_offline += 1

        # Aggregate queue depths
        for queue in self.queues.values():
            metrics.queue_depths[queue.queue_name] = queue.depth
            metrics.total_tasks_pending += queue.depth
            metrics.total_tasks_in_progress += queue.in_flight

        # Today's counts
        today = datetime.utcnow().date()
        for ts_entry in self.timeseries.get("system", []):
            entry_date = datetime.fromisoformat(ts_entry.get("timestamp", "2000-01-01")).date()
            if entry_date == today:
                metrics.tasks_completed_today = ts_entry.get("tasks", {}).get("completed_today", 0)
                metrics.tasks_failed_today = ts_entry.get("tasks", {}).get("failed_today", 0)

        return metrics

    def get_agent_metrics(self, agent_id: str) -> Optional[AgentMetrics]:
        """Get metrics for a specific agent."""
        return self.agents.get(agent_id)

    def get_all_agent_metrics(self) -> List[Dict[str, Any]]:
        """Get metrics for all agents."""
        return [a.to_dict() for a in self.agents.values()]

    def get_queue_metrics(self, queue_name: str) -> Optional[QueueMetrics]:
        """Get metrics for a specific queue."""
        return self.queues.get(queue_name)

    def get_timeseries(
        self,
        metric: str,
        start: Optional[datetime] = None,
        end: Optional[datetime] = None,
    ) -> List[Dict[str, Any]]:
        """Get time series data for a metric."""
        data = self.timeseries.get(metric, [])

        if start:
            data = [d for d in data if datetime.fromisoformat(d.get("timestamp", "2000-01-01")) >= start]
        if end:
            data = [d for d in data if datetime.fromisoformat(d.get("timestamp", "2999-01-01")) <= end]

        return data

    def get_event_rates(self) -> Dict[str, float]:
        """Get event rates per minute."""
        # This is a simplified version - real implementation would use sliding window
        return {k: v / 60.0 for k, v in self.event_counts.items()}

    def to_prometheus_format(self) -> str:
        """Export metrics in Prometheus format."""
        lines = []

        # System metrics
        metrics = self.get_system_metrics()

        lines.append(f"# HELP enterprise_agents_total Total number of agents")
        lines.append(f"# TYPE enterprise_agents_total gauge")
        lines.append(f'enterprise_agents_total{{state="idle"}} {metrics.agents_idle}')
        lines.append(f'enterprise_agents_total{{state="working"}} {metrics.agents_working}')
        lines.append(f'enterprise_agents_total{{state="blocked"}} {metrics.agents_blocked}')
        lines.append(f'enterprise_agents_total{{state="offline"}} {metrics.agents_offline}')

        lines.append(f"# HELP enterprise_tasks_total Total tasks by status")
        lines.append(f"# TYPE enterprise_tasks_total gauge")
        lines.append(f'enterprise_tasks_total{{status="pending"}} {metrics.total_tasks_pending}')
        lines.append(f'enterprise_tasks_total{{status="in_progress"}} {metrics.total_tasks_in_progress}')

        lines.append(f"# HELP enterprise_escalations_pending Pending escalations")
        lines.append(f"# TYPE enterprise_escalations_pending gauge")
        lines.append(f"enterprise_escalations_pending {metrics.pending_escalations}")

        # Per-queue metrics
        for queue_name, depth in metrics.queue_depths.items():
            lines.append(f'enterprise_queue_depth{{queue="{queue_name}"}} {depth}')

        # Per-agent metrics
        for agent in self.agents.values():
            labels = f'agent_id="{agent.agent_id}",agent_type="{agent.agent_type}"'
            lines.append(f'enterprise_agent_tasks_completed{{{labels}}} {agent.tasks_completed}')
            lines.append(f'enterprise_agent_tasks_failed{{{labels}}} {agent.tasks_failed}')
            lines.append(f'enterprise_agent_llm_tokens{{{labels}}} {agent.total_llm_tokens}')

        return "\n".join(lines)
