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

## Install Into A User Project

Codex:

```bash
curl -fsSL https://raw.githubusercontent.com/celer-network/x402-polymarket-agentpay-buyer/main/install.sh | bash -s -- --codex
```

Claude Code:

```bash
curl -fsSL https://raw.githubusercontent.com/celer-network/x402-polymarket-agentpay-buyer/main/install.sh | bash -s -- --claude
```

Both:

```bash
curl -fsSL https://raw.githubusercontent.com/celer-network/x402-polymarket-agentpay-buyer/main/install.sh | bash -s -- --codex --claude
```

## Configure Buyer Credentials

```bash
cp skills/codex-buyer-agentpay/templates/buyer.env.template /tmp/buyer-agentpay.env
```

Edit `/tmp/buyer-agentpay.env` and set:

```bash
export BUYER_KEY="<64_HEX_PRIVATE_KEY_NO_0x>"
```

Then generate the buyer profile:

```bash
source /tmp/buyer-agentpay.env
SELLER_HOST=$SELLER_HOST OUT=$BUYER_PROFILE bash deploy/gen-buyer-profile.sh
```

## Verify

```bash
source /tmp/buyer-agentpay.env
bash skills/codex-buyer-agentpay/scripts/preflight.sh
```

After preflight passes, ask your agent to run the Polymarket data buyer flow. Paid calls spend USDC from the buyer channel.

## Security

- Use a dedicated buyer key for this workflow.
- Never commit `/tmp/buyer-agentpay.env` or `BUYER_KEY`.
- Treat `BUYER_DATA_DIR` as sensitive local state.
