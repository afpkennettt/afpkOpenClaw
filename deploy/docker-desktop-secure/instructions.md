# Instructions: First Run, Tools, Settings, and "Souls"

This file is the quick-start companion for the secure Docker Desktop deployment.

## 1. Start / Stop

From repo root:

```powershell
powershell -ExecutionPolicy Bypass -File deploy/docker-desktop-secure/apply-phase1-hardening.ps1
powershell -ExecutionPolicy Bypass -File deploy/docker-desktop-secure/set-openai-key.ps1
docker compose --env-file deploy/docker-desktop-secure/.env.secure -f deploy/docker-desktop-secure/docker-compose.secure.yml up -d openclaw-gateway
```

Stop:

```powershell
docker compose --env-file deploy/docker-desktop-secure/.env.secure -f deploy/docker-desktop-secure/docker-compose.secure.yml down
```

## 2. Apply / Review the Baseline

```powershell
powershell -ExecutionPolicy Bypass -File deploy/docker-desktop-secure/apply-phase1-hardening.ps1
```

Baseline behavior:

- bind: `lan` inside container (Docker host port remains loopback-only)
- auth: `token`
- discovery (Bonjour/mDNS): disabled
- browser: disabled
- canvas host: disabled
- elevated mode: disabled
- runtime tools: denied
- file tools: workspace-only
- credentials directory permissions: `700`

To inspect the pinned config:

```powershell
Get-Content deploy/docker-desktop-secure/openclaw.secure.json5
```

The baseline now includes:

- default model: `openai/gpt-5.1-codex`
- WhatsApp channel block with `dmPolicy: "pairing"`
- per-channel DM scope (`session.dmScope: "per-channel-peer"`)

## 3. Configure Provider Secret (OpenAI)

Do this once per key rotation:

```powershell
powershell -ExecutionPolicy Bypass -File deploy/docker-desktop-secure/set-openai-key.ps1
docker compose --env-file deploy/docker-desktop-secure/.env.secure -f deploy/docker-desktop-secure/docker-compose.secure.yml up -d --force-recreate openclaw-gateway
```

This stores `OPENAI_API_KEY` in `/home/node/.openclaw/.env` inside the Docker volume.
It does not write the key to tracked repo files.

If commands fail with Node heap OOM, raise these in `.env.secure`:

- `OPENCLAW_CLI_MEM_LIMIT` (for container memory)
- `OPENCLAW_NODE_MAX_OLD_SPACE_MB` (for Node heap)

## 4. Dashboard

- Open `http://127.0.0.1:18789/`
- Paste your `OPENCLAW_GATEWAY_TOKEN` from `deploy/docker-desktop-secure/.env.secure`.

## 5. WhatsApp (Clean Linking Sequence)

Run this exact order to avoid stale session conflicts:

1. Stop gateway before linking:

```powershell
docker compose --env-file deploy/docker-desktop-secure/.env.secure -f deploy/docker-desktop-secure/docker-compose.secure.yml stop openclaw-gateway
```

2. Clear old WhatsApp session:

```powershell
docker compose --env-file deploy/docker-desktop-secure/.env.secure -f deploy/docker-desktop-secure/docker-compose.secure.yml run --rm openclaw-cli channels logout --channel whatsapp
```

3. Link via QR (scan in phone app: Settings -> Linked Devices -> Link a Device):

```powershell
docker compose --env-file deploy/docker-desktop-secure/.env.secure -f deploy/docker-desktop-secure/docker-compose.secure.yml run --rm openclaw-cli channels login --channel whatsapp --verbose
```

4. Start gateway again:

```powershell
docker compose --env-file deploy/docker-desktop-secure/.env.secure -f deploy/docker-desktop-secure/docker-compose.secure.yml up -d openclaw-gateway
```

5. Confirm runtime status:

```powershell
docker compose --env-file deploy/docker-desktop-secure/.env.secure -f deploy/docker-desktop-secure/docker-compose.secure.yml exec openclaw-gateway node openclaw.mjs channels status --probe
```

If status still shows `error:not linked`, check credentials state:

```powershell
docker compose --env-file deploy/docker-desktop-secure/.env.secure -f deploy/docker-desktop-secure/docker-compose.secure.yml exec openclaw-gateway node -e "const fs=require('fs');const p='/home/node/.openclaw/credentials/whatsapp/default/creds.json';if(!fs.existsSync(p)){console.log('creds:missing');process.exit(1)};const c=JSON.parse(fs.readFileSync(p,'utf8'));console.log('registered='+c.registered+', me='+(c?.me?.id||'unknown'));"
```

