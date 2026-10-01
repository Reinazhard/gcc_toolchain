# SPDX-License-Identifier: GPL-3.0
#
# Stage: Download & Extract sources

verify_checksum() {
  local file="sources/$1"
  local expected_sha256="$2"

  if [[ -z "${expected_sha256:-}" ]]; then
    warn "No SHA256 defined for $1. Skipping verification."
    return 0
  fi

  if [[ "${SKIP_CHECKSUM:-false}" == "true" ]]; then
    log "Skipping checksum verification for $1 (SKIP_CHECKSUM=true)"
    return 0
  fi

  log "Verifying checksum for $1..."
  echo "${expected_sha256}  ${file}" | sha256sum --check --status || \
    die "Checksum verification failed for ${file}!"
  ok "Checksum for $1 matches."
}

fetch() {
  local url="$1"
  local file="${url##*/}"
  local expected_sha256="${2:-}"

  if [[ -f "sources/${file}" ]]; then
    if [[ -n "${expected_sha256}" ]] && ! echo "${expected_sha256}  sources/${file}" | sha256sum --check --status 2>/dev/null; then
      warn "Existing sources/${file} failed checksum verification! Deleting and redownloading..."
      rm -f "sources/${file}"
    else
      ok "Cached sources/${file} (verified)"
      return 0
    fi
  fi

  log "Downloading ${file}..."
  if ! $DRY_RUN; then
    # -f: fail on HTTP >= 400 so a 403/404 moves us to the next mirror instead
    #     of silently saving an error page. --retry-all-errors covers 5xx/522
    #     and transient TLS/DNS failures. --speed-time/--speed-limit abort a
    #     mirror that connects but never delivers bytes (dead peers), which is
    #     what makes fallback reach a working mirror quickly.
    local curl_flags=(-fL --retry 5 --retry-delay 5 --retry-all-errors
                      --connect-timeout 30 --max-time 900
                      --speed-time 60 --speed-limit 1024)
    local -a urls
    _gen_mirrors "${url}" urls

    local success=false
    local try_url
    for try_url in "${urls[@]}"; do
      if curl "${curl_flags[@]}" -o "sources/${file}.tmp" "${try_url}"; then
        success=true
        break
      fi
      warn "Download failed from ${try_url}, trying next mirror..."
    done
    $success || die "All mirrors failed for ${file}"

    mv "sources/${file}.tmp" "sources/${file}"
    verify_checksum "${file}" "${expected_sha256}"
  else
    local -a dry_urls
    _gen_mirrors "${url}" dry_urls
    log "[DRY-RUN] curl -fL ... -o sources/${file}.tmp <firstworking-of: ${dry_urls[*]}> && mv sources/${file}.tmp sources/${file}"
  fi
}

