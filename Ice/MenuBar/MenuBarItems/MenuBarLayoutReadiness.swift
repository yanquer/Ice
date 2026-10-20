// 校验启动时分隔符的完整性与稳定性，阻止过渡坐标被当作最终分区发布。
import Foundation

/// 仅保存两个分隔符的最近位置，不缓存图像或不断增长的窗口历史。
struct MenuBarLayoutReadiness {
    /// 分隔符的系统坐标及当前是否应当展开以隐藏项目。
    struct Divider: Equatable {
        let frame: CGRect
        let isExpanded: Bool
    }

    private var previous: [Divider] = []
    private var stableSince: TimeInterval?

    /// 排除尚未创建、零尺寸、未展开或顺序错误的分隔符。
    static func isValid(hidden: Divider?, alwaysHidden: Divider?, requiresAlwaysHidden: Bool,
                        minimumExpandedWidth: CGFloat, requiresCorrectOrder: Bool = true) -> Bool {
        guard let hidden, !requiresAlwaysHidden || alwaysHidden != nil else { return false }
        let dividers: [Divider] = [hidden] + (alwaysHidden.map { [$0] } ?? [])
        guard dividers.allSatisfy({ divider in
            let frame: CGRect = divider.frame
            return !frame.isNull && !frame.isInfinite && frame.width >= 0 && frame.height > 0 &&
                (!divider.isExpanded || frame.width >= minimumExpandedWidth)
        }) else { return false }
        return !requiresCorrectOrder || (alwaysHidden.map { $0.frame.maxX <= hidden.frame.minX } ?? true)
    }

    /// 首次发布需要有效位置持续稳定至少 250 毫秒；无效样本会重置稳定窗口。
    mutating func observe(hidden: Divider?, alwaysHidden: Divider?, requiresAlwaysHidden: Bool,
                          minimumExpandedWidth: CGFloat, now: TimeInterval) -> Bool {
        guard Self.isValid(hidden: hidden, alwaysHidden: alwaysHidden, requiresAlwaysHidden: requiresAlwaysHidden,
                           minimumExpandedWidth: minimumExpandedWidth), let hidden else {
            previous = []
            stableSince = nil
            return false
        }
        let current: [Divider] = [hidden] + (alwaysHidden.map { [$0] } ?? [])
        if previous != current {
            previous = current
            stableSince = now
            return false
        }
        return stableSince.map { now - $0 >= 0.25 } ?? false
    }
}
