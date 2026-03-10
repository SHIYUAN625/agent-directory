#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Launch a psh-agent with identity, tools, instructions, and policies from Active Directory.

.DESCRIPTION
    Reads an agent's identity from the Samba4 DC via LDAP, assembles a system prompt
    from instruction GPOs, maps authorized tools to psh-agent tool definitions,
    creates policy enforcement hooks, and launches psh-agent.

.PARAMETER AgentName
    The agent's sAMAccountName (without trailing $). e.g., claude-assistant-01

.PARAMETER LdapUri
    LDAP URI to the domain controller. Default: ldaps://localhost

.PARAMETER BaseDN
    Base distinguished name. Default: DC=autonomy,DC=local

.PARAMETER AdminDN
    Bind DN for LDAP queries. Default: CN=Administrator,CN=Users,DC=autonomy,DC=local

.PARAMETER AdminPassword
    Bind password. Default: reads from AGENT_AD_PASSWORD env var or prompts.

.PARAMETER PshAgentPath
    Path to the PshAgent module. Default: ~/projects/psh-agent/PshAgent

.PARAMETER WorkingDirectory
    Working directory for the agent. Default: current directory.

.PARAMETER DryRun
    Show what would be launched without actually starting the agent.

.EXAMPLE
    ./Start-AgentFromAD.ps1 -AgentName claude-assistant-01
    ./Start-AgentFromAD.ps1 claude-assistant-01 -DryRun
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string]$AgentName,

    [string]$LdapUri,

    [string]$BaseDN,

    [string]$AdminDN,

    [string]$AdminPassword,

    [string]$PshAgentPath,

    [string]$WorkingDirectory,

    [string]$SysvolPath,

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# ============================================================================
# RESOLVE DEFAULTS FROM ENVIRONMENT
# ============================================================================

if (-not $LdapUri)          { $LdapUri          = if ($env:AGENT_AD_LDAP_URI)   { $env:AGENT_AD_LDAP_URI }   else { 'ldaps://dc1' } }
if (-not $BaseDN)           { $BaseDN           = if ($env:AGENT_AD_BASE_DN)    { $env:AGENT_AD_BASE_DN }    else { 'DC=autonomy,DC=local' } }
if (-not $AdminDN)          { $AdminDN          = if ($env:AGENT_AD_BIND_DN)    { $env:AGENT_AD_BIND_DN }    else { "CN=Administrator,CN=Users,$BaseDN" } }
if (-not $PshAgentPath)     { $PshAgentPath     = if ($env:AGENT_PSHAGENT_PATH) { $env:AGENT_PSHAGENT_PATH } else { '/opt/psh-agent/PshAgent' } }
if (-not $WorkingDirectory) { $WorkingDirectory = $PWD.Path }
if (-not $SysvolPath)       { $SysvolPath       = $env:AGENT_SYSVOL_PATH }

# ============================================================================
# LDAP HELPERS
# ============================================================================

function Invoke-LdapSearch {
    param(
        [string]$Base,
        [string]$Filter = '(objectClass=*)',
        [string[]]$Attributes = @('*'),
        [string]$Scope = 'sub'
    )

    $env:LDAPTLS_REQCERT = 'never'
    $ldapArgs = @(
        '-H', $script:LdapUri,
        '-x',
        '-D', $script:AdminDN,
        '-w', $script:AdminPassword,
        '-b', $Base,
        '-s', $Scope,
        $Filter
    ) + $Attributes

    $raw = & ldapsearch @ldapArgs 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "LDAP search failed (exit $LASTEXITCODE): base=$Base filter=$Filter"
    }

    # Parse LDIF output into hashtable(s)
    $entries = @()
    $current = @{}
    $lastAttr = $null

    foreach ($line in $raw) {
        # Skip comments and blank lines
        if ($line -match '^\s*#' -or $line -match '^\s*$') {
            if ($current.Count -gt 0) {
                $entries += $current
                $current = @{}
                $lastAttr = $null
            }
            continue
        }
        # Skip search metadata
        if ($line -match '^search:' -or $line -match '^result:' -or $line -match '^ref:') {
            continue
        }
        # Continuation line (starts with space)
        if ($line -match '^ (.+)') {
            if ($lastAttr -and $current[$lastAttr]) {
                if ($current[$lastAttr] -is [array]) {
                    $current[$lastAttr][-1] += $Matches[1]
                } else {
                    $current[$lastAttr] += $Matches[1]
                }
            }
            continue
        }
        # Attribute: value
        if ($line -match '^([^:]+):\s*(.*)$') {
            $attr = $Matches[1]
            $val = $Matches[2]
            $lastAttr = $attr

            if ($current.ContainsKey($attr)) {
                if ($current[$attr] -is [array]) {
                    $current[$attr] += $val
                } else {
                    $current[$attr] = @($current[$attr], $val)
                }
            } else {
                $current[$attr] = $val
            }
        }
    }
    if ($current.Count -gt 0) {
        $entries += $current
    }

    # Wrap in , to prevent PowerShell pipeline unrolling single-element arrays
    return ,$entries
}

