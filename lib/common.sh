# SPDX-License-Identifier: GPL-3.0
#
# Common helpers and logging routines.
# Sourced by build.sh and target scripts.

# Timestamped trace output for debugging (visible with `set -x` / bash -x)
PS4='+$(date +%H:%M:%S) ${BASH_SOURCE[0]}:${LINENO}: '

# Declare DRY_RUN so sourcing order does not matter
DRY_RUN=${DRY_RUN:-false}
LOG_FILE=""

# ── Colour helpers ────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log()    { echo -e "${CYAN}${BOLD}[INFO]${RESET}  $*"; }
ok()     { echo -e "${GREEN}${BOLD}[DONE]${RESET}  $*"; }
warn()   { echo -e "${YELLOW}${BOLD}[WARN]${RESET}  $*"; }
die()    { echo -e "${RED}${BOLD}[FAIL]${RESET}  $*" >&2; exit 1; }

# ── Elapsed-time tracker ──────────────────────────────────────────
START_TIME=$(date +%s)
elapsed() {
  local s=$(( $(date +%s) - START_TIME ))
  printf "%02d:%02d:%02d" $(( s/3600 )) $(( s%3600/60 )) $(( s%60 ))
}

header() {
  local title="$1"
  local bar; bar=$(printf '═%.0s' $(seq 1 ${#title}))
  echo
  echo -e "${YELLOW}${BOLD}╔══${bar}══╗"
  echo -e "║  ${title}  ║"
  echo -e "╚══${bar}══╝${RESET}"
  echo
}

safe_cd() {
  if [ ! -d "$1" ]; then
    if $DRY_RUN; then
      log "[DRY-RUN] cd $1"
      return 0
    else
      die "Directory $1 does not exist."
    fi
  fi
  cd "$1"
}

run_log() {
  local stage_name="$1"
  shift
  local log_dir="${WORK_DIR}/logs/${LOG_STAGE:?LOG_STAGE not set}"
  mkdir -p "${log_dir}"
  LOG_FILE="${log_dir}/${stage_name}.log"
  
  if $DRY_RUN; then
    log "[DRY-RUN] $*"
    return 0
  fi

  log "Running stage: ${stage_name} (log: logs/${LOG_STAGE}/${stage_name}.log)..."
  "$@" > "${LOG_FILE}" 2>&1
}

# Collect all *.log files from a build directory into the stage log dir.
# Usage: collect_logs <build_dir>
collect_logs() {
  local build_dir="$1"
  local log_dir="${WORK_DIR}/logs/${LOG_STAGE}"
  mkdir -p "${log_dir}"

  if $DRY_RUN; then
    log "[DRY-RUN] collect_logs ${build_dir}"
    return 0
  fi

  if [[ -d "${build_dir}" ]]; then
    find "${build_dir}" -maxdepth 1 -name '*.log' -exec mv -f {} "${log_dir}/" \;
  fi
}

cleanup() {
  local exit_code=$?
  if [ $exit_code -ne 0 ]; then
    # Collect logs from the current build directory on failure
    if [ -n "${LOG_STAGE:-}" ] && [ -n "${BUILD_DIR:-}" ]; then
      local build_dir
      for d in "${BUILD_DIR}"/build-*/; do
        [ -d "$d" ] && collect_logs "$d"
      done
    fi
    if [ -n "${LOG_FILE:-}" ] && [ -f "${LOG_FILE:-}" ]; then
      echo -e "\n${RED}${BOLD}!!! Build failed. Last 20 lines of ${LOG_FILE}:${RESET}"
      tail -n 20 "${LOG_FILE}"
    fi
  fi
  exit $exit_code
}
trap cleanup EXIT ERR INT TERM
