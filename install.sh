#!/usr/bin/env bash
# Oracle AI Database Free installer for macOS and Linux.
set -euo pipefail

IMAGE="${ORADB_IMAGE:-container-registry.oracle.com/database/free:latest}"
SQLCL_ZIP_URL="${SQLCL_ZIP_URL:-https://download.oracle.com/otn_software/java/sqldeveloper/sqlcl-latest.zip}"
READY_TIMEOUT="${ORADB_INSTALLER_READY_TIMEOUT:-900}"
ENGINE=""
OS=""
CONTAINER_NAME="oracle-free"
HOST_PORT="1521"
VOLUME_NAME="oracle-free-data"
CHARACTERSET="AL32UTF8"
ENABLE_ARCHIVELOG="false"
ENABLE_FORCE_LOGGING="false"
ORACLE_PWD=""

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
info() { printf '%s\n' "$*"; }

detect_os() {
  case "$(uname -s)" in
    Darwin) OS="macos" ;;
    Linux) OS="linux" ;;
    MINGW*|MSYS*|CYGWIN*)
      die "Use the Windows installer from PowerShell: irm https://raw.githubusercontent.com/klazarz/oradbinstaller/main/install.ps1 | iex"
      ;;
    *) die "Unsupported operating system: $(uname -s)." ;;
  esac
  info "Detected operating system: $(uname -s) $(uname -r)"
}

choose_engine() {
  if command -v podman >/dev/null 2>&1; then
    ENGINE="podman"
  elif command -v docker >/dev/null 2>&1; then
    ENGINE="docker"
  else
    if [[ "$OS" == "macos" ]]; then
      die "Neither Podman nor Docker is installed. Install Podman Desktop with: brew install --cask podman-desktop\nThen run: podman machine init && podman machine start"
    fi
    die "Neither Podman nor Docker is installed. Install Podman for your Linux distribution, start its service or machine, then run this installer again."
  fi

  "$ENGINE" info >/dev/null 2>&1 || die "$ENGINE is installed but is not ready. Start $ENGINE and run this installer again."
  info "Using container runtime: $ENGINE"
}

prompt_default() {
  local label="$1" default="$2" answer
  read -r -p "$label [$default]: " answer
  printf '%s' "${answer:-$default}"
}

prompt_yes_no() {
  local label="$1" default="$2" value
  while true; do
    value="$(prompt_default "$label (yes/no)" "$default")"
    case "${value,,}" in yes|y) printf 'true'; return ;; no|n) printf 'false'; return ;; esac
    info "Please answer yes or no."
  done
}

