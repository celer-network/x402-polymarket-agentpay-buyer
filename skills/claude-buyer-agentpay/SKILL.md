# Claude Code Buyer AgentPay Skill

Claude Code orchestration for buyer-side payment flow and API access on Base.

## When to use

Use this skill when the user asks to:
- Test buyer payment flow against the seller
- Validate paid or export endpoints
- Run buyer preflight checks
- Debug AgentPay connectivity or channel issues

## Shared scripts

This skill reuses scripts from the Codex sibling:

- `skills/codex-buyer-agentpay/scripts/preflight.sh`
- `skills/codex-buyer-agentpay/scripts/run-paid-checks.sh`
- `skills/codex-buyer-agentpay/scripts/run-export-checks.sh`
- `skills/codex-buyer-agentpay/bin/node`
- `skills/codex-buyer-agentpay/templates/buyer.env.template`

## Required environment

All scripts expect these env vars (set via env file or exported individually):

| Variable | Required | Description |
|---|---|---|
| `SELLER_HOST` | yes | Seller endpoint host |
| `SELLER_HTTP` | yes | Derived: `http://${SELLER_HOST}:8403` |
| `SELLER_GRPC` | yes | Derived: `${SELLER_HOST}:20001` |
| `RELAY_ADMIN` | yes | Derived: `http://${SELLER_HOST}:8190` |
| `BUYER_KEY` | yes | 64 hex chars, no `0x` prefix |
| `NODE_BIN` | no | Path to agent-pay-x402 node binary (default: `skills/codex-buyer-agentpay/bin/node`) |
| `BUYER_PROFILE` | yes | Path to buyer profile JSON |
| `BUYER_DATA_DIR` | yes | Buyer local state directory |
| `GO_BIN` | no | Go binary path (default: `go`) |
| `NETWORK` | no | Default: `eip155:8453` |
| `CHAIN_ID` | no | Default: `8453` |
| `OPEN_CHANNEL_ON_START` | no | `0` or `1` |
| `CHANNEL_DEPOSIT` | no | Default: `500000` |

## Workflow

### Step 1: Ensure env file exists

Check for `/tmp/buyer-agentpay.env`. If missing, copy the template and ask the user to fill in `BUYER_KEY`:

```bash
cp skills/codex-buyer-agentpay/templates/buyer.env.template /tmp/buyer-agentpay.env
```

Then prompt: "Please set BUYER_KEY in /tmp/buyer-agentpay.env before continuing."

### Step 2: Source and validate

```bash
source /tmp/buyer-agentpay.env
```

Verify critical vars are set. If `BUYER_KEY` is still the placeholder, stop and ask the user.

### Step 3: Generate buyer profile (if needed)

```bash
[ -f "$BUYER_PROFILE" ] || SELLER_HOST=$SELLER_HOST OUT=$BUYER_PROFILE bash deploy/gen-buyer-profile.sh
```

### Step 4: Preflight

```bash
source /tmp/buyer-agentpay.env && bash skills/codex-buyer-agentpay/scripts/preflight.sh
```

Read the output. If preflight fails:
- Unreachable seller → ask user to confirm SELLER_HOST or check if the seller is running.
- Missing node binary → check that `skills/codex-buyer-agentpay/bin/node` exists and is executable, or ask user for correct NODE_BIN path.
- gRPC unreachable → check if seller gRPC port is open.
- Low USDC balance → buyer needs USDC on Base before proceeding.
- Low allowance → buyer must approve USDC for AgentPayWallet and AgentPayLedger; preflight prints the exact `cast send` command.

### Step 5: Paid checks

```bash
source /tmp/buyer-agentpay.env && bash skills/codex-buyer-agentpay/scripts/run-paid-checks.sh
```

Parse the JSON summary from stdout. If a paid check fails:
- Exit code from `go run` → check if Go toolchain is available.
- 402 loop → check buyer balance/allowance.
- Channel error → report the specific error class and suggest remediation per the failure policy.

### Step 6: Export checks

```bash
source /tmp/buyer-agentpay.env && bash skills/codex-buyer-agentpay/scripts/run-export-checks.sh
```

Parse the JSON summary. Report per-route pass/fail. Export routes are paid workloads — the script sends POST requests and treats 402 (payment required) as a pass, confirming the route is reachable and wired up.

### Step 7: Report

Present a structured summary to the user:

1. **Preflight**: connectivity status, workloads discovered
2. **Paid endpoints**: pass/fail for `/markets`, payment status
3. **Export endpoints**: pass/fail per route
4. **Remediation**: actionable fixes for any failures

## Failure handling

| Error | Action |
|---|---|
| `402` payment loop | Check buyer USDC balance and AgentPayLedger allowance via preflight |
| `AlreadyExists` / inflight channel | Channel open already in progress — set `OPEN_CHANNEL_ON_START=0` and retry; the code will wait for join |
| `no route to destination` | Relay routing table is empty: restart `agentpay-seller-node` on EC2, then retry |
| `balance not enough, need N free 0` | Relay has 0 balance toward seller — fund the relay-seller channel via relay admin `/admin/deposit`; check with seller operator |
| `allowance` / `insufficient balance` | Approve USDC for AgentPayWallet and AgentPayLedger contracts; see preflight output for exact values |
| `5xx` / timeout on /markets | Upstream Gamma API issue — retry once, then report |
| Stale data dir after buyer key change | `BUYER_DATA_DIR` is keyed by buyer address; changing `BUYER_KEY` automatically uses a new dir |
| `free_balance=0` but on-chain Ledger has funds for the channel | Off-chain state desynced from chain (manual deposit, failed `-deposit` job with timed-out WaitMined). Run `x402-client -sync ...` (no on-chain tx) to pull on-chain state into local DB before depositing more USDC. Preflight does this automatically; manual invocation only needed if preflight is skipped. |
| `wait PAID: timeout ... last observed UNPAID` | Buyer-relay channel is fine; the relay→seller channel is drained or routing is broken. Buyer side is blocked — flag the seller operator. Operator runbook: `doc/deployment/relay-refill.md`. Preflight's `/readyz` check should surface this before paid calls are attempted. |
| `Deposit job ... failed: context deadline exceeded` | SDK's `WaitMined` defaults to 10s; on-chain tx may have actually succeeded. Do NOT retry `-deposit` (would burn another deposit). Run `-sync` to pull the confirmed state into local DB. |

## Security

1. Never print `BUYER_KEY` in any output or tool call.
2. When reading the env file, mask the key value.
3. Always confirm with the user before running paid checks (these spend real USDC).
4. Use `BUYER_DATA_DIR` isolation — never mix with other state.

## Differences from Codex variant

| Aspect | Codex | Claude Code |
|---|---|---|
| Secret handling | Pre-baked in sandbox env | Interactive — prompt user to set |
| Error recovery | Return remediation list | Interactive — diagnose and fix inline |
| Confirmation | None (autonomous) | Confirm before paid checks |
| Output format | Structured JSON for machine | Structured summary for human |
| Network access | Needs `--full-network` sandbox flag | Direct — no sandbox restrictions |
