param(
    [string]$EnvFile = "deploy/docker-desktop-secure/.env.secure",
    [string]$ComposeFile = "deploy/docker-desktop-secure/docker-compose.secure.yml"
)

$ErrorActionPreference = "Stop"

foreach ($path in @($EnvFile, $ComposeFile)) {
    if (-not (Test-Path $path)) {
        throw "Required file not found: $path"
    }
}

$secure = Read-Host -AsSecureString -Prompt "Enter NEW OpenAI API key (input hidden)"
$ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try {
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
} finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
}

if ($null -eq $plain) {
    $plain = ""
}
$key = $plain.Trim()
if ([string]::IsNullOrWhiteSpace($key)) {
    throw "OpenAI API key cannot be empty."
}
if (-not $key.StartsWith("sk-")) {
    Write-Warning "Key does not start with 'sk-'. Continue only if intentional."
}

$line = "OPENAI_API_KEY=$key`n"

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
    "umask 077 && mkdir -p /home/node/.openclaw && touch /home/node/.openclaw/.env && chmod 600 /home/node/.openclaw/.env && tmp=/tmp/openai-env.$$ && grep -v '^OPENAI_API_KEY=' /home/node/.openclaw/.env > $tmp || true && cat >> $tmp && mv $tmp /home/node/.openclaw/.env && chmod 600 /home/node/.openclaw/.env"
)

$line | docker @writeArgs
if ($LASTEXITCODE -ne 0) {
    throw "Failed to store OPENAI_API_KEY in /home/node/.openclaw/.env."
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
    "grep -E '^OPENAI_API_KEY=' /home/node/.openclaw/.env | sed 's/=.*/=<redacted>/'"
)

$masked = docker @verifyArgs
if ($LASTEXITCODE -ne 0) {
    throw "Stored key could not be verified."
}

Write-Host "Stored provider secret in Docker volume:" -ForegroundColor Green
Write-Host ($masked | Select-Object -Last 1)
Write-Host "Restart openclaw-gateway to pick up the updated .env." -ForegroundColor Yellow