function Read-SysvolFile {
    param([string]$RelativePath)
    $domain = $script:BaseDN -replace 'DC=', '' -replace ',', '.'

    # Try local SYSVOL path first (when running inside Docker with mounted SYSVOL)
    if ($script:SysvolPath) {
        $localPath = Join-Path $script:SysvolPath $RelativePath
        if (Test-Path $localPath) {
            return (Get-Content -Path $localPath -Raw)
        }
    }

    # Try SMB (when DC is on the network)
    $dcHost = $script:LdapUri -replace 'ldaps?://',''
    try {
        $content = smbclient "//$dcHost/sysvol" -U "Administrator%$($script:AdminPassword)" `
            -c "get $domain/$RelativePath /dev/stdout" 2>/dev/null
        if ($LASTEXITCODE -eq 0 -and $content) {
            return ($content -join "`n")
        }
    } catch {}

    # Fallback: try smbclient with full path
    try {
        $tmpFile = [System.IO.Path]::GetTempFileName()
        $null = smbclient "//$dcHost/sysvol" -U "Administrator%$($script:AdminPassword)" `
            -c "get $domain/$RelativePath $tmpFile" 2>/dev/null
        if ($LASTEXITCODE -eq 0 -and (Test-Path $tmpFile)) {
            $content = Get-Content -Path $tmpFile -Raw
            Remove-Item $tmpFile -Force
            if ($content) { return $content }
        }
        Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
    } catch {}

    Write-Warning "Could not read SYSVOL: $RelativePath"
    return $null
}

function Get-CnFromDn {
    param([string]$DN)
    if ($DN -match '^CN=([^,]+)') {
        return $Matches[1]
    }
    return $DN
}

# ============================================================================
# RESOLVE CREDENTIALS
# ============================================================================

if (-not $AdminPassword) {
    $AdminPassword = $env:AGENT_AD_PASSWORD
}
if (-not $AdminPassword) {
    $AdminPassword = Read-Host -Prompt 'AD admin password'
}

# ============================================================================
# LOAD AGENT IDENTITY FROM AD
# ============================================================================

Write-Host "`n[*] Loading identity for agent: $AgentName" -ForegroundColor Cyan

$agentDN = "CN=${AgentName}`$,CN=Agents,CN=System,$BaseDN"
$agentEntries = Invoke-LdapSearch -Base $agentDN -Scope 'base' -Filter '(objectClass=x-agent)' -Attributes @(
    'cn', 'sAMAccountName',
    'x-agent-Type', 'x-agent-TrustLevel', 'x-agent-Model', 'x-agent-Mission',
    'x-agent-AuthorizedTools', 'x-agent-DeniedTools',
    'x-agent-Policies', 'x-agent-InstructionGPOs',
    'x-agent-LLMAccess', 'x-agent-LLMQuota',
    'x-agent-NatsSubjects', 'x-agent-EscalationPath',
    'x-agent-Sandbox', 'x-agent-AuditLevel',
    'memberOf'
)

if ($agentEntries.Count -eq 0) {
    throw "Agent '$AgentName' not found in AD at: $agentDN"
}
$agent = $agentEntries[0]

$agentType      = $agent.'x-agent-Type'
$trustLevel     = [int]($agent.'x-agent-TrustLevel' ?? '0')
$model          = $agent.'x-agent-Model'
$mission        = $agent.'x-agent-Mission'
$auditLevel     = [int]($agent.'x-agent-AuditLevel' ?? '0')
$llmQuotaJson   = $agent.'x-agent-LLMQuota'

# Normalize multi-valued fields to arrays
$authorizedToolDNs = @($agent.'x-agent-AuthorizedTools' | Where-Object { $_ })
$deniedToolDNs     = @($agent.'x-agent-DeniedTools' | Where-Object { $_ })
$policyDNs         = @($agent.'x-agent-Policies' | Where-Object { $_ })
$gpoDNs            = @($agent.'x-agent-InstructionGPOs' | Where-Object { $_ })
$llmAccess         = @($agent.'x-agent-LLMAccess' | Where-Object { $_ })
$natsSubjects      = @($agent.'x-agent-NatsSubjects' | Where-Object { $_ })

Write-Host "    Type:        $agentType"
Write-Host "    Trust:       $trustLevel"
Write-Host "    Model:       $model"
Write-Host "    Mission:     $mission"
Write-Host "    Tools:       $($authorizedToolDNs.Count) granted, $($deniedToolDNs.Count) denied"
Write-Host "    Policies:    $($policyDNs.Count)"
Write-Host "    GPOs:        $($gpoDNs.Count)"

# ============================================================================
# RESOLVE TOOL GRANTS
# ============================================================================

Write-Host "`n[*] Resolving tool grants..." -ForegroundColor Cyan

$authorizedToolIds = @()
foreach ($toolDN in $authorizedToolDNs) {
    $toolEntries = Invoke-LdapSearch -Base $toolDN -Scope 'base' -Attributes @(
        'x-tool-Identifier', 'x-tool-Category', 'x-tool-RiskLevel'
    )
    if ($toolEntries.Count -gt 0) {
        $toolId = $toolEntries[0].'x-tool-Identifier'
        $risk = $toolEntries[0].'x-tool-RiskLevel'
        $authorizedToolIds += $toolId
        Write-Host "    [+] $toolId (risk: $risk)"
    }
}

$deniedToolIds = @()
foreach ($toolDN in $deniedToolDNs) {
    $toolEntries = Invoke-LdapSearch -Base $toolDN -Scope 'base' -Attributes @('x-tool-Identifier')
    if ($toolEntries.Count -gt 0) {
        $deniedToolIds += $toolEntries[0].'x-tool-Identifier'
    }
}

# ============================================================================
# MAP AD TOOL GRANTS -> PSH-AGENT TOOLS
# ============================================================================

# AD tool identifier -> psh-agent built-in tool mapping
$toolMapping = @{
    'filesystem.read'       = @('read_file', 'list_directory', 'search_files', 'grep')
    'filesystem.write'      = @('write_file')
    'filesystem.delete'     = @()  # No built-in for this
    'git.cli'               = @()  # Handled via run_command authorization
    'python.interpreter'    = @()  # Handled via run_command authorization
    'node.interpreter'      = @()  # Handled via run_command authorization
    'gnu.bash'              = @('run_command')
    'gnu.bash.restricted'   = @('run_command')
    'llm.inference'         = @()  # Authorizes the LLM call itself
}

# Tools that grant run_command with restrictions (prefix match on command)
$commandToolPrefixes = @{
    'git.cli'            = @('git ')
    'python.interpreter' = @('python ', 'python3 ', 'pip ', 'pip3 ')
    'node.interpreter'   = @('node ', 'npm ', 'npx ')
    'cargo.build'        = @('cargo ')
    'make.build'         = @('make ')
    'docker.cli'         = @('docker ', 'docker-compose ')
}

# Compute which psh-agent tools to register
$enabledBuiltinTools = [System.Collections.Generic.HashSet[string]]::new()
$allowedCommandPrefixes = [System.Collections.Generic.List[string]]::new()
$hasUnrestrictedShell = $false

foreach ($toolId in $authorizedToolIds) {
    if ($deniedToolIds -contains $toolId) {
        Write-Host "    [-] $toolId (denied override)" -ForegroundColor Red
        continue
    }

    # Map to built-in tools
    if ($toolMapping.ContainsKey($toolId)) {
        foreach ($bt in $toolMapping[$toolId]) {
            [void]$enabledBuiltinTools.Add($bt)
        }
    }

    # Check for command-prefix tools
    if ($commandToolPrefixes.ContainsKey($toolId)) {
        [void]$enabledBuiltinTools.Add('run_command')
        foreach ($p in $commandToolPrefixes[$toolId]) { $allowedCommandPrefixes.Add($p) }
    }

    # Unrestricted shell
    if ($toolId -eq 'gnu.bash') {
        $hasUnrestrictedShell = $true
    }
}

Write-Host "`n[*] Enabled psh-agent tools: $($enabledBuiltinTools -join ', ')" -ForegroundColor Cyan
if (-not $hasUnrestrictedShell -and $allowedCommandPrefixes.Count -gt 0) {
    Write-Host "    Command prefixes: $($allowedCommandPrefixes -join ', ')"
}

# ============================================================================
# READ INSTRUCTION GPOS -> SYSTEM PROMPT
# ============================================================================

Write-Host "`n[*] Assembling system prompt from instruction GPOs..." -ForegroundColor Cyan

$instructionParts = @()
foreach ($gpoDN in $gpoDNs) {
    $gpoEntries = Invoke-LdapSearch -Base $gpoDN -Scope 'base' -Attributes @(
        'x-gpo-DisplayName', 'x-gpo-InstructionPath', 'x-gpo-Priority', 'x-gpo-MergeStrategy'
    )
    if ($gpoEntries.Count -gt 0) {
        $gpo = $gpoEntries[0]
        $path = $gpo.'x-gpo-InstructionPath'
        $priority = [int]($gpo.'x-gpo-Priority' ?? '0')
        $name = $gpo.'x-gpo-DisplayName'

        $content = Read-SysvolFile -RelativePath $path
        if ($content) {
            $instructionParts += @{
                Name     = $name
                Priority = $priority
                Content  = $content
            }
            Write-Host "    [+] $name (priority: $priority)"
        } else {
            Write-Host "    [!] $name — content not found at $path" -ForegroundColor Yellow
        }
    }
}

# Sort by priority (lowest first = base instructions first)
$instructionParts = $instructionParts | Sort-Object { $_.Priority }

# Build system prompt
$systemPromptParts = @()

# Agent identity header
$systemPromptParts += @"
# Agent Identity

- **Name:** $AgentName
- **Type:** $agentType
- **Trust Level:** $trustLevel
- **Model:** $model
- **Mission:** $mission
- **Audit Level:** $auditLevel

Working directory: $WorkingDirectory
"@

# Append instruction GPO content in priority order
foreach ($part in $instructionParts) {
    $systemPromptParts += $part.Content
}

# Append tool authorization summary
$toolSection = @"

# Tool Authorization

You are authorized to use the following tools: $($authorizedToolIds -join ', ')
"@
if ($deniedToolIds.Count -gt 0) {
    $toolSection += "`nExplicitly denied: $($deniedToolIds -join ', ')"
}
if (-not $hasUnrestrictedShell -and $allowedCommandPrefixes.Count -gt 0) {
    $toolSection += "`nFor shell commands, you may only run: $($allowedCommandPrefixes -join ', ')"
}
$systemPromptParts += $toolSection

$systemPrompt = $systemPromptParts -join "`n`n"

# ============================================================================
# READ POLICIES -> ENFORCEMENT CONFIG
# ============================================================================

Write-Host "`n[*] Loading policies..." -ForegroundColor Cyan

$mergedPolicy = @{
    tools     = @{ deny = @() }
    execution = @{}
    llm       = @{}
    audit     = @{}
}

foreach ($policyDN in $policyDNs) {
    $policyEntries = Invoke-LdapSearch -Base $policyDN -Scope 'base' -Attributes @(
        'x-policy-Identifier', 'x-policy-Path', 'x-policy-Priority', 'x-policy-Enabled'
    )
    if ($policyEntries.Count -gt 0 -and $policyEntries[0].'x-policy-Enabled' -eq 'TRUE') {
        $policyPath = $policyEntries[0].'x-policy-Path'
        $policyId = $policyEntries[0].'x-policy-Identifier'
        $content = Read-SysvolFile -RelativePath $policyPath

        if ($content) {
            $policyJson = $content | ConvertFrom-Json -AsHashtable
            $settings = $policyJson.settings

            # Merge tool denials
            if ($settings.tools.deny) {
                $mergedPolicy.tools.deny += $settings.tools.deny
            }

            # Merge execution limits (higher priority overwrites)
            if ($settings.execution) {
                foreach ($k in $settings.execution.Keys) {
                    $mergedPolicy.execution[$k] = $settings.execution[$k]
                }
            }

            # Merge LLM limits
            if ($settings.llm) {
                foreach ($k in $settings.llm.Keys) {
                    $mergedPolicy.llm[$k] = $settings.llm[$k]
                }
            }

            # Merge audit settings
            if ($settings.audit) {
                foreach ($k in $settings.audit.Keys) {
                    $mergedPolicy.audit[$k] = $settings.audit[$k]
                }
            }

            Write-Host "    [+] $policyId"
        }
    }
}

# Also apply agent-specific LLM quota
$llmQuota = @{}
if ($llmQuotaJson) {
    $llmQuota = $llmQuotaJson | ConvertFrom-Json -AsHashtable
    if ($llmQuota.daily_tokens) {
        $mergedPolicy.llm['daily_token_limit'] = $llmQuota.daily_tokens
    }
    if ($llmQuota.max_context) {
        $mergedPolicy.llm['max_context_tokens'] = $llmQuota.max_context
    }
}

# Max iterations from policy
$maxSteps = [int]($mergedPolicy.execution.max_iterations ?? 50)

# ============================================================================
# MAP MODEL -> CONNECTION STRING
# ============================================================================

# Model names in AD map directly to API model IDs (e.g., claude-opus-4-5, claude-sonnet-4)
$provider = if ($model -match '^(claude|anthropic)') { 'anthropic' }
             elseif ($model -match '^(gpt|openai)') { 'openai' }
             else { 'anthropic' }
$connectionString = "$provider/$model"

Write-Host "`n[*] Connection: $connectionString" -ForegroundColor Cyan
Write-Host "    Max steps: $maxSteps"

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
    # Map policy tool IDs to psh-agent tool names that would be used
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
    $agentId = $AgentName
    $hooks += New-Hook -Name 'ad_audit_log' -EventType ToolEnd -Fn {
        param($event)
        $ts = [datetime]::UtcNow.ToString('o')
        $toolName = $event.ToolCall.Name
        $args = ($event.ToolCall.Arguments | ConvertTo-Json -Compress -Depth 3)
        if ($args.Length -gt 200) { $args = $args.Substring(0, 197) + '...' }
        # Write to stderr so it doesn't interfere with agent output
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

Write-Host "`n[*] Launching agent: $AgentName ($agentType)" -ForegroundColor Green
Write-Host "    Model:     $connectionString"
Write-Host "    Tools:     $($tools.Name -join ', ')"
Write-Host "    Hooks:     $($hooks.Name -join ', ')"
Write-Host "    Max steps: $maxSteps"
Write-Host ""

Start-PshAgent `
    -ConnectionString $connectionString `
    -SystemPrompt $systemPrompt `
    -Tools $tools `
    -Hooks $hooks `
    -MaxSteps $maxSteps
