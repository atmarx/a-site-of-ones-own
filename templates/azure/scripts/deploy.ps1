[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SubscriptionId,
    [Parameter(Mandatory)]
    [string]$ResourceGroupName,
    [string]$NamePrefix = 'rwh',
    [ValidateSet('dev', 'test', 'prod')]
    [string]$Environment = 'prod',
    [string]$AdminUsername = 'webadmin',
    [Parameter(Mandatory)]
    [string]$SshPublicKeyPath,
    [Parameter(Mandatory)]
    [string[]]$AdminSourceCidrs,
    [string]$Owner = 'Research Web Hosting',
    [string]$DataClassification = 'Public',
    [string]$VmSize = 'Standard_D2as_v7',
    [ValidateRange(32, 32767)]
    [int]$OsDiskSizeGB = 32,
    [ValidateRange(64, 32767)]
    [int]$DataDiskSizeGB = 64,
    [bool]$EnableDeletionLocks = $true,
    [switch]$SkipWhatIf,
    [switch]$Deploy,
    [ValidateRange(10, 180)]
    [int]$BootstrapTimeoutMinutes = 90
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$rockyGalleryName = 'rocky-dc1c6aa6-905b-4d9c-9577-63ccc28c482a'
$rockyImageDefinition = 'RESF-Rocky-10-x86_64-LVM'
$rockyImageVersion = '10.2.20260525'
$templateRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$templateFile = Join-Path $templateRoot 'main.bicep'
$verifyScript = Join-Path $PSScriptRoot 'verify.ps1'

function Invoke-AzCli {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,
        [switch]$Capture
    )

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& az @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($exitCode -ne 0) {
        throw "az $($Arguments -join ' ') failed:`n$($output -join [Environment]::NewLine)"
    }

    if ($Capture) {
        return ($output -join [Environment]::NewLine)
    }
    $output | ForEach-Object { Write-Host $_ }
}

function Assert-PublicIpv4Cidr {
    param([Parameter(Mandatory)][string]$Cidr)

    if ($Cidr -notmatch '^(?<address>(?:[0-9]{1,3}\.){3}[0-9]{1,3})/(?<prefix>[0-9]|[12][0-9]|3[0-2])$') {
        throw "Administrator source '$Cidr' is not an IPv4 CIDR."
    }

    $parsedAddress = $null
    if (-not [System.Net.IPAddress]::TryParse($Matches.address, [ref]$parsedAddress)) {
        throw "Administrator source '$Cidr' contains an invalid IPv4 address."
    }

    $octets = $parsedAddress.GetAddressBytes()
    $isPrivateOrSpecial =
        $octets[0] -eq 0 -or
        $octets[0] -eq 10 -or
        $octets[0] -eq 127 -or
        ($octets[0] -eq 169 -and $octets[1] -eq 254) -or
        ($octets[0] -eq 172 -and $octets[1] -ge 16 -and $octets[1] -le 31) -or
        ($octets[0] -eq 192 -and $octets[1] -eq 168) -or
        ($octets[0] -eq 100 -and $octets[1] -ge 64 -and $octets[1] -le 127) -or
        ($octets[0] -eq 192 -and $octets[1] -eq 0 -and $octets[2] -eq 2) -or
        ($octets[0] -eq 198 -and $octets[1] -ge 18 -and $octets[1] -le 19) -or
        ($octets[0] -eq 198 -and $octets[1] -eq 51 -and $octets[2] -eq 100) -or
        ($octets[0] -eq 203 -and $octets[1] -eq 0 -and $octets[2] -eq 113) -or
        $octets[0] -ge 224

    if ([int]$Matches.prefix -eq 0 -or $isPrivateOrSpecial) {
        throw "Administrator source '$Cidr' is not a restricted public IPv4 CIDR."
    }
}

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI (az) is not available on PATH.'
}
if (-not (Test-Path -LiteralPath $templateFile -PathType Leaf)) {
    throw "Bicep template not found: $templateFile"
}
if ($AdminSourceCidrs.Count -eq 0) {
    throw 'At least one administrator source CIDR is required.'
}
$AdminSourceCidrs | ForEach-Object { Assert-PublicIpv4Cidr -Cidr $_ }

$resolvedKeyPath = (Resolve-Path -LiteralPath $SshPublicKeyPath).Path
$sshPublicKey = (Get-Content -LiteralPath $resolvedKeyPath -Raw).Trim()
if ($sshPublicKey -match 'PRIVATE KEY' -or
    $sshPublicKey -notmatch '^(ssh-(ed25519|rsa)|ecdsa-sha2-nistp(256|384|521))\s+') {
    throw 'SshPublicKeyPath must contain one OpenSSH public key, never a private key.'
}

Invoke-AzCli -Arguments @('account', 'set', '--subscription', $SubscriptionId)
$accountSubscription = Invoke-AzCli -Arguments @(
    'account', 'show', '--query', 'id', '--output', 'tsv', '--only-show-errors'
) -Capture
if ($accountSubscription.Trim() -ne $SubscriptionId) {
    throw "Azure CLI selected subscription '$($accountSubscription.Trim())', expected '$SubscriptionId'."
}

$groupState = Invoke-AzCli -Arguments @(
    'group', 'show', '--subscription', $SubscriptionId,
    '--name', $ResourceGroupName,
    '--query', 'properties.provisioningState', '--output', 'tsv', '--only-show-errors'
) -Capture
if ($groupState.Trim() -ne 'Succeeded') {
    throw "Resource group '$ResourceGroupName' is not ready: $($groupState.Trim())"
}

