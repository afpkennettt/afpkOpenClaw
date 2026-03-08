param(
    [string]$EnvFile = "deploy/docker-desktop-secure/.env.secure",
    [string]$ComposeFile = "deploy/docker-desktop-secure/docker-compose.secure.yml",
    [string]$ConfigTemplate = "deploy/docker-desktop-secure/openclaw.secure.json5"
)

$ErrorActionPreference = "Stop"

foreach ($path in @($EnvFile, $ComposeFile, $ConfigTemplate)) {
    if (-not (Test-Path $path)) {
        throw "Required file not found: $path"
    }
}

$config = Get-Content -Path $ConfigTemplate -Raw
if ([string]::IsNullOrWhiteSpace($config)) {
    throw "Config template is empty: $ConfigTemplate"
}

$writeArgs = @(
    "compose",
    "--env-file", $EnvFile,
    "-f", $ComposeFile,
    "run",
    "--rm",
    "-T",
    "--entrypoint", "sh",
    "openclaw-cli",
    "-lc",
    "umask 077 && mkdir -p /home/node/.openclaw /home/node/.openclaw/credentials && chmod 700 /home/node/.openclaw/credentials && cat > /home/node/.openclaw/openclaw.json"
)

$config | docker @writeArgs
if ($LASTEXITCODE -ne 0) {
    throw "Failed to write /home/node/.openclaw/openclaw.json into the Docker volume."
}

$verifyArgs = @(
    "compose",
    "--env-file", $EnvFile,
    "-f", $ComposeFile,
    "run",
    "--rm",
    "-T",
    "--entrypoint", "sh",
    "openclaw-cli",
    "-lc",
    "test -s /home/node/.openclaw/openclaw.json && echo /home/node/.openclaw/openclaw.json"
)

$writtenPath = docker @verifyArgs
if ($LASTEXITCODE -ne 0) {
    throw "Config verification failed after writing openclaw.json."
}

Write-Host "Phase 1 baseline applied:" -ForegroundColor Green
Write-Host ($writtenPath | Select-Object -Last 1)
Write-Host "Restart openclaw-gateway to load the new config." -ForegroundColor Yellow
