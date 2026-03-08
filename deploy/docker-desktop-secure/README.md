# OpenClaw Secure Docker Desktop Deployment

This deployment profile is for running OpenClaw with no host bind mounts so containers do not get direct access to your local filesystem paths.

Use this with:

- `deploy/docker-desktop-secure/docker-compose.secure.yml`
- `deploy/docker-desktop-secure/.env.secure.example`
- `deploy/docker-desktop-secure/openclaw.secure.json5`
- `deploy/docker-desktop-secure/apply-phase1-hardening.ps1`
- `deploy/docker-desktop-secure/set-openai-key.ps1`
- `deploy/docker-desktop-secure/verify-no-bind-mounts.ps1`
- `deploy/docker-desktop-secure/architecture.md`
- `deploy/docker-desktop-secure/instructions.md`

## Security Reality Check

This setup is as strict as Docker Desktop can practically be for filesystem isolation:

- no host bind mounts
- named volumes only
- non-root runtime user from the image
- dropped Linux capabilities
- `no-new-privileges`
- read-only root filesystem
- Bonjour/mDNS discovery disabled
- canvas host disabled
- explicit OpenClaw baseline config written into the named volume

Networking note for Docker Desktop:

- gateway listens on container `lan` bind so Docker can proxy traffic from host into the container
- host publish is still loopback-only: `127.0.0.1:18789:18789`
- result: reachable from your local machine only, not from LAN/WAN unless you change compose/host firewall settings

Absolute "impossible to break" isolation is not something Docker Desktop can guarantee if the Docker daemon/host is compromised. But this profile removes normal host filesystem exposure paths used by containerized apps.

## Components

- `openclaw-gateway` service:
  - serves OpenClaw gateway on `127.0.0.1:<OPENCLAW_GATEWAY_PORT>`
  - stores config and session data inside Docker volume `openclaw_home_secure` (or your override)
- `openclaw-cli` service:
  - runs one-off admin commands using the same Docker volume
- Docker named volume:
  - `/home/node` inside container
  - persists OpenClaw state without host-path mounts
- Pinned gateway config:
  - source of truth: `deploy/docker-desktop-secure/openclaw.secure.json5`
  - runtime path: `/home/node/.openclaw/openclaw.json`

## Setup (PowerShell)

Run from repo root.

1. Build the image:

```powershell
docker build -t openclaw:local -f Dockerfile .
```

2. Create the secure env file:

```powershell
Copy-Item deploy/docker-desktop-secure/.env.secure.example deploy/docker-desktop-secure/.env.secure -Force
```

3. Generate a strong gateway token:

```powershell
$bytes = New-Object byte[] 32
[System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
$token = ($bytes | ForEach-Object { $_.ToString("x2") }) -join ""
(Get-Content deploy/docker-desktop-secure/.env.secure) `
  -replace '^OPENCLAW_GATEWAY_TOKEN=.*$', "OPENCLAW_GATEWAY_TOKEN=$token" `
  | Set-Content deploy/docker-desktop-secure/.env.secure
```

4. Apply the phase 1 hardening baseline:

```powershell
powershell -ExecutionPolicy Bypass -File deploy/docker-desktop-secure/apply-phase1-hardening.ps1
```

This writes `/home/node/.openclaw/openclaw.json` into the Docker volume with:

- loopback-only gateway bind
- token auth
- discovery disabled
- browser disabled
- canvas host disabled
- elevated mode disabled
- workspace-only file tools
- runtime, automation, node, and session fan-out tools denied by default

5. Store a provider key inside the Docker volume (not in compose env):

```powershell
powershell -ExecutionPolicy Bypass -File deploy/docker-desktop-secure/set-openai-key.ps1
```

This writes `OPENAI_API_KEY=...` to `/home/node/.openclaw/.env` with file mode `600`.

6. Start the gateway:

