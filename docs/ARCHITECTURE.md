# Architecture Diagrams

This document provides visual representations of the Agent Directory architecture using Mermaid diagrams.

## Schema Inheritance Chain

The msDS-Agent class inherits from User for identity. The msDS-AgentSandbox class inherits from Computer for execution environments.

```mermaid
classDiagram
    direction TB

    class top {
        <<abstract>>
        +objectClass
        +cn
    }

    class person {
        <<abstract>>
        +sn
        +telephoneNumber
    }

    class organizationalPerson {
        <<abstract>>
        +title
        +department
        +manager
    }

    class user {
        +sAMAccountName
        +userPrincipalName
        +unicodePwd
        +userAccountControl
        +servicePrincipalName
        +objectSid
    }

    class computer {
        +dNSHostName
        +operatingSystem
        +msDS-ManagedPasswordInterval
        +msDS-AllowedToDelegateTo
    }

    class msDS-Agent {
        +msDS-AgentType
        +msDS-AgentTrustLevel
        +msDS-AgentModel
        +msDS-AgentOwner
        +msDS-AgentCapabilities
        +msDS-AgentAuthorizedTools
        +msDS-AgentDeniedTools
        +msDS-AgentDelegationScope
        +msDS-AgentSandbox
    }

    class msDS-AgentSandbox {
        +msDS-SandboxEndpoint
        +msDS-SandboxAgents
        +msDS-SandboxSecurityProfile
        +msDS-SandboxResourcePolicy
        +msDS-SandboxNetworkPolicy
        +msDS-SandboxStatus
    }

    top <|-- person
    person <|-- organizationalPerson
    organizationalPerson <|-- user
    user <|-- computer
    user <|-- msDS-Agent
    computer <|-- msDS-AgentSandbox
```

## Object Relationships

```mermaid
erDiagram
    AGENT ||--o{ TOOL : "authorized to use"
    AGENT ||--o{ TOOL : "denied from using"
    AGENT }o--|| USER : "owned by"
    AGENT }o--o| AGENT : "parent of"
    AGENT }o--o{ GROUP : "member of"
    AGENT ||--o{ SANDBOX : "runs in"
    SANDBOX }o--o{ AGENT : "hosts"
    TOOL ||--o{ CONSTRAINT : "has"

    AGENT {
        string name
        string type
        int trustLevel
        string model
        string owner
    }

    TOOL {
        string identifier
        string displayName
        string category
        int riskLevel
        int requiredTrustLevel
    }

    USER {
        string name
        string distinguishedName
    }

    GROUP {
        string name
        string description
    }

    SANDBOX {
        string name
        string endpoint
        string securityProfile
        string status
        string resourcePolicy
    }

    CONSTRAINT {
        string key
        string value
    }
```

## Authentication Flow

### Kerberos Authentication

```mermaid
sequenceDiagram
    participant Agent as AI Agent Runtime
    participant KDC as Key Distribution Center
    participant Service as Target Service
    participant AD as Active Directory

    Agent->>KDC: AS-REQ (Agent SPN)
    KDC->>AD: Validate agent account
    AD-->>KDC: Account valid, trust level 2
    KDC-->>Agent: AS-REP (TGT)

    Agent->>KDC: TGS-REQ (Service SPN)
    KDC->>AD: Check delegation scope
    AD-->>KDC: Service in scope
    KDC-->>Agent: TGS-REP (Service Ticket)

    Agent->>Service: AP-REQ (Service Ticket)
    Service-->>Agent: AP-REP (Authenticated)
```

### Certificate Authentication

```mermaid
sequenceDiagram
    participant Agent as AI Agent Runtime
    participant DC as Domain Controller
    participant AD as Active Directory
    participant CA as Certificate Authority

    Agent->>DC: LDAP Bind with Certificate
    DC->>AD: Find agent by altSecurityIdentities
    AD-->>DC: Agent DN found
    DC->>CA: Validate certificate chain
    CA-->>DC: Certificate valid
    DC-->>Agent: Bind successful
```

### Constrained Delegation (S4U)

