# Contributing to mise-runtime-verify

**Guidelines for adding new RuntimeSpec versions, probes, and improvements.**

## Getting Started

### Fork & Clone
```bash
git clone https://github.com/rightlyfound/mise-runtime-verify.git
cd mise-runtime-verify
git checkout -b feature/add-runtime-x.y.z
```

### Local Setup
```bash
# Install dependencies
sudo apt-get update && sudo apt-get install -y jq curl podman shellcheck

# Verify setup
chmod +x run-*.sh verify-reports.sh
./run-batch.sh  # Should succeed with existing specs
```

---

## Adding a New RuntimeSpec Version

### 1. Create Spec File

```bash
mkdir -p specs
cat > specs/p_new.json <<'JSON'
{
  "id": "p_new",
  "name": "P_NEW - RuntimeSpec X.Y.Z verification",
  "runtime": "mise",
  "version": "X.Y.Z",
  "hermetic_seal": true,
  "required_env": ["RUNTIME_VERSION"],
  "timeout": 300,
  "description": "Verifies RuntimeSpec X.Y.Z with tool versions..."
}
JSON
```

### 2. Define Probe Logic

Edit `run-probe.sh` to add version-specific checks:

```bash
# Add to genuine-oci/run-probe.sh
if [[ "$probe_id" == "P_NEW" ]]; then
    # Custom probe logic for X.Y.Z
    python3 -c "import sys; assert sys.version_info >= (3,13)" || FAIL=1
    rustc --version | grep -q "1.85" || FAIL=1
fi
```

### 3. Run & Validate

```bash
export RUNTIME_VERSION=X.Y.Z
./run-batch.sh
./verify-reports.sh

# Check generated report
cat reports/p_new.json | jq .
```

### 4. Lint & Test

```bash
# Lint shell scripts
shellcheck -x run-batch.sh run-probe.sh verify-reports.sh

# Run with verbose logging
export VERBOSE=true
./run-batch.sh
```

### 5. Commit & Push

```bash
git add specs/p_new.json reports/p_new.json
git commit -m "feat: add RuntimeSpec X.Y.Z verification"
git push origin feature/add-runtime-x.y.z
```

---

## Adding a New Probe

### 1. Extend Probe Logic

Create a new function in `run-probe.sh`:

```bash
probe_custom_check() {
    local probe_name=$1
    log "INFO" "Running custom check: $probe_name"
    
    # Your probe logic
    if some_check_passes; then
        echo "CUSTOM-PROBE-OK: $probe_name"
        return 0
    else
        echo "CUSTOM-PROBE-FAIL: $probe_name"
        return 1
    fi
}
```

### 2. Add to Batch Execution

Modify `run-batch.sh`:

```bash
run_probe() {
    local probe_file=$1
    local probe_name=$(basename "$probe_file" .sh)
    
    # ... existing logic ...
    
    # Add custom probe
    if [[ "$probe_name" == "custom" ]]; then
        probe_custom_check "$probe_name"
    fi
}
```

### 3. Update Schema

Add to `.schemas/report-schema.json`:

```json
{
  "type": "object",
  "properties": {
    "custom_check": {
      "type": "boolean",
      "description": "Custom probe validation result"
    }
  }
}
```

### 4. Test

```bash
export VERBOSE=true PARALLEL_PROBES=false
./run-batch.sh
./verify-reports.sh
```

---

## Code Standards

### Shell Script Style

✅ **Required:**
```bash
#!/bin/bash
set -euo pipefail  # Strict mode

# Use local variables
local var_name="value"

# Use functions with clear names
log() {
    local level=$1
    shift
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $*" >&2
}

# Use error handling
if ! command -v tool &> /dev/null; then
    log "ERROR" "tool not found"
    exit 1
fi
```

❌ **Avoid:**
```bash
#!/bin/bash
set -e  # Incomplete error handling

VAR_NAME="value"  # Global variables

echo "log"  # No timestamp or level

command -v tool  # No error checking
```

### Best Practices

1. **Trap cleanup handlers:**
   ```bash
   cleanup() {
       local exit_code=$?
       rm -f "$tmp_file"
       exit $exit_code
   }
   trap cleanup EXIT INT TERM
   ```

2. **Quote variables:**
   ```bash
   echo "$var"  # ✅ Good
   echo $var    # ❌ Bad (word splitting)
   ```

3. **Use subshells for side effects:**
   ```bash
   (
       cd "$temp_dir"
       do_something
   )  # Returns to original directory
   ```

4. **Validate inputs early:**
   ```bash
   if [[ -z "$PROBE_ID" ]]; then
       log "ERROR" "PROBE_ID not set"
       exit 1
   fi
   ```

---

## Testing

### Manual Testing

```bash
# Run single probe
PROBE_ID=p0 ./run-probe.sh

# Run batch with timeout
PROBE_TIMEOUT=60 ./run-batch.sh

# Validate reports
./verify-reports.sh

# Check logs
tail -20 .cache/logs/batch.log
```

