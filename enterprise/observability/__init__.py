"""
Observability for Autonomous Enterprise

Provides monitoring, metrics, and dashboards for:
- Current tasking: active tasks, queue depths, blockers
- Workforce status: agent counts by type, idle/working/blocked
- Mission progress: goal status, decomposition tree
- Audit trail: agent actions, escalations, anomalies
"""

from .metrics import MetricsCollector, AgentMetrics, QueueMetrics, SystemMetrics
from .dashboard import DashboardService, create_dashboard_app
from .audit import AuditLogger, AuditEvent, AuditCategory, AuditSeverity

__all__ = [
    # Metrics
    "MetricsCollector",
    "AgentMetrics",
    "QueueMetrics",
    "SystemMetrics",
    # Dashboard
    "DashboardService",
    "create_dashboard_app",
    # Audit
    "AuditLogger",
    "AuditEvent",
    "AuditCategory",
    "AuditSeverity",
]
