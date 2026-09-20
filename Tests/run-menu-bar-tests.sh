#!/bin/bash
# 独立编译菜单栏识别与颜色采样生产代码，验证 Tahoe 兼容行为并清理产物。
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_directory="$(mktemp -d "${TMPDIR:-/tmp}/ice-menu-bar-tests.XXXXXX")"
trap 'rm -rf "$test_directory"' EXIT

xcrun swiftc -O -parse-as-library \
    "$repo_root/Ice/MenuBar/MenuBarItems/MenuBarItemInfo.swift" \
    "$repo_root/Ice/Utilities/CGImage+AverageColor.swift" \
    "$repo_root/Tests/MenuBarCompatibilityTests.swift" \
    -o "$test_directory/menu-bar-tests"
"$test_directory/menu-bar-tests"
