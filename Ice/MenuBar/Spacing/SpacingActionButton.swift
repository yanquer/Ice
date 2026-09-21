//
//  SpacingActionButton.swift
//  Ice
//
// 使用原生按钮处理间距操作的鼠标点击，保持启用状态、辅助功能与 SwiftUI 一致。

import SwiftUI

/// 复用于间距的应用和重置操作，避免依赖 SwiftUI 自动按钮样式的鼠标命中路径。
struct SpacingActionButton: NSViewRepresentable {
    let title: String
    var systemImage: String?
    let isEnabled: Bool
    let action: () -> Void

    /// 保存最新操作闭包，供 AppKit 的 target-action 调用。
    final class Coordinator: NSObject {
        var action: () -> Void

        /// 接收按钮初始操作。
        init(action: @escaping () -> Void) {
            self.action = action
        }

        /// 处理原生按钮操作并记录进入业务逻辑前的诊断日志。
        @objc func performAction(_ sender: NSButton) {
            Logger(category: "Spacing").info("Native spacing button action: \(sender.toolTip ?? sender.title)")
            action()
        }
    }

    /// 接受非活动窗口的首次点击，并记录真实鼠标进入按钮的路径。
    private final class ActionButton: NSButton {
        /// 点击按钮时同时激活窗口并执行操作，无需用户再点一次。
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        /// 记录按钮内的鼠标按下，便于区分鼠标命中失败与业务执行失败。
        override func mouseDown(with event: NSEvent) {
            Logger(category: "Spacing").info("Mouse down on spacing button; enabled: \(isEnabled)")
            super.mouseDown(with: event)
        }
    }

    /// 创建 AppKit 操作代理。
    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    /// 创建拥有独立鼠标命中区域的原生按钮。
    func makeNSView(context: Context) -> NSButton {
        let button = ActionButton(title: title, target: context.coordinator, action: #selector(Coordinator.performAction(_:)))
        button.setButtonType(.momentaryPushIn)
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    /// 同步文案、图标、启用状态和闭包，避免原生按钮持有旧的滑块状态。
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.title = systemImage == nil ? title : ""
        button.image = systemImage.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: title) }
        button.imagePosition = systemImage == nil ? .noImage : .imageOnly
        button.isBordered = systemImage == nil
        button.toolTip = title
        button.setAccessibilityLabel(title)
        button.isEnabled = isEnabled
    }
}
