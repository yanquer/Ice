#!/bin/bash
# 隔离系统事件并编译真实移动方法，验证等待、重试和失败时的光标生命周期。
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_directory="$(mktemp -d "${TMPDIR:-/tmp}/ice-item-cursor-tests.XXXXXX")"
trap 'rm -rf "$test_directory"' EXIT

# 保留生产方法原文；方法重命名或提取失败时明确失败，避免空测试误报通过。
{
    printf 'import Cocoa\nextension MenuBarItemManager {\n'
    awk '
        /^    private func (wakeUpItem|moveItemOnce)\(/ || /^    func move\(item:/ { copying = 1; count++ }
        copying { print }
        copying && /^    }$/ { copying = 0 }
        END { if (count != 3) exit 1 }
    ' "$repo_root/Ice/MenuBar/MenuBarItems/MenuBarItemManager.swift"
    printf '}\n'
} > "$test_directory/ItemMovement.swift"
xcrun swiftc -O -parse-as-library \
    "$test_directory/ItemMovement.swift" \
    "$repo_root/Tests/ItemCursorRegressionTests.swift" \
    -o "$test_directory/item-cursor-tests"
"$test_directory/item-cursor-tests"
