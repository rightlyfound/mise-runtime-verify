# Troubleshooting & FAQ

**Common issues, solutions, and frequently asked questions.**

## Installation Issues

### Q: `command not found: jq`
**A:** Install jq from your package manager
```bash
# Ubuntu/Debian
sudo apt-get install -y jq

# macOS
brew install jq

# Verify
jq --version
```

### Q: `command not found: cosign`
**A:** Download and install Cosign
```bash
curl -fsSL https://github.com/sigstore/cosign/releases/latest/download/cosign-linux-amd64 -o cosign
sudo install cosign /usr/local/bin/cosign
cosign version
```

### Q: `sudo: required to install tools`
**A:** Add your user to sudoers (if permitted) or ask admin
```bash
# Check if already authorized
sudo -n true && echo "sudo available"

# If not, ask admin to add: rightlyfound ALL=(ALL) NOPASSWD: /usr/bin/apt-get
```

---

## Execution Issues

### Q: `Probe timeout after 300s: P0`
**A:** Increase timeout and re-run
```bash
export PROBE_TIMEOUT=600  # 10 minutes
./run-batch.sh
```

### Q: `Exit code 124` (timeout)
**A:** Indicates probe was killed due to timeout
```bash
# Check log for details
tail .cache/logs/P0.log

# Increase timeout if system is slow
export PROBE_TIMEOUT=900  # 15 minutes
./run-batch.sh
```

### Q: `RUNTIME_VERSION environment variable not set`
**A:** Set required variable before running
```bash
export RUNTIME_VERSION=1.0.1
./run-batch.sh
```

### Q: `Probes directory not found: ./probes`
**A:** Run from repository root
```bash
cd mise-runtime-verify
pwd  # Should show /path/to/mise-runtime-verify
./run-batch.sh
```

---

## Report Validation Issues

### Q: `Missing required field 'exit_code' in report`
**A:** Probe script didn't generate valid JSON
```bash
# Check report
cat reports/P0.json | jq .

# If malformed, re-run probe
./run-probe.sh P0

# Verify output
cat reports/P0.json | jq '.exit_code'
```

### Q: `exit_code must be a number`
**A:** JSON schema validation failed (likely quoted string)
```bash
# ❌ Wrong
{"exit_code": "0"}

# ✅ Correct
{"exit_code": 0}

# Fix in run-probe.sh
jq -n --arg exit_code "0" '{exit_code: ($exit_code | tonumber)}'
```

### Q: `Regression detected: exit_code changed from 0 to 1`
**A:** Probe now failing (check environment/config)
```bash
# View baseline
cat .history/baseline-P0.json | jq .exit_code

# View current
cat reports/P0.json | jq .exit_code

# Debug probe
export VERBOSE=true
./run-probe.sh P0
```

### Q: `All report predicates satisfied` but CI still failed
**A:** Check individual assertion messages above summary
```bash
# Re-run with output
./verify-reports.sh 2>&1 | grep -E "PASS|FAIL"

# Or check JSON directly
cat reports/*.json | jq '.exit_code'
```

---

## Security Issues

### Q: `OCI images must use digest pins, not mutable tags`
**A:** Update mise.toml to use digest hash
```toml
# Current (bad)
from = "ubuntu:24.04"

# Fixed (good)
from = "ubuntu:24.04@sha256:abc123def456..."

# Find digest
docker pull ubuntu:24.04
docker inspect ubuntu:24.04 | jq '.[0].RepoDigests'
```

### Q: `No hardcoded secrets detected` but I see credentials
**A:** Secrets should be in GitHub Secrets, not in code
```bash
# ❌ Wrong: credentials in .env file
COSIGN_PASSWORD=mysecretpassword

# ✅ Correct: use GitHub Secrets
# Settings → Secrets and Variables → Actions → New repository secret
# Then reference in workflow: ${{ secrets.COSIGN_PASSWORD }}
```

### Q: `Potential hardcoded secrets detected`
**A:** Found reference to secret variable name (not the value)
```bash
# This is OK (reference, not value)
export COSIGN_PASSWORD="${{ secrets.COSIGN_PASSWORD }}"

# This is NOT OK (actual secret in code)
export COSIGN_PASSWORD="abc123xyz789"
```

### Q: Cannot submit to Rekor without signing material
**A:** Pre-flight check: do you have private key?
```bash
# Check for Rekor signing material
[[ -f ~/.cosign/cosign.key ]] && echo "Key found" || echo "Key not found"

# Generate key (if needed)
cosign generate-key-pair

# Use dry-run until ready
./submit-to-rekor.sh --dry-run
```

---

## Performance Issues

### Q: Batch takes 10 minutes for 6 probes
**A:** Enable parallel execution (experimental)
```bash
export PARALLEL_PROBES=true
./run-batch.sh  # Should take ~2 min instead of ~5 min
```

### Q: GitHub Actions job timeout after 60 minutes
**A:** Workflow has 60-minute timeout limit
```yaml
jobs:
  attest:
    timeout-minutes: 120  # Increase if needed (max 360)
```

### Q: Download speed is slow
**A:** Check network and retry logic
```bash
# View download attempts
tail .cache/logs/batch.log | grep "Downloading"

# Increase retry backoff
export MAX_RETRIES=5
./run-batch.sh
```

