#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-https://raw.githubusercontent.com/celer-network/x402-polymarket-agentpay-buyer/refs/heads/main}"
INSTALL_CODEX=0
INSTALL_CLAUDE=0
TARGET_DIR="."

usage() {
  cat <<'USAGE'
Install the x402 Polymarket Buyer AgentPay bundle.

Usage:
  install.sh [--codex] [--claude] [--target DIR]

Examples:
  curl -fsSL https://raw.githubusercontent.com/celer-network/x402-polymarket-agentpay-buyer/refs/heads/main/install.sh | bash -s -- --codex
  curl -fsSL https://raw.githubusercontent.com/celer-network/x402-polymarket-agentpay-buyer/refs/heads/main/install.sh | bash -s -- --claude --target my-agent-project

Environment:
  BASE_URL  Override download base URL for mirrors or tests.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --codex)
      INSTALL_CODEX=1
      ;;
    --claude)
      INSTALL_CLAUDE=1
      ;;
    --target)
      TARGET_DIR="${2:-}"
      [ -n "$TARGET_DIR" ] || { echo "ERROR: --target requires a directory" >&2; exit 2; }
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [ "$INSTALL_CODEX" = "0" ] && [ "$INSTALL_CLAUDE" = "0" ]; then
  INSTALL_CODEX=1
fi

mkdir -p "$TARGET_DIR"
cd "$TARGET_DIR"

fetch() {
  local src="$1"
  local dst="$2"
  mkdir -p "$(dirname "$dst")"
  curl --fail --location --silent --show-error --retry 3 --retry-delay 1 --retry-all-errors "$BASE_URL/$src" -o "$dst"
}

append_if_missing() {
  local file="$1"
  local marker="$2"
  local text="$3"
  touch "$file"
  if ! grep -q "$marker" "$file"; then
    {
      printf '\n'
      printf '%s\n' "$text"
    } >> "$file"
  fi
}

echo "==> Installing buyer AgentPay bundle into $(pwd)"

fetch "skills/codex-buyer-agentpay/SKILL.md" "skills/codex-buyer-agentpay/SKILL.md"
fetch "skills/claude-buyer-agentpay/SKILL.md" "skills/claude-buyer-agentpay/SKILL.md"
fetch "skills/codex-buyer-agentpay/templates/buyer.env.template" "skills/codex-buyer-agentpay/templates/buyer.env.template"
fetch "skills/codex-buyer-agentpay/templates/AGENTS.md.example" "skills/codex-buyer-agentpay/templates/AGENTS.md.example"
fetch "skills/codex-buyer-agentpay/scripts/preflight.sh" "skills/codex-buyer-agentpay/scripts/preflight.sh"
fetch "skills/codex-buyer-agentpay/scripts/run-paid-checks.sh" "skills/codex-buyer-agentpay/scripts/run-paid-checks.sh"
fetch "skills/codex-buyer-agentpay/scripts/run-export-checks.sh" "skills/codex-buyer-agentpay/scripts/run-export-checks.sh"
fetch "skills/codex-buyer-agentpay/scripts/run-withdraw.sh" "skills/codex-buyer-agentpay/scripts/run-withdraw.sh"
fetch "skills/codex-buyer-agentpay/bin/node" "skills/codex-buyer-agentpay/bin/node"
fetch "skills/codex-buyer-agentpay/bin/x402-client" "skills/codex-buyer-agentpay/bin/x402-client"
fetch "skills/codex-buyer-agentpay/bin/status-bridge" "skills/codex-buyer-agentpay/bin/status-bridge"
fetch "deploy/gen-buyer-profile.sh" "deploy/gen-buyer-profile.sh"
fetch "start-dashboard.sh" "start-dashboard.sh"

chmod +x \
  "skills/codex-buyer-agentpay/scripts/preflight.sh" \
  "skills/codex-buyer-agentpay/scripts/run-paid-checks.sh" \
  "skills/codex-buyer-agentpay/scripts/run-export-checks.sh" \
  "skills/codex-buyer-agentpay/scripts/run-withdraw.sh" \
  "skills/codex-buyer-agentpay/bin/node" \
  "skills/codex-buyer-agentpay/bin/x402-client" \
  "skills/codex-buyer-agentpay/bin/status-bridge" \
  "deploy/gen-buyer-profile.sh" \
  "start-dashboard.sh"

if [ "$INSTALL_CODEX" = "1" ]; then
  if [ -f "AGENTS.md" ]; then
    append_if_missing "AGENTS.md" "Buyer AgentPay Skill" "$(sed '1d' skills/codex-buyer-agentpay/templates/AGENTS.md.example)"
  else
    cp "skills/codex-buyer-agentpay/templates/AGENTS.md.example" "AGENTS.md"
  fi
  echo "==> Codex wiring installed: AGENTS.md"
fi

if [ "$INSTALL_CLAUDE" = "1" ]; then
  mkdir -p ".claude"
  append_if_missing "CLAUDE.md" "claude-buyer-agentpay/SKILL.md" "## Polymarket Data Skill

Access Polymarket prediction market and crypto price data via paid AgentPay channels.

Skill doc: \`skills/claude-buyer-agentpay/SKILL.md\`

Quick invocation:
1. Ensure \`/tmp/buyer-agentpay.env\` exists.
2. Set \`BUYER_KEY\` in the env file.
3. Run preflight, paid checks, and export checks per the skill doc."
  cat > ".claude/settings.local.json" <<'JSON'
{
  "permissions": {
    "allow": [
      "Bash(source /tmp/buyer-agentpay.env && bash skills/codex-buyer-agentpay/scripts/preflight.sh)",
      "Bash(source /tmp/buyer-agentpay.env && bash skills/codex-buyer-agentpay/scripts/run-export-checks.sh)",
      "Bash(bash deploy/gen-buyer-profile.sh)"
    ]
  }
}
JSON
  echo "==> Claude Code wiring installed: CLAUDE.md and .claude/settings.local.json"
fi

if [ ! -f "/tmp/buyer-agentpay.env" ]; then
  cp "skills/codex-buyer-agentpay/templates/buyer.env.template" "/tmp/buyer-agentpay.env"
  echo "==> Created /tmp/buyer-agentpay.env"
else
  echo "==> /tmp/buyer-agentpay.env already exists; left unchanged"
fi

cat <<'NEXT'

Next:
  1. Edit /tmp/buyer-agentpay.env and set BUYER_KEY.
  2. Run:
       source /tmp/buyer-agentpay.env
       SELLER_HOST=$SELLER_HOST OUT=$BUYER_PROFILE bash deploy/gen-buyer-profile.sh
       bash skills/codex-buyer-agentpay/scripts/preflight.sh
  3. Ask your Codex or Claude Code agent to run the Polymarket data buyer flow.
  4. Optional dashboard:
       bash start-dashboard.sh
NEXT