valid_identifier() { [[ "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]]; }
valid_port() { [[ "$1" =~ ^[0-9]+$ ]] && (( 1 <= 10#$1 && 10#$1 <= 65535 )); }
valid_password() {
  [[ ${#1} -ge 8 && "$1" =~ [[:upper:]] && "$1" =~ [[:lower:]] && "$1" =~ [[:digit:]] && "$1" != *[[:space:]]* ]]
}

prompt_password() {
  local first second
  while true; do
    read -r -s -p "Database password (8+ characters, upper/lowercase and digit): " first; printf '\n'
    read -r -s -p "Confirm database password: " second; printf '\n'
    [[ "$first" == "$second" ]] || { info "Passwords do not match."; continue; }
    valid_password "$first" || { info "Password must have 8+ characters, uppercase, lowercase, and a digit; spaces are not allowed."; continue; }
    ORACLE_PWD="$first"; return
  done
}

prompt_advanced() {
  local value
  while true; do value="$(prompt_default 'Container name' "$CONTAINER_NAME")"; valid_identifier "$value" && { CONTAINER_NAME="$value"; break; }; info 'Use letters, digits, dots, underscores, or hyphens.'; done
  while true; do value="$(prompt_default 'Host listener port' "$HOST_PORT")"; valid_port "$value" && { HOST_PORT="$value"; break; }; info 'Enter a port from 1 through 65535.'; done
  while true; do value="$(prompt_default 'Persistent volume name' "$VOLUME_NAME")"; valid_identifier "$value" && { VOLUME_NAME="$value"; break; }; info 'Use letters, digits, dots, underscores, or hyphens.'; done
  CHARACTERSET="$(prompt_default 'Database character set' "$CHARACTERSET")"
  [[ -n "$CHARACTERSET" ]] || die 'Character set cannot be empty.'
  ENABLE_ARCHIVELOG="$(prompt_yes_no 'Enable archive logging' 'no')"
  ENABLE_FORCE_LOGGING="$(prompt_yes_no 'Enable force logging' 'no')"
}

configure() {
  local mode
  while true; do
    mode="$(prompt_default 'Installation mode: quick or advanced' 'quick')"
    case "${mode,,}" in quick|q) break ;; advanced|a) prompt_advanced; break ;; *) info 'Enter quick or advanced.' ;; esac
  done
  prompt_password
}

check_existing_container() {
  if "$ENGINE" container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
    die "A container named '$CONTAINER_NAME' already exists. It was not changed. Choose another name in advanced mode or remove it yourself."
  fi
}

pull_image() {
  info "Pulling $IMAGE ..."
  "$ENGINE" pull "$IMAGE" || die "Could not pull $IMAGE. If Oracle Container Registry requests authentication or license acceptance, complete it with '$ENGINE login container-registry.oracle.com' and retry."
}

start_database() {
  "$ENGINE" volume inspect "$VOLUME_NAME" >/dev/null 2>&1 || "$ENGINE" volume create "$VOLUME_NAME" >/dev/null
  info "Starting $CONTAINER_NAME ..."
  "$ENGINE" run -d --name "$CONTAINER_NAME" \
    -p "${HOST_PORT}:1521" \
    -e "ORACLE_PWD=$ORACLE_PWD" \
    -e "ORACLE_CHARACTERSET=$CHARACTERSET" \
    -e "ENABLE_ARCHIVELOG=$ENABLE_ARCHIVELOG" \
    -e "ENABLE_FORCE_LOGGING=$ENABLE_FORCE_LOGGING" \
    -v "${VOLUME_NAME}:/opt/oracle/oradata" \
    "$IMAGE" >/dev/null || die "Container startup failed. Inspect logs with: $ENGINE logs $CONTAINER_NAME"
}

wait_for_database() {
  local elapsed=0
  info "Waiting for Oracle AI Database Free to become ready (up to ${READY_TIMEOUT}s) ..."
  while (( elapsed < READY_TIMEOUT )); do
    "$ENGINE" logs "$CONTAINER_NAME" 2>&1 | grep -q 'DATABASE IS READY TO USE!' && return
    "$ENGINE" container inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null | grep -qx true || {
      "$ENGINE" logs "$CONTAINER_NAME" >&2 || true
      die "Container stopped before the database became ready."
    }
    sleep 5
    ((elapsed += 5))
  done
  "$ENGINE" logs "$CONTAINER_NAME" >&2 || true
  die "Timed out waiting for the database. Check logs with: $ENGINE logs $CONTAINER_NAME"
}

java_17_available() {
  local version major
  command -v java >/dev/null 2>&1 || return 1
  version="$(java -version 2>&1 | head -n 1)"
  if [[ "$version" =~ \"([0-9]+)(\.[0-9]+)? ]]; then
    major="${BASH_REMATCH[1]}"
    [[ "$major" != 1 ]] && (( major >= 17 ))
  else
    return 1
  fi
}

add_sqlcl_to_path() {
  local bin_dir="$1" profile
  export PATH="$bin_dir:$PATH"
  if [[ "$OS" == macos && "${SHELL:-}" == */zsh ]]; then profile="$HOME/.zshrc"; else profile="$HOME/.bashrc"; fi
  if [[ ! -f "$profile" ]] || ! grep -Fq "$bin_dir" "$profile"; then
    printf '\n# Oracle SQLcl installed by oradbinstaller\nexport PATH="%s:$PATH"\n' "$bin_dir" >> "$profile"
    info "Added SQLcl to PATH in $profile. Open a new terminal after this installation."
  fi
}

install_sqlcl_zip() {
  local target="${SQLCL_INSTALL_DIR:-$HOME/.local/share/sqlcl}" temp
  command -v curl >/dev/null 2>&1 || { info 'curl is required to install SQLcl.'; return 1; }
  command -v unzip >/dev/null 2>&1 || { info 'unzip is required to install SQLcl.'; return 1; }
  temp="$(mktemp -d)"; trap 'rm -rf "$temp"' RETURN
  info 'Downloading SQLcl from Oracle ...'
  curl -fL "$SQLCL_ZIP_URL" -o "$temp/sqlcl.zip" || { info 'SQLcl download failed.'; return 1; }
  unzip -q "$temp/sqlcl.zip" -d "$temp" || { info 'SQLcl archive extraction failed.'; return 1; }
  [[ -x "$temp/sqlcl/bin/sql" ]] || { info 'The downloaded SQLcl archive has an unexpected layout.'; return 1; }
  mkdir -p "$target"
  cp -R "$temp/sqlcl/." "$target/"
  add_sqlcl_to_path "$target/bin"
}

ensure_sqlcl() {
  if command -v sql >/dev/null 2>&1; then
    info "SQLcl found: $(command -v sql)"
  else
    local install
    install="$(prompt_yes_no 'SQLcl is not installed. Install it natively now' 'yes')"
    [[ "$install" == true ]] || { info 'SQLcl installation skipped.'; return 0; }
    if [[ "$OS" == macos ]] && command -v brew >/dev/null 2>&1; then
      brew install sqlcl || { info 'Homebrew could not install SQLcl.'; return 0; }
    else
      install_sqlcl_zip || return 0
    fi
  fi
  if ! java_17_available; then
    info 'SQLcl is available, but Java 17 or later was not found. Install a supported JDK, open a new terminal, then run the connection command below.'
    return
  fi
}

show_sqlcl_connection() {
  info ''
  info 'SQLcl connection command (it will securely prompt for the password):'
  info "  sql sys@//localhost:${HOST_PORT}/FREEPDB1 as sysdba"
}

main() {
  detect_os
  choose_engine
  configure
  check_existing_container
  pull_image
  start_database
  wait_for_database
  ensure_sqlcl
  show_sqlcl_connection
  info "Container '$CONTAINER_NAME' is running. Manage it with: $ENGINE logs -f $CONTAINER_NAME"
}

if [[ "${ORADB_INSTALLER_TEST:-}" != 1 ]]; then
  main "$@"
fi
