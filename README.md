# Buyer AgentPay Public Bundle

This is the minimal user-side bundle for giving a Codex or Claude Code agent paid access to the x402 Polymarket data seller. Users do not need to clone the full service repository.

## What Gets Installed

- Agent instructions:
  - `AGENTS.md` for Codex
  - `CLAUDE.md` plus `.claude/settings.local.json` for Claude Code
- Buyer skill files:
  - `skills/codex-buyer-agentpay/SKILL.md`
  - `skills/claude-buyer-agentpay/SKILL.md`
  - `skills/codex-buyer-agentpay/templates/buyer.env.template`
  - `skills/codex-buyer-agentpay/templates/AGENTS.md.example`
- Runtime scripts:
  - `skills/codex-buyer-agentpay/scripts/preflight.sh`
  - `skills/codex-buyer-agentpay/scripts/run-paid-checks.sh`
  - `skills/codex-buyer-agentpay/scripts/run-export-checks.sh`
  - `skills/codex-buyer-agentpay/scripts/run-withdraw.sh`
  - `deploy/gen-buyer-profile.sh`
- Runtime binaries:
  - `skills/codex-buyer-agentpay/bin/node`
  - `skills/codex-buyer-agentpay/bin/x402-client`
  - `skills/codex-buyer-agentpay/bin/status-bridge`
- Local dashboard launcher:
  - `start-dashboard.sh`

## Install Into A User Project

Codex:

```bash
curl -fsSL https://raw.githubusercontent.com/celer-network/x402-polymarket-agentpay-buyer/refs/heads/main/install.sh | bash -s -- --codex
```

Claude Code:

```bash
curl -fsSL https://raw.githubusercontent.com/celer-network/x402-polymarket-agentpay-buyer/refs/heads/main/install.sh | bash -s -- --claude
```

Both:

```bash
curl -fsSL https://raw.githubusercontent.com/celer-network/x402-polymarket-agentpay-buyer/refs/heads/main/install.sh | bash -s -- --codex --claude
```

## Configure Buyer Credentials

`install.sh` already created `/tmp/buyer-agentpay.env` from the template. Edit it and set:

```bash
export BUYER_KEY="<64_HEX_PRIVATE_KEY_NO_0x>"
```

## Run

```bash
bash start-dashboard.sh
```

Then open `http://localhost:9100`. The dashboard generates the buyer profile, runs preflight, and lets you exercise the paid agent flow — no extra commands needed. Paid calls spend USDC from the buyer channel.

## Advanced: CLI Only

If you don't want the dashboard, run the same steps manually:

```bash
source /tmp/buyer-agentpay.env
bash deploy/gen-buyer-profile.sh
bash skills/codex-buyer-agentpay/scripts/preflight.sh
```

Then ask your Codex / Claude Code agent to run the Polymarket data buyer flow.

## Security

- Use a dedicated buyer key for this workflow.
- Never commit `/tmp/buyer-agentpay.env` or `BUYER_KEY`.
- Treat `BUYER_DATA_DIR` as sensitive local state.
