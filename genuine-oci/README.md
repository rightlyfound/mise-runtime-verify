# Genuine OCI RuntimeSpec verification

This directory contains the real OCI-based RuntimeSpec probe implementation and the reports from the verified Ubuntu 24.04 x86_64 run. It is distinct from the simulation scripts at repository root.

The batch uses `mise oci build` to create the OCI image and Podman to execute the probe with direct toolchain paths. The sandbox-compatible configuration uses networkless Podman execution, an Ubuntu 24.04 base, copied Rust toolchains, and separate standard/free-threaded Python runtimes.

Run:

```bash
chmod +x run-batch.sh run-probe.sh verify-reports.sh submit-to-rekor.sh generate-attestation.sh pre-trade-check.sh
./run-batch.sh
./verify-reports.sh
```

The final verification returned exit code 0 with all predicates passed.

## Attestation components

`submit-to-rekor.sh` creates a six-report receipt bundle. It defaults to a dry run and requires `--submit` plus signing material before making a public Rekor write. The live path uses Rekor’s `hashedrekord` REST endpoint and records the returned UUID, log index, integrated time, and inclusion proof.

`generate-attestation.sh` creates an Ed25519-signed JWT containing the runtime fingerprint, caller-supplied model fingerprint, Rekor index, issuance and five-minute expiry times, specification version, and OCI environment identifier. Ed25519 is the current classical signature; ML-DSA under FIPS 204 is the documented post-quantum migration path, not a claim that this implementation is already post-quantum secure.

`pre-trade-check.sh` is a local fail-closed gate. It validates trade argument syntax, verifies the JWT signature and expiry, checks the canonical runtime fingerprint, and confirms that the JWT’s Rekor index is linked to the P0 receipt. It does not submit orders, call an exchange, or replace exchange-side authorization and risk controls.

The workflow runs genuine OCI verification on Ubuntu 24.04, fails on probe or attestation-generation errors, and uploads the receipts, JWT, public key, and reports. Public Rekor submission is an explicit workflow-dispatch choice rather than an automatic side effect of every push.

## Recordkeeping and compliance boundary

These artifacts provide an auditable chain from a versioned verification specification to captured probe output, hashes, a runtime fingerprint, a transparency-log receipt, and a short-lived signed attestation. That supports evidence collection, reproducibility, and tamper-evidence. It is not by itself a legal conclusion that any FINRA requirement is satisfied; a compliance officer must map the controls to the applicable rule, retention policy, supervision process, access controls, and organizational records program.

| Artifact | Evidence supplied | Operational limitation |
|---|---|---|
| RuntimeSpec reports | Probe exit codes, output hashes, previews, and spec fingerprints | A report is only as strong as the build and execution environment that produced it |
| Rekor receipt bundle | UUID, log index, integrated time, and inclusion-proof material when submitted | Live submission requires signing material and network access |
| JWT attestation | Short-lived binding of runtime and model fingerprints | Model fingerprint provenance must be supplied and governed by the caller |
| Pre-trade hook | Fail-closed local decision before dispatch | Must be integrated with the actual trading control plane to enforce execution |
| GitHub Actions workflow | Repeatable CI enforcement and retained artifacts | GitHub permissions, secrets, retention, and reviewer controls remain separate concerns |

## Safe usage

Run `./submit-to-rekor.sh` for a local dry run. Do not use `--submit` until the report contents, signing key, public key, and destination are reviewed. Never commit private keys or long-lived signing secrets. The workflow deliberately does not submit to Rekor on ordinary pushes.
