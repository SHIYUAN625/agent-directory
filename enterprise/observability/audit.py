"""
Audit logging for autonomous enterprise.

Provides immutable audit trail for compliance and security monitoring.
"""

from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import Any, Dict, List, Optional
from uuid import UUID, uuid4
import json
import logging

logger = logging.getLogger(__name__)


class AuditCategory(str, Enum):
    """Categories of audit events."""
    AGENT_LIFECYCLE = "agent_lifecycle"    # Agent start/stop/provision
    AUTHENTICATION = "authentication"       # Kerberos, credential broker
    AUTHORIZATION = "authorization"         # Tool access, policy checks
    TOOL_EXECUTION = "tool_execution"       # Tool usage
    DATA_ACCESS = "data_access"            # File/LDAP/SMB access
    TASK_EXECUTION = "task_execution"      # Task processing
    ESCALATION = "escalation"              # Escalations
    POLICY_VIOLATION = "policy_violation"  # Policy violations
    CONFIGURATION = "configuration"         # Config changes
    SECURITY = "security"                  # Security events


class AuditSeverity(str, Enum):
    """Severity levels for audit events."""
    DEBUG = "debug"
    INFO = "info"
    WARNING = "warning"
    ERROR = "error"
    CRITICAL = "critical"


@dataclass
class AuditEvent:
    """An audit event."""
    id: UUID = field(default_factory=uuid4)
    timestamp: datetime = field(default_factory=datetime.utcnow)

    # Event classification
    category: AuditCategory = AuditCategory.TOOL_EXECUTION
    severity: AuditSeverity = AuditSeverity.INFO
    event_type: str = ""

    # Source
    agent_id: str = ""
    agent_type: str = ""
    trust_level: int = 0
    task_id: str = ""
    session_id: str = ""

    # Event details
    action: str = ""
    resource: str = ""
    outcome: str = "success"  # success, failure, denied
    details: Dict[str, Any] = field(default_factory=dict)

    # Additional context
    ip_address: str = ""
    user_agent: str = ""

    def to_dict(self) -> Dict[str, Any]:
        return {
            "id": str(self.id),
            "timestamp": self.timestamp.isoformat(),
            "category": self.category.value,
            "severity": self.severity.value,
            "event_type": self.event_type,
            "agent_id": self.agent_id,
            "agent_type": self.agent_type,
            "trust_level": self.trust_level,
            "task_id": self.task_id,
            "session_id": self.session_id,
            "action": self.action,
            "resource": self.resource,
            "outcome": self.outcome,
            "details": self.details,
            "ip_address": self.ip_address,
        }

    def to_json(self) -> str:
        return json.dumps(self.to_dict())


