//
//  WindowIDRegressionTests.swift
//  Ice
//
// 直接测试生产代码的窗口编号转换，覆盖真实崩溃值、边界值和无窗口场景。

import Cocoa

/// 模拟系统返回的窗口编号，无需修改真实菜单栏或触发系统崩溃。
@MainActor
private final class TestWindow: NSWindow {
    var simulatedWindowNumber: Int = 0

    /// 返回当前用例指定的窗口编号。
    override var windowNumber: Int {
        simulatedWindowNumber
    }
}

/// 独立运行窗口编号回归测试，任一用例失败时以非零状态退出。
@main
private enum WindowIDRegressionTests {
    /// 在主线程使用真实 NSWindow 子类验证两处调用方共用的安全转换。
    @MainActor
    static func main() throws {
        _ = NSApplication.shared
        let window = TestWindow(
            contentRect: .zero,
            styleMask: .borderless,
            backing: .buffered,
            defer: true
        )
        let cases: [(name: String, number: Int, expected: CGWindowID?)] = [
            ("reported macOS 26 crash", 4_294_967_296, nil),
            ("negative window number", -1, nil),
            ("minimum Int", Int.min, nil),
            ("maximum Int", Int.max, nil),
            ("zero retains existing behavior", 0, 0),
            ("ordinary window number", 42, 42),
            ("maximum CGWindowID", 4_294_967_295, .max),
        ]

        for test in cases {
            window.simulatedWindowNumber = test.number
            let actual: CGWindowID? = window.cgWindowID
            guard actual == test.expected else {
                throw NSError(domain: "WindowIDRegressionTests", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "FAIL: \(test.name): expected \(String(describing: test.expected)), got \(String(describing: actual))",
                ])
            }
            print("PASS: \(test.name)")
        }

        let missingWindow: NSWindow? = nil
        guard missingWindow?.cgWindowID == nil else {
            throw NSError(domain: "WindowIDRegressionTests", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "FAIL: missing window must produce nil",
            ])
        }
        print("PASS: missing window")
        print("All 8 window ID regression cases passed.")
    }
}
