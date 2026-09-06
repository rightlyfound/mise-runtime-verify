# Security Hardening Guide

**Comprehensive security analysis and mitigation strategies for RuntimeSpec verification.**

## Executive Summary

This mise-runtime-verify project has been hardened against:
- ✅ Network-based attacks (checksum verification, HTTPS-only)
- ✅ Execution failures (timeouts, retry logic, cleanup)
- ✅ Configuration mistakes (environment validation, schema checks)
- ✅ Supply chain compromises (OCI digest pinning, Cosign attestation)
- ✅ Operational drift (regression detection, audit logging)

---

## Threat Model

### Attack Vector 1: Compromised Download Source

**Scenario:** Attacker intercepts tool download and injects malware

**Mitigation:**
- ✅ SHA256 checksum verification on all downloads
- ✅ Cache validation before reuse
- ✅ HTTPS-only (TLS 1.2+)
- ✅ Fail-closed on checksum mismatch

**Code:**
```bash
download_with_checksum() {
    local url=$1 expected_sha256=$2
    local actual_sha=$(sha256sum "$file" | awk '{print $1}')
    [[ "$expected_sha" == "$actual_sha" ]] || exit 1
}
```

### Attack Vector 2: OCI Image Tampering

**Scenario:** Attacker pushes malicious image with same tag

**Mitigation:**
- ✅ OCI image digest pinning (immutable content hash)
- ✅ Cosign signature verification
- ✅ Rekor transparency log validation
- ✅ Policy enforcement in workflow

**Config:**
```toml
# ✅ SECURE: Image tagged by digest
[oci]
from = "ubuntu:24.04@sha256:abc123def456..."

# ❌ INSECURE: Mutable tag (can be re-pushed)
[oci]
from = "ubuntu:24.04"
```

### Attack Vector 3: Silent Probe Failures

**Scenario:** Probe hangs indefinitely, CI never completes

**Mitigation:**
- ✅ Timeout enforcement (default 5 min/probe)
- ✅ Explicit error handling (`set -euo pipefail`)
- ✅ Kill lingering processes on exit
- ✅ Cleanup trap handlers

**Code:**
```bash
timeout "$TIMEOUT_SECONDS" retry_with_backoff bash "$probe_file"
trap 'pkill -P $$' EXIT
```

### Attack Vector 4: Missing Environment Variables

**Scenario:** Probe runs without RUNTIME_VERSION, reports meaningless result

**Mitigation:**
- ✅ Pre-flight environment validation
- ✅ Required variable checks
- ✅ Clear error messages
- ✅ Exit on missing dependencies

**Code:**
```bash
if [[ -z "${RUNTIME_VERSION:-}" ]]; then
    log "ERROR" "RUNTIME_VERSION environment variable not set"
    exit 1
fi
```

### Attack Vector 5: Report Forgery

**Scenario:** Attacker modifies report JSON to hide failures

**Mitigation:**
- ✅ JSON schema validation (type checking)
- ✅ Required field enforcement
- ✅ Regression detection (baseline comparison)
- ✅ Immutable archive (.history/ folder)

**Validation:**
```bash
validate_json_schema() {
    local report_file=$1
    jq -e '.exit_code | type == "number"' "$report_file" || exit 1
    jq -e '.hermetic_ok | type == "boolean"' "$report_file" || exit 1
}
```

---

## Supply Chain Security

### Cosign Integration

**Identity-based verification (no secrets in repo):**

```bash
# GitHub Actions OIDC provider automatically signs
cosign verify \
  --certificate-identity "https://github.com/rightlyfound/mise-runtime-verify/.github/workflows/attest-and-submit.yml@refs/heads/main" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  ghcr.io/rightlyfound/runtime:sha256-abc123
```

**Benefits:**
- ✅ No private keys in GitHub Secrets
- ✅ Keyless signing via OIDC
- ✅ Automatic key rotation
- ✅ Auditable through GitHub Actions logs

### Rekor Transparency Log

**Immutable audit trail:**

```bash
# Submit verification receipt to Rekor (public ledger)
./submit-to-rekor.sh --submit

# Anyone can verify inclusion
curl https://rekor.sigstore.dev/api/v1/log/entries?logID=<entry-uuid>
```

**Features:**
- ✅ Public searchable ledger
- ✅ Merkle tree inclusion proofs
- ✅ Timestamp certification
- ✅ Cryptographic verification

### SBOM & Attestation

**Ed25519 JWT attestation:**

```json
{
  "iss": "https://token.actions.githubusercontent.com",
  "sub": "repo:rightlyfound/mise-runtime-verify:ref:refs/heads/main",
  "aud": "mise-runtime-verify",
  "exp": 1234567890,
  "iat": 1234567800,
  "runtime_fingerprint": "sha256:abc123...",
  "model_fingerprint": "sha256:def456...",
  "rekor_log_index": 12345678
}
```

---

## GitHub Actions Security

### Minimal Token Scope

```yaml
permissions:
  contents: read        # Only read code, no write
  id-token: write       # Only for OIDC signing
```

**Why minimal:**
- ✅ Principle of least privilege
- ✅ Limits blast radius if token leaked
- ✅ Cannot modify repo settings or secrets
- ✅ Cannot create arbitrary releases

### Tool Caching with Integrity

