"""
Dashboard service for enterprise monitoring.
"""

from dataclasses import dataclass
from datetime import datetime
from typing import Any, Dict, List, Optional
import json
import logging

from .metrics import MetricsCollector, SystemMetrics

logger = logging.getLogger(__name__)


@dataclass
class DashboardView:
    """A dashboard view configuration."""
    name: str
    widgets: List[Dict[str, Any]]


class DashboardService:
    """
    Dashboard service for real-time enterprise monitoring.

    Provides:
    - Current tasking: active tasks, queue depths, blockers
    - Workforce status: agent counts by type, idle/working/blocked
    - Mission progress: goal status, decomposition tree
    - Audit trail: agent actions, escalations, anomalies
    """

    def __init__(
        self,
        metrics: MetricsCollector,
        nats_client: Any = None,
    ):
        """
        Initialize dashboard service.

        Args:
            metrics: Metrics collector
            nats_client: NATS client for real-time updates
        """
        self.metrics = metrics
        self.nc = nats_client

        # Active dashboard sessions (WebSocket connections)
        self.sessions: Dict[str, Any] = {}

        # Dashboard configurations
        self.dashboards: Dict[str, DashboardView] = {
            "overview": DashboardView(
                name="Enterprise Overview",
                widgets=[
                    {"type": "agent_status", "title": "Agent Status"},
                    {"type": "queue_depths", "title": "Queue Depths"},
                    {"type": "task_throughput", "title": "Task Throughput"},
                    {"type": "escalation_status", "title": "Escalations"},
                ],
            ),
            "workforce": DashboardView(
                name="Workforce Management",
                widgets=[
                    {"type": "agent_table", "title": "All Agents"},
                    {"type": "pool_status", "title": "Agent Pools"},
                    {"type": "agent_performance", "title": "Performance"},
                ],
            ),
            "tasks": DashboardView(
                name="Task Management",
                widgets=[
                    {"type": "active_tasks", "title": "Active Tasks"},
                    {"type": "queue_table", "title": "Queues"},
                    {"type": "task_timeline", "title": "Timeline"},
                ],
            ),
            "audit": DashboardView(
                name="Audit Trail",
                widgets=[
                    {"type": "event_log", "title": "Recent Events"},
                    {"type": "escalation_log", "title": "Escalations"},
                    {"type": "anomaly_detection", "title": "Anomalies"},
                ],
            ),
        }

    def get_overview(self) -> Dict[str, Any]:
        """Get overview dashboard data."""
        system = self.metrics.get_system_metrics()

        return {
            "timestamp": datetime.utcnow().isoformat(),
            "agents": {
                "summary": {
                    "total": system.total_agents,
                    "idle": system.agents_idle,
                    "working": system.agents_working,
                    "blocked": system.agents_blocked,
                    "offline": system.agents_offline,
                },
                "by_type": self._get_agents_by_type(),
            },
            "tasks": {
                "pending": system.total_tasks_pending,
                "in_progress": system.total_tasks_in_progress,
                "completed_today": system.tasks_completed_today,
                "failed_today": system.tasks_failed_today,
            },
            "queues": system.queue_depths,
            "escalations": {
                "pending": system.pending_escalations,
                "today": system.escalations_today,
            },
            "resources": {
                "llm_tokens_today": system.total_llm_tokens_today,
                "tool_executions_today": system.total_tool_executions_today,
            },
        }

    def get_workforce_status(self) -> Dict[str, Any]:
        """Get detailed workforce status."""
        agents = self.metrics.get_all_agent_metrics()

        # Group by type
        by_type = {}
        for agent in agents:
            agent_type = agent.get("agent_type", "unknown")
            if agent_type not in by_type:
                by_type[agent_type] = []
            by_type[agent_type].append(agent)

        # Calculate pool stats
        pools = {}
        for agent_type, type_agents in by_type.items():
            pools[agent_type] = {
                "total": len(type_agents),
                "idle": sum(1 for a in type_agents if a.get("state") == "idle"),
                "working": sum(1 for a in type_agents if a.get("state") == "working"),
                "offline": sum(1 for a in type_agents if a.get("state") == "offline"),
                "avg_tasks_completed": sum(a.get("tasks_completed", 0) for a in type_agents) / max(len(type_agents), 1),
            }

        return {
            "timestamp": datetime.utcnow().isoformat(),
            "agents": agents,
            "pools": pools,
            "totals": {
                "agents": len(agents),
                "types": len(by_type),
            },
        }

    def get_task_status(self) -> Dict[str, Any]:
        """Get detailed task status."""
        # This would query NATS JetStream for queue states
        return {
            "timestamp": datetime.utcnow().isoformat(),
            "queues": [
                q.to_dict() if hasattr(q, 'to_dict') else q
                for q in self.metrics.queues.values()
            ],
            "active_tasks": [],  # Would be populated from JetStream
            "blockers": [],      # Tasks that are blocking others
        }

    def get_mission_progress(self) -> Dict[str, Any]:
        """Get mission/goal progress."""
        # This would query coordinator state
        return {
            "timestamp": datetime.utcnow().isoformat(),
            "active_missions": [],
            "goals": [],
            "decomposition_tree": {},
        }

    def get_audit_trail(
        self,
        limit: int = 100,
        event_types: Optional[List[str]] = None,
        agent_id: Optional[str] = None,
    ) -> Dict[str, Any]:
        """Get audit trail events."""
        # Filter from metrics timeseries
        events = self.metrics.timeseries.get("events", [])[-limit:]

        if event_types:
            events = [e for e in events if e.get("_type") in event_types]

        if agent_id:
            events = [e for e in events if e.get("agent_id") == agent_id]

        return {
            "timestamp": datetime.utcnow().isoformat(),
            "events": events,
            "count": len(events),
        }

    def get_anomalies(self) -> Dict[str, Any]:
        """Get detected anomalies."""
        anomalies = []

        # Check for offline agents
        for agent in self.metrics.agents.values():
            if agent.state == "offline":
                anomalies.append({
                    "type": "agent_offline",
                    "severity": "warning",
                    "agent_id": agent.agent_id,
                    "message": f"Agent {agent.agent_id} is offline",
                    "last_seen": agent.last_heartbeat.isoformat(),
                })

        # Check for high failure rates
        for agent in self.metrics.agents.values():
            if agent.tasks_processed > 10:
                failure_rate = agent.tasks_failed / agent.tasks_processed
                if failure_rate > 0.3:
                    anomalies.append({
                        "type": "high_failure_rate",
                        "severity": "error",
                        "agent_id": agent.agent_id,
                        "message": f"Agent {agent.agent_id} has {failure_rate:.0%} failure rate",
                        "failure_rate": failure_rate,
                    })

        # Check for queue buildup
        for queue_name, depth in self.metrics.get_system_metrics().queue_depths.items():
            if depth > 1000:
                anomalies.append({
                    "type": "queue_buildup",
                    "severity": "warning",
                    "queue": queue_name,
                    "message": f"Queue {queue_name} has {depth} pending tasks",
                    "depth": depth,
                })

        return {
            "timestamp": datetime.utcnow().isoformat(),
            "anomalies": anomalies,
            "count": len(anomalies),
        }

    def _get_agents_by_type(self) -> Dict[str, int]:
        """Get agent count by type."""
        by_type = {}
        for agent in self.metrics.agents.values():
            agent_type = agent.agent_type
            by_type[agent_type] = by_type.get(agent_type, 0) + 1
        return by_type


