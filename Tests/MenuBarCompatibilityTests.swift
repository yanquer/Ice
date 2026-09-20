//
//  MenuBarCompatibilityTests.swift
//  Ice
//
// 独立验证 macOS 26 托管窗口识别、同名图标缓存隔离和透明截图背景降级。

import Cocoa

/// 提供生产模型依赖的固定应用标识，不初始化菜单栏或读取用户设置。
enum Constants {
    static let bundleIdentifier: String = "com.jordanbaird.Ice"
}

/// 仅提供生产模型使用的现有分隔符名称，避免测试创建真实状态栏项目。
enum ControlItem {
    enum Identifier: String {
        case iceIcon = "SItem"
        case hidden = "HItem"
        case alwaysHidden = "AHItem"
    }
}

/// 运行真实生产模型与图像采样方法的兼容性回归测试。
@main
private enum MenuBarCompatibilityTests {
    /// 汇总执行识别和背景颜色用例，失败时返回非零退出状态。
    static func main() throws {
        try testIdentity()
        try testAverageColor()
        print("All menu bar compatibility regression cases passed.")
    }

    /// 检查条件并输出可定位的用例名称。
    private static func expect(_ condition: Bool, _ name: String) throws {
        guard condition else {
            throw NSError(domain: "MenuBarCompatibilityTests", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "FAIL: \(name)",
            ])
        }
        print("PASS: \(name)")
    }

    /// 使用真实窗口元数据样例验证 Ice 分隔符、系统项目和同名第三方图标。
    private static func testIdentity() throws {
        let hosted: (UInt32, String) -> MenuBarItemInfo = { windowID, title in
            MenuBarItemInfo(windowID: windowID, title: title, ownerBundleIdentifier: "com.apple.controlcenter", isReparented: true)
        }
        try expect(hosted(104303, "SItem") == .iceIcon, "hosted Ice icon")
        try expect(hosted(104304, "HItem") == .hiddenControlItem, "hosted hidden divider")
        try expect(hosted(104305, "AHItem") == .alwaysHiddenControlItem, "hosted always-hidden divider")
        try expect(hosted(53659, "BentoBox-0") == .controlCenter, "renamed Control Center stays immovable")
        try expect(hosted(53657, "Clock") == .clock, "clock retains identity")
        let first = hosted(53870, "Item-0")
        let second = hosted(53814, "Item-0")
        let images = [first: "first image", second: "second image"]
        try expect(images.count == 2 && images[first] == "first image", "same-title icons keep separate caches")
        try expect(hosted(53870, "Item-0") == first, "window identity remains stable across refreshes")
        let encoded = try JSONEncoder().encode(first)
        try expect(try JSONDecoder().decode(MenuBarItemInfo.self, from: encoded) == first, "hosted identity round trip")
        let legacy = MenuBarItemInfo(windowID: 1, title: "HItem", ownerBundleIdentifier: "com.jordanbaird.Ice", isReparented: false)
        try expect(legacy == .hiddenControlItem, "legacy Ice divider")
        let foreign = MenuBarItemInfo(windowID: 1, title: "HItem", ownerBundleIdentifier: "example.other", isReparented: true)
        try expect(foreign != .hiddenControlItem, "unrelated app title does not become an Ice divider")
        let legacyHosted = MenuBarItemInfo(windowID: 1, title: "HItem", ownerBundleIdentifier: "com.apple.controlcenter", isReparented: false)
        try expect(legacyHosted.namespace == .controlCenter, "pre-Tahoe ownership stays unchanged")
    }

    /// 创建极小的测试截图，不读取桌面或申请屏幕录制权限。
    private static func makeImage(color: CGColor) throws -> CGImage {
        guard let context = CGContext(
            data: nil,
            width: 2,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 8,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw NSError(domain: "MenuBarCompatibilityTests", code: 2)
        }
        context.setFillColor(color)
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        guard let image = context.makeImage() else {
            throw NSError(domain: "MenuBarCompatibilityTests", code: 3)
        }
        return image
    }

    /// 验证全透明截图不会生成 NaN 白底，正常深浅色截图仍保留原有结果。
    private static func testAverageColor() throws {
        let transparent = try makeImage(color: CGColor(gray: 0, alpha: 0))
        try expect(transparent.averageColor(makeOpaque: true) == nil, "transparent image uses fallback background")
        try expect(transparent.averageColor() == nil, "transparent Ice Bar sampling uses fallback")
        for value: CGFloat in [0, 1] {
            let image = try makeImage(color: CGColor(gray: value, alpha: 1))
            let components = image.averageColor(makeOpaque: true)?.components ?? []
            try expect(components.count == 4 && components.allSatisfy(\.isFinite), "opaque color stays finite: \(value)")
            try expect(abs((components.first ?? -1) - value) < 0.01, "opaque color stays accurate: \(value)")
        }
        let faint = try makeImage(color: CGColor(gray: 1, alpha: 0.1))
        try expect(faint.averageColor() == nil, "pixels below alpha threshold use fallback")
    }
}
