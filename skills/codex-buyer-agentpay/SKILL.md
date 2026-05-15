# Codex Buyer AgentPay Skill

Codex-first standalone skill for buyer-side payment flow and API access on Base.

Status:
- Primary target: Codex
- Future expansion: Claude Code / OpenClaw / OpenCode (after settlement)

## Purpose

Use this skill when a Codex agent must:
1. Bootstrap buyer runtime config.
2. Discover seller-supported APIs from `/workloads`.
3. Complete AgentPay payment flow for paid endpoints.
4. Access export endpoints and validate response integrity.

## Scope

- Network: Base (`eip155:8453`)
- Seller default host: see `SELLER_HOST` in env template
- Paid routes:
  - `/api/v1/markets`
- Export routes:
  - `/api/v1/export/*` (full supported set discovered via `/workloads`)

## Required Inputs

Load from environment:
- `SELLER_HOST` — seller endpoint host
- `SELLER_HTTP` — derived: `http://${SELLER_HOST}:8403`
- `SELLER_GRPC` — optional; empty for remote buyers
- `RELAY_ADMIN` — optional; empty for remote buyers
- `BUYER_KEY` (hex private key, no `0x`)
- `NODE_BIN`
- `BUYER_PROFILE`
- `BUYER_DATA_DIR`

All derived values are set in the env template. Source the template before running any script.

Optional:
- `CHAIN_ID` (default `8453`)
- `NETWORK` (default `eip155:8453`)
- `GO_BIN` (default `go`)
- `OPEN_CHANNEL_ON_START` (`0`/`1`)
- `CHANNEL_DEPOSIT` (default `500000`)
- `AGENTPAY_STATUS_WEBHOOK` — stream events to an observation tool

## Security Rules

1. Never print `BUYER_KEY`.
2. Mask sensitive env values in logs.
3. Use isolated `BUYER_DATA_DIR`.
4. Use a dedicated key for this workflow.

## File Layout

- `templates/buyer.env.template`
- `scripts/preflight.sh`
- `scripts/run-paid-checks.sh`
- `scripts/run-export-checks.sh`
- `scripts/run-withdraw.sh`
- `bin/node`

## Quick Start

1. Copy env template and set `BUYER_KEY`:
```bash
cp skills/codex-buyer-agentpay/templates/buyer.env.template /tmp/buyer-agentpay.env
```

2. Generate buyer profile:
```bash
source /tmp/buyer-agentpay.env
bash deploy/gen-buyer-profile.sh
```

3. Run preflight:
```bash
source /tmp/buyer-agentpay.env
bash skills/codex-buyer-agentpay/scripts/preflight.sh
```

4. Run paid checks:
```bash
source /tmp/buyer-agentpay.env
bash skills/codex-buyer-agentpay/scripts/run-paid-checks.sh
```

5. Run export checks:
```bash
source /tmp/buyer-agentpay.env
bash skills/codex-buyer-agentpay/scripts/run-export-checks.sh
```

6. (Optional) Withdraw remaining channel balance when done:
```bash
source /tmp/buyer-agentpay.env
bash skills/codex-buyer-agentpay/scripts/run-withdraw.sh
```

## Failure handling

| Error | Action |
|---|---|
| `402` payment loop | Check buyer USDC balance and AgentPayLedger allowance via preflight |
| `AlreadyExists` / inflight channel | Channel open already in progress — set `OPEN_CHANNEL_ON_START=0` and retry |
| `no route to destination` | Relay routing table empty — restart `agentpay-seller-node` on EC2 |
| `balance not enough, need N free 0` | Relay has 0 balance toward seller — contact seller operator to fund relay-seller channel |
| `allowance` / `insufficient balance` | Approve USDC for AgentPayWallet and AgentPayLedger; preflight prints the exact command |
| `5xx` / timeout on /markets | Upstream Gamma API issue — retry once with bounded backoff and surface upstream classification |

## Codex Execution Contract

Codex should return:
1. Preflight status (connectivity, USDC balance/allowance, channel balance, workloads discovered).
2. Paid flow result for `/markets`.
3. Export route result summary (pass/fail per route).
4. Final remediation list for any failures.
5. Withdraw result (if requested by user).

## Expansion Plan

Sibling skills reuse the same scripts/templates, customizing only runtime orchestration:
- `skills/claude-buyer-agentpay` — done (interactive Claude Code orchestration)
- `skills/openclaw-buyer-agentpay` — planned (after settlement)
- `skills/opencode-buyer-agentpay` — planned (after settlement)
