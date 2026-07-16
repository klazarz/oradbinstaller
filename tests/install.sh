#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORADB_INSTALLER_TEST=1 source "$ROOT/install.sh"

assert_true() { "$@" || { echo "FAILED: $*" >&2; exit 1; }; }
assert_false() { if "$@"; then echo "FAILED (expected false): $*" >&2; exit 1; fi; }
assert_eq() { [[ "$1" == "$2" ]] || { echo "FAILED: expected '$1', got '$2'" >&2; exit 1; }; }

assert_true valid_identifier oracle-free
assert_true valid_identifier data_1.0
assert_false valid_identifier 'bad name'
assert_true valid_port 1521
assert_true valid_port 65535
assert_false valid_port 0
assert_false valid_port 65536
assert_true valid_password 'Abcdefg1'
assert_false valid_password 'abcdefgh1'
assert_false valid_password 'ABCDEFGH1'
assert_false valid_password 'Abcdefgh'

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/podman" <<'MOCK'
#!/usr/bin/env bash
case "$1" in info) exit 0 ;; esac
MOCK
chmod +x "$tmp/podman"
old_path="$PATH"; PATH="$tmp:$PATH"; ENGINE=""; choose_engine; assert_eq podman "$ENGINE"; PATH="$old_path"

cat > "$tmp/podman" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$ORADB_MOCK_LOG"
case "$1 $2" in
  'info ') exit 0 ;;
  'container inspect')
    if [[ "${3:-}" == '-f' ]]; then printf 'true\n'; exit 0; fi
    exit 1
    ;;
  'volume inspect') exit 1 ;;
  'volume create'|'pull container-registry.oracle.com/database/free:latest'|'run -d') exit 0 ;;
  'logs oracle-free') printf 'DATABASE IS READY TO USE!\n'; exit 0 ;;
esac
exit 0
MOCK
chmod +x "$tmp/podman"
export ORADB_MOCK_LOG="$tmp/runtime.log"
printf 'quick\nAbcdefg1\nAbcdefg1\ny\n' | PATH="$tmp:$old_path" ORADB_INSTALLER_READY_TIMEOUT=1 bash "$ROOT/install.sh" > "$tmp/output"
assert_true grep -Fq 'pull container-registry.oracle.com/database/free:latest' "$ORADB_MOCK_LOG"
assert_true grep -Fq 'run -d --name oracle-free -p 1521:1521' "$ORADB_MOCK_LOG"
assert_true grep -Fq 'ENABLE_ARCHIVELOG=false' "$ORADB_MOCK_LOG"
assert_true grep -Fq "Container 'oracle-free' is running" "$tmp/output"
assert_true grep -Fq 'sql sys@//localhost:1521/FREEPDB1 as sysdba' "$tmp/output"

echo 'install.sh unit tests passed'
