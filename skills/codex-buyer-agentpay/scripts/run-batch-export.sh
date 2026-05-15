#!/usr/bin/env bash
# run-batch-export.sh — invoke x402-client in batch-export mode using env defaults.
# The LLM agent calls this from /run via a single Bash command; status events
# stream to AGENTPAY_STATUS_WEBHOOK so the dashboard Payment Flow stays live.
set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_BUNDLED_CLIENT="${X402_CLIENT_BIN:-${_SCRIPT_DIR}/../bin/x402-client}"
: "${SELLER_HTTP:?SELLER_HTTP required}"
: "${BUYER_KEY:?BUYER_KEY required}"
: "${BUYER_PROFILE:?BUYER_PROFILE required}"
: "${BUYER_DATA_DIR:?BUYER_DATA_DIR required}"
: "${NODE_BIN:?NODE_BIN required}"
: "${BATCH_MARKET_ID:?BATCH_MARKET_ID required}"
: "${CHAIN_ID:=8453}"
: "${NETWORK:=eip155:8453}"
: "${CHANNEL_TOKEN_ADDR:=833589fcd6edb6e08f4c7c32d4f71b54bda02913}"
: "${CHANNEL_DEPOSIT:=500000}"
: "${BATCH_COIN:=btc}"
: "${BATCH_LIMIT:=500}"
: "${BATCH_FROM_MINS:=5}"
: "${BATCH_MAX_PAGES:=5}"
: "${AGENTPAY_STATUS_WEBHOOK:=}"
: "${AGENTPAY_SESSION_ID:=}"

export AGENTPAY_SIGNER_PRIVATE_KEY_HEX="$BUYER_KEY"

args=(
  -mode=batch-export
  -server="$SELLER_HTTP"
  -url="$SELLER_HTTP"
  -signer-chain-id="$CHAIN_ID"
  -node-bin="$NODE_BIN"
  -buyer-profile="$BUYER_PROFILE"
  -buyer-data-dir="$BUYER_DATA_DIR"
  -channel-token-addr="$CHANNEL_TOKEN_ADDR"
  -channel-deposit="$CHANNEL_DEPOSIT"
  -network="$NETWORK"
  -batch-coin="$BATCH_COIN"
  -batch-market-id="$BATCH_MARKET_ID"
  -batch-limit="$BATCH_LIMIT"
  -batch-from-mins="$BATCH_FROM_MINS"
  -batch-max-pages="$BATCH_MAX_PAGES"
)
[ -n "${BATCH_FROM:-}" ] && [ -n "${BATCH_TO:-}" ] && args+=(-batch-from="$BATCH_FROM" -batch-to="$BATCH_TO")
[ -n "${SELLER_GRPC:-}" ] && args+=(-seller-grpc="$SELLER_GRPC")
[ -n "${RELAY_ADMIN:-}" ] && args+=(-relay-admin-url="$RELAY_ADMIN")
[ -n "$AGENTPAY_STATUS_WEBHOOK" ] && args+=(-status-webhook="$AGENTPAY_STATUS_WEBHOOK")
[ -n "$AGENTPAY_SESSION_ID" ] && args+=(-session-id="$AGENTPAY_SESSION_ID")

exec "$_BUNDLED_CLIENT" "${args[@]}"
