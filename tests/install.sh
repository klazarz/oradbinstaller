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
USING_EXISTING_CONTAINER=false
assert_eq false "$USING_EXISTING_CONTAINER"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/podman" <<'MOCK'
#!/usr/bin/env bash
case "$1" in info) exit 0 ;; esac
MOCK
chmod +x "$tmp/podman"
old_path="$PATH"; PATH="$tmp:$PATH"; ENGINE=""; choose_engine; assert_eq podman "$ENGINE"; PATH="$old_path"

progress="$(step '3/6' 'Downloading database image')"
assert_eq $'\n==> [3/6] Downloading database image' "$progress"
assert_true grep -Fq 'INPUT_DEVICE="${ORADB_INSTALLER_TTY:-/dev/tty}"' "$ROOT/install.sh"

echo 'install.sh unit tests passed'
