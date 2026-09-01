# Genuine OCI RuntimeSpec verification

This directory contains the real OCI-based RuntimeSpec probe implementation and the reports from the verified Ubuntu 24.04 x86_64 run. It is distinct from the simulation scripts at repository root.

The batch uses `mise oci build` to create the OCI image and Podman to execute the probe with direct toolchain paths. The sandbox-compatible configuration uses networkless Podman execution, an Ubuntu 24.04 base, copied Rust toolchains, and separate standard/free-threaded Python runtimes.

Run:

```bash
chmod +x run-batch.sh run-probe.sh verify-reports.sh
./run-batch.sh
./verify-reports.sh
```

The final verification returned exit code 0 with all predicates passed.
