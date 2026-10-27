#!/usr/bin/env bash
# scripts/common.sh

set -euo pipefail

# Guard: refuse to run this file directly, it only makes sense sourced.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "✗ common.sh is a library — source it from another script, don't run it directly." >&2
    exit 1
fi

# logging helpers
log()  { echo "→ $*"; }
warn() { echo "⚠ $*" >&2; }
die()  { echo "✗ $*" >&2; exit 1; }

# device JSON field reader — prints the value, or nothing when the field is absent
read_field() {
    local field="$1"
    local value

    : "${DEVICE:?read_field: DEVICE is not set}"
    : "${DEVICE_JSON:?read_field: DEVICE_JSON is not set}"

    if [[ ! -f "$DEVICE_JSON" ]]; then
        die "read_field: device config not found at $DEVICE_JSON"
    fi

    if ! value=$(jq -r --arg d "$DEVICE" --arg f "$field" \
        '.[$d][$f] // empty' "$DEVICE_JSON" 2>/dev/null); then
        die "read_field: invalid JSON in $DEVICE_JSON"
    fi

    if ! jq -e --arg d "$DEVICE" '.[$d]' "$DEVICE_JSON" >/dev/null 2>&1; then
        die "read_field: device '$DEVICE' not found in $DEVICE_JSON"
    fi

    printf '%s\n' "$value"
}

# config fragment writer
fragment_add() {
    local fragment_file="$1"
    local directive="$2"
    mkdir -p "$(dirname "$fragment_file")"
    echo "$directive" >> "$fragment_file"
}

# resilient fetch
retry_fetch() {
    local url="$1"
    local out="$2"
    local attempts="${3:-3}"
    local n=1

    while (( n <= attempts )); do
        if curl -fsSL --connect-timeout 15 "$url" -o "$out"; then
            return 0
        fi
        warn "fetch failed (attempt $n/$attempts): $url"
        n=$((n + 1))
        if (( n <= attempts )); then
            sleep 5
        fi
    done

    die "failed to fetch after $attempts attempts: $url"
}

# kernel version preflight check
verify_kernel_version() {
    local expected="$1"
    local actual

    if [[ ! -f "Makefile" ]]; then
        die "verify_kernel_version: no Makefile in $(pwd) — run this from the kernel source root"
    fi

    actual=$(head -n 5 Makefile | grep -E '^(VERSION|PATCHLEVEL) =' | awk '{print $3}' | paste -sd '.')

    if [[ -z "$actual" ]]; then
        die "verify_kernel_version: could not determine kernel version from Makefile"
    fi

    if [[ "$actual" != "$expected" ]]; then
        die "kernel_version mismatch — device JSON says '$expected', but the checked-out kernel's Makefile reports '$actual'. Fix devices/*.json before continuing."
    fi

    log "kernel_version verified: $actual"
}
