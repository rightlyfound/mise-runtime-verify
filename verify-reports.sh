#!/bin/bash
# verify-reports.sh – Report validator with schema checking and diff capability
# Validates generated reports against expected schemas and tracks regressions.

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT_DIR="${REPORT_DIR:-${SCRIPT_DIR}/reports}"
SCHEMA_DIR="${SCRIPT_DIR}/.schemas"
HISTORY_DIR="${SCRIPT_DIR}/.history"
VERBOSE=${VERBOSE:-false}

# Logging
log() {
    local level=$1
    shift
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $*" >&2
}

# Validate tools
validate_tools() {
    local required_tools=(jq diff)
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log "ERROR" "Required tool not found: $tool"
            exit 1
        fi
    done
}

# Validate JSON schema
validate_json_schema() {
    local report_file=$1
    local probe_id=$(basename "$report_file" .json)
    
    if [[ ! -f "$report_file" ]]; then
        log "ERROR" "Report file not found: $report_file"
        return 1
    fi
    
    # Check if JSON is valid
    if ! jq empty "$report_file" 2>/dev/null; then
        log "ERROR" "Invalid JSON in report: $report_file"
        return 1
    fi
    
    # Validate required fields
    local required_fields=(id name runtime version timestamp hermetic_ok exit_code)
    for field in "${required_fields[@]}"; do
        if ! jq -e ".$field" "$report_file" > /dev/null 2>&1; then
            log "ERROR" "Missing required field '$field' in $probe_id"
            return 1
        fi
    done
    
    # Validate field types
    if ! jq -e '.exit_code | type == "number"' "$report_file" > /dev/null 2>&1; then
        log "ERROR" "exit_code must be a number in $probe_id"
        return 1
    fi
    
    if ! jq -e '.hermetic_ok | type == "boolean"' "$report_file" > /dev/null 2>&1; then
        log "ERROR" "hermetic_ok must be a boolean in $probe_id"
        return 1
    fi
    
    return 0
}

# Compare reports and detect regressions
check_regression() {
    local probe_id=$1
    local current_report="$REPORT_DIR/$probe_id.json"
    local baseline_report="$HISTORY_DIR/baseline-$probe_id.json"
    
    if [[ ! -f "$baseline_report" ]]; then
        log "INFO" "No baseline found for $probe_id (first run)"
        return 0
    fi
    
    local current_exit=$(jq -r '.exit_code' "$current_report")
    local baseline_exit=$(jq -r '.exit_code' "$baseline_report")
    
    if [[ "$current_exit" != "$baseline_exit" ]]; then
        log "WARN" "Regression detected in $probe_id: exit_code changed from $baseline_exit to $current_exit"
        return 1
    fi
    
    return 0
}

# Main validation
main() {
    validate_tools
    
    if [[ ! -d "$REPORT_DIR" ]]; then
        log "ERROR" "Reports directory not found: $REPORT_DIR"
        exit 2
    fi
    
    mkdir -p "$HISTORY_DIR"
    
    local failed=0
    local passed=0
    local regressions=0
    
    log "INFO" "Validating reports in $REPORT_DIR"
    
    # Find all report files
    local reports
    reports=$(find "$REPORT_DIR" -maxdepth 1 -name "*.json" -type f | sort)
    
    if [[ -z "$reports" ]]; then
        log "ERROR" "No report files found in $REPORT_DIR"
        exit 3
    fi
    
    while IFS= read -r report_file; do
        local probe_id=$(basename "$report_file" .json)
        
        log "INFO" "Validating report: $probe_id"
        
        # Validate schema
        if ! validate_json_schema "$report_file"; then
            ((failed++))
            continue
        fi
        
        # Check for regressions
        if ! check_regression "$probe_id"; then
            ((regressions++))
        fi
        
        ((passed++))
    done <<< "$reports"
    
    # Summary
    log "INFO" "Validation complete: $passed passed, $failed failed, $regressions regression(s)"
    
    if [[ $failed -gt 0 ]]; then
        log "ERROR" "Validation failed"
        exit 4
    fi
    
    if [[ $regressions -gt 0 ]]; then
        log "WARN" "Regressions detected; review above"
    fi
    
    # Archive current reports as baseline
    mkdir -p "$HISTORY_DIR"
    for report_file in $reports; do
        local probe_id=$(basename "$report_file" .json)
        cp "$report_file" "$HISTORY_DIR/baseline-$probe_id.json"
    done
    
    log "INFO" "Reports validated and archived"
    exit 0
}

main "$@"
