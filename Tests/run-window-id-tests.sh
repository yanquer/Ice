#!/bin/bash
# 编译生产代码与独立回归测试，在临时目录运行并自动清理测试产物。
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_directory="$(mktemp -d "${TMPDIR:-/tmp}/ice-window-id-tests.XXXXXX")"
trap 'rm -rf "$test_directory"' EXIT

xcrun swiftc -O -parse-as-library \
    "$repo_root/Ice/Utilities/NSWindow+WindowID.swift" \
    "$repo_root/Tests/WindowIDRegressionTests.swift" \
    -o "$test_directory/window-id-tests"
"$test_directory/window-id-tests"
