#!/usr/bin/env bash
set -euo pipefail

# Remote buyers don't run their own relay/seller-node, so SELLER_GRPC and
# RELAY_ADMIN are optional — x402-client spawns a local buyer-node that reaches
# the relay via BUYER_PROFILE's Osp.Host. Only fail on truly required vars.
required_vars=(NETWORK CHAIN_ID NODE_BIN BUYER_PROFILE BUYER_DATA_DIR)
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
_extra=()
[ -n "${SELLER_GRPC:-}" ] && _extra+=(-seller-grpc "$SELLER_GRPC")
[ -n "${RELAY_ADMIN:-}" ] && _extra+=(-relay-admin-url "$RELAY_ADMIN")

# Use a temp file instead of $(...) capture: x402-client spawns a buyer-node
# that inherits stdout. Command substitution would block until every fd holder
# closes — the grandchild keeps the pipe open and wedges the script. Writing
# to a file lets bash waitpid() the direct child cleanly.
_tmpout=$(mktemp /tmp/x402-withdraw.XXXXXX)
trap 'rm -f "$_tmpout"' RETURN EXIT
"${_CLIENT_CMD[@]}" \
  -balance \
  -network "$NETWORK" \
  -signer-chain-id "$CHAIN_ID" \
  -node-bin "$NODE_BIN" \
  -buyer-profile "$BUYER_PROFILE" \
  -buyer-data-dir "$BUYER_DATA_DIR" \
  "${_extra[@]}" \
  -price "$_PRICE" \
  >"$_tmpout" 2>&1 || true
_BAL_OUT=$(grep -E '^\{.*"free_balance"' "$_tmpout" | tail -1)

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
  "${_extra[@]}"

echo "Withdraw complete"
