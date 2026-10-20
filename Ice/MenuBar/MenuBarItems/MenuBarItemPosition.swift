// 按实际相邻顺序确认菜单栏移动，避免系统间隙使已经到位的项目被误判为超时。
import CoreGraphics

/// 使用同一轮窗口坐标判断左右邻接，保留分隔符以防跨分区误报成功。
enum MenuBarItemPosition {
    enum Side { case left, right }

    /// 保存参与排列的窗口身份和坐标，不依赖重复的 Item-0 标题。
    struct Window {
        let id: CGWindowID
        let frame: CGRect
    }

    /// 允许边缘舍入误差和系统间隙，但拒绝反向、重叠、跨行或隔着其他项目的落点。
    static func isCorrect(itemID: CGWindowID, targetID: CGWindowID, side: Side, windows: [Window]) -> Bool {
        guard itemID != targetID,
              let item: CGRect = windows.first(where: { $0.id == itemID })?.frame,
              let target: CGRect = windows.first(where: { $0.id == targetID })?.frame,
              isValid(item), isValid(target),
              overlapsVertically(item, target) else { return false }

        let tolerance: CGFloat = 0.5
        switch side {
        case .left:
            guard item.midX <= target.midX, item.maxX <= target.minX + tolerance else { return false }
        case .right:
            guard item.midX >= target.midX, item.minX >= target.maxX - tolerance else { return false }
        }
        let lowerX: CGFloat = min(item.midX, target.midX)
        let upperX: CGFloat = max(item.midX, target.midX)
        return !windows.contains { window in
            guard window.id != itemID, window.id != targetID,
                  isValid(window.frame), overlapsVertically(item, window.frame) else { return false }
            // 零宽度分隔符仍是分区边界，不能因不可见而跳过。
            return window.frame.midX > lowerX && window.frame.midX < upperX
        }
    }

    /// 排除系统尚未给出有效坐标的窗口，同时允许收起后的零宽度分隔符。
    private static func isValid(_ frame: CGRect) -> Bool {
        [frame.origin.x, frame.origin.y, frame.width, frame.height].allSatisfy { $0.isFinite } &&
            !frame.isNull && frame.width >= 0 && frame.height > 0
    }

    /// 只比较同一菜单栏行的项目，避免其他显示器的窗口阻挡邻接判断。
    private static func overlapsVertically(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        max(lhs.minY, rhs.minY) < min(lhs.maxY, rhs.maxY)
    }
}
