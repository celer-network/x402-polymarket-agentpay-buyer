#!/usr/bin/env bash
set -euo pipefail

required_vars=(
  SELLER_HOST SELLER_HTTP
  NETWORK CHAIN_ID BUYER_KEY NODE_BIN BUYER_PROFILE BUYER_DATA_DIR
)

for v in "${required_vars[@]}"; do
  if [ -z "${!v:-}" ]; then
    echo "ERROR: missing env var: $v" >&2
    exit 1
  fi
done

if ! [[ "$BUYER_KEY" =~ ^[0-9a-fA-F]{64}$ ]]; then
  echo "ERROR: BUYER_KEY must be 64 hex chars without 0x" >&2
  exit 1
fi

echo "== Preflight =="
echo "SELLER_HOST=$SELLER_HOST"
echo "NETWORK=$NETWORK CHAIN_ID=$CHAIN_ID"
echo "NODE_BIN=$NODE_BIN"
echo "BUYER_PROFILE=$BUYER_PROFILE"
echo "BUYER_DATA_DIR=$BUYER_DATA_DIR"

[ -x "$NODE_BIN" ] || { echo "ERROR: node binary not executable: $NODE_BIN" >&2; exit 1; }

mkdir -p "$BUYER_DATA_DIR"

echo "-- seller workloads --"
curl -sS "${SELLER_HTTP}/workloads" | jq '.workloads | map({id,route})'

echo "-- seller readiness (relay→seller channel) --"
_ready=$(curl -sS -m 10 -o /dev/null -w "%{http_code}" "${SELLER_HTTP}/readyz" || echo "000")
if [ "$_ready" = "200" ]; then
  echo "seller /readyz OK — relay→seller channel has free balance"
elif [ "$_ready" = "503" ]; then
  _body=$(curl -sS -m 10 "${SELLER_HTTP}/readyz" 2>/dev/null || echo '{}')
  _reason=$(echo "$_body" | jq -r '.reason // "unknown"' 2>/dev/null)
  echo ""
  echo "  ⚠️  seller /readyz = 503 (reason=${_reason})"
  if [ "$_reason" = "channel_drained" ]; then
    echo "  relay→seller channel has zero free balance — paid calls will fail with UNPAID."
    echo "  Fix on EC2:"
    echo "    curl -sS -X POST http://localhost:8190/admin/deposit -H 'Content-Type: application/json' \\"
    echo "      -d '{\"peer_addr\":\"<SELLER_ADDR>\",\"token_addr\":\"<TOKEN_ADDR>\",\"to_peer\":false,\"amt_wei\":\"500000\",\"max_wait_s\":0}'"
    echo "  (Top up relay USDC wallet first if it's also empty.)"
  fi
  echo ""
elif [ "$_ready" = "404" ]; then
  echo "seller /readyz not mounted (older seller-server build — upgrade to enable readiness probe)"
else
  echo "WARN: /readyz returned http=${_ready}"
fi

echo "-- relay admin reachable --"
if [ -n "${RELAY_ADMIN:-}" ]; then
  code=$(curl -sS -m 10 -o /dev/null -w "%{http_code}" "${RELAY_ADMIN}/" || echo "000")
  if [ "$code" = "000" ]; then
    echo "ERROR: relay admin unreachable: ${RELAY_ADMIN}" >&2
    exit 1
  fi
  echo "relay admin http=$code"
else
  echo "relay admin not configured (remote buyer mode)"
fi

echo "-- seller gRPC reachable --"
if [ -z "${SELLER_GRPC:-}" ]; then
  echo "seller gRPC not configured (remote buyer mode)"
elif command -v nc &>/dev/null; then
  grpc_host="${SELLER_GRPC%%:*}"
  grpc_port="${SELLER_GRPC##*:}"
  if nc -z -w 5 "$grpc_host" "$grpc_port" 2>/dev/null; then
    echo "seller gRPC reachable at ${SELLER_GRPC}"
  else
    echo "ERROR: seller gRPC unreachable: ${SELLER_GRPC}" >&2
    exit 1
  fi
else
  echo "WARN: nc not available, skipping gRPC connectivity check"
fi