async def create_dashboard_app(metrics: MetricsCollector):
    """Create FastAPI app for dashboard."""
    from fastapi import FastAPI, WebSocket
    from fastapi.responses import HTMLResponse

    app = FastAPI(title="Enterprise Dashboard")
    dashboard = DashboardService(metrics)

    @app.get("/")
    async def root():
        return HTMLResponse("""
        <html>
        <head><title>Enterprise Dashboard</title></head>
        <body>
            <h1>Autonomous Enterprise Dashboard</h1>
            <ul>
                <li><a href="/api/overview">Overview</a></li>
                <li><a href="/api/workforce">Workforce</a></li>
                <li><a href="/api/tasks">Tasks</a></li>
                <li><a href="/api/audit">Audit</a></li>
                <li><a href="/metrics">Prometheus Metrics</a></li>
            </ul>
        </body>
        </html>
        """)

    @app.get("/api/overview")
    async def overview():
        return dashboard.get_overview()

    @app.get("/api/workforce")
    async def workforce():
        return dashboard.get_workforce_status()

    @app.get("/api/tasks")
    async def tasks():
        return dashboard.get_task_status()

    @app.get("/api/audit")
    async def audit(limit: int = 100):
        return dashboard.get_audit_trail(limit=limit)

    @app.get("/api/anomalies")
    async def anomalies():
        return dashboard.get_anomalies()

    @app.get("/metrics")
    async def prometheus_metrics():
        from fastapi.responses import PlainTextResponse
        return PlainTextResponse(
            metrics.to_prometheus_format(),
            media_type="text/plain",
        )

    @app.websocket("/ws")
    async def websocket_endpoint(websocket: WebSocket):
        await websocket.accept()
        try:
            while True:
                # Send updates every 5 seconds
                data = dashboard.get_overview()
                await websocket.send_json(data)
                await asyncio.sleep(5)
        except Exception:
            pass

    return app


import asyncio
