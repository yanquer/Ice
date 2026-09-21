#!/bin/bash
# 编译真实间距偏好实现，在独立测试域运行回归检查并清理编译产物。
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_directory="$(mktemp -d "${TMPDIR:-/tmp}/ice-spacing-tests.XXXXXX")"
trap 'rm -rf "$test_directory"' EXIT

xcrun swiftc -O -parse-as-library \
    "$repo_root/Ice/MenuBar/Spacing/MenuBarSpacingPreferences.swift" \
    "$repo_root/Tests/MenuBarSpacingTests.swift" \
    -o "$test_directory/spacing-tests"
"$test_directory/spacing-tests"
