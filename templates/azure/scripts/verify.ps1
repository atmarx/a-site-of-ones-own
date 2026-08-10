[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SubscriptionId,
    [Parameter(Mandatory)]
    [string]$ResourceGroupName,
    [Parameter(Mandatory)]
    [string]$VmName,
    [string]$PublicIpAddress,
    [string]$ExpectedVmSize = 'Standard_D2as_v7',
    [ValidateRange(500, 30000)]
    [int]$TcpTimeoutMilliseconds = 4000
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-AzCli {
    param([Parameter(Mandatory)][string[]]$Arguments)

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
    return ($output -join [Environment]::NewLine)
}

function Test-TcpPort {
    param(
        [Parameter(Mandatory)][string]$HostName,
        [Parameter(Mandatory)][int]$Port,
        [Parameter(Mandatory)][int]$TimeoutMilliseconds
    )

    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        $pending = $client.BeginConnect($HostName, $Port, $null, $null)
        if (-not $pending.AsyncWaitHandle.WaitOne($TimeoutMilliseconds)) {
            return $false
        }
        $client.EndConnect($pending)
        return $client.Connected
    }
    catch {
        return $false
    }
    finally {
        $client.Dispose()
    }
}

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI (az) is not available on PATH.'
}

$vmJson = Invoke-AzCli -Arguments @(
    'vm', 'show', '--subscription', $SubscriptionId,
    '--resource-group', $ResourceGroupName, '--name', $VmName,
    '--show-details', '--output', 'json', '--only-show-errors'
)
$vm = $vmJson | ConvertFrom-Json
if ($vm.provisioningState -ne 'Succeeded') {
    throw "VM provisioning state is '$($vm.provisioningState)'."
}
if ($vm.hardwareProfile.vmSize -ne $ExpectedVmSize) {
    throw "VM size is '$($vm.hardwareProfile.vmSize)', expected '$ExpectedVmSize'."
}
if ($vm.securityProfile.securityType -ne 'TrustedLaunch') {
    throw "VM security type is '$($vm.securityProfile.securityType)', expected TrustedLaunch."
}
if ($vm.storageProfile.diskControllerType -ne 'NVMe') {
    throw "VM disk controller is '$($vm.storageProfile.diskControllerType)', expected NVMe."
}
$dataDisks = @($vm.storageProfile.dataDisks)
if ($dataDisks.Count -ne 1 -or $dataDisks[0].lun -ne 0) {
    throw 'Expected exactly one attached data disk at LUN 0.'
}

if (-not $PublicIpAddress) {
    $PublicIpAddress = (Invoke-AzCli -Arguments @(
        'vm', 'list-ip-addresses', '--subscription', $SubscriptionId,
        '--resource-group', $ResourceGroupName, '--name', $VmName,
        '--query', '[0].virtualMachine.network.publicIpAddresses[0].ipAddress',
        '--output', 'tsv', '--only-show-errors'
    )).Trim()
}
if ($PublicIpAddress -notmatch '^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$') {
    throw "Unable to resolve the VM public IPv4 address: '$PublicIpAddress'."
}

$guestVerification = @'
set -Eeuo pipefail
test -f /var/lib/research-web-hosting/bootstrap-complete
test ! -f /var/lib/research-web-hosting/bootstrap-failed
test "$(getenforce)" = Permissive
test "$(findmnt -rn -o TARGET | grep -cx /home)" = 1
home_mount=$(findmnt -rn -o TARGET,SOURCE,FSTYPE,OPTIONS | awk '$1 == "/home" { print }')
test "$(awk '{ print $3 }' <<< "$home_mount")" = xfs
grep -q usrquota <<< "$home_mount"
grep -q grpquota <<< "$home_mount"
mountpoint -q /var/lib/mysql
test -f /home/.research-web-hosting-volume
if test -b /dev/disk/azure/data/by-lun/0; then
  data_disk=$(readlink -f /dev/disk/azure/data/by-lun/0)
else
  data_disk=$(readlink -f /dev/disk/azure/scsi1/lun0)
fi
if [[ "$data_disk" =~ [0-9]$ ]]; then
  data_partition="${data_disk}p1"
else
  data_partition="${data_disk}1"
fi
test "$(pvs --noheadings -o vg_name "$data_partition" | xargs)" = vg_webdata
test -b /dev/vg_webdata/lv_webdata
rpm -q webmin-virtual-server >/dev/null
rpm -q webmin-virtualmin-nginx webmin-virtualmin-nginx-ssl >/dev/null
command -v azcopy >/dev/null
nginx -t
for service in nginx mariadb php-fpm webmin firewalld; do
  systemctl is-active --quiet "$service"
done
systemctl is-enabled --quiet virtualmin-blob-backup.timer
for service in httpd.service cockpit.service cockpit.socket postfix dovecot named proftpd spamassassin spamd clamd; do
  ! systemctl is-active --quiet "$service"
done
! ss -lntup | grep -Eq ':(21|25|53|110|143|465|587|993|995|9090)[[:space:]]'
while IFS= read -r listener; do
  case "$listener" in
    127.*:3306|'[::1]':3306) ;;
    *) echo "MariaDB is exposed on $listener" >&2; exit 1 ;;
  esac
done < <(ss -H -lnt 'sport = :3306' | awk '{ print $4 }')
curl --silent --show-error --output /dev/null --max-time 10 http://127.0.0.1/
timeout 5 bash -c '</dev/tcp/127.0.0.1/10000'
findmnt /home
findmnt /var/lib/mysql
vgs vg_webdata
lvs /dev/vg_webdata/lv_webdata
echo VERIFY_OK
'@
$guestVerificationBase64 = [Convert]::ToBase64String(
    [Text.Encoding]::UTF8.GetBytes($guestVerification)
)
$guestVerificationCommand = "printf '%s' '$guestVerificationBase64' | base64 --decode | bash -x"

$guestResult = Invoke-AzCli -Arguments @(
    'vm', 'run-command', 'invoke',
    '--subscription', $SubscriptionId,
    '--resource-group', $ResourceGroupName,
    '--name', $VmName,
    '--command-id', 'RunShellScript',
    '--scripts', $guestVerificationCommand,
    '--query', 'value[0].message', '--output', 'tsv', '--only-show-errors'
)
if ($guestResult -notmatch 'VERIFY_OK') {
    throw "Guest verification did not complete successfully:`n$guestResult"
}

$expectedPorts = [ordered]@{
    '22' = $true
    '25' = $false
    '53' = $false
    '80' = $true
    '443' = $true
    '3306' = $false
    '9090' = $false
    '10000' = $true
}
foreach ($port in $expectedPorts.Keys) {
    $reachable = Test-TcpPort -HostName $PublicIpAddress -Port ([int]$port) -TimeoutMilliseconds $TcpTimeoutMilliseconds
    if ($reachable -ne $expectedPorts[$port]) {
        throw "Public TCP $port reachability is '$reachable', expected '$($expectedPorts[$port])'."
    }
    Write-Host ('TCP {0,-5} {1}' -f $port, $(if ($reachable) { 'reachable' } else { 'blocked' }))
}

Write-Host "Verified $VmName ($ExpectedVmSize) at $PublicIpAddress."
Write-Host 'The host baseline, data volume, no-mail posture, and public port policy passed.'
