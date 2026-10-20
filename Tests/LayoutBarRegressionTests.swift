// 编译真实布局视图，隔离系统菜单栏与鼠标事件，验证拖动锁释放和旧窗口恢复。
import Cocoa
import Combine
import SwiftUI

/// 为布局视图提供可控制的数据源，不创建真实状态栏项目。
struct MenuBarItem: Equatable {
    let info: Int
    var frame: CGRect = CGRect(x: 0, y: 0, width: 18, height: 24)
    var isMovable: Bool = true
    var ownerPID: pid_t { 0 }
    var displayName: String { "Item-0" }
}

/// 替代系统进程探测，测试只覆盖布局行为。
enum Bridging {
    enum Responsivity { case responsive, unresponsive }
    /// 测试中无需向真实应用发送事件。
    static func responsivity(for pid: pid_t) -> Responsivity { .responsive }
}

/// 提供粘贴板命名空间。
enum Constants { static let bundleIdentifier: String = "test.ice.layout" }

extension NSImage {
    /// 为未响应提示提供系统图像，测试无需加载应用资源包。
    static var warning: NSImage { NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)! }
}

/// 提供三个真实布局分区对应的标识。
struct MenuBarSection {
    enum Name: Hashable { case visible, hidden, alwaysHidden }
    let name: Name
}

/// 模拟应用发布的新窗口快照，用于驱动真实布局容器。
final class MenuBarItemManager {
    /// 保存测试中各分区的窗口快照。
    struct ItemCache: Equatable {
        var items: [MenuBarSection.Name: [MenuBarItem]] = [:]
        /// 返回指定分区的当前快照。
        func managedItems(for section: MenuBarSection.Name) -> [MenuBarItem] { items[section, default: []] }
    }
    @Published var itemCache: ItemCache = ItemCache()
}

/// 模拟截图缓存，允许验证尚未取得图像的项目。
final class MenuBarItemImageCache {
    @Published var images: [Int: CGImage] = [:]
    var screen: NSScreen? = NSScreen.main
}

/// 向真实视图注入测试数据，避免读取用户偏好或启动菜单栏管理器。
final class AppState {
    let itemManager: MenuBarItemManager = MenuBarItemManager()
    let imageCache: MenuBarItemImageCache = MenuBarItemImageCache()
}

/// 执行来源分区冻结、取消拖动和窗口编号更新的回归测试。
@main
@MainActor
private enum LayoutBarRegressionTests {
    /// 在 AppKit 主线程中验证生产视图，不移动用户的真实菜单栏。
    static func main() throws {
        _ = NSApplication.shared
        try testCrossSectionDrag()
        try testCancelledDrag()
        try testFailedMoveReconciliation()
        try testMissingImageRendering()
        print("All layout bar regression cases passed.")
    }

