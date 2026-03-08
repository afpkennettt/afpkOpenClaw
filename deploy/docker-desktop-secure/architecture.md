# Architecture: Secure Docker Desktop Deployment

## Objective

Run OpenClaw on Docker Desktop with no direct container access to host filesystem paths.

## Design Summary

- Runtime uses named volumes only.
- No host bind mounts are allowed in compose.
- Gateway is bound to `lan` inside container (required for Docker Desktop host-port publishing).
- Host publish remains loopback-only (`127.0.0.1:18789`).
- Containers use defense-in-depth hardening flags.
- OpenClaw policy is pinned by `openclaw.secure.json5` and copied into the named volume.
- Bonjour/mDNS discovery is explicitly disabled.

## Component Layout

```text
Host (Windows + Docker Desktop)
|
|-- Docker Engine
    |
    |-- Container: openclaw-gateway
    |     |- Read-only root filesystem
    |     |- tmpfs: /tmp, /run
    |     |- Config: /home/node/.openclaw/openclaw.json
    |     |- Provider env: /home/node/.openclaw/.env
    |     `- Volume mount: openclaw_home_secure -> /home/node
    |
    |-- Container: openclaw-cli (ephemeral)
    |     |- Read-only root filesystem
    |     |- tmpfs: /tmp, /run
    |     `- Volume mount: openclaw_home_secure -> /home/node
    |
    `-- Named volume: openclaw_home_secure
          `- Stores ~/.openclaw state (inside Docker-managed storage)
```

## Trust Boundaries

1. Host filesystem boundary:
   - Enforced by absence of bind mounts.
   - Container cannot traverse `C:\` or other host paths as mounted filesystems.
2. Container privilege boundary:
   - `cap_drop: [ALL]`
   - `security_opt: no-new-privileges:true`
   - `user: 1000:1000`
   - `read_only: true`
   - memory, CPU, and `nofile` caps
3. Network boundary:
   - container listener uses Docker bridge interface (`bind: lan`)
   - host publish is loopback-only (`127.0.0.1:18789`)
   - no direct LAN listener unless compose is changed
4. OpenClaw policy boundary:
   - token auth required
   - discovery disabled (`discovery.mdns.mode: off`, env `OPENCLAW_DISABLE_BONJOUR=1`)
   - OpenAI model default pinned (`openai/gpt-5.1-codex`)
   - WhatsApp channel policy pinned (pairing by default)
   - browser disabled
   - canvas host disabled
   - elevated mode disabled
   - workspace-only file tools
   - runtime, automation, and node tools denied by default

## Data Flow

1. Client browser connects to `http://127.0.0.1:18789`.
2. Gateway reads and writes config, sessions, and credentials under `/home/node/.openclaw`.
3. `apply-phase1-hardening.ps1` copies `openclaw.secure.json5` into `/home/node/.openclaw/openclaw.json`.
4. `set-openai-key.ps1` writes provider secrets to `/home/node/.openclaw/.env`.
5. Docker persists `/home/node` to named volume `openclaw_home_secure`.
6. CLI admin tasks use the same named volume and gateway token.

## Security Controls

- no bind mounts
- read-only container root filesystem
- tmpfs for transient writable paths
- dropped Linux capabilities
- no-new-privileges flag
- loopback-only host published gateway port
- discovery disabled (no mDNS beacon broadcast)
- explicit OpenClaw deny policy for browser, runtime, and automation surfaces
- canvas host disabled
- workspace-only guardrail for filesystem tools
- loop detection enabled
- credentials directory permissions forced to mode `700`

## Known Limits

- If Docker daemon or host is compromised, container isolation can be bypassed.
- If someone edits compose and adds bind mounts, host filesystem exposure returns.
- Secrets inside env files still require endpoint and account hygiene.
- Outbound egress is still available unless you add host firewall or proxy restrictions.
- Because gateway bind is loopback, sidecar/one-off containers cannot probe `127.0.0.1` on the gateway container. Run gateway-aware CLI commands via `docker compose exec openclaw-gateway`.

## Hardening Roadmap

1. Keep `deploy/docker-desktop-secure/openclaw.secure.json5` as the source of truth and reapply via `apply-phase1-hardening.ps1` after any config drift.
2. Keep discovery off (`OPENCLAW_DISABLE_BONJOUR=1` and `discovery.mdns.mode: off`) unless you intentionally need LAN discovery.
3. Keep gateway loopback-only and do not publish non-loopback ports in compose.
4. Re-run `openclaw security audit --deep` after any channel/provider change.
5. If this becomes multi-user, split trust boundaries by running separate gateways and credentials per user.

## Maintenance Checklist (Keep This Updated)

When this deployment changes, update this file and `README.md` together:

1. Service names, ports, and bind mode
2. Volume names and mount points
3. Security flags (`read_only`, `cap_drop`, `security_opt`, `tmpfs`, `pids_limit`, resource caps)
4. Pinned OpenClaw policy in `openclaw.secure.json5`
5. Auth assumptions and secret handling
6. Verification procedure (`verify-no-bind-mounts.ps1`, `openclaw security audit --deep`)
