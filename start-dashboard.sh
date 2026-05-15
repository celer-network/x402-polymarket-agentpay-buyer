#!/usr/bin/env bash
set -euo pipefail

# Launch the buyer-side AgentPay dashboard from the public bundle.
# This script intentionally does not require the full x402-polymarket-data repo.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}"

ENV_FILE="${BUYER_ENV_FILE:-/tmp/buyer-agentpay.env}"
if [ -f "${ENV_FILE}" ]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
else
  echo "WARN: ${ENV_FILE} not found; dashboard will show setup guidance."
  if [ -f "${REPO_ROOT}/skills/codex-buyer-agentpay/templates/buyer.env.template" ]; then
    cp "${REPO_ROOT}/skills/codex-buyer-agentpay/templates/buyer.env.template" "${ENV_FILE}"
    echo "      Created ${ENV_FILE}; set BUYER_KEY there before running paid flows."
  fi
fi

: "${SELLER_HOST:=35.83.247.203}"
: "${SELLER_HTTP:=http://${SELLER_HOST}:8403}"
: "${SELLER_GRPC:=}"
: "${RELAY_ADMIN:=}"
: "${NETWORK:=eip155:8453}"
: "${CHAIN_ID:=8453}"
: "${RPC_URL:=https://mainnet.base.org}"
: "${CHANNEL_TOKEN_ADDR:=833589fcd6edb6e08f4c7c32d4f71b54bda02913}"
: "${CHANNEL_DEPOSIT:=500000}"
: "${BATCH_MARKET_ID:=2239711}"
: "${BATCH_COIN:=btc}"
: "${BATCH_LIMIT:=500}"
: "${BATCH_FROM_MINS:=5}"
: "${AGENT_NAME:=Buyer Agent}"
: "${DASHBOARD_PORT:=9100}"
: "${BUYER_PROFILE:=${HOME}/.x402/buyer-profile.json}"
: "${BUYER_DATA_DIR:=${HOME}/.x402/buyer-data}"
: "${NODE_BIN:=${REPO_ROOT}/skills/codex-buyer-agentpay/bin/node}"
: "${X402_CLIENT_BIN:=${REPO_ROOT}/skills/codex-buyer-agentpay/bin/x402-client}"
: "${STATUS_BRIDGE_BIN:=${REPO_ROOT}/skills/codex-buyer-agentpay/bin/status-bridge}"

if [ -z "${BUYER_KEY:-}" ] || [ "${BUYER_KEY:-}" = "<SET_ME_64_HEX_NO_0x>" ]; then
  echo "WARN: BUYER_KEY is not set; dashboard will open, but RUN AGENT stays disabled."
  echo "      Generate a fresh key: ${X402_CLIENT_BIN} -genkey"
elif [ "${#BUYER_KEY}" -ne 64 ]; then
  echo "WARN: BUYER_KEY must be exactly 64 hex characters without 0x."
fi

[ -x "${STATUS_BRIDGE_BIN}" ] || { echo "ERROR: status-bridge not executable: ${STATUS_BRIDGE_BIN}" >&2; exit 1; }
[ -x "${X402_CLIENT_BIN}" ] || { echo "ERROR: x402-client not executable: ${X402_CLIENT_BIN}" >&2; exit 1; }
[ -x "${NODE_BIN}" ] || { echo "ERROR: node not executable: ${NODE_BIN}" >&2; exit 1; }

if [ ! -f "${BUYER_PROFILE}" ]; then
  echo "==> Generating buyer profile -> ${BUYER_PROFILE}"
  mkdir -p "$(dirname "${BUYER_PROFILE}")"
  OUT="${BUYER_PROFILE}" SELLER_HOST="${SELLER_HOST}" \
    bash "${REPO_ROOT}/deploy/gen-buyer-profile.sh"
fi
mkdir -p "${BUYER_DATA_DIR}"

if command -v lsof >/dev/null 2>&1 && lsof -ti ":${DASHBOARD_PORT}" >/dev/null 2>&1; then
  echo "==> Stopping existing process on :${DASHBOARD_PORT}"
  lsof -ti ":${DASHBOARD_PORT}" | xargs kill -9 2>/dev/null || true
fi

export SELLER_HTTP SELLER_GRPC RELAY_ADMIN
export REPO_ROOT BUYER_KEY BUYER_PROFILE BUYER_DATA_DIR NODE_BIN
export RPC_URL CHAIN_ID NETWORK CHANNEL_TOKEN_ADDR CHANNEL_DEPOSIT
export BATCH_MARKET_ID BATCH_COIN BATCH_LIMIT BATCH_FROM_MINS AGENT_NAME
export X402_CLIENT_BIN
export STATUS_BRIDGE_URL="http://127.0.0.1:${DASHBOARD_PORT}"

DATA_DIR="${HOME}/.x402/status-bridge"
mkdir -p "${DATA_DIR}"

echo ""
echo "==> Dashboard: http://localhost:${DASHBOARD_PORT}"
echo "    Seller : ${SELLER_HTTP}"
echo "    Market : ${BATCH_MARKET_ID}"
echo ""

"${STATUS_BRIDGE_BIN}" -addr ":${DASHBOARD_PORT}" -data-dir "${DATA_DIR}" &
BRIDGE_PID=$!

cleanup() {
  echo
  echo "Stopping dashboard..."
  kill -TERM "${BRIDGE_PID}" 2>/dev/null || true
  exit 0
}
trap cleanup INT TERM

for _ in $(seq 1 20); do
  curl -sf "http://127.0.0.1:${DASHBOARD_PORT}/config" >/dev/null 2>&1 && break
  sleep 0.3
done

URL="http://localhost:${DASHBOARD_PORT}"
if command -v open >/dev/null 2>&1; then
  open "${URL}"
elif command -v xdg-open >/dev/null 2>&1; then
  xdg-open "${URL}" >/dev/null 2>&1 &
fi

echo "Press Ctrl-C to stop."
wait "${BRIDGE_PID}"
