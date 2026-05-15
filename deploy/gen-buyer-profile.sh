#!/usr/bin/env bash
set -euo pipefail

# gen-buyer-profile.sh
# Generate a buyer profile JSON for Base AgentPay flows.
#
# Usage:
#   bash deploy/gen-buyer-profile.sh
#   SELLER_HOST=35.83.247.203 OUT=/tmp/buyer-profile.json bash deploy/gen-buyer-profile.sh
#
# Optional overrides:
#   SELLER_HOST      default: 35.83.247.203
#   OSP_ADDR         default: 0x2bbB4a539630C57677d84e5022d1fa49Ed0619B7
#   CHAIN_ID         default: 8453
#   ETH_GATEWAY      default: https://mainnet.base.org
#   OUT              default: /tmp/buyer-profile.json

SELLER_HOST="${SELLER_HOST:-35.83.247.203}"
OSP_ADDR="${OSP_ADDR:-0x2bbB4a539630C57677d84e5022d1fa49Ed0619B7}"
CHAIN_ID="${CHAIN_ID:-8453}"
ETH_GATEWAY="${ETH_GATEWAY:-https://mainnet.base.org}"
OUT="${OUT:-/tmp/buyer-profile.json}"

mkdir -p "$(dirname "$OUT")"

cat >"$OUT" <<EOF
{
  "Version": "0.1",
  "Ethereum": {
    "Gateway": "${ETH_GATEWAY}",
    "ChainId": ${CHAIN_ID},
    "BlockIntervalSec": 2,
    "BlockDelayNum": 5,
    "DisputeTimeout": 0,
    "Contracts": {
      "Wallet": "0x12525158a2c1aa2423ecb58d5f2da0b7920819af",
      "Ledger": "0x35c0a03a5943ef4db1b3ddc83b29e4274a6a2e2a",
      "VirtResolver": "0xa9cbd28635c7e742db9d14443d2885f1d4180a0b",
      "NativeWrap": "0x4200000000000000000000000000000000000006",
      "PayResolver": "0xb44f42718d7f6f01a066ed9346a9c7a1c2483b30",
      "PayRegistry": "0xe0419c6de652b3760aeed57db176d30d8356fdb0",
      "RouterRegistry": "0xe280d399e657434ba74d9af279770418e766cb75",
      "Ledgers": null
    },
    "CheckInterval": null
  },
  "Osp": {
    "Host": "${SELLER_HOST}:10001",
    "Address": "${OSP_ADDR}",
    "ExplorerUrl": ""
  },
  "Sgn": {
    "Gateway": "",
    "SgnContractAddr": ""
  }
}
EOF

echo "Buyer profile written: ${OUT}"
echo "Relay OSP host: ${SELLER_HOST}:10001"
echo "Chain ID: ${CHAIN_ID}"
