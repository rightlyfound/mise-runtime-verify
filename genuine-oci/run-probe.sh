#!/usr/bin/env bash
set -euo pipefail

FAIL=0
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Python: GIL must be disabled in free-threaded builds.
set +e
python - <<'PY'
import os
import sys

if not hasattr(sys, "_is_gil_enabled"):
    print("PYTHON-PROBE-FAIL: GIL_ENABLED (probe requires Python 3.13+)")
    raise SystemExit(1)

if sys._is_gil_enabled():
    marker = "GIL_ENABLED_RUNTIME" if os.environ.get("PYTHON_GIL") == "1" else "GIL_ENABLED"
    print(f"PYTHON-PROBE-FAIL: {marker}")
    raise SystemExit(1)

print("PYTHON-PROBE-OK: GIL disabled")
PY
python_status=$?
set -e
if [[ "$python_status" -ne 0 ]]; then
    FAIL=1
fi

# Rust: edition 2024 must compile on 1.85.0.
cat > "$TMPDIR/rust_probe.rs" <<'RUST'
fn main() { let _ = 42; }
RUST

if rustc --edition 2024 --emit=metadata "$TMPDIR/rust_probe.rs" -o "$TMPDIR/rust_probe.rmeta" 2>/dev/null; then
    echo "RUST-PROBE-OK: Edition 2024 compiles"
else
    echo "RUST-PROBE-FAIL: edition 2024 not supported"
    FAIL=1
fi

# Node: require(esm) must work on 24.x.
mkdir -p "$TMPDIR/node_probe"
cat > "$TMPDIR/node_probe/package.json" <<'JSON'
{ "name": "probe", "type": "module" }
JSON

cat > "$TMPDIR/node_probe/index.js" <<'JS'
export const answer = 42;
JS

cat > "$TMPDIR/node_probe/test.cjs" <<'CJS'
const m = require('./index.js');
if (m.answer === 42) {
    console.log("NODE-PROBE-OK: require(esm) works");
    process.exit(0);
}
console.log("NODE-PROBE-FAIL: require(esm) unexpected result");
process.exit(1);
CJS

if (cd "$TMPDIR/node_probe" && node test.cjs); then
    :
else
    echo "NODE-PROBE-FAIL: ERR_REQUIRE_ESM"
    FAIL=1
fi

if [[ "$FAIL" -eq 0 ]]; then
    echo "ALL-PROBES-OK"
    exit 0
fi
exit 1