class AuditLogger:
    """
    Audit logger for enterprise operations.

    Logs to:
    - NATS JetStream (events.audit) for durable storage
    - Local file for backup
    - Optional external SIEM integration
    """

    def __init__(
        self,
        nats_client: Any = None,
        log_path: Optional[str] = None,
        siem_endpoint: Optional[str] = None,
    ):
        """
        Initialize audit logger.

        Args:
            nats_client: NATS client for publishing
            log_path: Path to local audit log file
            siem_endpoint: Optional SIEM webhook endpoint
        """
        self.nc = nats_client
        self.log_path = log_path
        self.siem_endpoint = siem_endpoint

        # In-memory buffer for recent events
        self.recent_events: List[AuditEvent] = []
        self.max_buffer_size = 10000

        # Setup file logging if path provided
        if log_path:
            self.file_handler = logging.FileHandler(log_path)
            self.file_handler.setFormatter(
                logging.Formatter('%(message)s')
            )
        else:
            self.file_handler = None

    async def log(self, event: AuditEvent):
        """Log an audit event."""
        # Add to buffer
        self.recent_events.append(event)
        if len(self.recent_events) > self.max_buffer_size:
            self.recent_events = self.recent_events[-self.max_buffer_size:]

        # Publish to NATS
        if self.nc:
            try:
                js = self.nc.jetstream()
                await js.publish(
                    "events.audit",
                    event.to_json().encode(),
                )
            except Exception as e:
                logger.error(f"Failed to publish audit event: {e}")

        # Write to file
        if self.file_handler:
            self.file_handler.emit(
                logging.LogRecord(
                    name="audit",
                    level=logging.INFO,
                    pathname="",
                    lineno=0,
                    msg=event.to_json(),
                    args=(),
                    exc_info=None,
                )
            )

        # Send to SIEM if configured
        if self.siem_endpoint and event.severity in [AuditSeverity.ERROR, AuditSeverity.CRITICAL]:
            await self._send_to_siem(event)

    async def _send_to_siem(self, event: AuditEvent):
        """Send event to external SIEM."""
        logger.warning("SIEM integration not implemented — dropping event %s (severity=%s)", event.id, event.severity.value)

    # Convenience methods for common event types

    async def log_agent_start(
        self,
        agent_id: str,
        agent_type: str,
        trust_level: int,
        task_id: str = "",
    ):
        """Log agent start event."""
        await self.log(AuditEvent(
            category=AuditCategory.AGENT_LIFECYCLE,
            event_type="agent_start",
            agent_id=agent_id,
            agent_type=agent_type,
            trust_level=trust_level,
            task_id=task_id,
            action="start",
            outcome="success",
        ))

    async def log_agent_stop(
        self,
        agent_id: str,
        reason: str = "normal",
        error: Optional[str] = None,
    ):
        """Log agent stop event."""
        await self.log(AuditEvent(
            category=AuditCategory.AGENT_LIFECYCLE,
            event_type="agent_stop",
            agent_id=agent_id,
            action="stop",
            outcome="success" if not error else "error",
            details={"reason": reason, "error": error},
        ))

    async def log_authentication(
        self,
        agent_id: str,
        auth_type: str,
        success: bool,
        details: Optional[Dict[str, Any]] = None,
    ):
        """Log authentication event."""
        await self.log(AuditEvent(
            category=AuditCategory.AUTHENTICATION,
            severity=AuditSeverity.INFO if success else AuditSeverity.WARNING,
            event_type=f"auth_{auth_type}",
            agent_id=agent_id,
            action="authenticate",
            outcome="success" if success else "failure",
            details=details or {},
        ))

    async def log_tool_access(
        self,
        agent_id: str,
        tool_name: str,
        allowed: bool,
        reason: str = "",
    ):
        """Log tool access check."""
        await self.log(AuditEvent(
            category=AuditCategory.AUTHORIZATION,
            severity=AuditSeverity.INFO if allowed else AuditSeverity.WARNING,
            event_type="tool_access_check",
            agent_id=agent_id,
            action="access_check",
            resource=tool_name,
            outcome="allowed" if allowed else "denied",
            details={"reason": reason},
        ))

    async def log_tool_execution(
        self,
        agent_id: str,
        task_id: str,
        tool_name: str,
        arguments: Dict[str, Any],
        result: Any,
        duration_ms: int,
        success: bool,
    ):
        """Log tool execution."""
        await self.log(AuditEvent(
            category=AuditCategory.TOOL_EXECUTION,
            event_type="tool_execution",
            agent_id=agent_id,
            task_id=task_id,
            action="execute",
            resource=tool_name,
            outcome="success" if success else "failure",
            details={
                "arguments": arguments,
                "duration_ms": duration_ms,
            },
        ))

    async def log_data_access(
        self,
        agent_id: str,
        access_type: str,  # ldap_search, smb_read, smb_write
        resource: str,
        success: bool,
    ):
        """Log data access."""
        await self.log(AuditEvent(
            category=AuditCategory.DATA_ACCESS,
            event_type=access_type,
            agent_id=agent_id,
            action=access_type,
            resource=resource,
            outcome="success" if success else "failure",
        ))

    async def log_escalation(
        self,
        agent_id: str,
        task_id: str,
        target: str,
        reason: str,
    ):
        """Log escalation."""
        await self.log(AuditEvent(
            category=AuditCategory.ESCALATION,
            severity=AuditSeverity.WARNING,
            event_type="task_escalation",
            agent_id=agent_id,
            task_id=task_id,
            action="escalate",
            resource=target,
            details={"reason": reason},
        ))

    async def log_policy_violation(
        self,
        agent_id: str,
        policy_name: str,
        violation_type: str,
        action_taken: str,
        details: Dict[str, Any],
    ):
        """Log policy violation."""
        await self.log(AuditEvent(
            category=AuditCategory.POLICY_VIOLATION,
            severity=AuditSeverity.ERROR,
            event_type="policy_violation",
            agent_id=agent_id,
            action=violation_type,
            resource=policy_name,
            outcome="blocked",
            details={
                "action_taken": action_taken,
                **details,
            },
        ))

    async def log_security_event(
        self,
        event_type: str,
        severity: AuditSeverity,
        agent_id: str = "",
        details: Optional[Dict[str, Any]] = None,
    ):
        """Log security event."""
        await self.log(AuditEvent(
            category=AuditCategory.SECURITY,
            severity=severity,
            event_type=event_type,
            agent_id=agent_id,
            action="security_event",
            details=details or {},
        ))

    def get_recent_events(
        self,
        limit: int = 100,
        category: Optional[AuditCategory] = None,
        severity: Optional[AuditSeverity] = None,
        agent_id: Optional[str] = None,
    ) -> List[Dict[str, Any]]:
        """Get recent events with optional filtering."""
        events = self.recent_events[-limit:]

        if category:
            events = [e for e in events if e.category == category]
        if severity:
            events = [e for e in events if e.severity == severity]
        if agent_id:
            events = [e for e in events if e.agent_id == agent_id]

        return [e.to_dict() for e in events]

    def get_event_counts(self) -> Dict[str, int]:
        """Get event counts by category."""
        counts = {}
        for event in self.recent_events:
            key = event.category.value
            counts[key] = counts.get(key, 0) + 1
        return counts