```mermaid
sequenceDiagram
    participant User as End User
    participant Agent as AI Agent
    participant KDC as Key Distribution Center
    participant Service as Backend Service

    User->>Agent: Request action
    Note over Agent: Agent needs to access Service on behalf of User

    Agent->>KDC: S4U2Self (get ticket for User)
    KDC-->>Agent: User's forwardable ticket

    Agent->>KDC: S4U2Proxy (User ticket → Service ticket)
    Note over KDC: Check msDS-AllowedToDelegateTo
    KDC-->>Agent: Service ticket (as User)

    Agent->>Service: AP-REQ (as User)
    Service-->>Agent: Response
    Agent-->>User: Action completed

    Note over Agent,Service: RBCD (Resource-Based Constrained Delegation) is configured<br/>on the msDS-AgentSandbox (computer) object, not the<br/>msDS-Agent (user) object. The sandbox computer account<br/>holds the msDS-AllowedToActOnBehalfOfOtherIdentity attribute.
```

## Tool Authorization Flow

```mermaid
flowchart TD
    A[Agent requests tool] --> B{Tool in DeniedTools?}
    B -->|Yes| C[DENY - ExplicitDeny]
    B -->|No| D{Tool in AuthorizedTools?}
    D -->|Yes| E[ALLOW - DirectGrant]
    D -->|No| F{Agent in tool-grant group?}
    F -->|Yes| G[ALLOW - GroupGrant]
    F -->|No| H{Agent TrustLevel >= Tool RequiredTrustLevel?}
    H -->|Yes| I[ALLOW - TrustLevelSufficient]
    H -->|No| J[DENY - TrustLevelInsufficient]

    E --> K{Check tool constraints}
    G --> K
    I --> K
    K -->|Pass| L[Execute tool]
    K -->|Fail| M[DENY - ConstraintViolation]

    L --> N[Log event 4000]
    C --> O[Log event 3001]
    J --> O
    M --> O
```

## Event Logging Architecture

```mermaid
flowchart LR
    subgraph Sources["Event Sources"]
        DC1[Domain Controller 1]
        DC2[Domain Controller 2]
        AgentRuntime[Agent Runtime]
    end

    subgraph EventLogs["Windows Event Logs"]
        Operational[Microsoft-AgentDirectory/Operational]
        Admin[Microsoft-AgentDirectory/Admin]
        Debug[Microsoft-AgentDirectory/Debug]
    end

    subgraph Collection["Event Collection"]
        WEF[Windows Event Forwarding]
        Collector[Event Collector Server]
    end

    subgraph SIEM["SIEM Integration"]
        Splunk[Splunk]
        Sentinel[Azure Sentinel]
        Elastic[Elastic SIEM]
    end

    DC1 --> Operational
    DC2 --> Operational
    AgentRuntime --> Operational
    DC1 --> Admin
    DC2 --> Admin

    Operational --> WEF
    Admin --> WEF
    WEF --> Collector
    Collector --> Splunk
    Collector --> Sentinel
    Collector --> Elastic
```

## Trust Level Hierarchy

```mermaid
graph TB
    subgraph TrustLevels["Trust Levels"]
        L0[Level 0: Untrusted]
        L1[Level 1: Basic]
        L2[Level 2: Standard]
        L3[Level 3: Elevated]
        L4[Level 4: System]
    end

    subgraph Capabilities["Allowed Capabilities"]
        C0[Read-only access<br/>No network<br/>No delegation]
        C1[Limited read/write<br/>No delegation<br/>Basic tools]
        C2[Normal operations<br/>Constrained delegation<br/>Most tools]
        C3[Broad access<br/>Protocol transition<br/>Management tools]
        C4[Full trust<br/>Unconstrained delegation<br/>All tools]
    end

    L0 --> C0
    L1 --> C1
    L2 --> C2
    L3 --> C3
    L4 --> C4

    style L0 fill:#ff6b6b
    style L1 fill:#feca57
    style L2 fill:#48dbfb
    style L3 fill:#ff9ff3
    style L4 fill:#1dd1a1
```

## Container Structure

```mermaid
graph TD
    subgraph Domain["DC=corp,DC=contoso,DC=com"]
        System["CN=System"]

        subgraph AgentContainer["CN=Agents"]
            Agent1[CN=claude-assistant-01]
            Agent2[CN=data-processor-01]
            AgentOU[OU=Department-Agents]
            Agent3[CN=dept-agent-01]
        end

        subgraph ToolContainer["CN=Agent Tools"]
            Tool1[CN=microsoft.powershell]
            Tool2[CN=microsoft.word]
            Tool3[CN=microsoft.sccm]
        end

        subgraph SandboxContainer["CN=Agent Sandboxes"]
            Sandbox1[CN=sandbox-prod-001]
            Sandbox2[CN=sandbox-dev-001]
        end
    end

    Domain --> System
    System --> AgentContainer
    System --> ToolContainer
    System --> SandboxContainer
    AgentOU --> Agent3
```

