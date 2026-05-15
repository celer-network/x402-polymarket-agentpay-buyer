#!/usr/bin/env bash
set -euo pipefail

required_vars=(SELLER_HOST SELLER_HTTP NETWORK CHAIN_ID NODE_BIN BUYER_PROFILE BUYER_DATA_DIR)
for v in "${required_vars[@]}"; do
  [ -n "${!v:-}" ] || { echo "ERROR: missing env var: $v" >&2; exit 1; }
done

if [ -z "${BUYER_KEY:-}" ]; then
  echo "ERROR: missing env var: BUYER_KEY" >&2
  exit 1
fi

# Resolve x402-client: use bundled binary, explicit override, or go run fallback.
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_BUNDLED_CLIENT="${X402_CLIENT_BIN:-${_SCRIPT_DIR}/../bin/x402-client}"
if [ -x "$_BUNDLED_CLIENT" ]; then
  _CLIENT_CMD=("$_BUNDLED_CLIENT")
elif [ -n "${GO_BIN:-}" ] && [ -f "./cmd/x402-client/main.go" ]; then
  _CLIENT_CMD=("$GO_BIN" "run" "./cmd/x402-client")
else
  echo "ERROR: no x402-client available. Either:" >&2
  echo "  - ensure skills/codex-buyer-agentpay/bin/x402-client exists (bundled), or" >&2
  echo "  - set X402_CLIENT_BIN to a prebuilt binary path, or" >&2
  echo "  - set X402_CLIENT_BIN to a prebuilt binary path" >&2
  exit 1
fi
echo "x402-client: ${_CLIENT_CMD[*]}"

export AGENTPAY_SIGNER_PRIVATE_KEY_HEX="$BUYER_KEY"

# Each run-paid-checks invocation owns its own dashboard session so the
# timeline reflects one round-trip, not minutes-apart reruns piled onto a
# stale env var. Honor an explicit override (CI / orchestrators that bundle
# multiple paid-checks calls into one logical session) but otherwise mint a
# fresh ID per run.
if [ -z "${AGENTPAY_SESSION_ID:-}" ] || [ "${AGENTPAY_SESSION_ID_AUTO:-1}" = "1" ]; then
  export AGENTPAY_SESSION_ID="paid-$(date +%s)-$$"
fi
echo "session: $AGENTPAY_SESSION_ID"

# Emit a status event to AGENTPAY_STATUS_WEBHOOK if set (best-effort).
emit() {
  [ -z "${AGENTPAY_STATUS_WEBHOOK:-}" ] && return 0
  local event="$1"; shift
  local extra="$*"
  local ts
  ts=$(date +%s%3N 2>/dev/null || echo "0")
  local sid="${AGENTPAY_SESSION_ID:-}"
  local payload="{\"session_id\":\"${sid}\",\"event\":\"${event}\",\"ts\":${ts}${extra:+,${extra}}}"
  curl -sS -m 3 -X POST -H "Content-Type: application/json" \
    -d "$payload" "$AGENTPAY_STATUS_WEBHOOK" >/dev/null 2>&1 || true
}

echo "== Paid checks =="

results='[]'
pass=0
fail=0

run_paid() {
  local url="$1"
  local method="$2"
  local body="$3"
  local open_ch="$4"
  local rc=0
  local extra_args=()
  if [ -n "$body" ]; then
    extra_args+=(-body "$body")
  fi
  if [ -n "${SELLER_GRPC:-}" ]; then
    extra_args+=(-seller-grpc "$SELLER_GRPC")
  fi
  if [ -n "${RELAY_ADMIN:-}" ]; then
    extra_args+=(-relay-admin-url "$RELAY_ADMIN")
  fi
  # Use a temp file instead of command substitution: the node subprocess inherits
  # os.Stderr from x402-client. If x402-client exits without killing the node
  # (e.g. via os.Exit), bash command substitution blocks until every FD holder
  # exits. Writing to a file avoids that — bash waits on x402-client (waitpid),
  # not on the pipe EOF.
  local _tmpout
  _tmpout=$(mktemp /tmp/x402-paid-check.XXXXXX)
  trap 'rm -f "$_tmpout"' RETURN
  "${_CLIENT_CMD[@]}" \
    -mode agentpay \
    -url "$url" \
    -server "$SELLER_HTTP" \
    -method "$method" \
    "${extra_args[@]}" \
    -network "$NETWORK" \
    -signer-chain-id "$CHAIN_ID" \
    -node-bin "$NODE_BIN" \
    -buyer-profile "$BUYER_PROFILE" \
    -buyer-data-dir "$BUYER_DATA_DIR" \
    -open-channel="$open_ch" \
    -channel-deposit="${CHANNEL_DEPOSIT:-500000}" \
    -v >"$_tmpout" 2>&1 || rc=$?
  local output
  output=$(tail -c 512 "$_tmpout")
  local status="pass"
  if [ "$rc" -ne 0 ]; then
    status="fail"
    fail=$((fail + 1))
  else
    pass=$((pass + 1))
  fi
  local entry
  entry=$(jq -n --arg url "$url" --arg status "$status" --arg rc "$rc" \
    --arg output "$(echo "$output" | tail -c 512)" \
    '{url:$url, status:$status, exit_code:($rc|tonumber), output:$output}')
  results=$(echo "$results" | jq --argjson e "$entry" '. + [$e]')
  emit "paid_check_result" "\"url\":\"${url}\",\"status\":\"${status}\",\"exit_code\":${rc}"
  if [ "$status" = "pass" ]; then
    echo "PASS $url"
  else
    echo "FAIL $url (exit $rc)"
  fi
}

emit "paid_checks_start"
# AgentPay seller maps workloads as POST routes; body is parsed as JSON by Execute().
run_paid "${SELLER_HTTP}/api/v1/markets" POST '{"search":"election","status":"open","limit":"2"}' "${OPEN_CHANNEL_ON_START:-0}"

echo "$results" | jq '{paid_checks: {pass:'"$pass"', fail:'"$fail"', results:.}}'
emit "paid_checks_done" "\"pass\":${pass},\"fail\":${fail}"

if [ "$fail" -ne 0 ]; then
  echo "Paid checks failed" >&2
  exit 1
fi

echo "Paid checks complete"
