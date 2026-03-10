<#
.SYNOPSIS
    Simple agent runtime.

.EXAMPLE
    .\Agent.ps1 -Identity "my-agent"

.EXAMPLE
    .\Agent.ps1 -Identity "my-agent" -Task "Read /data/report.txt and summarize it"
#>

#Requires -Modules AgentDirectory

param(
    [Parameter(Mandatory)]
    [string]$Identity,

    [Parameter()]
    [string]$Task,

    [Parameter()]
    [string]$User
)

class Agent {
    [PSCustomObject]$Info
    [string]$User

    Agent([string]$identity, [string]$user) {
        $this.Info = Get-ADAgent -Identity $identity -ErrorAction Stop

        if (-not $this.Info.Enabled) {
            throw "Agent is disabled"
        }

        $this.User = $user

        Write-ADAgentEvent -EventId 1000 -AgentName $this.Info.Name `
            -Message "Agent started" -Level Information
    }

    # -------------------------------------------------------------------------
    # USE A TOOL
    # -------------------------------------------------------------------------
    [object] UseTool([string]$tool, [hashtable]$params) {
        # Check authorization
        $auth = Test-ADAgentToolAccess -Identity $this.Info.Name -Tool $tool

        if (-not $auth.Allowed) {
            Write-ADAgentEvent -EventId 3001 -AgentName $this.Info.Name `
                -ToolId $tool -Message "Denied: $($auth.Reason)" -Level Warning
            throw "Tool '$tool' denied: $($auth.Reason)"
        }

        # Log and execute
        Write-ADAgentEvent -EventId 4000 -AgentName $this.Info.Name `
            -ToolId $tool -Message "Executing tool" -Level Information

        return $this.ExecuteTool($tool, $params)
    }

    hidden [object] ExecuteTool([string]$tool, [hashtable]$params) {
        switch ($tool) {
            'filesystem.read'  { return Get-Content -Path $params.Path -Raw }
            'filesystem.write' { Set-Content -Path $params.Path -Value $params.Content; return "OK" }
            'api.http'         { return Invoke-RestMethod -Uri $params.Uri -Method ($params.Method ?? 'GET') }
            default            { throw "Unknown tool: $tool" }
        }
    }

    # -------------------------------------------------------------------------
    # CALL ANOTHER AGENT
    # -------------------------------------------------------------------------
    [object] CallAgent([string]$agentName, [hashtable]$input) {
        # Check if we can delegate to this agent
        $scope = $this.Info.DelegationScope
        $allowed = ("AGENT/$agentName" -in $scope) -or ("AGENT/*" -in $scope)

        if (-not $allowed) {
            throw "Cannot call agent '$agentName': not in delegation scope"
        }

        Write-ADAgentEvent -EventId 5000 -AgentName $this.Info.Name `
            -TargetResource "AGENT/$agentName" -Message "Calling agent" -Level Information

        # In practice: HTTP call to agent's runtime endpoint
        # For now: simulate
        Write-Host "  [CALL] $agentName <- $($input | ConvertTo-Json -Compress)" -ForegroundColor Magenta

        return @{ status = "ok"; agent = $agentName; simulated = $true }
    }

    # -------------------------------------------------------------------------
    # INTERACTIVE LOOP
    # -------------------------------------------------------------------------
    [void] Interactive() {
        Write-Host "`nAgent: $($this.Info.Name) (Trust: $($this.Info.TrustLevel))" -ForegroundColor Cyan
        Write-Host "Commands: read <path>, write <path> <content>, call <agent>, quit`n"

        while ($true) {
            $input = Read-Host ">"

            if ($input -eq 'quit') { break }

            try {
                $output = $this.ProcessCommand($input)
                if ($output) { Write-Host $output -ForegroundColor Green }
            } catch {
                Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }

    hidden [string] ProcessCommand([string]$cmd) {
        if ($cmd -match '^read\s+(.+)') {
            $path = $Matches[1].Trim('"', "'")
            return $this.UseTool('filesystem.read', @{ Path = $path })
        }

        if ($cmd -match '^write\s+(\S+)\s+(.+)') {
            $path = $Matches[1]
            $content = $Matches[2]
            return $this.UseTool('filesystem.write', @{ Path = $path; Content = $content })
        }

        if ($cmd -match '^call\s+(\S+)\s*(.*)') {
            $agent = $Matches[1]
            $data = if ($Matches[2]) { $Matches[2] | ConvertFrom-Json -AsHashtable } else { @{} }
            $result = $this.CallAgent($agent, $data)
            return $result | ConvertTo-Json
        }

        if ($cmd -match '^http\s+(\S+)') {
            return $this.UseTool('api.http', @{ Uri = $Matches[1] }) | ConvertTo-Json
        }

        return "Unknown command. Try: read, write, call, http, quit"
    }

    # -------------------------------------------------------------------------
    # RUN A TASK
    # -------------------------------------------------------------------------
    [object] RunTask([string]$task) {
        Write-Host "Task: $task" -ForegroundColor Yellow

        # Simple task parsing (real implementation would use LLM)
        if ($task -match 'read\s+(\S+)') {
            return $this.UseTool('filesystem.read', @{ Path = $Matches[1] })
        }

        if ($task -match 'call\s+(\S+)') {
            return $this.CallAgent($Matches[1], @{ task = $task })
        }

        return "Don't know how to: $task"
    }

    [void] Stop() {
        Write-ADAgentEvent -EventId 1001 -AgentName $this.Info.Name `
            -Message "Agent stopped" -Level Information
    }
}

# === MAIN ===

try {
    $agent = [Agent]::new($Identity, $User)

    if ($Task) {
        $result = $agent.RunTask($Task)
        Write-Host $result
    } else {
        $agent.Interactive()
    }

    $agent.Stop()
}
catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
