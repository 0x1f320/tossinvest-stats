#!/usr/bin/env bash
# Runs the test suite with `swift test`.
#
# With only the Command Line Tools installed (no Xcode), the Swift Testing framework
# ships with the toolchain but is not on the default search paths, so point the
# compiler, linker and runtime at it.
set -euo pipefail
cd "$(dirname "$0")/.."

DEVELOPER_DIR="$(xcode-select -p)"
if [[ "$DEVELOPER_DIR" == *CommandLineTools* ]]; then
  FRAMEWORKS="$DEVELOPER_DIR/Library/Developer/Frameworks"
  LIBS="$DEVELOPER_DIR/Library/Developer/usr/lib"
  exec swift test \
    -Xswiftc -F"$FRAMEWORKS" \
    -Xlinker -F"$FRAMEWORKS" \
    -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
    -Xlinker -rpath -Xlinker "$LIBS" \
    "$@"
fi
exec swift test "$@"
