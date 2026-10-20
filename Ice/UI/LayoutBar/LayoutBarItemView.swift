//
//  LayoutBarItemView.swift
//  Ice
//

import Cocoa
import Combine

// MARK: - LayoutBarItemView

/// A view that displays an image in a menu bar layout view.
final class LayoutBarItemView: NSView {
    private weak var appState: AppState?

    private var cancellables = Set<AnyCancellable>()

    /// The item that the view represents.
    let item: MenuBarItem

    /// Temporary information that the item view retains when it is moved outside
    /// of a layout view.
    ///
    /// When the item view is dragged outside of a layout view, this property is set
    /// to hold the layout view's container view, as well as the index of the item
    /// view in relation to the container's other items. Upon being inserted into a
    /// new layout view, these values are removed. If the item is dropped outside of
    /// a layout view, these values are used to reinsert the item view in its original
    /// layout view.
    var oldContainerInfo: (container: LayoutBarContainer, index: Int)?

    /// 在整个拖动会话中保留来源分区，跨区放下或取消时都必须解除它的刷新锁。
    private weak var dragSourceContainer: LayoutBarContainer?

    /// A Boolean value that indicates whether the item view is currently inside a container.
    var hasContainer = false

    /// The image displayed inside the view.
    private var image: NSImage? {
        didSet {
            if
                let image,
                let screen = appState?.imageCache.screen
            {
                let size = CGSize(
                    width: image.size.width / screen.backingScaleFactor,
                    height: image.size.height / screen.backingScaleFactor
                )
                setFrameSize(size)
            } else {
                setFrameSize(CGSize(width: max(item.frame.width, 20), height: max(item.frame.height, 24)))
            }
            needsDisplay = true
        }
    }

    /// A Boolean value that indicates whether the item view is a dragging placeholder.
    ///
    /// If this value is `true`, the item view does not draw its image.
    var isDraggingPlaceholder = false {
        didSet {
            needsDisplay = true
        }
    }

    /// A Boolean value that indicates whether the view is enabled.
    var isEnabled = true {
        didSet {
            needsDisplay = true
        }
    }

    /// Creates a view that displays the given menu bar item.
    init(appState: AppState, item: MenuBarItem) {
        self.item = item
        self.appState = appState

        // set the frame to the full item frame size; the image will be centered when displayed
        super.init(frame: CGRect(origin: .zero, size: item.frame.size))
        unregisterDraggedTypes()

        self.toolTip = item.displayName
        self.isEnabled = item.isMovable

        configureCancellables()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        if let appState {
            appState.imageCache.$images
                .sink { [weak self] images in
                    guard
                        let self,
                        let cgImage = images[item.info]
                    else {
                        return
                    }
                    image = NSImage(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))
                }
                .store(in: &c)
        }

        cancellables = c
    }

    /// 没有截图时沿用 Ice 栏的恢复符号，保留可见且可拖动的项目入口。
    private var displayImage: NSImage? {
        image ?? NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: item.displayName)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.labelColor]))
    }

    /// Provides an alert to display when the item view is disabled.
    func provideAlertForDisabledItem() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = String(localized: "Menu bar item is not movable.")
        alert.informativeText = String(localized: "macOS prohibits \"\(item.displayName)\" from being moved.")
        return alert
    }

    /// Provides an alert to display when a menu bar item is unresponsive.
    func provideAlertForUnresponsiveItem() -> NSAlert {
        let alert = provideAlertForDisabledItem()
        alert.informativeText = String(localized: "\(item.displayName) is unresponsive. Until it is restarted, it cannot be moved. Movement of other menu bar items may also be affected until this is resolved.")
        return alert
    }

    override func draw(_ dirtyRect: NSRect) {
        if !isDraggingPlaceholder {
            displayImage?.draw(
                in: image == nil ? CGRect(x: bounds.midX - 8, y: bounds.midY - 8, width: 16, height: 16) : bounds,
                from: .zero,
                operation: .sourceOver,
                fraction: isEnabled ? 1.0 : 0.67
            )
            if Bridging.responsivity(for: item.ownerPID) == .unresponsive {
                let warningImage = NSImage.warning
                let width: CGFloat = 15
                let scale = width / warningImage.size.width
                let size = CGSize(
                    width: width,
                    height: warningImage.size.height * scale
                )
                warningImage.draw(
                    in: CGRect(
                        x: bounds.maxX - size.width,
                        y: bounds.minY,
                        width: size.width,
                        height: size.height
                    )
                )
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)

        guard isEnabled else {
            let alert = provideAlertForDisabledItem()
            alert.runModal()
            return
        }

        guard Bridging.responsivity(for: item.ownerPID) != .unresponsive else {
            let alert = provideAlertForUnresponsiveItem()
            alert.runModal()
            return
        }

        let pasteboardItem = NSPasteboardItem()
        // contents of the pasteboard item don't matter here, as all needed information
        // is available directly from the dragging session; what matters is that the type
        // is set to `layoutBarItem`, as that is what the layout bar registers for
        pasteboardItem.setData(Data(), forType: .layoutBarItem)

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        draggingItem.setDraggingFrame(bounds, contents: displayImage)

        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }
}

// MARK: LayoutBarItemView: NSDraggingSource
extension LayoutBarItemView: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return .move
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        // make sure the container doesn't update its arranged views and that items
        // aren't arranged during a dragging session
        beginLayoutDragging()

        // prevent the dragging image from animating back to its original location
        session.animatesToStartingPositionsOnCancelOrFail = false

        // async to prevent the view from disappearing before the dragging image appears
        DispatchQueue.main.async {
            if self.dragSourceContainer != nil {
                self.isDraggingPlaceholder = true
            }
        }
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        endLayoutDragging(operation: operation)
    }

    /// 记录真实来源并暂停列表刷新，避免依赖拖动目标的回调才能记住来源。
    func beginLayoutDragging() {
        guard let container = superview as? LayoutBarContainer,
              let index: Int = container.arrangedViews.firstIndex(of: self) else { return }
        dragSourceContainer = container
        oldContainerInfo = (container, index)
        container.canSetArrangedViews = false
    }

    /// 无论成功、失败或取消都解锁来源；取消时立即恢复，成功放下由移动完成回调对账。
    func endLayoutDragging(operation: NSDragOperation) {
        isDraggingPlaceholder = false
        let source: LayoutBarContainer? = dragSourceContainer
        let target: LayoutBarContainer? = superview as? LayoutBarContainer
        source?.canSetArrangedViews = true
        target?.canSetArrangedViews = true
        if operation.isEmpty || !hasContainer {
            if target !== source { target?.resumeUpdatesAfterDragging() }
            source?.resumeUpdatesAfterDragging()
        }
        dragSourceContainer = nil
        oldContainerInfo = nil
    }
}

extension LayoutBarItemView: NSAccessibilityLayoutItem { }

// MARK: Layout Bar Item Pasteboard Type
extension NSPasteboard.PasteboardType {
    static let layoutBarItem = Self("\(Constants.bundleIdentifier).layout-bar-item")
}
