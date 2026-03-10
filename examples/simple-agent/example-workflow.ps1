<#
.SYNOPSIS
    Example: One agent calling others. No orchestrator needed.

.DESCRIPTION
    Shows how a "main" agent can delegate work to specialized agents.
    This is just normal code - no special workflow engine required.
#>

#Requires -Modules AgentDirectory

# Setup (run once)
# .\create-agent.ps1 -Name "main-agent" -TrustLevel 2 -Tools @('filesystem.read') -CanCall @('summarizer', 'translator')
# .\create-agent.ps1 -Name "summarizer" -TrustLevel 1 -Tools @('filesystem.read')
# .\create-agent.ps1 -Name "translator" -TrustLevel 1

# --- The "workflow" is just code ---

class MainAgent {
    [Agent]$agent

    MainAgent([string]$identity) {
        $this.agent = [Agent]::new($identity, $null)
    }

    [object] ProcessDocument([string]$path, [string]$targetLanguage) {
        Write-Host "Processing: $path" -ForegroundColor Cyan

        # Step 1: Read the file (using our own tool)
        $content = $this.agent.UseTool('filesystem.read', @{ Path = $path })
        Write-Host "  Read $($content.Length) chars"

        # Step 2: Call summarizer agent
        $summary = $this.agent.CallAgent('summarizer', @{
            text = $content
            max_length = 200
        })
        Write-Host "  Got summary"

        # Step 3: Call translator agent
        $translated = $this.agent.CallAgent('translator', @{
            text = $summary.output
            target = $targetLanguage
        })
        Write-Host "  Translated to $targetLanguage"

        return @{
            original_length = $content.Length
            summary = $summary.output
            translated = $translated.output
        }
    }
}

# --- Usage ---

# $workflow = [MainAgent]::new("main-agent")
# $result = $workflow.ProcessDocument("C:\docs\report.txt", "spanish")

Write-Host @"

This example shows the pattern:

1. Main agent reads a file (its own tool)
2. Main agent calls 'summarizer' agent (delegation)
3. Main agent calls 'translator' agent (delegation)

No orchestrator mode. No workflow engine. Just code.

The msDS primitives enforced:
- Main agent must have 'filesystem.read' tool access
- Main agent must have 'summarizer' and 'translator' in delegation scope
- Each sub-agent enforces its own tool access

"@ -ForegroundColor Gray