```yaml
- uses: actions/cache@v4
  with:
    path: /usr/local/bin/jq
    key: tools-jq-${{ runner.os }}
    # Cache is immutable; prevents version drift
```

### Environment Pinning

```yaml
runs-on: ubuntu-22.04  # ✅ Pinned OS version
  # NOT: ubuntu-latest (changes weekly)

steps:
  - uses: actions/checkout@v4  # ✅ Pinned action version
```

### Artifact Retention

```yaml
- uses: actions/upload-artifact@v4
  with:
    retention-days: 90  # ✅ Limited retention
    # NOT: default (90 days is too long for sensitive data)
```

---

## Local Development Security

### Pre-Commit Checks

```bash
# Enable in .git/hooks/pre-commit
#!/bin/bash
set -euo pipefail

# Lint shell scripts
shellcheck -x run-*.sh verify-reports.sh

# Check for hardcoded secrets
grep -r "COSIGN_PASSWORD\|PRIVATE_KEY" . --include="*.sh" && exit 1

# Check for insecure URLs
grep -r "http://" . --include="*.toml" --include="*.sh" && exit 1

exit 0
```

### Environment File Security

```bash
# ✅ GOOD: Local .env with restrictive permissions
echo "COSIGN_PASSWORD=xxx" > .env.local
chmod 600 .env.local
git add .env.local.example  # Never commit actual secrets

# ❌ BAD: Storing secrets in git
git add .env  # Contains COSIGN_PASSWORD!
```

---

## Compliance & Audit

### Audit Trail

**All execution logged:**
```bash
[2024-09-06 15:51:41] [INFO] Starting batch verification for RuntimeSpec 1.0.1
[2024-09-06 15:51:42] [INFO] Starting probe: P0
[2024-09-06 15:51:45] [INFO] Probe succeeded: P0
[2024-09-06 15:52:10] [INFO] Batch complete: 6 passed, 0 failed
```

**Stored in:**
- `.cache/logs/batch.log` (local runs)
- GitHub Actions logs (CI runs)
- Rekor entries (attestation submissions)

### Reproducibility

**Every probe execution is reproducible:**

```json
{
  "id": "P0",
  "spec_fingerprint": "sha256:abc123def456...",
  "runtime_version": "1.0.1",
  "timestamp": "2024-09-06T15:51:41Z",
  "exit_code": 0
}
```

**To reproduce:**
```bash
export RUNTIME_VERSION=1.0.1
./run-probe.sh P0
# Will produce identical results if environment unchanged
```

---

## Incident Response

### If Probe Fails

1. **Immediate:**
   ```bash
   tail -50 .cache/logs/batch.log
   cat reports/P0.json | jq .
   ```

2. **Investigate:**
   ```bash
   # Check environment
   env | grep RUNTIME
   
   # Check tool versions
   jq --version && curl --version
   ```

3. **Remediate:**
   ```bash
   # Update tool
   sudo apt-get update && sudo apt-get install -y jq
   
   # Re-run probe
   export PROBE_TIMEOUT=600
   ./run-batch.sh
   ```

### If Report Validation Fails

1. **Schema violation:**
   ```bash
   # Ensure exit_code is number (not string)
   cat reports/P0.json | jq .exit_code
   ```

2. **Regression detected:**
   ```bash
   # Compare baseline vs current
   diff .history/baseline-P0.json reports/P0.json
   ```

3. **Intentional change:**
   ```bash
   # Accept new baseline
   cp reports/P0.json .history/baseline-P0.json
   ```

### If Attestation Fails

1. **Check signing material:**
   ```bash
   [[ -f attestation.jwt ]] || echo "JWT not generated"
   cosign verify-blob --key cosign.pub attestation.jwt
   ```

2. **Check Rekor submission:**
   ```bash
   ./submit-to-rekor.sh --dry-run
   # Review without submitting
   ```

3. **Contact support:**
   - Rekor status: https://status.rekor.dev
   - Cosign docs: https://github.com/sigstore/cosign

---

## Security Best Practices

### Do's ✅

- ✅ Use HTTPS for all downloads
- ✅ Verify checksums on every download
- ✅ Pin OCI images by digest
- ✅ Use environment variables for secrets (not files)
- ✅ Enable audit logging
- ✅ Rotate signing keys quarterly
- ✅ Review attestations before submission
- ✅ Monitor Rekor for unexpected entries

### Don'ts ❌

- ❌ Download from insecure `http://` URLs
- ❌ Use mutable image tags (`:latest`, `:v1`)
- ❌ Commit `.env` files with secrets
- ❌ Run probes without timeouts
- ❌ Skip schema validation
- ❌ Store long-lived signing keys in git
- ❌ Use `sudo` without necessity
- ❌ Ignore error messages and continue

---

## References

- **SLSA Framework:** https://slsa.dev/spec/v1.0/
- **Sigstore:** https://www.sigstore.dev
- **Cosign:** https://github.com/sigstore/cosign
- **Rekor:** https://github.com/sigstore/rekor
- **NIST Supply Chain Security:** https://csrc.nist.gov/projects/supply-chain-risk-management

---

## Questions?

For security concerns: rightlyfound@users.noreply.github.com  
For security vulnerabilities: Use GitHub Security Advisory (private)