Then approve first pairing code (default `dmPolicy: pairing`):

```powershell
docker compose --env-file deploy/docker-desktop-secure/.env.secure -f deploy/docker-desktop-secure/docker-compose.secure.yml exec openclaw-gateway node openclaw.mjs pairing list whatsapp
docker compose --env-file deploy/docker-desktop-secure/.env.secure -f deploy/docker-desktop-secure/docker-compose.secure.yml exec openclaw-gateway node openclaw.mjs pairing approve whatsapp <CODE>
```

If phone app does not show a linked device:

- update WhatsApp mobile app to latest
- keep phone online during the full QR flow
- remove old linked sessions in the phone app first
- rerun the clean sequence above

## 6. Tools (What To Configure First)

### Providers / channels

Use the configure flow:

```powershell
docker compose --env-file deploy/docker-desktop-secure/.env.secure -f deploy/docker-desktop-secure/docker-compose.secure.yml exec openclaw-gateway node openclaw.mjs configure
```

### Health check

```powershell
docker compose --env-file deploy/docker-desktop-secure/.env.secure -f deploy/docker-desktop-secure/docker-compose.secure.yml logs -f openclaw-gateway
```

### Security audit

```powershell
docker compose --env-file deploy/docker-desktop-secure/.env.secure -f deploy/docker-desktop-secure/docker-compose.secure.yml exec openclaw-gateway node openclaw.mjs security audit --deep
```

Note: with loopback bind hardening, one-off `openclaw-cli` containers cannot probe the gateway's `127.0.0.1` endpoint. Use `exec openclaw-gateway` for gateway-aware commands (`channels status`, `configure`, `pairing`, `security audit`).

### Verify no host filesystem bind mounts

```powershell
powershell -ExecutionPolicy Bypass -File deploy/docker-desktop-secure/verify-no-bind-mounts.ps1 -EnvFile deploy/docker-desktop-secure/.env.secure -ComposeFile deploy/docker-desktop-secure/docker-compose.secure.yml
```

## 7. Settings (Core Baseline)

Good defaults in secure mode:

- gateway bind: `lan` (container) + host publish `127.0.0.1` (loopback-only)
- gateway auth: token enabled
- discovery disabled
- browser disabled
- canvas host disabled
- elevated tools disabled
- runtime, automation, and nodes denied
- `tools.fs.workspaceOnly: true`
- avoid adding host bind mounts unless required

If you later need config inspection from inside the container:

```powershell
docker compose --env-file deploy/docker-desktop-secure/.env.secure -f deploy/docker-desktop-secure/docker-compose.secure.yml run --rm --entrypoint sh openclaw-cli -lc "ls -la /home/node/.openclaw && sed -n '1,200p' /home/node/.openclaw/openclaw.json"
```

## 8. VS Code Secure Workflow

Use the volume-based devcontainer:

- file: `.devcontainer/secure-volume/devcontainer.json`
- command: `Dev Containers: Open Folder in Container...` and select this config

Practical workflow:

1. develop in the volume-backed workspace (no host source bind mount)
2. run gateway via `deploy/docker-desktop-secure/docker-compose.secure.yml`
3. keep secrets in `/home/node/.openclaw/.env` using `set-openai-key.ps1`

## 9. Souls (Interpreted As Skills + Agent Persona)

OpenClaw's practical equivalent of "souls" is:

- skills: reusable task behavior and tooling instructions
- `AGENTS.md` / system prompt style: persona and operating behavior

Start with skills:

```powershell
docker compose --env-file deploy/docker-desktop-secure/.env.secure -f deploy/docker-desktop-secure/docker-compose.secure.yml run --rm openclaw-cli skills status
```

If you meant something different by "souls" (for example multi-agent personalities), define each agent with its own workspace and tools policy in OpenClaw config.

## 10. What Is Amphetamine?

Amphetamine is a macOS utility app that keeps your Mac awake based on manual toggles or rules.

Why people use it with OpenClaw:

- prevents Mac sleep during long gateway sessions, model runs, or remote access windows
- avoids dropped sessions caused by sleep

It is optional and separate from Docker. It does not add security by itself.
