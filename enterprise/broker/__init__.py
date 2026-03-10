"""
Credential Broker for Agent VMs

The broker package provides tools for assembling agent configuration
from AD/LDAP and SYSVOL, producing sealed config bundles that agent
launchers consume without direct LDAP access.
"""

from .config_assembler import ConfigAssembler

__all__ = [
    "ConfigAssembler",
]
