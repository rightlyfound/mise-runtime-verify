# RuntimeSpec v1.0.1 Verification Matrix

**Comprehensive verification suite for RuntimeSpec v1.0.1 with supply chain security, compliance tracking, and attestation.**

## Quick Start

### Prerequisites

- **Bash 4.0+** with `set -euo pipefail` support
- **jq** (JSON query tool)
- **curl** with certificate validation
- **cosign** (for signature verification)
- **podman** (for OCI verification)

**Ubuntu/Debian Installation:**
```bash
sudo apt-get update && sudo apt-get install -y jq curl podman
curl -fsSL https://github.com/sigstore/cosign/releases/latest/download/cosign-linux-amd64 -o cosign
sudo install cosign /usr/local/bin/cosign
```

### Run Full Verification (5 minutes)

```bash
# Clone repository
git clone https://github.com/rightlyfound/mise-runtime-verify.git
cd mise-runtime-verify

# Set runtime version
export RUNTIME_VERSION=1.0.1

# Execute batch verification
./run-batch.sh

# Validate all reports
./verify-reports.sh
```

**Expected Output:**
```
[INFO] Batch complete: 6 passed, 0 failed
[INFO] All report predicates satisfied.
```

---

## Architecture

### Scripts Overview

| Script | Purpose | Exit Code |
|--------|---------|-----------|
| **run-batch.sh** | Batch executor with timeouts, retries, and cleanup | 0 = all pass, 1 = ≥1 fail |
| **run-probe.sh** | Single probe runner with env validation & checksums | 0 = success, 1 = runtime fail, 2 = config error |
| **verify-reports.sh** | Schema validator with regression detection | 0 = valid, 4 = invalid |

### Directory Structure

```
mise-runtime-verify/
├── run-batch.sh          # Orchestrator (hardened)
├── run-probe.sh          # Individual probe (with checksums)
├── verify-reports.sh     # Schema validator (with history)
├── specs/                # Probe specifications (JSON)
├── reports/              # Verification reports (generated)
├── .cache/               # Logs, downloads, history
├── .schemas/             # JSON schema definitions
├── docs/                 # Documentation & templates
├── genuine-oci/          # OCI-based verification (real probes)
└── README.md             # This file
```

---

## Hardening Improvements

### Error Handling & Reliability

✅ **Before:** Basic `set -e` with no timeouts or retries  
✅ **After:**
- `set -euo pipefail` enforces strict error checking
- Timeout mechanism (default 5 min per probe)
- Exponential backoff retry logic (max 3 attempts)
- Cleanup trap handlers (`trap 'cleanup' EXIT INT TERM`)
- Proper exit codes for debugging

### Network & Download Safety

✅ **Before:** `curl` without `--fail` or checksums  
✅ **After:**
- SHA256 checksum verification on all downloads
- Download cache with integrity validation
- Retry logic with exponential backoff
- Timeout enforcement (`--max-time 60s`)
- No insecure `http://` URLs (all `https://`)

### Environment Validation

✅ **Before:** Silent failures on missing env vars  
✅ **After:**
- Pre-flight environment checks
- Required tool validation (jq, curl, timeout, etc.)
- Spec-level environment variable requirements
- Informative error messages with remediation steps

### Report Validation

✅ **Before:** Partial key presence checks only  
✅ **After:**
- Full JSON schema validation
- Type checking (exit_code must be number, hermetic_ok must be boolean)
- Regression detection (compares against baseline)
- Historical archive for trend analysis

---

## GitHub Actions Hardening

### Verify Runtime Spec Workflow

**Location:** `.github/workflows/verify-runtime-spec.yml`

**Features:**
- ✅ ShellCheck linting on all pushes
- ✅ Tool caching (jq, cosign) to save 30-60s per run
- ✅ Reduced GITHUB_TOKEN scope (`contents: read` only)
- ✅ Artifact retention policies (reports: 30 days, logs: 7 days)
- ✅ Workflow dispatch for manual re-runs
- ✅ Job timeouts (15 min max)

**Run:**
```bash
# Manually trigger via GitHub UI
# Settings → Actions → Workflows → Verify RuntimeSpec Matrix → Run workflow
```

### Secure Attestation Workflow (Reference)

**Location:** `docs/ATTEST_WORKFLOW.yml` (template)

**Features:**
- ✅ Pre-flight validation (OCI image digest pinning)
- ✅ Cosign identity-based verification (no long-lived keys)
- ✅ Rekor submission with dry-run mode
- ✅ Ed25519 JWT attestation generation
- ✅ OIDC-based signing (GitHub Actions provider)
- ✅ Artifact retention (attestation: 90 days, logs: 30 days)

---

## Supply Chain Security

### OCI Image Verification

**Requirement:** All OCI images must use **digest pins**, not mutable tags.

```toml
# ✅ GOOD
[oci]
from = "ubuntu:24.04@sha256:abc123..."

# ❌ BAD (mutable tag)
[oci]
from = "ubuntu:24.04"
```

### Cosign Integration

**Identity-based verification (no secrets in workflow):**
```bash
# Verify image signature with GitHub OIDC provider
cosign verify \
  --certificate-identity "https://github.com/rightlyfound/mise-runtime-verify/.github/workflows/attest-and-submit.yml@refs/heads/main" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  ghcr.io/rightlyfound/runtime:sha256-abc123
```

### Rekor Transparency Log

**Features:**
- Immutable audit trail of all verifications
- Public searchable ledger (no authorization required)
- Artifact hashes and timestamps
- Integration with cosign for verification

