#!/bin/bash
# probe-template.sh – Template for new RuntimeSpec probes
# Copy and customize this template for each new probe

set -euo pipefail

# Configuration
PROBE_ID="${1:-p_template}"
TMPDIR="${TMPDIR:-/tmp}"
FAIL=0

# Logging
log() {
    local level=$1
    shift
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] [$PROBE_ID] $*" >&2
}

# Cleanup
cleanup() {
    rm -rf "$TMPDIR/$PROBE_ID"
}
trap cleanup EXIT

log "INFO" "Starting probe execution"

# ============================================================================
# SECTION 1: Environment Validation
# ============================================================================

log "INFO" "Validating environment"

# Check required environment variables
required_vars=(RUNTIME_VERSION)
for var in "${required_vars[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        log "ERROR" "Required environment variable not set: $var"
        exit 2
    fi
done

# Check required tools
required_tools=(jq curl)
for tool in "${required_tools[@]}"; do
    if ! command -v "$tool" &> /dev/null; then
        log "ERROR" "Required tool not found: $tool"
        exit 2
    fi
done

log "INFO" "Environment validated"

# ============================================================================
# SECTION 2: Probe Logic
# ============================================================================

# Create temporary directory
mkdir -p "$TMPDIR/$PROBE_ID"
cd "$TMPDIR/$PROBE_ID"

log "INFO" "Running probe checks"

# CUSTOM CHECK 1: Python runtime
log "INFO" "Checking Python runtime"
set +e
python3 - <<'PYTHON'
import sys
print(f"Python version: {sys.version}")
sys.exit(0 if sys.version_info >= (3, 13) else 1)
PYTHON
python_status=$?
set -e

if [[ $python_status -ne 0 ]]; then
    log "WARN" "Python check failed (status: $python_status)"
    FAIL=1
else
    log "INFO" "Python check passed"
fi

# CUSTOM CHECK 2: Rust compiler
log "INFO" "Checking Rust compiler"
set +e
rustc --version
rust_status=$?
set -e

if [[ $rust_status -ne 0 ]]; then
    log "WARN" "Rust check failed (status: $rust_status)"
    FAIL=1
else
    log "INFO" "Rust check passed"
fi

# CUSTOM CHECK 3: Node.js runtime
log "INFO" "Checking Node.js runtime"
set +e
node --version
node_status=$?
set -e

if [[ $node_status -ne 0 ]]; then
    log "WARN" "Node.js check failed (status: $node_status)"
    FAIL=1
else
    log "INFO" "Node.js check passed"
fi

# ============================================================================
# SECTION 3: Result Reporting
# ============================================================================

log "INFO" "Probe execution complete (exit code: $FAIL)"

if [[ $FAIL -eq 0 ]]; then
    echo "PROBE-OK: $PROBE_ID completed successfully"
    exit 0
else
    echo "PROBE-FAIL: $PROBE_ID completed with failures"
    exit 1
fi
