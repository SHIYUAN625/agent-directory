#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Launch a psh-agent from a sealed configuration JSON file.

.DESCRIPTION
    Config-based launcher that replaces Start-AgentFromAD.ps1 in the broker architecture.
    Reads all agent identity, tools, instructions, and policies from a JSON file
    assembled by the Python broker — NO LDAP access, NO admin credentials.

.PARAMETER ConfigPath
    Path to the sealed config JSON file written by agent-broker.py.

.PARAMETER PshAgentPath
    Path to the PshAgent module. Default: /opt/psh-agent/PshAgent

.PARAMETER WorkingDirectory
    Working directory for the agent. Default: current directory.

.PARAMETER DryRun
    Show what would be launched without actually starting the agent.

.EXAMPLE
    ./Start-AgentFromConfig.ps1 /run/agent-config/claude-assistant-01.json
    ./Start-AgentFromConfig.ps1 /run/agent-config/claude-assistant-01.json -DryRun
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string]$ConfigPath,

    [string]$PshAgentPath,

    [string]$WorkingDirectory,

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# ============================================================================
# RESOLVE DEFAULTS
# ============================================================================

if (-not $PshAgentPath)     { $PshAgentPath     = if ($env:AGENT_PSHAGENT_PATH) { $env:AGENT_PSHAGENT_PATH } else { '/opt/psh-agent/PshAgent' } }
if (-not $WorkingDirectory) { $WorkingDirectory = $PWD.Path }

# ============================================================================
# LOAD SEALED CONFIG
# ============================================================================

Write-Host "`n[*] Loading sealed config: $ConfigPath" -ForegroundColor Cyan

if (-not (Test-Path $ConfigPath)) {
    throw "Config file not found: $ConfigPath"
}

$config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json -AsHashtable

$identity         = $config.agent
$connectionString = $config.connection_string
$systemPrompt     = $config.system_prompt
$toolsConfig      = $config.tools
$mergedPolicy     = $config.policy
$maxSteps         = $config.max_steps

$agentName  = $identity.name
$agentType  = $identity.type
$trustLevel = $identity.trust_level
$model      = $identity.model

Write-Host "    Agent:       $agentName"
Write-Host "    Type:        $agentType"
Write-Host "    Trust:       $trustLevel"
Write-Host "    Model:       $model"
Write-Host "    Mission:     $($identity.mission)"

# ============================================================================
# EXTRACT TOOL CONFIG
# ============================================================================

$enabledBuiltinTools     = [System.Collections.Generic.HashSet[string]]::new()
$allowedCommandPrefixes  = [System.Collections.Generic.List[string]]::new()
$hasUnrestrictedShell    = [bool]$toolsConfig.has_unrestricted_shell

foreach ($bt in $toolsConfig.enabled_builtin_tools) {
    [void]$enabledBuiltinTools.Add($bt)
}
foreach ($p in $toolsConfig.allowed_command_prefixes) {
    $allowedCommandPrefixes.Add($p)
}

Write-Host "`n[*] Enabled psh-agent tools: $($enabledBuiltinTools -join ', ')" -ForegroundColor Cyan
if (-not $hasUnrestrictedShell -and $allowedCommandPrefixes.Count -gt 0) {
    Write-Host "    Command prefixes: $($allowedCommandPrefixes -join ', ')"
}

# ============================================================================
# DRY RUN OUTPUT
# ============================================================================

if ($DryRun) {
    Write-Host "`n========================================" -ForegroundColor Yellow
    Write-Host "DRY RUN — would launch with:" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host "`n--- System Prompt ---`n" -ForegroundColor Magenta
    Write-Host $systemPrompt
    Write-Host "`n--- Enabled Tools ---" -ForegroundColor Magenta
    Write-Host ($enabledBuiltinTools -join ', ')
    Write-Host "`n--- Policy (merged) ---" -ForegroundColor Magenta
    Write-Host ($mergedPolicy | ConvertTo-Json -Depth 5)
    Write-Host "`n--- Connection ---" -ForegroundColor Magenta
    Write-Host "Model: $connectionString"
    Write-Host "Max steps: $maxSteps"
    Write-Host "Broker socket: $($env:BROKER_SOCKET ?? 'not set')"
    return
}

# ============================================================================
# IMPORT PSH-AGENT AND BUILD TOOLS
# ============================================================================

Write-Host "`n[*] Loading psh-agent module..." -ForegroundColor Cyan

Import-Module $PshAgentPath -Force

# Register only authorized built-in tools
$tools = @()
if ($enabledBuiltinTools -contains 'read_file')       { $tools += Read-FileContent }
if ($enabledBuiltinTools -contains 'write_file')       { $tools += Write-FileContent }
if ($enabledBuiltinTools -contains 'list_directory')   { $tools += Get-DirectoryListing }
if ($enabledBuiltinTools -contains 'search_files')     { $tools += Search-Files }
if ($enabledBuiltinTools -contains 'grep')             { $tools += Search-FileContent }
if ($enabledBuiltinTools -contains 'run_command')      { $tools += Invoke-ShellCommand }

