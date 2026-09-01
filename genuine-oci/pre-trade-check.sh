#!/usr/bin/env bash
set -euo pipefail

PAIR="${1:-}"; SIDE="${2:-}"; QTY="${3:-}"; PRICE="${4:-}"
JWT_FILE="${JWT_FILE:-./attestation.jwt}"
PUB="${PUB:-./attestation-public.pem}"
RECEIPTS="${RECEIPTS:-./rekor-receipts.json}"
EXPECTED_FP="${EXPECTED_FP:-d02147dc0e389bf665696632d8ec5c7bb2a3bbe27a58add543a735c74eb0e536}"
fail() { echo "ATTESTATION-FAIL: $*"; exit 1; }
[[ -n "$PAIR" && "$SIDE" =~ ^(buy|sell)$ && "$QTY" =~ ^[0-9]+([.][0-9]+)?$ && "$PRICE" =~ ^[0-9]+([.][0-9]+)?$ ]] || fail 'invalid trade arguments'
[[ -s "$JWT_FILE" && -s "$PUB" && -f "$RECEIPTS" ]] || fail 'attestation files missing'
command -v openssl >/dev/null || fail 'openssl is required'
command -v jq >/dev/null || fail 'jq is required'
IFS=. read -r h p s < "$JWT_FILE" || fail 'malformed JWT'
[[ -n "$h" && -n "$p" && -n "$s" ]] || fail 'malformed JWT'
b64d() { local x="$1"; x="${x//-/+}"; x="${x//_//}"; while (( ${#x} % 4 )); do x+='='; done; printf '%s' "$x" | openssl base64 -d -A; }
sign_input="$h.$p"
verify_input=$(mktemp); verify_sig=$(mktemp)
printf '%s' "$sign_input" > "$verify_input"
b64d "$s" > "$verify_sig" || { rm -f "$verify_input" "$verify_sig"; fail 'invalid JWT signature encoding'; }
openssl pkeyutl -verify -rawin -pubin -inkey "$PUB" -in "$verify_input" -sigfile "$verify_sig" >/dev/null 2>&1 || { rm -f "$verify_input" "$verify_sig"; fail 'JWT signature invalid'; }
rm -f "$verify_input" "$verify_sig"
payload=$(b64d "$p") || fail 'invalid JWT payload'
now=$(date +%s); exp=$(jq -r '.expires_at // 0' <<<"$payload"); runtime=$(jq -r '.runtime_fingerprint // empty' <<<"$payload"); idx=$(jq -r '.rekor_log_index // empty' <<<"$payload")
(( exp > now )) || fail 'JWT expired'
[[ "$runtime" == "$EXPECTED_FP" ]] || fail 'runtime fingerprint mismatch'
if [[ -n "$idx" ]]; then jq -e --argjson i "$idx" '.receipts[] | select(.spec_id=="P0" and .log_index==$i)' "$RECEIPTS" >/dev/null 2>&1 || fail 'Rekor receipt linkage invalid'; fi
echo "ATTESTATION-OK: $PAIR $SIDE quantity=$QTY price=$PRICE jwt=$(cat "$JWT_FILE")"