### CI/CD Testing

```bash
# Lint before push
shellcheck -x run-*.sh verify-reports.sh

# Dry-run attestation
cd genuine-oci && ./submit-to-rekor.sh --dry-run
```

---

## Pull Request Checklist

Before submitting:

- [ ] Code follows style guide (shellcheck passes)
- [ ] New specs added to `specs/` directory
- [ ] Reports generated and validated
- [ ] README updated (if adding new features)
- [ ] Security hardening maintained (no `http://`, validated env vars)
- [ ] Commit messages descriptive (feat: ..., fix: ..., docs: ...)
- [ ] No secrets in commit history
- [ ] Artifact retention policies respected

### PR Template

```markdown
## Description
Brief description of changes

## Type of Change
- [ ] New RuntimeSpec version
- [ ] New probe
- [ ] Security hardening
- [ ] Documentation
- [ ] Bug fix

## Testing
Describe testing performed:
```bash
export RUNTIME_VERSION=X.Y.Z
./run-batch.sh && ./verify-reports.sh
# Output: [INFO] Batch complete: 6 passed, 0 failed
```

## Security Impact
- [ ] No secrets exposed
- [ ] Environment vars validated
- [ ] OCI images digest-pinned
- [ ] No new network calls without checksums

## Checklist
- [ ] Code lints (shellcheck)
- [ ] Reports validate
- [ ] Documentation updated
```

---

## Performance Optimization

### Tips for Faster Verification

1. **Use parallel execution (experimental):**
   ```bash
   export PARALLEL_PROBES=true
   ./run-batch.sh  # ~2 min vs ~5 min
   ```

2. **Cache downloads:**
   ```bash
   # Automatic caching in .cache/downloads/
   # Reuse previous downloads to save time
   ```

3. **Skip validation if reports unchanged:**
   ```bash
   # Reports from .history/ are reused
   ./verify-reports.sh  # Fast, checks only new files
   ```

4. **Increase timeout for slow systems:**
   ```bash
   export PROBE_TIMEOUT=600  # 10 min max
   ./run-batch.sh
   ```

---

## Troubleshooting

### ShellCheck Failures

**Error:** `SC2086: Double quote to prevent globbing`
```bash
# ❌ Bad
echo $var

# ✅ Good
echo "$var"
```

**Error:** `SC2181: Check exit code directly`
```bash
# ❌ Bad
cmd
if [[ $? -eq 0 ]]; then

# ✅ Good
if cmd; then
```

### Report Validation Failures

**Error:** `Missing required field 'exit_code'`
```bash
# Check probe output
cat reports/p0.json | jq .

# Ensure run-probe.sh includes exit_code
jq -n --arg exit_code "0" '{exit_code: ($exit_code | tonumber)}'
```

**Error:** `Regression detected: exit_code changed`
```bash
# Review baseline
cat .history/baseline-p0.json

# Compare with current
diff .history/baseline-p0.json reports/p0.json

# If intentional, update baseline
cp reports/p0.json .history/baseline-p0.json
```

---

## Documentation

### Adding to README

1. Update `Quick Start` section if adding new commands
2. Add new feature to `Hardening Improvements` table
3. Update troubleshooting with new error scenarios
4. Add configuration option to `Configuration` table

### Code Comments

```bash
# ✅ Good: explains WHY, not WHAT
# We use mktemp to avoid TOCTOU race condition
tmp="$(mktemp)"

# ❌ Bad: obvious what code does
# Create temporary file
tmp="$(mktemp)"
```

---

## Security Guidelines

### Secrets Management

- ❌ Never commit `.env` files or `.cosign-key`
- ❌ Never log COSIGN_PASSWORD or REKOR_SIGNATURE_BASE64
- ✅ Store secrets in GitHub Secrets, not in code
- ✅ Use OIDC provider for keyless signing

### URL Validation

```bash
# ❌ Insecure
curl http://example.com/file

# ✅ Secure
curl --proto '=https' https://example.com/file
```

### Checksum Verification

```bash
# ✅ Always verify downloads
expected_sha="abc123..."
actual_sha=$(sha256sum "$file" | awk '{print $1}')
[[ "$expected_sha" == "$actual_sha" ]] || exit 1
```

---

## Release Process

### Versioning

Use [Semantic Versioning](https://semver.org/):
- `v1.0.0` - Initial release
- `v1.1.0` - New features (backward compatible)
- `v1.0.1` - Bug fixes
- `v2.0.0` - Breaking changes

### Release Checklist

1. Update version in `README.md`
2. Create CHANGELOG entry
3. Tag commit: `git tag v1.0.1`
4. Push tag: `git push origin v1.0.1`
5. GitHub creates release with artifacts

---

## Questions?

- 📋 **Issues:** https://github.com/rightlyfound/mise-runtime-verify/issues
- 💬 **Discussions:** https://github.com/rightlyfound/mise-runtime-verify/discussions
- 📧 **Email:** rightlyfound@users.noreply.github.com

Thank you for contributing! 🎉
