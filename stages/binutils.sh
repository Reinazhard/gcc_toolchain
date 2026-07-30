# SPDX-License-Identifier: GPL-3.0
#
# Stage 3: Build Binutils

build_binutils() {
  require_build_context
  header "STAGE 3: BINUTILS"
  LOG_STAGE="binutils"
  safe_cd "${BUILD_DIR}"
  mkdir -p build-binutils && safe_cd build-binutils

  run_log "binutils-configure" "${WORK_DIR}/binutils-src/configure" \
      --target="${TARGET}" \
      --prefix="${PREFIX}" \
      --with-sysroot="${SYSROOT}" \
      --build="${BUILD_TRIPLE}" \
      --host="${BUILD_TRIPLE}" \
      --enable-static \
      --disable-shared \
      --enable-plugins \
      --enable-relro \
      --enable-threads \
      --enable-lto \
      --with-zstd \
      --with-system-zlib \
      --enable-deterministic-archives \
      --disable-nls \
      --disable-werror \
      --disable-gprofng \
      --disable-source-highlight \
      --disable-docs \
      CFLAGS="${HOST_CFLAGS}" \
      CXXFLAGS="${HOST_CXXFLAGS}" \
      LDFLAGS="-static-libstdc++ -static-libgcc ${HOST_LDFLAGS}"

  local binutils_ver; binutils_ver=$(cat "${WORK_DIR}/binutils-src/bfd/version/config.bfd" 2>/dev/null | grep -oP 'version=\K.*' || echo "unknown")
  record_build_flags "binutils" \
    "version=${binutils_ver}" \
    "target=${TARGET}" \
    "static=true" \
    "shared=false" \
    "lto=true" \
    "zstd=true"

  run_log "binutils-make" make
  run_log "binutils-install" make install

  safe_cd "${WORK_DIR}"
  collect_logs "${BUILD_DIR}/build-binutils"
  ok "Binutils done  [$(elapsed)]"
}
register_stage "build_binutils" "Build binutils"
