# Simple msDS-Agent

One agent. It has tools. It can call other agents. That's it.

## The Model

```
┌─────────────────────────────────────────┐
│               AGENT                     │
│                                         │
│  Identity      → AD account             │
│  Trust Level   → What it can do (0-4)   │
│  Tools         → What tools it can use  │
│  Delegation    → What agents it can call│
└─────────────────────────────────────────┘
```

## Create an Agent

```powershell
New-ADAgent -Name "my-agent" -TrustLevel 2 -Owner $myDN
Grant-ADAgentToolAccess -Identity "my-agent" -Tool @('filesystem.read', 'api.http')
Set-ADAgent -Identity "my-agent" -Enabled $true
```

## Run It

```powershell
# Interactive
.\Agent.ps1 -Identity "my-agent"

# With a task
.\Agent.ps1 -Identity "my-agent" -Task "Summarize the files in /data"
```

## Call Another Agent

If your agent needs help, it calls another agent:

```powershell
$result = $agent.CallAgent("pdf-converter", @{ file = $path })
```

This requires:
- Trust level 2+
- `pdf-converter` in your `msDS-AgentDelegationScope`