**Submit (requires private key):**
```bash
cd genuine-oci
./submit-to-rekor.sh --submit
```

**Dry-run (safe, no submission):**
```bash
./submit-to-rekor.sh --dry-run
```

---

## Troubleshooting

### Common Errors

#### Error: `jq: command not found`
```bash
# Install jq
sudo apt-get install -y jq

# Verify
jq --version
```

#### Error: `Probe timeout after 300s`
```bash
# Increase timeout
export PROBE_TIMEOUT=600
./run-batch.sh
```

#### Error: `Missing required field 'exit_code' in report`
```bash
# Ensure run-probe.sh writes valid JSON
cd genuine-oci
./run-probe.sh P0

# Check report
cat reports/P0.json | jq .
```

#### Error: `OCI images must use digest pins`
```bash
# Pin OCI image in mise.toml
sed -i 's/ubuntu:24.04/ubuntu:24.04@sha256:abc123.../g' mise.toml
```

### Debugging

**Enable verbose logging:**
```bash
export VERBOSE=true
export RUNTIME_VERSION=1.0.1
./run-batch.sh
```

**View recent logs:**
```bash
tail -50 .cache/logs/batch.log
tail -50 .cache/logs/P0.log
```

**Inspect a single report:**
```bash
cat reports/P0.json | jq .
```

---

## Contributing

### Adding a New RuntimeSpec Version

1. **Create probe specification:**
   ```bash
   cat > specs/p_new.json <<'JSON'
   {
     "name": "P_NEW description",
     "runtime": "mise",
     "version": "X.Y.Z",
     "hermetic_seal": true,
     "required_env": ["RUNTIME_VERSION"]
   }
   JSON
   ```

2. **Run batch verification:**
   ```bash
   export RUNTIME_VERSION=X.Y.Z
   ./run-batch.sh
   ```

3. **Validate report:**
   ```bash
   ./verify-reports.sh
   ```

4. **Commit and push:**
   ```bash
   git add specs/ reports/
   git commit -m "add: RuntimeSpec X.Y.Z verification"
   git push origin main
   ```

### Adding a New Probe

1. **Extend run-probe.sh** with new probe logic
2. **Add test in test/ folder** (if available)
3. **Update schema** in `.schemas/report-schema.json`
4. **Run linting:**
   ```bash
   shellcheck -x run-probe.sh
   ```

---

## Configuration

### Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `RUNTIME_VERSION` | (required) | Target RuntimeSpec version |
| `PROBE_TIMEOUT` | 300 | Max seconds per probe |
| `PARALLEL_PROBES` | false | Run probes in parallel (experimental) |
| `VERBOSE` | false | Enable debug logging |
| `SPEC_DIR` | ./specs | Probe specification directory |
| `REPORT_DIR` | ./reports | Report output directory |
| `MAX_RETRIES` | 3 | Download retry attempts |
| `DOWNLOAD_TIMEOUT` | 60 | Download timeout (seconds) |

### Setting Environment Variables

```bash
# Inline (single run)
export RUNTIME_VERSION=1.0.1 PROBE_TIMEOUT=600
./run-batch.sh

# In .env file (source before running)
cat > .env <<'ENV'
RUNTIME_VERSION=1.0.1
PROBE_TIMEOUT=600
VERBOSE=true
ENV

source .env
./run-batch.sh
```

---

## Performance

### Optimization Tips

1. **Cache tool downloads:**
   ```bash
   # GitHub Actions automatically caches with actions/cache@v4
   # Local: downloads cached in .cache/downloads/
   ```

2. **Run probes in parallel:**
   ```bash
   export PARALLEL_PROBES=true
   ./run-batch.sh  # Reduces runtime from ~5min to ~2min
   ```

3. **Skip re-verification:**
   ```bash
   # Reports are cached; re-run validation without probes
   ./verify-reports.sh
   ```

### Benchmark

| Scenario | Time | Notes |
|----------|------|-------|
| Full batch (sequential) | ~5 min | 6 probes, 1 min each |
| Full batch (parallel) | ~2 min | With `PARALLEL_PROBES=true` |
| Report validation | ~10 sec | Schema + regression checks |
| GitHub Actions CI | ~3 min | With tool caching |

---

## Security Policy

### Secrets Management

- ✅ No secrets in git history (use GitHub Secrets)
- ✅ Cosign private key stored in secure vault (not in repo)
- ✅ OIDC provider (GitHub Actions) signs attestations
- ✅ Rekor public key distributed via transparency log

### Access Control

- ✅ Branch protection on `main` (require reviews)
- ✅ Minimal GitHub token permissions (contents:read)
- ✅ Artifact retention policies enforced
- ✅ Secrets rotated quarterly

### Compliance

- ✅ All probes logged with timestamps (RFC 3339)
- ✅ Reports include exit codes and output hashes
- ✅ Attestations include model & runtime fingerprints
- ✅ Transparency log (Rekor) for audit trails

---

## References

- **RuntimeSpec v1.0.1:** https://github.com/opencontainers/runtime-spec/releases/tag/v1.0.1
- **Cosign:** https://github.com/sigstore/cosign
- **Rekor:** https://github.com/sigstore/rekor
- **Sigstore:** https://www.sigstore.dev
- **SLSA Framework:** https://slsa.dev

---

## License

MIT License – See `LICENSE` file

## Support

For issues, questions, or contributions:
- 📋 **Issues:** https://github.com/rightlyfound/mise-runtime-verify/issues
- 💬 **Discussions:** https://github.com/rightlyfound/mise-runtime-verify/discussions
- 📧 **Email:** rightlyfound@users.noreply.github.com
