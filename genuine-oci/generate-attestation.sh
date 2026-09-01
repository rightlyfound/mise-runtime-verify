#!/usr/bin/env bash
set -euo pipefail

MODEL_FP="${1:-}"
RECEIPTS="${RECEIPTS:-./rekor-receipts.json}"
OUT="${OUT:-./attestation.jwt}"
PUB="${PUB:-./attestation-public.pem}"
KEY="${KEY:-./attestation-private.pem}"
SPEC_VERSION="${SPEC_VERSION:-v1.0.1}"
OCI_IMAGE_SHA="${OCI_IMAGE_SHA:-unknown}"
RUNTIME_FP="${RUNTIME_FP:-$(jq -r '.receipts[] | select(.spec_id=="P0") | .fingerprint' "$RECEIPTS")}" 
REKOR_INDEX="${REKOR_INDEX:-$(jq -r '.receipts[] | select(.spec_id=="P0") | .log_index // empty' "$RECEIPTS")}" 
[[ -n "$MODEL_FP" ]] || { echo "usage: $0 MODEL_FINGERPRINT" >&2; exit 2; }
command -v openssl >/dev/null || { echo 'openssl is required' >&2; exit 2; }
command -v jq >/dev/null || { echo 'jq is required' >&2; exit 2; }

[[ -f "$KEY" ]] || openssl genpkey -algorithm Ed25519 -out "$KEY" 2>/dev/null
openssl pkey -in "$KEY" -pubout -out "$PUB" 2>/dev/null
b64() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
now=$(date +%s); exp=$((now + 300))
header=$(printf '%s' '{"alg":"EdDSA","typ":"JWT"}' | b64)
payload=$(jq -cn --arg r "$RUNTIME_FP" --arg m "$MODEL_FP" --arg i "$REKOR_INDEX" --arg v "$SPEC_VERSION" --arg o "$OCI_IMAGE_SHA" --argjson n "$now" --argjson e "$exp" '{runtime_fingerprint:$r,model_fingerprint:$m,rekor_log_index:(if $i=="" then null else ($i|tonumber) end),issued_at:$n,expires_at:$e,spec_version:$v,environment:$o,pq_readiness:"Ed25519 now; ML-DSA/FIPS 204 migration path noted"}' | b64)
signing="$header.$payload"
sign_file=$(mktemp)
sig_file=$(mktemp)
printf '%s' "$signing" > "$sign_file"
openssl pkeyutl -sign -rawin -inkey "$KEY" -in "$sign_file" -out "$sig_file"
sig=$(b64 < "$sig_file")
rm -f "$sign_file" "$sig_file"
printf '%s.%s\n' "$signing" "$sig" > "$OUT"
chmod 600 "$KEY" "$OUT"
echo "Wrote $OUT and $PUB"
