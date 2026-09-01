#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="./reports"
FAILED=0

assert_eq() {
    local field="$1" expected="$2" actual="$3" id="$4"
    if [[ "$expected" != "$actual" ]]; then
        echo "FAIL [$id]: $field expected '$expected', got '$actual'" >&2
        FAILED=1
    else
        echo "PASS [$id]: $field = '$expected'"
    fi
}

assert_ne() {
    local field="$1" unexpected="$2" actual="$3" id="$4"
    if [[ "$unexpected" == "$actual" ]]; then
        echo "FAIL [$id]: $field expected != '$unexpected', got '$actual'" >&2
        FAILED=1
    else
        echo "PASS [$id]: $field != '$unexpected'"
    fi
}

P0=$(cat "$REPORT_DIR/P0.json")
assert_eq "exit_code" "0" "$(echo "$P0" | jq -r '.exit_code')" "P0"
if ! echo "$P0" | jq -r '.stdout_preview' | grep -q "ALL-PROBES-OK"; then
    echo "FAIL [P0]: stdout missing ALL-PROBES-OK" >&2; FAILED=1
else
    echo "PASS [P0]: stdout contains ALL-PROBES-OK"
fi

P1=$(cat "$REPORT_DIR/P1.json")
assert_ne "exit_code" "0" "$(echo "$P1" | jq -r '.exit_code')" "P1"
if ! echo "$P1" | jq -r '.stdout_preview + .stderr_preview' | grep -qiE "GIL_ENABLED"; then
    echo "FAIL [P1]: output missing GIL_ENABLED" >&2; FAILED=1
else
    echo "PASS [P1]: output contains GIL_ENABLED"
fi

P2=$(cat "$REPORT_DIR/P2.json")
assert_ne "exit_code" "0" "$(echo "$P2" | jq -r '.exit_code')" "P2"
if ! echo "$P2" | jq -r '.stdout_preview + .stderr_preview' | grep -qiE "GIL_ENABLED_RUNTIME"; then
    echo "FAIL [P2]: output missing GIL_ENABLED_RUNTIME" >&2; FAILED=1
else
    echo "PASS [P2]: output contains GIL_ENABLED_RUNTIME"
fi

P3=$(cat "$REPORT_DIR/P3.json")
assert_ne "exit_code" "0" "$(echo "$P3" | jq -r '.exit_code')" "P3"
if ! echo "$P3" | jq -r '.stdout_preview + .stderr_preview' | grep -qiE "GIL_ENABLED|error|flavor"; then
    echo "FAIL [P3]: stderr missing expected gate error" >&2; FAILED=1
else
    echo "PASS [P3]: stderr contains gate error"
fi

P4=$(cat "$REPORT_DIR/P4.json")
assert_ne "exit_code" "0" "$(echo "$P4" | jq -r '.exit_code')" "P4"
if ! echo "$P4" | jq -r '.stdout_preview + .stderr_preview' | grep -qiE "edition 2024"; then
    echo "FAIL [P4]: stderr missing 'edition 2024' error" >&2; FAILED=1
else
    echo "PASS [P4]: stderr contains 'edition 2024'"
fi

P5=$(cat "$REPORT_DIR/P5.json")
assert_ne "exit_code" "0" "$(echo "$P5" | jq -r '.exit_code')" "P5"
if ! echo "$P5" | jq -r '.stderr_preview' | grep -qiE "ERR_REQUIRE_ESM"; then
    echo "FAIL [P5]: stderr missing ERR_REQUIRE_ESM" >&2; FAILED=1
else
    echo "PASS [P5]: stderr contains ERR_REQUIRE_ESM"
fi

echo
if [[ "$FAILED" -eq 0 ]]; then
    echo ">>> ALL PREDICATES PASSED. RuntimeSpec v1.0.1 is VERIFIED."
else
    echo ">>> VERIFICATION FAILED. Review flagged predicates above."
    exit 1
fi
