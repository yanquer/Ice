#!/bin/bash
# 编译真实布局视图与隔离数据源，验证拖动恢复；不改动用户菜单栏或偏好。
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_directory="$(mktemp -d "${TMPDIR:-/tmp}/ice-layout-bar-tests.XXXXXX")"
trap 'rm -rf "$test_directory"' EXIT
xcrun swiftc -O -parse-as-library \
    "$repo_root/Ice/UI/LayoutBar/LayoutBarItemView.swift" \
    "$repo_root/Ice/UI/LayoutBar/LayoutBarContainer.swift" \
    "$repo_root/Tests/LayoutBarRegressionTests.swift" \
    -o "$test_directory/layout-bar-tests"
"$test_directory/layout-bar-tests"
