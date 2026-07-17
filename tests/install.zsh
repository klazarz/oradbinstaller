#!/usr/bin/env zsh
set -euo pipefail

ROOT=${0:A:h:h}
ORADB_INSTALLER_TEST=1 source "$ROOT/install.sh"

assert() { "$@" || { print -u2 "FAILED: $*"; exit 1; }; }

assert test "$(lowercase QuIcK)" = quick
assert valid_identifier oracle-free
assert valid_port 1521
assert valid_password Abcdefg1

java() { print -u2 'openjdk version "17.0.1"'; }
assert java_17_available

java() { print -u2 'openjdk version "1.8.0"'; }
if java_17_available; then
  print -u2 'FAILED: Java 8 must not be accepted'
  exit 1
fi

print 'install.sh zsh compatibility tests passed'