# _gen_mirrors <primary-url> <out-array-name>
#
# Builds an ordered, de-duplicated list of URL candidates for a source tarball.
# Only mirrors that were verified by hand to answer HTTP 200/206 for the pinned
# versions are listed. The list deliberately mixes hosts in different
# organisations/datacenters (GNU savannah, kernel.org/Fastly, academic and ISP
# mirrors spread across DE/FR/NL/JP/CN/US) so no single outage, rate-limit or
# region-wide block can fail the download. Deliberately excludes SourceForge.
_gen_mirrors() {
  local url="$1"
  local -n _out="$2"
  local path               # path below the mirror's document root
  local -a _candidates=()
  local u

  if [[ "${url}" == *ftp.gnu.org/gnu/* || "${url}" == *ftpmirror.gnu.org/* ]]; then
    path="${url#*ftp.gnu.org/gnu/}"
    [[ "${url}" == *ftpmirror.gnu.org/* ]] && path="${url#*ftpmirror.gnu.org/}"
    _candidates=(
      "https://ftpmirror.gnu.org/${path}"              # official round-robin of GNU mirrors
      "https://ftp.gnu.org/gnu/${path}"                # authoritative origin
      "https://mirror.ibcp.fr/pub/gnu/${path}"         # FR
      "https://ftp.fau.de/gnu/${path}"                 # DE (RRZE)
      "https://ftp.jaist.ac.jp/pub/GNU/${path}"        # JP
      "https://mirrors.ustc.edu.cn/gnu/${path}"        # CN
      "https://mirrors.dotsrc.org/gnu/${path}"         # DK
      "https://mirrors.ocf.berkeley.edu/gnu/${path}"   # US
    )
  elif [[ "${url}" == *gcc.gnu.org/pub/gcc/infrastructure/* ]]; then
    path="${url#*gcc.gnu.org/pub/gcc/infrastructure/}"
    _candidates=(
      "https://gcc.gnu.org/pub/gcc/infrastructure/${path}"          # authoritative
      "https://sourceware.org/pub/gcc/infrastructure/${path}"       # official binutils/GCC home
      "https://www.mirrorservice.org/sites/sourceware.org/pub/gcc/infrastructure/${path}" # UK mirror of sourceware
    )
  elif [[ "${url}" == *kernel.org/pub/scm/* ]]; then
    # Git snapshots (git.kernel.org/pub/scm/...) are generated on the fly and are
    # served ONLY from git.kernel.org. cdn./mirrors.edge./mirrors.kernel.org 301-
    # or 404- the /pub/scm/ path (cdn redirects to git.kernel.org, mirrors.kernel.org
    # returns 404), so they must not be listed as mirrors here.
    _candidates=(
      "https://git.kernel.org/${url#*kernel.org/}"     # authoritative (identity)
    )
  elif [[ "${url}" == *kernel.org/pub/* ]]; then
    path="${url#*kernel.org/pub/}"
    _candidates=(
      "https://cdn.kernel.org/pub/${path}"             # Fastly CDN (kernel.org origin)
      "https://mirrors.edge.kernel.org/pub/${path}"    # geo-routed kernel.org mirror pool
      "https://mirrors.kernel.org/pub/${path}"         # kernel.org US
    )
  else
    _candidates=("${url}")
  fi

  # Primary URL first, then the mirror set; drop duplicates preserving order.
  _out=()
  local -A _seen=()
  for u in "${url}" "${_candidates[@]}"; do
    [[ -n "${u}" ]] || continue
    [[ -n "${_seen[${u}]:-}" ]] && continue
    _seen["${u}"]=1
    _out+=("${u}")
  done
}

download_resources() {
  header "DOWNLOADING & CLONING SOURCES"
  mkdir -p sources

  # Git Sources
  if [[ ! -d "gcc-src" ]]; then
    log "Cloning GCC from ${GCC_BRANCH}..."
    if $DRY_RUN; then
      log "[DRY-RUN] git clone --branch=${GCC_BRANCH} ..."
    elif [[ -n "${GCC_COMMIT}" ]]; then
      log "Pinning GCC to commit: ${GCC_COMMIT}"
      git clone --shallow-since="${SHALLOW_SINCE}" --branch="${GCC_BRANCH}" --single-branch --no-tags https://gnu.googlesource.com/gcc gcc-src
      git -C gcc-src checkout "${GCC_COMMIT}"
    else
      git clone --depth=1 --branch="${GCC_BRANCH}" --single-branch --no-tags https://gnu.googlesource.com/gcc gcc-src
    fi
  fi

  if [[ ! -d "binutils-src" ]]; then
    log "Cloning Binutils from ${BINUTILS_BRANCH}..."
    if $DRY_RUN; then
      log "[DRY-RUN] git clone --branch=${BINUTILS_BRANCH} ..."
    elif [[ -n "${BINUTILS_COMMIT}" ]]; then
      log "Pinning Binutils to commit: ${BINUTILS_COMMIT}"
      git clone --shallow-since="${SHALLOW_SINCE}" --branch="${BINUTILS_BRANCH}" --single-branch --no-tags https://gnu.googlesource.com/binutils-gdb binutils-src
      git -C binutils-src checkout "${BINUTILS_COMMIT}"
    else
      git clone --depth=1 --branch="${BINUTILS_BRANCH}" --single-branch --no-tags https://gnu.googlesource.com/binutils-gdb binutils-src
    fi
  fi

  local fetch_pids=()
  fetch "https://ftp.gnu.org/gnu/glibc/glibc-${GLIBC_VER}.tar.xz" "${GLIBC_SHA256:-}" & fetch_pids+=($!)
  fetch "https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/snapshot/linux-${LINUX_VER}.tar.gz" "${LINUX_SHA256:-}" & fetch_pids+=($!)
  fetch "https://ftp.gnu.org/gnu/gmp/gmp-${GMP_VER}.tar.xz" "${GMP_SHA256:-}" & fetch_pids+=($!)
  fetch "https://ftp.gnu.org/gnu/mpfr/mpfr-${MPFR_VER}.tar.xz" "${MPFR_SHA256:-}" & fetch_pids+=($!)
  fetch "https://ftp.gnu.org/gnu/mpc/mpc-${MPC_VER}.tar.xz" "${MPC_SHA256:-}" & fetch_pids+=($!)
  # ISL ships .bz2 (not .xz) and is hosted on gcc.gnu.org/sourceware, never SourceForge.
  fetch "https://gcc.gnu.org/pub/gcc/infrastructure/isl-${ISL_VER}.tar.bz2" "${ISL_SHA256:-}" & fetch_pids+=($!)
  
  for pid in "${fetch_pids[@]}"; do
    wait "$pid" || die "A background download failed!"
  done

  header "EXTRACTING SOURCES"

  local extract_pids=()
  for pkg in \
    "glibc-${GLIBC_VER}" \
    "linux-${LINUX_VER}" \
    "gmp-${GMP_VER}" \
    "mpfr-${MPFR_VER}" \
    "mpc-${MPC_VER}" \
    "isl-${ISL_VER}"
  do
    if [[ ! -d "${pkg}" ]]; then
      log "Extracting ${pkg}..."
      if $DRY_RUN; then
        log "[DRY-RUN] tar xf sources/${pkg}.tar.*"
      else
        tar xf "sources/${pkg}.tar."* & extract_pids+=($!)
      fi
    fi
  done
  
  for pid in "${extract_pids[@]}"; do
    wait "$pid" || die "A background extraction failed!"
  done

  # Integrate prerequisites as in-tree symlinks for both GCC and Binutils.
  if ! $DRY_RUN; then
    log "Linking prerequisites in-tree..."
    for dep_dir in "gmp-${GMP_VER}" "mpfr-${MPFR_VER}" "mpc-${MPC_VER}" "isl-${ISL_VER}"; do
      local dep_name="${dep_dir%%-*}"
      ln -sfn "../${dep_dir}" "gcc-src/${dep_name}"
      ln -sfn "../${dep_dir}" "binutils-src/${dep_name}"
    done
  fi
  ok "All sources ready  [$(elapsed)]"
}
register_stage "download_resources" "Download and extract all sources"