echo "-- buyer USDC balance and allowance --"
_TOKEN="${CHANNEL_TOKEN_ADDR:-0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913}"
_WALLET="${WALLET_CONTRACT_ADDR:-0x12525158a2c1aa2423ecb58d5f2da0b7920819af}"
_LEDGER="${LEDGER_CONTRACT_ADDR:-0x35c0a03a5943ef4db1b3ddc83b29e4274a6a2e2a}"
_RPC="${RPC_URL:-https://mainnet.base.org}"
_DEPOSIT="${CHANNEL_DEPOSIT:-500000}"

if command -v cast >/dev/null 2>&1; then
  _BUYER_ADDR=$(cast wallet address --private-key "0x$BUYER_KEY" 2>/dev/null || true)
  if [ -n "$_BUYER_ADDR" ]; then
    echo "Buyer address: $_BUYER_ADDR"
    _BAL=$(cast call "$_TOKEN" "balanceOf(address)(uint256)" "$_BUYER_ADDR" --rpc-url "$_RPC" 2>/dev/null | awk '{print $1}' || echo "error")
    _WALL=$(cast call "$_TOKEN" "allowance(address,address)(uint256)" "$_BUYER_ADDR" "$_WALLET" --rpc-url "$_RPC" 2>/dev/null | awk '{print $1}' || echo "error")
    _LEDG=$(cast call "$_TOKEN" "allowance(address,address)(uint256)" "$_BUYER_ADDR" "$_LEDGER" --rpc-url "$_RPC" 2>/dev/null | awk '{print $1}' || echo "error")
    echo "USDC balance:         $_BAL  (need $_DEPOSIT for new channel)"
    echo "Allowance -> Wallet:  $_WALL"
    echo "Allowance -> Ledger:  $_LEDG"
    # Only require on-chain balance when opening a new channel.
    # If a channel is already open (OPEN_CHANNEL_ON_START=0), funds are inside
    # the channel and on-chain balance can be 0 — just warn.
    if [ "${OPEN_CHANNEL_ON_START:-0}" = "1" ]; then
      if [ "$_BAL" != "error" ] && [ "$_BAL" -lt "$_DEPOSIT" ] 2>/dev/null; then
        echo "ERROR: USDC balance ($_BAL) is below CHANNEL_DEPOSIT ($_DEPOSIT)" >&2
        exit 1
      fi
    elif [ "$_BAL" != "error" ] && [ "$_BAL" -eq 0 ] 2>/dev/null; then
      echo "  NOTE: on-chain USDC is 0 — funds are in the open channel (expected)"
    fi
    if [ "${OPEN_CHANNEL_ON_START:-0}" = "1" ]; then
      if { [ "$_WALL" != "error" ] && [ "$_WALL" -lt "$_DEPOSIT" ] 2>/dev/null; } || \
         { [ "$_LEDG" != "error" ] && [ "$_LEDG" -lt "$_DEPOSIT" ] 2>/dev/null; }; then
        echo "ERROR: USDC allowance for Wallet or Ledger is below CHANNEL_DEPOSIT ($_DEPOSIT)" >&2
        echo "  Approve: cast send $_TOKEN 'approve(address,uint256)' $_WALLET 115792089237316195423570985008687907853269984665640564039457584007913129639935 --rpc-url $_RPC --private-key 0x<KEY>" >&2
        exit 1
      fi
    fi
  fi
else
  echo "  WARN: cast (Foundry) not found — skipping on-chain USDC balance/allowance check"
  echo "  Install Foundry to enable this check:"
  echo "    curl -L https://foundry.paradigm.xyz | bash"
  echo "    foundryup"
  echo "  cast is required to verify on-chain USDC balance and approve contracts before first deposit."
fi

echo "-- channel balance --"
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_BUNDLED_CLIENT="${X402_CLIENT_BIN:-${_SCRIPT_DIR}/../bin/x402-client}"
if [ -x "$_BUNDLED_CLIENT" ]; then
  _CLIENT_CMD=("$_BUNDLED_CLIENT")
elif [ -n "${GO_BIN:-}" ] && [ -f "./cmd/x402-client/main.go" ]; then
  _CLIENT_CMD=("$GO_BIN" "run" "./cmd/x402-client")