# ============================================================================
# BUILD ENFORCEMENT HOOKS
# ============================================================================

$hooks = @()

# Hook 1: Tool authorization — block run_command for unauthorized commands
if (-not $hasUnrestrictedShell -and $allowedCommandPrefixes.Count -gt 0) {
    $prefixes = $allowedCommandPrefixes.ToArray()
    $hooks += New-Hook -Name 'ad_command_authorization' -EventType ToolStart -Fn {
        param($event)
        if ($event.ToolCall.Name -ne 'run_command') { return $null }

        $cmd = $event.ToolCall.Arguments.command
        if (-not $cmd) { return $null }
        $cmdTrimmed = $cmd.TrimStart()

        $allowed = $false
        foreach ($prefix in $prefixes) {
            if ($cmdTrimmed.StartsWith($prefix)) {
                $allowed = $true
                break
            }
        }

        if (-not $allowed) {
            return [Reaction]::RetryWithFeedback(
                "POLICY VIOLATION: You are not authorized to run '$($cmdTrimmed.Split(' ')[0])'. " +
                "Allowed commands: $($prefixes -join ', '). Use only your authorized tools."
            )
        }
        return $null
    }.GetNewClosure()
}

# Hook 2: Policy-denied tools — block tools denied by policy
$policyDeniedTools = @($mergedPolicy.tools.deny | Where-Object { $_ })
if ($policyDeniedTools.Count -gt 0) {
    # Load tool mapping to resolve denied tool IDs to command prefixes
    $toolMappingPath = $env:AGENT_TOOL_MAPPING
    if (-not $toolMappingPath) { $toolMappingPath = '/opt/agent-launcher/tool-mapping.json' }

    $commandToolPrefixes = @{}
    if (Test-Path $toolMappingPath) {
        $mappingJson = Get-Content -Path $toolMappingPath -Raw | ConvertFrom-Json -AsHashtable
        $commandToolPrefixes = $mappingJson.command_tool_prefixes ?? @{}
    }

    $policyDeniedCommands = @()
    foreach ($denied in $policyDeniedTools) {
        if ($commandToolPrefixes.ContainsKey($denied)) {
            $policyDeniedCommands += $commandToolPrefixes[$denied]
        }
    }
    if ($policyDeniedCommands.Count -gt 0) {
        $deniedCmds = $policyDeniedCommands
        $hooks += New-Hook -Name 'ad_policy_denial' -EventType ToolStart -Fn {
            param($event)
            if ($event.ToolCall.Name -ne 'run_command') { return $null }
            $cmd = ($event.ToolCall.Arguments.command ?? '').TrimStart()
            foreach ($denied in $deniedCmds) {
                if ($cmd.StartsWith($denied)) {
                    return [Reaction]::Fail("POLICY DENIED: '$($cmd.Split(' ')[0])' is blocked by security policy.")
                }
            }
            return $null
        }.GetNewClosure()
    }
}

# Hook 3: Audit logging
if ($mergedPolicy.audit.log_all_tool_calls) {
    $agentId = $agentName
    $hooks += New-Hook -Name 'ad_audit_log' -EventType ToolEnd -Fn {
        param($event)
        $ts = [datetime]::UtcNow.ToString('o')
        $toolName = $event.ToolCall.Name
        $args = ($event.ToolCall.Arguments | ConvertTo-Json -Compress -Depth 3)
        if ($args.Length -gt 200) { $args = $args.Substring(0, 197) + '...' }
        [Console]::Error.WriteLine("[AUDIT] [$ts] agent=$agentId tool=$toolName args=$args")
        return $null
    }.GetNewClosure()
}

# Add default hooks
$hooks += New-BackoffOnRatelimitHook
$hooks += New-DangerousCommandHook
$hooks += New-RetryWithFeedbackHook -Feedback 'Please use a tool to make progress. If stuck, try a different approach.'

# ============================================================================
# LAUNCH
# ============================================================================

Write-Host "`n[*] Launching agent: $agentName ($agentType)" -ForegroundColor Green
Write-Host "    Model:     $connectionString"
Write-Host "    Tools:     $($tools.Name -join ', ')"
Write-Host "    Hooks:     $($hooks.Name -join ', ')"
Write-Host "    Max steps: $maxSteps"
Write-Host "    Source:    sealed config (DC-enforced, no LDAP creds)"
Write-Host ""

Start-PshAgent `
    -ConnectionString $connectionString `
    -SystemPrompt $systemPrompt `
    -Tools $tools `
    -Hooks $hooks `
    -MaxSteps $maxSteps
