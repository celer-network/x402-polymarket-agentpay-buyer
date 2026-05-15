#!/usr/bin/env bash
set -euo pipefail

required_vars=(SELLER_HOST SELLER_HTTP)
for v in "${required_vars[@]}"; do
  [ -n "${!v:-}" ] || { echo "ERROR: missing env var: $v" >&2; exit 1; }
done

# Emit a status event to AGENTPAY_STATUS_WEBHOOK if set (best-effort, non-blocking).
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

# Mint a fresh session id per run (see run-paid-checks.sh for rationale).
if [ -z "${AGENTPAY_SESSION_ID:-}" ] || [ "${AGENTPAY_SESSION_ID_AUTO:-1}" = "1" ]; then
  export AGENTPAY_SESSION_ID="export-$(date +%s)-$$"
fi
echo "session: $AGENTPAY_SESSION_ID"
echo "== Export checks =="

tmpfile=$(mktemp /tmp/export-check.XXXXXX.json)
trap 'rm -f "$tmpfile"' EXIT

# Export routes are paid workloads on the AgentPay seller, accessed via POST.
# A 402 response confirms the route exists and the payment flow is wired up.
# All routes are flat (no path params); identifiers are passed as body params.
# Format: route|json-body
checks=(
  # Polymarket Up/Down Markets
  '/export/prediction-markets|{"coin":"btc","limit":"2"}'
  '/export/prediction-market|{"coin":"btc","market_id":"1"}'
  '/export/prediction-market-by-slug|{"coin":"btc","slug":"test"}'
  '/export/prediction-market-snapshots|{"coin":"btc","market_id":"1"}'
  '/export/prediction-market-snapshot-at|{"coin":"btc","market_id":"1","timestamp":"2026-01-01T00:00:00Z"}'
  # Binance Spot
  '/export/crypto-spot-latest|{"coin":"btc"}'
  '/export/crypto-spot-snapshots|{"coin":"btc","limit":"2"}'
  '/export/crypto-spot-latest-trade|{"coin":"btc"}'
  '/export/crypto-spot-trades|{"coin":"btc","limit":"2"}'
)

pass=0
fail=0
results='[]'

emit "export_checks_start" "\"total\":${#checks[@]}"

for item in "${checks[@]}"; do
  r="${item%%|*}"
  body="${item#*|}"
  url="${SELLER_HTTP}${r}"
  emit "export_check_sent" "\"url\":\"${url}\""
  code=$(curl -sS -m 15 -o "$tmpfile" -w "%{http_code}" \
    -X POST -H "Content-Type: application/json" -d "$body" "$url" || echo "000")
  # 402 = route exists, payment required (expected for all export workloads)
  # 2xx = route returned data (would happen if payment was included)
  if [[ "$code" =~ ^(2[0-9][0-9]|402)$ ]]; then
    echo "PASS [$code] $r"
    status="pass"
    pass=$((pass + 1))
  else
    echo "FAIL [$code] $r"
    head -c 240 "$tmpfile" 2>/dev/null || true
    echo
    status="fail"
    fail=$((fail + 1))
  fi
  emit "export_check_result" "\"url\":\"${url}\",\"status\":\"${status}\",\"http_status\":${code}"
  entry=$(jq -n --arg route "$r" --arg status "$status" --arg code "$code" \
    '{route:$route, status:$status, http_code:($code|tonumber)}')
  results=$(echo "$results" | jq --argjson e "$entry" '. + [$e]')
done

echo "$results" | jq '{export_checks: {pass:'"$pass"', fail:'"$fail"', results:.}}'
emit "export_checks_done" "\"pass\":${pass},\"fail\":${fail}"

if [ "$fail" -ne 0 ]; then
  echo "Export checks failed" >&2
  exit 1
fi

echo "Export checks complete"
