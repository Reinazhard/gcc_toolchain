# SPDX-License-Identifier: GPL-3.0
#
# Stage 10: Host Linking Validation
# Ensures host tools link against glibc, not musl.
# This prevents leftover musl binaries from previous build attempts.

validate_host_linking() {
  header "STAGE 10: HOST LINKING VALIDATION"

  local host_bins=()
  for bin in "${PREFIX}/bin/${TARGET}-"*; do
    [[ -f "${bin}" ]] && host_bins+=("${bin}")
  done

  if (( ${#host_bins[@]} == 0 )); then
    die "No host binaries found in ${PREFIX}/bin/"
  fi

  log "Checking ${#host_bins[@]} host binaries for musl linkage..."

  local failed=0
  for bin_path in "${host_bins[@]}"; do
    local bin_name
    bin_name=$(basename "${bin_path}")

    # Statically linked binaries have no dynamic section — that's fine
    local dyn
    dyn=$(readelf -d "${bin_path}" 2>/dev/null | grep NEEDED || true)
    if [[ -z "${dyn}" ]]; then
      ok "  ${bin_name}: statically linked"
      continue
    fi

    # Check for musl
    if echo "${dyn}" | grep -q "libc.musl"; then
      warn "  ${bin_name}: LINKS AGAINST MUSL"
      failed=1
    fi

    # Check for glibc
    if echo "${dyn}" | grep -q "libc.so.6\|ld-linux"; then
      ok "  ${bin_name}: glibc-linked"
    fi
  done

  if (( failed )); then
    die "Host tools linked against musl. Rebuild binutils/GDB on a glibc host."
  fi

  ok "Host linking validation successful — all tools use glibc."
}
register_stage "validate_host_linking" "Validate host tools link against glibc"