## Deployment Architecture

```mermaid
flowchart TB
    subgraph SchemaLayer["Schema Layer (Forest-wide)"]
        Schema[(AD Schema)]
        Attrs[Agent & Tool Attributes]
        Classes[msDS-Agent, msDS-AgentSandbox & msDS-AgentTool Classes]
    end

    subgraph DomainLayer["Domain Layer"]
        DC1[(Domain Controller 1)]
        DC2[(Domain Controller 2)]
        Containers[Agents & Tools Containers]
    end

    subgraph ManagementLayer["Management Layer"]
        PSModule[PowerShell Module]
        EventLog[Event Provider]
        GPO[Group Policy]
    end

    subgraph RuntimeLayer["Runtime Layer"]
        AgentRuntime1[Agent Runtime 1]
        AgentRuntime2[Agent Runtime 2]
        SandboxRuntime[Sandbox Runtime]
        ToolGateway[Tool Gateway Service]
    end

    Schema --> Attrs
    Schema --> Classes
    Attrs --> DC1
    Classes --> DC1
    DC1 <--> DC2
    DC1 --> Containers
    DC2 --> Containers

    PSModule --> DC1
    EventLog --> DC1
    GPO --> DC1

    AgentRuntime1 --> ToolGateway
    AgentRuntime2 --> ToolGateway
    ToolGateway --> DC1
```

## Component Interaction

```mermaid
flowchart LR
    subgraph Client["Client Application"]
        AI[AI Model]
        Runtime[Agent Runtime]
    end

    subgraph Gateway["Tool Gateway"]
        AuthZ[Authorization Check]
        Audit[Audit Logger]
        Executor[Tool Executor]
    end

    subgraph AD["Active Directory"]
        AgentObj[(Agent Object)]
        ToolObj[(Tool Object)]
        EventLog[(Event Log)]
    end

    subgraph Tools["Tools"]
        PS[PowerShell]
        Office[Office Apps]
        Mgmt[Management Tools]
    end

    AI --> Runtime
    Runtime --> AuthZ
    AuthZ --> AgentObj
    AuthZ --> ToolObj
    AuthZ --> Executor
    Executor --> Audit
    Audit --> EventLog
    Executor --> PS
    Executor --> Office
    Executor --> Mgmt
```

## Security Boundaries

```mermaid
flowchart TB
    subgraph Internet["Internet (Untrusted)"]
        ExtAPI[External APIs]
    end

    subgraph DMZ["DMZ"]
        Gateway[API Gateway]
        WAF[Web Application Firewall]
    end

    subgraph Corporate["Corporate Network"]
        subgraph AgentZone["Agent Zone"]
            AgentRuntime[Agent Runtimes]
            ToolGateway[Tool Gateway]
        end

        subgraph DataZone["Data Zone"]
            FileServers[File Servers]
            Databases[Databases]
        end

        subgraph ManagementZone["Management Zone"]
            DCs[Domain Controllers]
            SCCM[SCCM Server]
            PKI[PKI Infrastructure]
        end
    end

    ExtAPI -.->|Blocked| Gateway
    Gateway --> AgentRuntime
    AgentRuntime --> ToolGateway
    ToolGateway -->|Trust Level 2+| FileServers
    ToolGateway -->|Trust Level 3+| SCCM
    ToolGateway -->|Trust Level 4| DCs
    AgentRuntime --> DCs
```

## Viewing These Diagrams

These diagrams are written in [Mermaid](https://mermaid.js.org/) syntax. To view them:

1. **GitHub/GitLab**: These platforms render Mermaid diagrams natively in markdown files
2. **VS Code**: Install the "Markdown Preview Mermaid Support" extension
3. **Online**: Use the [Mermaid Live Editor](https://mermaid.live/)
4. **Documentation**: Export to PNG/SVG using Mermaid CLI: `mmdc -i ARCHITECTURE.md -o diagrams/`
