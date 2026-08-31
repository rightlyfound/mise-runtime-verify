#!/usr/bin/env bash
set -euo pipefail

SPEC_DIR="${SPEC_DIR:-./specs}"
REPORT_DIR="${REPORT_DIR:-./reports}"
id="${1:-p0}"

mkdir -p "$SPEC_DIR"
mkdir -p "$REPORT_DIR"

spec_file="$SPEC_DIR/$id.json"
if [[ ! -f "$spec_file" ]]; then
  echo "spec file not found: $spec_file" >&2
  exit 2
fi

tmp="$(mktemp -t probe.XXXXXX.json)"
trap 'rm -f "$tmp"' EXIT

name="$(jq -r '.name // "unknown"' "$spec_file")"
runtime="$(jq -r '.runtime // "unknown"' "$spec_file")"
version="$(jq -r '.version // empty' "$spec_file" || true)"
timestamp="$(date --utc +%Y-%m-%dT%H:%M:%SZ || date -u +%Y-%m-%dT%H:%M:%SZ)"
hermetic="$(jq -r '.hermetic_seal // "true"' "$spec_file")"
seal_ok=true
if [[ "$hermetic" == "false" || "$hermetic" == "0" ]]; then
  seal_ok=false
fi

jq -n \
  --arg id "$id" \
  --arg name "$name" \
  --arg runtime "$runtime" \
  --arg version "$version" \
  --arg timestamp "$timestamp" \
  --argjson hermetic_ok "$seal_ok" \
  '{
    id: $id,
    name: $name,
    runtime: $runtime,
    version: $version,
    timestamp: $timestamp,
    hermetic_ok: $hermetic_ok,
    probe: {
      summary: ("Probe executed for " + $id),
      checks: { "file_exists": true }
    }
  }' > "$tmp"

mv "$tmp" "$REPORT_DIR/$id.json"
trap - EXIT

echo "Wrote report: $REPORT_DIR/$id.json"
exit 0
