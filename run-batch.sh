#!/bin/bash
# run-batch.sh – Batch executor for RuntimeSpec probes
# Runs multiple probes in parallel/sequence with full error handling and cleanup.

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBES_DIR="${SCRIPT_DIR}/probes"
REPORTS_DIR="${SCRIPT_DIR}/reports"
LOG_DIR="${SCRIPT_DIR}/.cache/logs"
TIMEOUT_SECONDS=${PROBE_TIMEOUT:-300}  # 5 min per probe
PARALLEL=${PARALLEL_PROBES:-false}
VERBOSE=${VERBOSE:-false}

# Cleanup handler
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        echo "[ERROR] Batch execution failed with exit code $exit_code" >&2
    fi
    # Kill any lingering probe processes
    pkill -P $$ || true
    exit $exit_code
}

trap cleanup EXIT INT TERM

# Logging
log() {
    local level=$1
    shift
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a "${LOG_DIR}/batch.log"
}

# Validate environment
validate_env() {
    log "INFO" "Validating environment..."
    
    # Check required directories
    if [[ ! -d "$PROBES_DIR" ]]; then
        log "ERROR" "Probes directory not found: $PROBES_DIR"
        exit 1
    fi
    
    # Check required tools
    for tool in jq curl timeout; do
        if ! command -v $tool &> /dev/null; then
            log "ERROR" "Required tool not found: $tool"
            exit 1
        fi
    done
    
    # Ensure runtime version is set
    if [[ -z "${RUNTIME_VERSION:-}" ]]; then
        log "ERROR" "RUNTIME_VERSION environment variable not set"
        exit 1
    fi
    
    # Create output directories
    mkdir -p "$REPORTS_DIR" "$LOG_DIR"
    
    log "INFO" "Environment validated. RUNTIME_VERSION=$RUNTIME_VERSION"
}

# Retry logic with exponential backoff
retry_with_backoff() {
    local max_attempts=3
    local attempt=1
    local delay=2
    
    while [[ $attempt -le $max_attempts ]]; do
        if "$@"; then
            return 0
        fi
        
        if [[ $attempt -lt $max_attempts ]]; then
            log "WARN" "Attempt $attempt failed. Retrying in ${delay}s..."
            sleep $delay
            delay=$((delay * 2))
        fi
        
        ((attempt++))
    done
    
    log "ERROR" "Command failed after $max_attempts attempts: $*"
    return 1
}

# Run a single probe with timeout and retry
run_probe() {
    local probe_file=$1
    local probe_name=$(basename "$probe_file" .sh)
    local probe_log="${LOG_DIR}/${probe_name}.log"
    
    log "INFO" "Starting probe: $probe_name"
    
    # Run probe with timeout and capture output
    if timeout "$TIMEOUT_SECONDS" \
        retry_with_backoff bash "$probe_file" > "$probe_log" 2>&1; then
        
        log "INFO" "Probe succeeded: $probe_name"
        echo "$probe_name" >> "${REPORTS_DIR}/.passed"
        return 0
    else
        local exit_code=$?
        if [[ $exit_code -eq 124 ]]; then
            log "ERROR" "Probe timeout after ${TIMEOUT_SECONDS}s: $probe_name"
        else
            log "ERROR" "Probe failed with exit code $exit_code: $probe_name"
        fi
        echo "$probe_name" >> "${REPORTS_DIR}/.failed"
        return 1
    fi
}

# Main execution
main() {
    validate_env
    
    log "INFO" "Starting batch verification for RuntimeSpec $RUNTIME_VERSION"
    
    # Find all probe scripts
    local probes=()
    while IFS= read -r -d '' probe; do
        probes+=("$probe")
    done < <(find "$PROBES_DIR" -maxdepth 1 -name "*.sh" -type f -print0 | sort -z)
    
    if [[ ${#probes[@]} -eq 0 ]]; then
        log "WARN" "No probes found in $PROBES_DIR"
        return 0
    fi
    
    log "INFO" "Found ${#probes[@]} probes to execute"
    
    # Clear previous results
    rm -f "${REPORTS_DIR}/.passed" "${REPORTS_DIR}/.failed"
    
    # Execute probes
    if [[ "$PARALLEL" == "true" ]]; then
        log "INFO" "Running probes in parallel..."
        for probe in "${probes[@]}"; do
            run_probe "$probe" &
        done
        wait || {
            log "WARN" "Some parallel probes failed"
        }
    else
        log "INFO" "Running probes sequentially..."
        local failed=0
        for probe in "${probes[@]}"; do
            if ! run_probe "$probe"; then
                ((failed++))
            fi
        done
        
        if [[ $failed -gt 0 ]]; then
            log "ERROR" "$failed probe(s) failed"
            exit 1
        fi
    fi
    
    # Summary
    local passed=$(wc -l < "${REPORTS_DIR}/.passed" 2>/dev/null || echo 0)
    local failed=$(wc -l < "${REPORTS_DIR}/.failed" 2>/dev/null || echo 0)
    
    log "INFO" "Batch complete: $passed passed, $failed failed"
    
    if [[ $failed -gt 0 ]]; then
        exit 1
    fi
}

main "$@"
