#!/usr/bin/env bash
set -euo pipefail

SPEC_DIR="./specs"
REPORT_DIR="./reports"
mkdir -p "$SPEC_DIR" "$REPORT_DIR"

canonical_fingerprint() {
    local spec_file="$1"
    sha256sum "$spec_file" | awk '{print $1}'
}

cat > "$SPEC_DIR/P0.toml" <<'TOML'
[tools]
python = { version = "3.14.0" }
rust   = { version = "1.85.0", profile = "minimal" }
node   = "24.15.0"

[oci.env]
PYTHON_GIL       = "0"
RUSTUP_TOOLCHAIN = "1.85.0-x86_64-unknown-linux-gnu"
NODE_OPTIONS     = ""

[env]
PYTHON_GIL       = "0"
RUSTUP_TOOLCHAIN = "1.85.0-x86_64-unknown-linux-gnu"
NODE_OPTIONS     = ""

[settings]
experimental = true

[oci]
from        = "ubuntu:24.04"
tag         = "ghcr.io/bridge/probe:ps-v1"
workdir     = "/workspace"
mount_point = "/mise"

[[oci.copy]]
host  = "/home/ubuntu/.rustup/toolchains/1.85.0-x86_64-unknown-linux-gnu"
image = "/root/.rustup/toolchains/1.85.0-x86_64-unknown-linux-gnu"

[[oci.copy]]
host  = "/home/ubuntu/.rustup/toolchains/1.83.0-x86_64-unknown-linux-gnu"
image = "/root/.rustup/toolchains/1.83.0-x86_64-unknown-linux-gnu"

[[oci.copy]]
host  = "/home/ubuntu/.local/share/mise-standard/installs/python/3.14.0"
image = "/root/.local/share/mise-standard/installs/python/3.14.0"
TOML

sed 's/python = { version = "3\.14\.0" }/python = { version = "3.14.0" }/' \
    "$SPEC_DIR/P0.toml" > "$SPEC_DIR/P1.toml"

awk '
    /^\[oci\.env\]/ { in_oci=1; print; next }
    in_oci && /^\[/ { in_oci=0 }
    in_oci && /^PYTHON_GIL[[:space:]]*=/ { print "PYTHON_GIL       = \"1\""; next }
    { print }
' "$SPEC_DIR/P0.toml" > "$SPEC_DIR/P2.toml"

cp "$SPEC_DIR/P0.toml" "$SPEC_DIR/P3.toml"
sed 's/rust   = { version = "1\.85\.0", profile = "minimal" }/rust   = { version = "1.83.0", profile = "minimal" }/' \
    "$SPEC_DIR/P0.toml" > "$SPEC_DIR/P4.toml"
sed 's/node   = "24\.15\.0"/node   = "20.0.0"/' \
    "$SPEC_DIR/P0.toml" > "$SPEC_DIR/P5.toml"

for id in P0 P1 P2 P3 P4 P5; do
    echo ">>> Running $id..."
    spec="$SPEC_DIR/$id.toml"
    report="$REPORT_DIR/$id.json"
    fp=$(canonical_fingerprint "$spec")

    export MISE_EXPERIMENTAL=1
    export MISE_PYTHON_COMPILE=0
    if [[ "$id" == "P3" ]]; then
        export MISE_PYTHON_PRECOMPILED_FLAVOR="standard"
    else
        export MISE_PYTHON_PRECOMPILED_FLAVOR="freethreaded+pgo-full"
    fi

    cp "$spec" ./mise.toml
    mise install 2>/dev/null || true
    mise oci build -o ./img 2>/dev/null || true

    set +e
    load_output=$(podman load -i ./img 2>/dev/null)
    image=$(printf '%s\n' "$load_output" | sed -n 's/^Loaded image: //p' | tail -1)
    if [[ -z "$image" ]]; then
        image=$(podman images --format '{{.ID}}' | head -1)
    fi

    stdout_file=$(mktemp)
    stderr_file=$(mktemp)
    runtime_path="/mise/installs/python/3.14.0/bin:/root/.rustup/toolchains/1.85.0-x86_64-unknown-linux-gnu/bin:/mise/installs/node/24.15.0/bin"
    python_lib="/mise/installs/python/3.14.0/lib"
    if [[ "$id" == "P1" || "$id" == "P3" ]]; then
        runtime_path="/root/.local/share/mise-standard/installs/python/3.14.0/bin:/root/.rustup/toolchains/1.85.0-x86_64-unknown-linux-gnu/bin:/mise/installs/node/24.15.0/bin"
        python_lib="/root/.local/share/mise-standard/installs/python/3.14.0/lib"
    elif [[ "$id" == "P4" ]]; then
        runtime_path="/mise/installs/python/3.14.0/bin:/root/.rustup/toolchains/1.83.0-x86_64-unknown-linux-gnu/bin:/mise/installs/node/24.15.0/bin"
    elif [[ "$id" == "P5" ]]; then
        runtime_path="/mise/installs/python/3.14.0/bin:/root/.rustup/toolchains/1.85.0-x86_64-unknown-linux-gnu/bin:/mise/installs/node/20.0.0/bin"
    fi
    runtime_env="export PATH=$runtime_path:\$PATH; export LD_LIBRARY_PATH=$python_lib;"
    if [[ "$id" == "P2" ]]; then
        runtime_env+=" export PYTHON_GIL=1;"
    elif [[ "$id" == "P1" || "$id" == "P3" ]]; then
        runtime_env+=" unset PYTHON_GIL;"
    fi
    podman run --rm --cgroups=disabled --network=none --security-opt label=disable \
        --volume "$PWD:/workspace:Z" --workdir /workspace "$image" \
        sh -lc "$runtime_env exec /workspace/run-probe.sh" \
        >"$stdout_file" 2>"$stderr_file"
    exit_code=$?
    set -e

    stdout_sha=$(sha256sum "$stdout_file" | awk '{print $1}')
    stderr_sha=$(sha256sum "$stderr_file" | awk '{print $1}')
    stdout_preview=$(head -c 200 "$stdout_file" | jq -R -s '.')
    stderr_preview=$(head -c 200 "$stderr_file" | jq -R -s '.')

    cat > "$report" <<REPORT
{
  "spec_id": "$id",
  "exit_code": $exit_code,
  "stdout_sha256": "$stdout_sha",
  "stderr_sha256": "$stderr_sha",
  "fingerprint": "$fp",
  "stdout_preview": $stdout_preview,
  "stderr_preview": $stderr_preview
}
REPORT

    rm -f "$stdout_file" "$stderr_file"
    echo "    Report: $report"
done

echo
echo ">>> Batch complete. Reports in $REPORT_DIR/"
