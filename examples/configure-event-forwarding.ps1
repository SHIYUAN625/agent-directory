<#
.SYNOPSIS
    Example: Configure Windows Event Forwarding for Agent Directory events.

.DESCRIPTION
    This script demonstrates how to set up WEF to collect Agent Directory
    events from multiple Domain Controllers to a central collector.

.NOTES
    Prerequisites:
    - Windows Event Collector service available
    - AgentDirectory event provider installed on source computers
    - Network connectivity between sources and collector
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory, ParameterSetName = 'Collector')]
    [switch]$CollectorMode,

    [Parameter(Mandatory, ParameterSetName = 'Source')]
    [switch]$SourceMode,

    [Parameter(ParameterSetName = 'Source')]
    [string]$CollectorServer,

    [Parameter()]
    [string]$SubscriptionName = 'AgentDirectory-Events'
)

Write-Host "Agent Directory Event Forwarding Configuration" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

if ($CollectorMode) {
    Write-Host "Configuring as Event Collector..." -ForegroundColor Yellow
    Write-Host ""

    # Enable WEC service
    Write-Host "Enabling Windows Event Collector service..." -ForegroundColor White
    Set-Service -Name Wecsvc -StartupType Automatic
    Start-Service -Name Wecsvc

    # Configure WinRM for collector
    Write-Host "Configuring WinRM..." -ForegroundColor White
    winrm quickconfig -q

    # Create subscription XML
    $subscriptionXml = @"
<Subscription xmlns="http://schemas.microsoft.com/2006/03/windows/events/subscription">
    <SubscriptionId>$SubscriptionName</SubscriptionId>
    <SubscriptionType>SourceInitiated</SubscriptionType>
    <Description>Collects Agent Directory events from Domain Controllers</Description>
    <Enabled>true</Enabled>
    <Uri>http://schemas.microsoft.com/wbem/wsman/1/windows/EventLog</Uri>
    <ConfigurationMode>MinLatency</ConfigurationMode>
    <Delivery Mode="Push">
        <Batching>
            <MaxLatencyTime>30000</MaxLatencyTime>
        </Batching>
        <PushSettings>
            <Heartbeat Interval="3600000"/>
        </PushSettings>
    </Delivery>
    <Query>
        <![CDATA[
        <QueryList>
            <Query Id="0" Path="Microsoft-AgentDirectory/Operational">
                <Select Path="Microsoft-AgentDirectory/Operational">*</Select>
            </Query>
            <Query Id="1" Path="Microsoft-AgentDirectory/Admin">
                <Select Path="Microsoft-AgentDirectory/Admin">*[System[(Level=1 or Level=2 or Level=3)]]</Select>
            </Query>
        </QueryList>
        ]]>
    </Query>
    <ReadExistingEvents>true</ReadExistingEvents>
    <TransportName>HTTP</TransportName>
    <ContentFormat>RenderedText</ContentFormat>
    <Locale Language="en-US"/>
    <LogFile>ForwardedEvents</LogFile>
    <AllowedSourceNonDomainComputers></AllowedSourceNonDomainComputers>
    <AllowedSourceDomainComputers>O:NSG:BAD:P(A;;GA;;;DC)S:</AllowedSourceDomainComputers>
</Subscription>
"@

    # Save subscription
    $subscriptionFile = "$env:TEMP\$SubscriptionName.xml"
    $subscriptionXml | Out-File -FilePath $subscriptionFile -Encoding UTF8

    Write-Host "Creating subscription..." -ForegroundColor White
    wecutil cs $subscriptionFile

    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "Collector configured successfully!" -ForegroundColor Green
        Write-Host ""
        Write-Host "Subscription details:" -ForegroundColor Cyan
        wecutil gs $SubscriptionName
    }
    else {
        Write-Error "Failed to create subscription"
    }

    Remove-Item $subscriptionFile -Force

    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "  1. Run this script with -SourceMode on each Domain Controller"
    Write-Host "  2. Verify events appear in 'Forwarded Events' log"
    Write-Host "  3. Configure SIEM to read from this collector"
}
elseif ($SourceMode) {
    if (-not $CollectorServer) {
        $CollectorServer = Read-Host "Enter collector server FQDN"
    }

    Write-Host "Configuring as Event Source..." -ForegroundColor Yellow
    Write-Host "Collector: $CollectorServer"
    Write-Host ""

    # Configure WinRM
    Write-Host "Configuring WinRM..." -ForegroundColor White
    winrm quickconfig -q

    # Add collector to trusted hosts if needed
    Write-Host "Configuring event forwarding..." -ForegroundColor White

    # Configure group policy for event forwarding
    $gpoPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\EventLog\EventForwarding\SubscriptionManager"

    if (-not (Test-Path $gpoPath)) {
        New-Item -Path $gpoPath -Force | Out-Null
    }

    $subscriptionUrl = "Server=http://$CollectorServer`:5985/wsman/SubscriptionManager/WEC,Refresh=60"
    Set-ItemProperty -Path $gpoPath -Name "1" -Value $subscriptionUrl

    # Restart WinRM to apply
    Restart-Service -Name WinRM

    Write-Host ""
    Write-Host "Source configured successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Subscription URL: $subscriptionUrl"
    Write-Host ""
    Write-Host "Verify with:" -ForegroundColor Cyan
    Write-Host "  wecutil gr $SubscriptionName"
}

Write-Host ""
Write-Host "Troubleshooting:" -ForegroundColor Cyan
Write-Host "  - Check 'Microsoft-Windows-Forwarding/Operational' log on sources"
Write-Host "  - Check 'Microsoft-Windows-EventCollector/Operational' log on collector"
Write-Host "  - Ensure firewall allows WinRM (TCP 5985)"
Write-Host "  - Verify computer accounts have 'Read' permission on ForwardedEvents log"
Write-Host ""