```powershell
docker compose `
  --env-file deploy/docker-desktop-secure/.env.secure `
  -f deploy/docker-desktop-secure/docker-compose.secure.yml `
  up -d openclaw-gateway
```

7. Verify mount isolation:

```powershell
powershell -ExecutionPolicy Bypass -File deploy/docker-desktop-secure/verify-no-bind-mounts.ps1
```

8. Run OpenClaw's audit from inside the hardened container:

```powershell
docker compose `
  --env-file deploy/docker-desktop-secure/.env.secure `
  -f deploy/docker-desktop-secure/docker-compose.secure.yml `
  exec openclaw-gateway node openclaw.mjs security audit --deep
```

9. Open the dashboard:

- `http://127.0.0.1:18789/`

## Configure Providers And Channels

The phase 1 baseline replaces first-run onboarding for gateway security. After the gateway is up, configure model providers or channels explicitly:

```powershell
docker compose `
  --env-file deploy/docker-desktop-secure/.env.secure `
  -f deploy/docker-desktop-secure/docker-compose.secure.yml `
  exec openclaw-gateway node openclaw.mjs configure
```

Note: because the gateway bind is loopback-hardened, use `exec openclaw-gateway` for gateway-aware commands instead of one-off `openclaw-cli` containers.

## WhatsApp Setup (With This Profile)

Use this order to avoid stale session conflicts.

1. Stop gateway:

```powershell
docker compose --env-file deploy/docker-desktop-secure/.env.secure -f deploy/docker-desktop-secure/docker-compose.secure.yml stop openclaw-gateway
```

2. Clear old WhatsApp session:

```powershell
docker compose --env-file deploy/docker-desktop-secure/.env.secure -f deploy/docker-desktop-secure/docker-compose.secure.yml run --rm openclaw-cli channels logout --channel whatsapp
```

3. Link WhatsApp account (QR flow):

```powershell
docker compose --env-file deploy/docker-desktop-secure/.env.secure -f deploy/docker-desktop-secure/docker-compose.secure.yml run --rm openclaw-cli channels login --channel whatsapp --verbose
```

4. Start gateway:

```powershell
docker compose --env-file deploy/docker-desktop-secure/.env.secure -f deploy/docker-desktop-secure/docker-compose.secure.yml up -d openclaw-gateway
```

5. Approve first pairing request (if using default `dmPolicy: "pairing"`):

```powershell
docker compose --env-file deploy/docker-desktop-secure/.env.secure -f deploy/docker-desktop-secure/docker-compose.secure.yml exec openclaw-gateway node openclaw.mjs pairing list whatsapp
docker compose --env-file deploy/docker-desktop-secure/.env.secure -f deploy/docker-desktop-secure/docker-compose.secure.yml exec openclaw-gateway node openclaw.mjs pairing approve whatsapp <CODE>
```

6. Check channel status:

```powershell
docker compose --env-file deploy/docker-desktop-secure/.env.secure -f deploy/docker-desktop-secure/docker-compose.secure.yml exec openclaw-gateway node openclaw.mjs channels status
```

## Operations

Show logs:

```powershell
docker compose --env-file deploy/docker-desktop-secure/.env.secure -f deploy/docker-desktop-secure/docker-compose.secure.yml logs -f openclaw-gateway
```

Stop:

```powershell
docker compose --env-file deploy/docker-desktop-secure/.env.secure -f deploy/docker-desktop-secure/docker-compose.secure.yml down
```

If CLI commands hit Node heap OOM, increase:

- `OPENCLAW_CLI_MEM_LIMIT` (container memory cap)
- `OPENCLAW_NODE_MAX_OLD_SPACE_MB` (Node heap cap)

Remove the data volume (destructive):

```powershell
docker volume rm openclaw_home_secure
```

## VS Code Project (No Host Workspace Mount)

Use the volume-based devcontainer profile at:

- `.devcontainer/secure-volume/devcontainer.json`

This keeps code and workspace data in Docker volumes instead of your host filesystem. See `architecture.md` for details.
