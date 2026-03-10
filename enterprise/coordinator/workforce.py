"""
Workforce management for mission coordination.

Coordinators manage a workforce of agents, tracking their status
and distributing work appropriately.
"""

from dataclasses import dataclass, field
from datetime import datetime, timedelta
from enum import Enum
from typing import Any, Dict, List, Optional
from uuid import UUID, uuid4
import asyncio
import logging

import httpx

logger = logging.getLogger(__name__)


class AgentState(str, Enum):
    """State of an agent in the workforce."""
    IDLE = "idle"               # Ready for work
    WORKING = "working"         # Processing a task
    BLOCKED = "blocked"         # Waiting on external resource
    OFFLINE = "offline"         # Not responding
    STARTING = "starting"       # Being provisioned


@dataclass
class AgentStatus:
    """Current status of a managed agent."""
    agent_id: str
    agent_type: str
    trust_level: int
    state: AgentState = AgentState.IDLE
    current_task: Optional[UUID] = None
    tasks_completed: int = 0
    tasks_failed: int = 0
    last_heartbeat: datetime = field(default_factory=datetime.utcnow)
    started_at: datetime = field(default_factory=datetime.utcnow)
    capabilities: List[str] = field(default_factory=list)
    vm_id: Optional[str] = None
    credential_ref: Optional[str] = None

    @property
    def is_available(self) -> bool:
        return self.state == AgentState.IDLE

    @property
    def is_responsive(self) -> bool:
        return (datetime.utcnow() - self.last_heartbeat) < timedelta(minutes=2)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "agent_id": self.agent_id,
            "agent_type": self.agent_type,
            "trust_level": self.trust_level,
            "state": self.state.value,
            "current_task": str(self.current_task) if self.current_task else None,
            "tasks_completed": self.tasks_completed,
            "tasks_failed": self.tasks_failed,
            "last_heartbeat": self.last_heartbeat.isoformat(),
            "started_at": self.started_at.isoformat(),
            "capabilities": self.capabilities,
            "vm_id": self.vm_id,
            "credential_ref": self.credential_ref,
            "is_available": self.is_available,
            "is_responsive": self.is_responsive,
        }


@dataclass
class AgentPool:
    """A pool of agents of a specific type."""
    agent_type: str
    min_size: int = 1
    max_size: int = 10
    target_size: int = 5
    agents: Dict[str, AgentStatus] = field(default_factory=dict)

    @property
    def current_size(self) -> int:
        return len(self.agents)

    @property
    def available_count(self) -> int:
        return sum(1 for a in self.agents.values() if a.is_available)

    @property
    def working_count(self) -> int:
        return sum(1 for a in self.agents.values() if a.state == AgentState.WORKING)

    @property
    def offline_count(self) -> int:
        return sum(1 for a in self.agents.values() if not a.is_responsive)

    def needs_scale_up(self, headroom: float = 0.2) -> bool:
        """Check if pool needs more agents."""
        if self.current_size >= self.max_size:
            return False
        min_available = max(1, int(self.current_size * headroom))
        return self.available_count < min_available

    def can_scale_down(self) -> bool:
        """Check if pool can reduce agents."""
        return (
            self.current_size > self.min_size and
            self.available_count > max(1, int(self.current_size * 0.5))
        )

    def get_available_agent(self) -> Optional[AgentStatus]:
        """Get an available agent from the pool."""
        for agent in self.agents.values():
            if agent.is_available and agent.is_responsive:
                return agent
        return None

    def to_dict(self) -> Dict[str, Any]:
        return {
            "agent_type": self.agent_type,
            "min_size": self.min_size,
            "max_size": self.max_size,
            "target_size": self.target_size,
            "current_size": self.current_size,
            "available_count": self.available_count,
            "working_count": self.working_count,
            "offline_count": self.offline_count,
            "agents": {k: v.to_dict() for k, v in self.agents.items()},
        }