    /// 检查预期行为并输出可定位的用例名称。
    private static func expect(_ condition: Bool, _ name: String) throws {
        guard condition else {
            throw NSError(domain: "LayoutBarRegressionTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "FAIL: \(name)"])
        }
        print("PASS: \(name)")
    }

    /// 复现从始终隐藏拖到隐藏后，来源分区必须继续接受应用重启产生的新窗口。
    private static func testCrossSectionDrag() throws {
        let state: AppState = AppState()
        let original: MenuBarItem = MenuBarItem(info: 101)
        state.itemManager.itemCache.items = [.alwaysHidden: [original]]
        let source: LayoutBarContainer = LayoutBarContainer(appState: state, section: MenuBarSection(name: .alwaysHidden), spacing: 0)
        let target: LayoutBarContainer = LayoutBarContainer(appState: state, section: MenuBarSection(name: .hidden), spacing: 0)
        let view: LayoutBarItemView = source.arrangedViews[0]
        view.beginLayoutDragging()
        try expect(!source.canSetArrangedViews, "source freezes only during drag")
        source.arrangedViews = []
        target.arrangedViews = [view]
        target.canSetArrangedViews = false
        view.endLayoutDragging(operation: .move)
        try expect(source.canSetArrangedViews && target.canSetArrangedViews, "cross-section drop unlocks source and destination")
        state.itemManager.itemCache.items = [.alwaysHidden: [MenuBarItem(info: 202)], .hidden: [original]]
        try expect(source.arrangedViews.map(\.item.info) == [202], "recreated window replaces stale source item")
        try expect(target.arrangedViews.map(\.item.info) == [101], "destination follows actual section")
    }

    /// 取消前尚未触发目标回调也能恢复来源，并接收拖动期间遗漏的窗口更新。
    private static func testCancelledDrag() throws {
        let state: AppState = AppState()
        state.itemManager.itemCache.items = [.hidden: [MenuBarItem(info: 1)]]
        let source: LayoutBarContainer = LayoutBarContainer(appState: state, section: MenuBarSection(name: .hidden), spacing: 0)
        let view: LayoutBarItemView = source.arrangedViews[0]
        view.beginLayoutDragging()
        state.itemManager.itemCache.items = [.hidden: [MenuBarItem(info: 2)]]
        view.endLayoutDragging(operation: [])
        try expect(source.canSetArrangedViews && source.arrangedViews.map(\.item.info) == [2], "cancel replays missed cache update")
        try expect(view.oldContainerInfo == nil && !view.isDraggingPlaceholder, "cancel clears drag state")
        let replacement: LayoutBarItemView = source.arrangedViews[0]
        replacement.beginLayoutDragging()
        source.arrangedViews = []
        replacement.endLayoutDragging(operation: [])
        try expect(source.arrangedViews.map(\.item.info) == [2], "drop outside restores source without target callbacks")
        let target: LayoutBarContainer = LayoutBarContainer(appState: state, section: MenuBarSection(name: .alwaysHidden), spacing: 0)
        let current: LayoutBarItemView = source.arrangedViews[0]
        current.beginLayoutDragging()
        source.arrangedViews = []
        target.arrangedViews = [current]
        target.canSetArrangedViews = false
        state.itemManager.itemCache.items = [.hidden: [MenuBarItem(info: 3)]]
        current.endLayoutDragging(operation: [])
        try expect(source.arrangedViews.map(\.item.info) == [3] && target.arrangedViews.isEmpty,
                   "cancel over destination restores both sections from latest snapshot")
        try expect(target.canSetArrangedViews, "cancel unlocks destination")
    }

    /// 模拟无效窗口导致移动失败，缓存未变化时也必须撤销两个分区的乐观布局。
    private static func testFailedMoveReconciliation() throws {
        let state: AppState = AppState()
        state.itemManager.itemCache.items = [.alwaysHidden: [MenuBarItem(info: 7)]]
        let source: LayoutBarContainer = LayoutBarContainer(appState: state, section: MenuBarSection(name: .alwaysHidden), spacing: 0)
        let target: LayoutBarContainer = LayoutBarContainer(appState: state, section: MenuBarSection(name: .hidden), spacing: 0)
        let view: LayoutBarItemView = source.arrangedViews[0]
        view.beginLayoutDragging()
        source.arrangedViews = []
        target.arrangedViews = [view]
        view.endLayoutDragging(operation: .move)
        source.resumeUpdatesAfterDragging()
        target.resumeUpdatesAfterDragging()
        try expect(source.arrangedViews.map(\.item.info) == [7] && target.arrangedViews.isEmpty, "failed move rolls back unchanged cache")
        try expect(source.canSetArrangedViews && target.canSetArrangedViews, "both sections recover after failure")
        try expect(source.arrangedViews[0].bounds.width > 0 && source.arrangedViews[0].bounds.height > 0, "uncaptured icon keeps draggable bounds")
        source.resumeUpdatesAfterDragging()
        try expect(source.arrangedViews.count == 1, "repeated recovery never duplicates item")
    }

    /// 在深浅外观下实际绘制无截图项目，确保占位符不会成为看不见的空白。
    private static func testMissingImageRendering() throws {
        let state: AppState = AppState()
        let view: LayoutBarItemView = LayoutBarItemView(appState: state, item: MenuBarItem(info: 9))
        for name: NSAppearance.Name in [.aqua, .darkAqua] {
            let bitmap: NSBitmapImageRep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 18, pixelsHigh: 24,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            NSAppearance(named: name)!.performAsCurrentDrawingAppearance { view.draw(view.bounds) }
            NSGraphicsContext.restoreGraphicsState()
            let colors: [NSColor] = (0..<24).flatMap { y in (0..<18).compactMap { x in bitmap.colorAt(x: x, y: y) } }
            let visible: [NSColor] = colors.filter { $0.alphaComponent > 0.5 }
            try expect(!visible.isEmpty, "missing icon renders visible symbol: \(name.rawValue)")
            try expect(visible.contains { name == .darkAqua ? $0.brightnessComponent > 0.7 : $0.brightnessComponent < 0.3 },
                       "missing icon contrasts with appearance: \(name.rawValue)")
        }
    }
}
