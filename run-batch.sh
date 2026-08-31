#!/usr/bin/env bash
set -euo pipefail

SPEC_DIR="./specs"
REPORT_DIR="./reports"
PROBE="./run-probe.sh"

mkdir -p "$SPEC_DIR"
mkdir -p "$REPORT_DIR"

write_spec() {
  local id="$1"
  local content="$2"
  printf '%s\n' "$content" > "$SPEC_DIR/$id.json"
  echo "Wrote $SPEC_DIR/$id.json"
}

write_spec "p0" '{"name":"P0 baseline","runtime":"mise","version":"1.0.1","hermetic_seal":true}'
write_spec "p1" '{"name":"P1 small change","runtime":"mise","version":"1.0.1-rc1","hermetic_seal":true}'
write_spec "p2" '{"name":"P2 hermetic failure","runtime":"mise","version":"3.14.0t","hermetic_seal":false,"notes":"This spec should trigger hermetic-seal failure detection"}'
write_spec "p3" '{"name":"P3 alternation test","runtime":"mise","version":"1.0.2","features":["a","b","c"],"hermetic_seal":true}'
write_spec "p4" '{"name":"P4 metadata","runtime":"mise","version":"1.0.3","hermetic_seal":true}'
write_spec "p5" '{"name":"P5 heavy","runtime":"mise","version":"2.0.0","hermetic_seal":true}'

for id in p0 p1 p2 p3 p4 p5; do
  echo "Probing $id ..."
  if ! "$PROBE" "$id"; then
    echo "Probe failed for $id" >&2
  fi
done

echo "All probes completed. Reports are in $REPORT_DIR/"
