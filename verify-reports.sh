#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="./reports"
expected=(p0 p1 p2 p3 p4 p5)

if [[ ! -d "$REPORT_DIR" ]]; then
  echo "No reports directory found at $REPORT_DIR" >&2
  exit 2
fi

missing=()
wrong=()

for id in "${expected[@]}"; do
  report="$REPORT_DIR/$id.json"
  if [[ ! -f "$report" ]]; then
    missing+=("$id")
    continue
  fi

  name="$(jq -r '.name // empty' "$report")" || name=""
  hermetic_ok="$(jq -r '.hermetic_ok // empty' "$report")" || hermetic_ok=""

  if [[ -z "$name" || -z "$hermetic_ok" ]]; then
    wrong+=("$id")
    continue
  fi

  if [[ "$id" == "p2" ]]; then
    if [[ "$hermetic_ok" != "false" && "$hermetic_ok" != "0" ]]; then
      wrong+=("$id (expected hermetic_ok=false; got $hermetic_ok)")
    fi
  fi
done

if (( ${#missing[@]} )); then
  echo "Missing reports: ${missing[*]}" >&2
  exit 3
fi

if (( ${#wrong[@]} )); then
  echo "Reports with unexpected contents:"
  for w in "${wrong[@]}"; do echo " - $w"; done
  exit 4
fi

echo "All report predicates satisfied."
exit 0
