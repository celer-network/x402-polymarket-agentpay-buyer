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
  - `skills/codex-buyer-agentpay/scripts/run-batch-export.sh` (driven by the dashboard's LLM-based RUN AGENT)
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

### Recommended: Use A Private Base RPC

By default `RPC_URL` points at the public `https://mainnet.base.org` endpoint, which is rate-limited and flaky under load — preflight balance checks and channel ops will intermittently fail. For reliable runs, swap it for your own Base mainnet RPC from a provider like [Alchemy](https://www.alchemy.com/) or [NodeReal](https://nodereal.io/):

```bash
# In /tmp/buyer-agentpay.env
export RPC_URL="https://base-mainnet.g.alchemy.com/v2/<YOUR_API_KEY>"
# or
export RPC_URL="https://base-mainnet.nodereal.io/v1/<YOUR_API_KEY>"
```

## Run

```bash
bash start-dashboard.sh
```

Then open `http://localhost:9100`. The dashboard generates the buyer profile, runs preflight, and exposes a **RUN AGENT** button.

### Where the dashboard page comes from

The public buyer bundle does not store a standalone `dashboard.html` file. The local page is compiled into the bundled `skills/codex-buyer-agentpay/bin/status-bridge` binary from the service repository:

```go
// x402-polymarket-data/cmd/status-bridge/main.go
//go:embed dashboard.html
```

`start-dashboard.sh` launches that binary and opens `http://localhost:9100`; the binary serves the embedded page from `/`.

### Syncing dashboard changes into this bundle

When `x402-polymarket-data/cmd/status-bridge/dashboard.html`, `cmd/status-bridge/main.go`, or `cmd/x402-client` changes, rebuild the runtime binaries from `x402-polymarket-data` and copy them into this public bundle before publishing:

```bash
DATA_REPO=/path/to/x402-polymarket-data
BUYER_REPO=/path/to/x402-polymarket-agentpay-buyer

cd "$DATA_REPO"
go test ./...
go build -o "$BUYER_REPO/skills/codex-buyer-agentpay/bin/status-bridge" ./cmd/status-bridge/
go build -o "$BUYER_REPO/skills/codex-buyer-agentpay/bin/x402-client" ./cmd/x402-client/
chmod +x "$BUYER_REPO/skills/codex-buyer-agentpay/bin/status-bridge" \
  "$BUYER_REPO/skills/codex-buyer-agentpay/bin/x402-client"

cd "$BUYER_REPO"
git status --short
```

Commit the updated binaries together with any bundle docs, scripts, or env template changes. This is what makes dashboard UI fixes available to users who install via `install.sh`.

### How RUN AGENT works

Clicking RUN AGENT forks your local LLM CLI — `codex` if present, otherwise `claude` — and prompts it to invoke `skills/codex-buyer-agentpay/scripts/run-batch-export.sh`. The wrapper runs `x402-client` in batch-export mode; paid x402 calls stream through your AgentPay channel and events feed the Payment Flow / Response panels live.

Requirements for the LLM path (recommended):

- One of `codex` (`brew install codex` or vendor install) or `claude` (`npm i -g @anthropic-ai/claude-code`) on `PATH`.
- That CLI must be signed in (`codex login` or `claude auth login`).

The dashboard's "Agent Setup → LLM CLI signed in" row reflects this. If no CLI is available, RUN AGENT falls back to a direct `x402-client` fork so the demo still works, but the LLM-driven framing is lost.

Paid calls spend USDC from the buyer channel.

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
