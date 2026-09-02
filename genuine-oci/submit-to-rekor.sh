#!/usr/bin/env bash
set -euo pipefail

KEY="${KEY:-/home/ubuntu/.attestation/mise-runtime-verify.key}"
REPORT_DIR="${REPORT_DIR:-./reports}"
OUT="${OUT:-./rekor-receipts.json}"
REKOR_URL="${REKOR_URL:-https://rekor.sigstore.dev}"
COSIGN="${COSIGN:-/home/ubuntu/.local/bin/cosign}"
MODE="dry-run"
case "${1:-}" in
  '') ;;
  --test) MODE="test" ;;
  --submit) MODE="submit" ;;
  *) echo "usage: $0 [--test|--submit]" >&2; exit 2 ;;
esac

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing prerequisite: $1" >&2; exit 2; }; }
need jq; need curl; need sha256sum; need openssl
[[ -x "$COSIGN" ]] || { echo "missing prerequisite: cosign at $COSIGN" >&2; exit 2; }
"$COSIGN" version >/dev/null 2>&1 || { echo "cosign failed version check: $COSIGN" >&2; exit 2; }
TMP_FILES=()
cleanup() { ((${#TMP_FILES[@]} == 0)) || rm -f -- "${TMP_FILES[@]}"; }
trap cleanup EXIT
mktemp_track() { local f; f=$(mktemp); TMP_FILES+=("$f"); printf '%s' "$f"; }

if [[ "$MODE" != "dry-run" ]]; then
  [[ -f "$KEY" ]] || { echo "missing key: $KEY" >&2; exit 2; }
  COSIGN_PASSWORD="${COSIGN_PASSWORD:-}" "$COSIGN" public-key --key "$KEY" >/dev/null 2>&1 || { echo "KEY is not a valid cosign private key" >&2; exit 2; }
fi

sign_submit_entry() {
  local artifact_file="$1" bundle_file="$2" log_index integrated_time inclusion_proof log_id uuid entry
  "$COSIGN" sign-blob --key "$KEY" --bundle "$bundle_file" --yes "$artifact_file" >/dev/null
  log_index=$(jq -r '.verificationMaterial.tlogEntries[0].logIndex | if type == "string" then tonumber else . end' "$bundle_file")
  integrated_time=$(jq -r '.verificationMaterial.tlogEntries[0].integratedTime | if type == "string" then tonumber else . end' "$bundle_file")
  inclusion_proof=$(jq -c '.verificationMaterial.tlogEntries[0].inclusionProof' "$bundle_file")
  log_id=$(jq -r '.verificationMaterial.tlogEntries[0].logId.keyId // empty' "$bundle_file")
  [[ -n "$log_index" && "$log_index" != "null" && -n "$integrated_time" && "$integrated_time" != "null" && -n "$log_id" && "$log_id" != "null" && "$inclusion_proof" != "null" ]] || { echo "cosign bundle missing Rekor tlog fields" >&2; return 1; }
  uuid=$(curl --silent --fail-with-body --max-time 15 "${REKOR_URL}/api/v1/log/entries?logIndex=${log_index}" | jq -r 'keys[0] // empty')
  [[ -n "$uuid" && "$uuid" != "null" ]] || { echo "Rekor UUID lookup failed for log index $log_index" >&2; return 1; }
  entry=$(jq -n --arg u "$uuid" --arg i "$log_index" --arg t "$integrated_time" --arg l "$log_id" --argjson p "$inclusion_proof" '{uuid:$u,log_index:($i|tonumber),integrated_time:($t|tonumber),log_id:$l,inclusion_proof:$p}')
  printf '%s\n' "$entry"
}

if [[ "$MODE" == "test" ]]; then
  echo 'Submitting one disposable Rekor test entry.'
  test_file=$(mktemp_track)
  printf 'RuntimeSpec disposable Rekor test %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$test_file"
  test_digest=$(sha256sum "$test_file" | awk '{print $1}')
  bundle_file=$(mktemp_track)
  entry=$(sign_submit_entry "$test_file" "$bundle_file")
  uuid=$(jq -r '.uuid' <<<"$entry"); index=$(jq -r '.log_index' <<<"$entry"); integrated=$(jq -r '.integrated_time' <<<"$entry"); proof=$(jq -c '.inclusion_proof' <<<"$entry")
  [[ -n "$uuid" && "$uuid" != "null" && "$index" =~ ^[1-9][0-9]*$ && -n "$integrated" && "$integrated" != "null" && "$proof" != "null" ]] || { echo 'Rekor test response missing required fields' >&2; exit 1; }
  echo "Rekor test succeeded: uuid=$uuid log_index=$index integrated_time=$integrated"
  echo "Verify at: ${REKOR_URL}/api/v1/log/entries/${uuid}"
  exit 0
fi

receipts='[]'
if [[ "$MODE" == "submit" ]]; then
  echo 'WARNING: This will create permanent public Rekor entries.'
fi
for report in "$REPORT_DIR"/P{0,1,2,3,4,5}.json; do
  [[ -f "$report" ]] || { echo "missing report: $report" >&2; exit 1; }
  id=$(jq -r '.spec_id' "$report")
  fp=$(jq -r '.fingerprint' "$report")
  digest=$(sha256sum "$report" | awk '{print $1}')
  if [[ "$MODE" == "dry-run" ]]; then
    echo "[$id] dry-run: digest=$digest"
    receipt=$(jq -n --arg id "$id" --arg fp "$fp" --arg d "$digest" --arg url "$REKOR_URL" '{spec_id:$id,fingerprint:$fp,report_sha256:$d,status:"dry-run",rekor_url:$url}')
  else
    echo "[$id] submitting digest=$digest"
    bundle_file="$REPORT_DIR/${id}-bundle.json"
    entry=$(sign_submit_entry "$report" "$bundle_file")
    receipt=$(jq -n --arg id "$id" --arg fp "$fp" --arg d "$digest" --arg url "$REKOR_URL" --argjson e "$entry" '{spec_id:$id,fingerprint:$fp,report_sha256:$d,status:"submitted",rekor_url:$url,uuid:$e.uuid,log_index:$e.log_index,integrated_time:$e.integrated_time,log_id:$e.log_id,inclusion_proof:$e.inclusion_proof}')
    echo "[$id] submitted: uuid=$(jq -r '.uuid' <<<"$receipt") log_index=$(jq -r '.log_index // "null"' <<<"$receipt")"
  fi
  receipts=$(jq --argjson r "$receipt" '. + [$r]' <<<"$receipts")
done
jq -n --arg mode "$MODE" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg url "$REKOR_URL" --argjson receipts "$receipts" '{version:"1.0",mode:(if $mode=="submit" then "submitted" else $mode end),generated_at:$now,rekor_url:$url,receipts:$receipts}' > "$OUT"
echo "Wrote $OUT"