---

## GitHub Actions Issues

### Q: Workflow not triggering on push
**A:** Check branch name and permissions
```yaml
on:
  push:
    branches: [main]  # Must match your default branch
    # If branch is "master", change to:
    # branches: [master]
```

### Q: Artifact upload fails: `Artifact name already exists`
**A:** Multiple jobs uploading with same name
```yaml
# Ensure unique names
- uses: actions/upload-artifact@v4
  with:
    name: runtime-spec-reports-${{ matrix.os }}  # Add unique suffix
```

### Q: Cannot find secrets in workflow
**A:** Secrets must be configured in repository settings
```bash
# Steps:
# 1. Go to Settings → Secrets and Variables → Actions
# 2. Click "New repository secret"
# 3. Name: REKOR_PUBLIC_KEY, Value: (paste key)
# 4. Reference in workflow: ${{ secrets.REKOR_PUBLIC_KEY }}
```

### Q: Workflow logs show `***` instead of actual value
**A:** GitHub automatically masks secrets in logs (good!)
```bash
# This is expected behavior
echo "${{ secrets.COSIGN_PASSWORD }}"
# Output: echo ***
```

---

## OCI/Podman Issues

### Q: `podman: command not found`
**A:** Install container runtime
```bash
# Ubuntu/Debian
sudo apt-get install -y podman

# Verify
podman --version
```

### Q: `Cannot pull image: permission denied`
**A:** May need authentication or cgroup permission
```bash
# For rootless podman
podman pull ubuntu:24.04

# If fails, try with sudo
sudo podman pull ubuntu:24.04

# Or use docker instead
docker pull ubuntu:24.04
```

### Q: `Error running OCI probe: exit code 1`
**A:** Check pod logs
```bash
# View last pod logs
podman logs <pod-id>

# Or re-run with verbose
export VERBOSE=true
cd genuine-oci && ./run-batch.sh
```

---

## Cosign/Rekor Issues

### Q: `cosign: certificate verification failed`
**A:** Check OIDC issuer and identity
```bash
# Verify certificate chain
cosign verify-blob \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  --certificate-identity-regexp "https://github.com/rightlyfound/.*" \
  attestation.jwt
```

### Q: `Rekor entry not found`
**A:** Check if Rekor is accessible and entry exists
```bash
# Test Rekor connectivity
curl -s https://rekor.sigstore.dev/api/v1/log/info | jq .

# Search for entry
curl "https://rekor.sigstore.dev/api/v1/log/entries?q=<cert-hash>"
```

### Q: `Submit to Rekor timed out`
**A:** Network issue or Rekor slow
```bash
# Check Rekor status
open https://status.rekor.dev

# Increase timeout
export REKOR_TIMEOUT=60  # seconds
./submit-to-rekor.sh --dry-run
```

---

## Git & Version Control Issues

### Q: `fatal: not a git repository`
**A:** Run from repository root
```bash
cd mise-runtime-verify
git status  # Should work
```

### Q: `fatal: Permission denied (publickey)`
**A:** SSH key not configured
```bash
# Generate SSH key (if none exists)
ssh-keygen -t ed25519

# Add public key to GitHub
# Settings → SSH and GPG keys → New SSH key

# Test connection
ssh -T git@github.com
```

### Q: `Your branch is behind by X commits`
**A:** Fetch latest changes
```bash
git fetch origin
git pull origin main

# Or reset to remote state
git reset --hard origin/main
```

---

## Verification Failed Issues

### Q: Exit code 0 but "Verification Failed"
**A:** Individual check failed (see message above summary)
```bash
# Re-run and capture full output
./verify-reports.sh 2>&1 | tee verify.log

# Look for "FAIL" entries
grep "FAIL" verify.log
```

### Q: One probe failed; want to continue?
**A:** Run only specific probe
```bash
# Run single probe
./run-probe.sh P0

# Check result
cat reports/P0.json | jq .exit_code

# Then verify all
./verify-reports.sh
```

---

## Getting Help

### Check Documentation
- README.md – Quick start and features
- docs/CONTRIBUTING.md – Adding new probes
- docs/SECURITY.md – Security hardening
- docs/TROUBLESHOOTING.md – This file

### Enable Verbose Logging
```bash
export VERBOSE=true
export RUNTIME_VERSION=1.0.1
./run-batch.sh 2>&1 | tee debug.log
```

### Collect Debug Info
```bash
# Gather system info
uname -a > debug.txt
jq --version >> debug.txt
curl --version >> debug.txt
env | grep RUNTIME >> debug.txt
```

### Report an Issue
- **GitHub Issues:** https://github.com/rightlyfound/mise-runtime-verify/issues
- **Include:** Error message, reproduction steps, debug logs
- **Title:** Clear description of problem

---

## Still Stuck?

1. **Search existing issues:** https://github.com/rightlyfound/mise-runtime-verify/issues
2. **Check GitHub Discussions:** https://github.com/rightlyfound/mise-runtime-verify/discussions
3. **Email support:** rightlyfound@users.noreply.github.com

We're here to help! 🙏
