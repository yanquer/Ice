//
//  MenuBarItemImageCache.swift
//  Ice
//

import Cocoa
import Combine

/// Cache for menu bar item images.
final class MenuBarItemImageCache: ObservableObject {
    /// The cached item images.
    @Published private(set) var images = [MenuBarItemInfo: CGImage]()

    /// The screen of the cached item images.
    private(set) var screen: NSScreen?

    /// The height of the menu bar of the cached item images.
    private(set) var menuBarHeight: CGFloat?

    /// The shared app state.
    private weak var appState: AppState?

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// Creates a cache with the given app state.
    init(appState: AppState) {
        self.appState = appState
    }

    /// Sets up the cache.
    @MainActor
    func performSetup() {
        configureCancellables()
    }

    /// Configures the internal observers for the cache.
    @MainActor
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        if let appState {
            Publishers.Merge3(
                // Update every 3 seconds at minimum.
                Timer.publish(every: 3, on: .main, in: .default).autoconnect().mapToVoid(),

                // Update when the active space or screen parameters change.
                Publishers.Merge(
                    NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification),
                    NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
                )
                .mapToVoid(),

                // Update when the average menu bar color or cached items change.
                Publishers.Merge(
                    appState.menuBarManager.$averageColorInfo.removeDuplicates().mapToVoid(),
                    appState.itemManager.$itemCache.removeDuplicates().mapToVoid()
                )
            )
            .throttle(for: 0.5, scheduler: DispatchQueue.main, latest: false)
            .sink { [weak self] in
                guard let self else {
                    return
                }
                Task.detached {
                    if ScreenCapture.cachedCheckPermissions() {
                        await self.updateCache()
                    }
                }
            }
            .store(in: &c)
        }

        cancellables = c
    }

    /// Logs a reason for skipping the cache.
    private func logSkippingCache(reason: String) {
        Logger.imageCache.debug("Skipping menu bar item image cache as \(reason)")
    }

    /// Returns a Boolean value that indicates whether caching menu bar items failed for
    /// the given section.
    @MainActor
    func cacheFailed(for section: MenuBarSection.Name) -> Bool {
        guard ScreenCapture.cachedCheckPermissions() else {
            return true
        }
        let items = appState?.itemManager.itemCache[section] ?? []
        guard !items.isEmpty else {
            return false
        }
        let keys = Set(images.keys)
        for item in items where keys.contains(item.info) {
            return false
        }
        return true
    }

    /// 批量抓取当前分区图标，对移动中或透明的裁剪结果逐项回退到单窗口截图。
    func createImages(for section: MenuBarSection.Name, screen: NSScreen) async -> [MenuBarItemInfo: CGImage] {
        guard let appState else {
            return [:]
        }

        let items = await appState.itemManager.itemCache[section]

        var images = [MenuBarItemInfo: CGImage]()
        let backingScaleFactor = screen.backingScaleFactor
        let displayBounds = CGDisplayBounds(screen.displayID)
        let option: CGWindowImageOption = [.boundsIgnoreFraming, .bestResolution]

        var itemInfos = [CGWindowID: MenuBarItemInfo]()
        var itemFrames = [CGWindowID: CGRect]()
        var windowIDs = [CGWindowID]()
        var frame = CGRect.null

        for item in items {
            let windowID = item.windowID
            guard
                // Use the most up-to-date window frame.
                let itemFrame = Bridging.getWindowFrame(for: windowID),
                itemFrame.minY == displayBounds.minY
            else {
                continue
            }
            itemInfos[windowID] = item.info
            itemFrames[windowID] = itemFrame
            windowIDs.append(windowID)
            frame = frame.union(itemFrame)
        }

        if
            let compositeImage = ScreenCapture.captureWindows(windowIDs, option: option),
            CGFloat(compositeImage.width) == frame.width * backingScaleFactor
        {
            for windowID in windowIDs {
                guard
                    let itemInfo = itemInfos[windowID],
                    let itemFrame = itemFrames[windowID]
                else {
                    continue
                }

                let frame = CGRect(
                    x: (itemFrame.origin.x - frame.origin.x) * backingScaleFactor,
                    y: (itemFrame.origin.y - frame.origin.y) * backingScaleFactor,
                    width: itemFrame.width * backingScaleFactor,
                    height: itemFrame.height * backingScaleFactor
                )

                guard
                    Bridging.getWindowFrame(for: windowID) == itemFrame,
                    let itemImage = compositeImage.cropping(to: frame),
                    itemImage.hasVisibleMenuBarPixels
                else {
                    continue
                }

                images[itemInfo] = itemImage
            }
        } else {
            Logger.imageCache.warning("Composite image capture failed. Attempting to capturing items individually.")
        }

        // 合成图整体成功，不代表其中每个图标都成功；只重抓缺失项目。
        for windowID in windowIDs {
            guard let itemInfo = itemInfos[windowID], images[itemInfo] == nil else {
                continue
            }
            if let image = captureItemImage(windowID: windowID, screen: screen) {
                images[itemInfo] = image
            } else {
                Logger.imageCache.debug("Empty image for \(itemInfo); retaining the last valid snapshot")
            }
        }

        return images
    }

    /// 单独截取菜单栏图标，保持原有裁剪方式并拒绝全透明结果。
    private func captureItemImage(windowID: CGWindowID, screen: NSScreen) -> CGImage? {
        guard let frame = Bridging.getWindowFrame(for: windowID) else {
            return nil
        }
        let scale = screen.backingScaleFactor
        let thickness = NSStatusBar.system.thickness * scale
        let crop = CGRect(x: 0, y: (frame.height * scale - thickness) / 2, width: frame.width * scale, height: thickness)
        guard
            let image = ScreenCapture.captureWindow(windowID, option: [.boundsIgnoreFraming, .bestResolution]),
            let cropped = image.cropping(to: crop),
            cropped.hasVisibleMenuBarPixels
        else {
            return nil
        }
        return cropped
    }

    /// 在图标仍处于可见位置时保存快照，防止回藏后的系统空图使其永久消失。
    func cacheImageBeforeRehiding(_ item: MenuBarItem) async {
        let screen = await MainActor.run {
            NSScreen.screens.first { CGDisplayBounds($0.displayID).contains(item.frame) }
        }
        guard let screen, let image = captureItemImage(windowID: item.windowID, screen: screen) else {
            return
        }
        await MainActor.run {
            images.mergeVisibleMenuBarImages([item.info: image])
        }
        Logger.imageCache.debug("Saved snapshot before rehiding \(item.logString)")
    }

    /// Updates the cache for the given sections, without checking whether caching is necessary.
    func updateCacheWithoutChecks(sections: [MenuBarSection.Name]) async {
        guard
            let appState,
            let screen = NSScreen.main
        else {
            return
        }

        var newImages = [MenuBarItemInfo: CGImage]()

        for section in sections {
            guard await !appState.itemManager.itemCache[section].isEmpty else {
                continue
            }
            let sectionImages = await createImages(for: section, screen: screen)
            guard !sectionImages.isEmpty else {
                Logger.imageCache.warning("Update image cache failed for \(section.logString)")
                continue
            }
            newImages.merge(sectionImages) { (_, new) in new }
        }

        await MainActor.run { [newImages] in
            self.screen = screen
            self.menuBarHeight = screen.getMenuBarHeight()
            images.mergeVisibleMenuBarImages(newImages)
        }
    }

    /// Updates the cache for the given sections, if necessary.
    func updateCache(sections: [MenuBarSection.Name]) async {
        guard let appState else {
            return
        }

        let isIceBarPresented = await appState.navigationState.isIceBarPresented
        let isSearchPresented = await appState.navigationState.isSearchPresented

        if !isIceBarPresented && !isSearchPresented {
            guard await appState.navigationState.isAppFrontmost else {
                logSkippingCache(reason: "Ice Bar not visible, app not frontmost")
                return
            }
            guard await appState.navigationState.isSettingsPresented else {
                logSkippingCache(reason: "Ice Bar not visible, Settings not visible")
                return
            }
            guard case .menuBarLayout = await appState.navigationState.settingsNavigationIdentifier else {
                logSkippingCache(reason: "Ice Bar not visible, Settings visible but not on Menu Bar Layout")
                return
            }
        }

        guard await !appState.itemManager.isMovingItem else {
            logSkippingCache(reason: "an item is currently being moved")
            return
        }

        guard await !appState.itemManager.itemHasRecentlyMoved else {
            logSkippingCache(reason: "an item was recently moved")
            return
        }

        await updateCacheWithoutChecks(sections: sections)
    }

    /// Updates the cache for all sections, if necessary.
    func updateCache() async {
        guard let appState else {
            return
        }

        let isIceBarPresented = await appState.navigationState.isIceBarPresented
        let isSearchPresented = await appState.navigationState.isSearchPresented
        let isSettingsPresented = await appState.navigationState.isSettingsPresented

        var sectionsNeedingDisplay = [MenuBarSection.Name]()
        if isSettingsPresented || isSearchPresented {
            sectionsNeedingDisplay = MenuBarSection.Name.allCases
        } else if
            isIceBarPresented,
            let section = await appState.menuBarManager.iceBarPanel.currentSection
        {
            sectionsNeedingDisplay.append(section)
        }

        await updateCache(sections: sectionsNeedingDisplay)
    }
}

// MARK: - Logger

private extension Logger {
    static let imageCache = Logger(category: "MenuBarItemImageCache")
}
