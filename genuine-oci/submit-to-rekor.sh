#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="${REPORT_DIR:-./reports}"
OUT="${OUT:-./rekor-receipts.json}"
REKOR_URL="${REKOR_URL:-https://rekor.sigstore.dev}"
SUBMIT=0
[[ "${1:-}" == "--submit" ]] && SUBMIT=1
command -v jq >/dev/null || { echo 'jq is required' >&2; exit 2; }
command -v curl >/dev/null || { echo 'curl is required' >&2; exit 2; }
command -v sha256sum >/dev/null || { echo 'sha256sum is required' >&2; exit 2; }

entries='[]'
for report in "$REPORT_DIR"/P{0,1,2,3,4,5}.json; do
  [[ -f "$report" ]] || { echo "missing report: $report" >&2; exit 1; }
  id=$(jq -r '.spec_id' "$report")
  fp=$(jq -r '.fingerprint' "$report")
  digest=$(sha256sum "$report" | awk '{print $1}')
  # Rekor hashedrekord signs the digest with an Ed25519 key. For an unsigned
  # public-record submission, --submit requires REKOR_PUBLIC_KEY and
  # REKOR_SIGNATURE_BASE64 to be supplied by the caller.
  if (( SUBMIT == 0 )); then
    receipt=$(jq -n --arg id "$id" --arg fp "$fp" --arg digest "$digest" --arg url "$REKOR_URL" '{spec_id:$id,fingerprint:$fp,report_sha256:$digest,status:"dry-run",rekor_url:$url}')
  else
    [[ -n "${REKOR_PUBLIC_KEY:-}" && -n "${REKOR_SIGNATURE_BASE64:-}" ]] || { echo 'REKOR_PUBLIC_KEY and REKOR_SIGNATURE_BASE64 are required with --submit' >&2; exit 2; }
    payload=$(jq -n --arg alg sha256 --arg value "$digest" --arg sig "$REKOR_SIGNATURE_BASE64" --arg pk "$REKOR_PUBLIC_KEY" '{kind:"hashedrekord",apiVersion:"1.0.0",spec:{data:{hash:{algorithm:$alg,value:$value}},signature:{content:$sig,publicKey:{content:$pk}}}}')
    response=$(curl --fail-with-body --silent --show-error -X POST "$REKOR_URL/api/v1/log/entries" -H 'Content-Type: application/json' --data "$payload")
    uuid=$(jq -r 'keys[0]' <<<"$response")
    entry=$(jq -r --arg u "$uuid" '.[$u]' <<<"$response")
    receipt=$(jq -n --arg id "$id" --arg fp "$fp" --arg url "$REKOR_URL" --arg uuid "$uuid" --argjson e "$entry" '{spec_id:$id,fingerprint:$fp,log_index:(($e.logIndex // null) | if . == null then null else tonumber end),uuid:$uuid,integrated_time:($e.integratedTime // null),inclusion_proof:($e.verification.inclusionProof // null),rekor_url:$url}')
  fi
  entries=$(jq --argjson r "$receipt" '. + [$r]' <<<"$entries")
done
jq -n --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg rekor_url "$REKOR_URL" --argjson receipts "$entries" '{version:"1.0",generated_at:$generated_at,rekor_url:$rekor_url,receipts:$receipts}' > "$OUT"
echo "Wrote $OUT"