else
  _CLIENT_CMD=()
fi

_query_balance() {
  "${_CLIENT_CMD[@]}" \
    -balance \
    -network "$NETWORK" \
    -signer-chain-id "$CHAIN_ID" \
    -node-bin "$NODE_BIN" \
    -buyer-profile "$BUYER_PROFILE" \
    -buyer-data-dir "$BUYER_DATA_DIR" \
    -seller-grpc "$SELLER_GRPC" \
    -relay-admin-url "$RELAY_ADMIN" \
    -price "$_PRICE" \
    2>/dev/null || echo ""
}

if [ "${#_CLIENT_CMD[@]}" -gt 0 ]; then
  export AGENTPAY_SIGNER_PRIVATE_KEY_HEX="$BUYER_KEY"
  _PRICE="${PRICE_TOKEN_UNITS:-50000}"
  _BAL_OUT=$(_query_balance)
  if [ -n "$_BAL_OUT" ]; then
    echo "$_BAL_OUT"
    _FREE=$(echo "$_BAL_OUT" | jq -r '.free_balance // "0"' 2>/dev/null || echo "0")
    _CALLS=$(echo "$_BAL_OUT" | jq -r '.estimated_calls_remaining // "0"' 2>/dev/null || echo "0")

    # If off-chain free_balance is 0, an on-chain deposit may have desynced
    # from local state (manual deposit, failed -deposit job, or stale data dir).
    # Auto-run -sync once before declaring the channel underfunded — it's cheap
    # (no on-chain tx) and recovers state without spending more USDC.
    if [ "$_FREE" = "0" ] || [ "$_FREE" = "null" ] || [ "$_FREE" = "" ]; then
      echo ""
      echo "  free_balance=0 — running on-chain state sync (no tx) before declaring underfunded..."
      "${_CLIENT_CMD[@]}" \
        -sync \
        -network "$NETWORK" \
        -signer-chain-id "$CHAIN_ID" \
        -node-bin "$NODE_BIN" \
        -buyer-profile "$BUYER_PROFILE" \
        -buyer-data-dir "$BUYER_DATA_DIR" \
        -seller-grpc "$SELLER_GRPC" \
        -relay-admin-url "$RELAY_ADMIN" \
        >/dev/null 2>&1 && echo "  sync ok" || echo "  sync skipped (older x402-client?)"
      _BAL_OUT=$(_query_balance)
      echo "$_BAL_OUT"
      _FREE=$(echo "$_BAL_OUT" | jq -r '.free_balance // "0"' 2>/dev/null || echo "0")
      _CALLS=$(echo "$_BAL_OUT" | jq -r '.estimated_calls_remaining // "0"' 2>/dev/null || echo "0")
    fi

    if [ "$_FREE" = "0" ] || [ "$_FREE" = "null" ] || [ "$_FREE" = "" ]; then
      echo ""
      echo "  ACTION REQUIRED: Channel has no funds (sync confirmed nothing on-chain)."
      echo "  State channels amortize gas cost across many payments — deposit once, pay many times."
      echo "  Recommended deposit: ${CHANNEL_DEPOSIT:-500000} USDC-units (0.50 USDC ≈ 10 calls at $_PRICE/call)"
      echo ""
      echo "  To open a channel and deposit:"
      echo "    export OPEN_CHANNEL_ON_START=1"
      echo "    bash skills/codex-buyer-agentpay/scripts/run-paid-checks.sh"
      echo ""
      echo "  On-chain prerequisites (if not already done):"
      echo "    cast send ${_TOKEN} 'approve(address,uint256)' ${_WALLET} 115792089237316195423570985008687907853269984665640564039457584007913129639935 --rpc-url ${_RPC:-https://mainnet.base.org} --private-key 0x<BUYER_KEY>"
    else
      echo "  Channel OK: free_balance=${_FREE}, estimated_calls_remaining=${_CALLS}"
    fi
  else
    echo "  WARN: could not query channel balance (node may not be running yet)"
  fi
else
  echo "  WARN: x402-client not available, skipping channel balance check"
fi

echo "Preflight OK"
