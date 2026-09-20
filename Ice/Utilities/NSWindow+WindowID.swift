//
//  NSWindow+WindowID.swift
//  Ice
//
// 为窗口编号提供安全转换，避免 macOS 26 状态栏窗口编号越界导致崩溃。

import Cocoa

extension NSWindow {
    /// 将窗口编号精确转换为 Core Graphics 窗口 ID，负数或越界时返回 nil。
    var cgWindowID: CGWindowID? {
        CGWindowID(exactly: windowNumber)
    }
}
