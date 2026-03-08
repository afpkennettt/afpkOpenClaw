param(
    [string]$EnvFile = "deploy/docker-desktop-secure/.env.secure",
    [string]$ComposeFile = "deploy/docker-desktop-secure/docker-compose.secure.yml"
)

$containerId = docker compose --env-file $EnvFile -f $ComposeFile ps -q openclaw-gateway
if ([string]::IsNullOrWhiteSpace($containerId)) {
    Write-Error "openclaw-gateway is not running. Start it first."
    exit 1
}

$mounts = docker inspect $containerId --format "{{json .Mounts}}" | ConvertFrom-Json
$bindMounts = @($mounts | Where-Object { $_.Type -eq "bind" })

if ($bindMounts.Count -gt 0) {
    Write-Host "FAIL: bind mounts detected:" -ForegroundColor Red
    $bindMounts | ForEach-Object {
        Write-Host ("  {0} -> {1}" -f $_.Source, $_.Destination)
    }
    exit 1
}

Write-Host "PASS: no bind mounts detected on openclaw-gateway." -ForegroundColor Green
Write-Host "Mounted volumes:" -ForegroundColor Green
$mounts | ForEach-Object {
    Write-Host ("  {0} -> {1}" -f $_.Name, $_.Destination)
}
