#!/usr/bin/env bash
set -euo pipefail

required_vars=(SELLER_HOST SELLER_GRPC RELAY_ADMIN NETWORK CHAIN_ID NODE_BIN BUYER_PROFILE BUYER_DATA_DIR)
for v in "${required_vars[@]}"; do
  [ -n "${!v:-}" ] || { echo "ERROR: missing env var: $v" >&2; exit 1; }
done

if [ -z "${BUYER_KEY:-}" ]; then
  echo "ERROR: missing env var: BUYER_KEY" >&2
  exit 1
fi

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_BUNDLED_CLIENT="${X402_CLIENT_BIN:-${_SCRIPT_DIR}/../bin/x402-client}"
if [ -x "$_BUNDLED_CLIENT" ]; then
  _CLIENT_CMD=("$_BUNDLED_CLIENT")
elif [ -n "${GO_BIN:-}" ] && [ -f "./cmd/x402-client/main.go" ]; then
  _CLIENT_CMD=("$GO_BIN" "run" "./cmd/x402-client")
else
  echo "ERROR: no x402-client available" >&2
  exit 1
fi

export AGENTPAY_SIGNER_PRIVATE_KEY_HEX="$BUYER_KEY"
_PRICE="${PRICE_TOKEN_UNITS:-50000}"

echo "== Channel withdraw =="

echo "-- current balance --"
_BAL_OUT=$("${_CLIENT_CMD[@]}" \
  -balance \
  -network "$NETWORK" \
  -signer-chain-id "$CHAIN_ID" \
  -node-bin "$NODE_BIN" \
  -buyer-profile "$BUYER_PROFILE" \
  -buyer-data-dir "$BUYER_DATA_DIR" \
  -seller-grpc "$SELLER_GRPC" \
  -relay-admin-url "$RELAY_ADMIN" \
  -price "$_PRICE" \
  2>/dev/null || echo "")

if [ -z "$_BAL_OUT" ]; then
  echo "ERROR: could not query channel balance" >&2
  exit 1
fi

echo "$_BAL_OUT"
_FREE=$(echo "$_BAL_OUT" | jq -r '.free_balance // "0"')

if [ "$_FREE" = "0" ] || [ "$_FREE" = "null" ]; then
  echo "Nothing to withdraw: free_balance is 0"
  exit 0
fi

echo ""
echo "-- initiating cooperative withdraw --"
"${_CLIENT_CMD[@]}" \
  -withdraw \
  -network "$NETWORK" \
  -signer-chain-id "$CHAIN_ID" \
  -node-bin "$NODE_BIN" \
  -buyer-profile "$BUYER_PROFILE" \
  -buyer-data-dir "$BUYER_DATA_DIR" \
  -seller-grpc "$SELLER_GRPC" \
  -relay-admin-url "$RELAY_ADMIN"

echo "Withdraw complete"