class WorkforceManager:
    """
    Manages the workforce of agents for a coordinator.

    Responsibilities:
    - Track agent status and availability
    - Scale pools up/down based on demand
    - Route tasks to appropriate agents
    - Handle agent failures
    """

    def __init__(
        self,
        provisioner_url: str,
        api_key: str,
        nats_client: Any = None,
        db_session: Any = None,
    ):
        """
        Initialize workforce manager.

        Args:
            provisioner_url: URL of provisioning service
            api_key: API key for authenticating with the provisioner
            nats_client: NATS client for messaging
            db_session: Database session for state
        """
        self.provisioner_url = provisioner_url.rstrip("/")
        self.api_key = api_key
        self.nc = nats_client
        self.db = db_session
        self._http_client: Optional[httpx.AsyncClient] = None

        # Agent pools by type
        self.pools: Dict[str, AgentPool] = {}

        # Default pool configurations
        self.pool_configs = {
            "worker": {"min": 5, "max": 50, "target": 10},
            "code-reviewer": {"min": 2, "max": 20, "target": 5},
            "analyst": {"min": 2, "max": 20, "target": 5},
            "coordinator": {"min": 1, "max": 5, "target": 2},
        }

        self._running = False
        self._maintenance_task = None

    async def start(self):
        """Start workforce management."""
        self._running = True

        # HTTP client for provisioner API calls
        self._http_client = httpx.AsyncClient(
            base_url=self.provisioner_url,
            headers={"X-API-Key": self.api_key},
            timeout=httpx.Timeout(30.0),
        )

        # Initialize pools
        for agent_type, config in self.pool_configs.items():
            self.pools[agent_type] = AgentPool(
                agent_type=agent_type,
                min_size=config["min"],
                max_size=config["max"],
                target_size=config["target"],
            )

        # Subscribe to agent heartbeats
        if self.nc:
            await self.nc.subscribe(
                "events.agent.*.heartbeat",
                cb=self._handle_heartbeat,
            )

        # Start maintenance loop
        self._maintenance_task = asyncio.create_task(self._maintenance_loop())

        logger.info("Workforce manager started")

    async def stop(self):
        """Stop workforce management."""
        self._running = False
        if self._maintenance_task:
            self._maintenance_task.cancel()
            try:
                await self._maintenance_task
            except asyncio.CancelledError:
                pass

        if self._http_client:
            await self._http_client.aclose()
            self._http_client = None

        logger.info("Workforce manager stopped")

    async def request_agent(
        self,
        agent_type: str,
        requirements: Optional[Dict[str, Any]] = None,
    ) -> Optional[str]:
        """
        Request an agent for a task.

        Args:
            agent_type: Type of agent needed
            requirements: Optional requirements (capabilities, trust level)

        Returns:
            Agent ID if one is available, None otherwise
        """
        pool = self.pools.get(agent_type)
        if not pool:
            logger.warning(f"Unknown agent type: {agent_type}")
            return None

        # Find available agent
        agent = pool.get_available_agent()

        if agent:
            # Check requirements
            if requirements:
                min_trust = requirements.get("min_trust_level", 0)
                if agent.trust_level < min_trust:
                    logger.debug(f"Agent {agent.agent_id} doesn't meet trust requirement")
                    agent = None

                required_caps = set(requirements.get("capabilities", []))
                if required_caps and not required_caps.issubset(set(agent.capabilities)):
                    logger.debug(f"Agent {agent.agent_id} doesn't have required capabilities")
                    agent = None

        if agent:
            return agent.agent_id

        # No agent available - try to scale up
        if pool.needs_scale_up():
            await self._scale_up(agent_type)

        return None

    async def release_agent(self, agent_id: str, task_id: UUID, success: bool):
        """
        Release an agent after task completion.

        Args:
            agent_id: Agent that completed work
            task_id: Task that was completed
            success: Whether task succeeded
        """
        for pool in self.pools.values():
            if agent_id in pool.agents:
                agent = pool.agents[agent_id]
                agent.state = AgentState.IDLE
                agent.current_task = None
                if success:
                    agent.tasks_completed += 1
                else:
                    agent.tasks_failed += 1
                agent.last_heartbeat = datetime.utcnow()
                return

    async def mark_agent_working(self, agent_id: str, task_id: UUID):
        """Mark an agent as working on a task."""
        for pool in self.pools.values():
            if agent_id in pool.agents:
                agent = pool.agents[agent_id]
                agent.state = AgentState.WORKING
                agent.current_task = task_id
                agent.last_heartbeat = datetime.utcnow()
                return

    async def _handle_heartbeat(self, msg):
        """Handle agent heartbeat message."""
        try:
            import json
            data = json.loads(msg.data.decode('utf-8'))
            agent_id = data.get("agent_id")
            agent_type = data.get("agent_type")

            if not agent_id or not agent_type:
                return

            pool = self.pools.get(agent_type)
            if not pool:
                return

            if agent_id in pool.agents:
                agent = pool.agents[agent_id]
                agent.last_heartbeat = datetime.utcnow()
            else:
                # New agent registered
                pool.agents[agent_id] = AgentStatus(
                    agent_id=agent_id,
                    agent_type=agent_type,
                    trust_level=data.get("trust_level", 2),
                    capabilities=data.get("capabilities", []),
                )
                logger.info(f"Registered new agent: {agent_id}")

        except Exception as e:
            logger.warning(f"Error handling heartbeat: {e}")

    async def _maintenance_loop(self):
        """Background maintenance for workforce."""
        while self._running:
            try:
                await self._check_agent_health()
                await self._balance_pools()
            except Exception as e:
                logger.error(f"Maintenance error: {e}")

            await asyncio.sleep(30)

    async def _check_agent_health(self):
        """Check health of all agents and mark unresponsive ones offline."""
        for pool in self.pools.values():
            for agent in pool.agents.values():
                if not agent.is_responsive:
                    if agent.state != AgentState.OFFLINE:
                        logger.warning(f"Agent {agent.agent_id} is unresponsive")
                        agent.state = AgentState.OFFLINE

    async def _balance_pools(self):
        """Scale pools up or down based on demand."""
        for agent_type, pool in self.pools.items():
            if pool.needs_scale_up():
                await self._scale_up(agent_type)
            elif pool.can_scale_down():
                await self._scale_down(agent_type)

    async def _scale_up(self, agent_type: str):
        """Request a new agent from the provisioner.

        Calls POST /provision, registers the new agent as STARTING,
        and stores the credential_ref for the orchestrator to inject
        into the VM.
        """
        pool = self.pools.get(agent_type)
        if not pool or pool.current_size >= pool.max_size:
            return

        vm_id = f"vm-{uuid4()}"

        try:
            resp = await self._http_client.post(
                "/provision",
                json={"agent_type": agent_type, "vm_id": vm_id},
            )
            resp.raise_for_status()
            data = resp.json()

            identity = data["identity"]
            agent_id = identity["name"]

            pool.agents[agent_id] = AgentStatus(
                agent_id=agent_id,
                agent_type=agent_type,
                trust_level=identity.get("trust_level", 2),
                state=AgentState.STARTING,
                capabilities=identity.get("capabilities", []),
                vm_id=vm_id,
                credential_ref=data.get("credential_ref"),
            )

            logger.info(
                "Provisioned %s agent %s for vm=%s (credential_ref=%s)",
                agent_type, agent_id, vm_id, data.get("credential_ref"),
            )
        except httpx.HTTPStatusError as e:
            logger.error(
                "Provisioner returned %d when scaling up %s: %s",
                e.response.status_code, agent_type, e.response.text,
            )
        except httpx.HTTPError as e:
            logger.error("Failed to scale up %s: %s", agent_type, e)

    async def _scale_down(self, agent_type: str):
        """Return an idle agent to the provisioner.

        Calls POST /release and removes the agent from the pool.
        """
        pool = self.pools.get(agent_type)
        if not pool:
            return

        # Find oldest idle agent
        idle_agents = [
            a for a in pool.agents.values()
            if a.is_available and a.is_responsive
        ]

        if not idle_agents:
            return

        oldest = min(idle_agents, key=lambda a: a.started_at)

        try:
            resp = await self._http_client.post(
                "/release",
                json={
                    "identity_name": oldest.agent_id,
                    "vm_id": oldest.vm_id or "",
                },
            )
            resp.raise_for_status()
            del pool.agents[oldest.agent_id]
            logger.info("Released %s agent %s", agent_type, oldest.agent_id)
        except httpx.HTTPStatusError as e:
            logger.error(
                "Provisioner returned %d when releasing %s: %s",
                e.response.status_code, oldest.agent_id, e.response.text,
            )
        except httpx.HTTPError as e:
            logger.error("Failed to release %s: %s", oldest.agent_id, e)

    def get_workforce_status(self) -> Dict[str, Any]:
        """Get current workforce status."""
        total_agents = sum(p.current_size for p in self.pools.values())
        total_available = sum(p.available_count for p in self.pools.values())
        total_working = sum(p.working_count for p in self.pools.values())
        total_offline = sum(p.offline_count for p in self.pools.values())

        return {
            "total_agents": total_agents,
            "total_available": total_available,
            "total_working": total_working,
            "total_offline": total_offline,
            "pools": {k: v.to_dict() for k, v in self.pools.items()},
        }