$groupLocation = Invoke-AzCli -Arguments @(
    'group', 'show', '--subscription', $SubscriptionId,
    '--name', $ResourceGroupName,
    '--query', 'location', '--output', 'tsv', '--only-show-errors'
) -Capture
$communityImageId = Invoke-AzCli -Arguments @(
    'sig', 'image-version', 'show-community',
    '--public-gallery-name', $rockyGalleryName,
    '--gallery-image-definition', $rockyImageDefinition,
    '--gallery-image-version', $rockyImageVersion,
    '--location', $groupLocation.Trim(),
    '--query', 'uniqueId', '--output', 'tsv', '--only-show-errors'
) -Capture
if ($communityImageId -notmatch [regex]::Escape($rockyImageVersion)) {
    throw "The pinned Rocky community image is unavailable in '$($groupLocation.Trim())'."
}

Invoke-AzCli -Arguments @('bicep', 'build', '--file', $templateFile, '--stdout') -Capture | Out-Null

$parameterDocument = [ordered]@{
    '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
    contentVersion = '1.0.0.0'
    parameters = [ordered]@{
        namePrefix = @{ value = $NamePrefix }
        environment = @{ value = $Environment }
        adminUsername = @{ value = $AdminUsername }
        sshPublicKey = @{ value = $sshPublicKey }
        adminSourceCidrs = @{ value = @($AdminSourceCidrs) }
        owner = @{ value = $Owner }
        dataClassification = @{ value = $DataClassification }
        vmSize = @{ value = $VmSize }
        osDiskSizeGB = @{ value = $OsDiskSizeGB }
        dataDiskSizeGB = @{ value = $DataDiskSizeGB }
        enableDeletionLocks = @{ value = $EnableDeletionLocks }
    }
}

$temporaryParameters = Join-Path ([System.IO.Path]::GetTempPath()) (
    'research-web-hosting-{0}.parameters.json' -f [guid]::NewGuid().ToString('N')
)

try {
    $parameterDocument | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temporaryParameters -Encoding utf8
    $deploymentName = 'research-web-hosting-{0}' -f (Get-Date -Format 'yyyyMMdd-HHmmss')
    $commonArguments = @(
        '--subscription', $SubscriptionId,
        '--resource-group', $ResourceGroupName,
        '--name', $deploymentName,
        '--template-file', $templateFile,
        '--parameters', "@$temporaryParameters",
        '--only-show-errors'
    )

    Write-Host 'Validating the deployment with Azure Resource Manager...'
    Invoke-AzCli -Arguments (@('deployment', 'group', 'validate') + $commonArguments + @('--output', 'none'))

    if (-not $SkipWhatIf) {
        Write-Host 'Running Azure Resource Manager what-if...'
        Invoke-AzCli -Arguments (@('deployment', 'group', 'what-if') + $commonArguments)
    }

    if (-not $Deploy) {
        Write-Host 'Validation completed. No resources were changed; rerun with -Deploy after reviewing what-if.'
        return
    }

    Write-Host "Deploying '$deploymentName' to '$ResourceGroupName'..."
    $outputsJson = Invoke-AzCli -Arguments (
        @('deployment', 'group', 'create') + $commonArguments +
        @('--query', 'properties.outputs', '--output', 'json')
    ) -Capture
    $outputs = $outputsJson | ConvertFrom-Json

    $vmName = $outputs.vmName.value
    $publicIpAddress = $outputs.publicIpAddress.value
    Write-Host "ARM deployment succeeded. Waiting for guest bootstrap on $vmName..."

    $deadline = (Get-Date).AddMinutes($BootstrapTimeoutMinutes)
    do {
        $status = Invoke-AzCli -Arguments @(
            'vm', 'run-command', 'invoke',
            '--subscription', $SubscriptionId,
            '--resource-group', $ResourceGroupName,
            '--name', $vmName,
            '--command-id', 'RunShellScript',
            '--scripts', 'if test -f /var/lib/research-web-hosting/bootstrap-complete; then echo COMPLETE; elif test -f /var/lib/research-web-hosting/bootstrap-failed; then echo FAILED; else echo RUNNING; fi',
            '--query', 'value[0].message', '--output', 'tsv', '--only-show-errors'
        ) -Capture

        if ($status -match 'COMPLETE') {
            break
        }
        if ($status -match 'FAILED') {
            $failureLog = Invoke-AzCli -Arguments @(
                'vm', 'run-command', 'invoke',
                '--subscription', $SubscriptionId,
                '--resource-group', $ResourceGroupName,
                '--name', $vmName,
                '--command-id', 'RunShellScript',
                '--scripts', 'journalctl -u virtualmin-bootstrap.service -n 200 --no-pager',
                '--query', 'value[0].message', '--output', 'tsv', '--only-show-errors'
            ) -Capture
            throw "Guest bootstrap failed:`n$failureLog"
        }
        if ((Get-Date) -ge $deadline) {
            throw "Guest bootstrap did not finish within $BootstrapTimeoutMinutes minutes."
        }

        Write-Host 'Bootstrap is still running; checking again in 30 seconds.'
        Start-Sleep -Seconds 30
    } while ($true)

    & $verifyScript `
        -SubscriptionId $SubscriptionId `
        -ResourceGroupName $ResourceGroupName `
        -VmName $vmName `
        -PublicIpAddress $publicIpAddress `
        -ExpectedVmSize $VmSize
    if (-not $?) {
        throw 'Post-deployment verification failed.'
    }

    Write-Host ''
    Write-Host "SSH: $($outputs.sshCommand.value)"
    Write-Host "Virtualmin: $($outputs.virtualminUrl.value)"
    Write-Host 'Set the Webmin password over SSH, enable MFA, then add explicit domain A records.'
}
finally {
    if (Test-Path -LiteralPath $temporaryParameters) {
        Remove-Item -LiteralPath $temporaryParameters -Force
    }
}
