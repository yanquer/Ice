//
//  MenuBarItemSpacingManager.swift
//  Ice
//

import Cocoa

/// Manager for menu bar item spacing.
@MainActor
final class MenuBarItemSpacingManager {
    /// Returns a log string for the given app.
    private nonisolated func logString(for app: NSRunningApplication) -> String {
        app.localizedName ?? app.bundleIdentifier ?? "<NIL>"
    }

    /// 有界等待应用退出；仅允许强制刷新由系统自动重启的控制中心。
    private func signalAppToQuit(_ app: NSRunningApplication) async throws {
        guard !app.isTerminated else {
            return
        }
        Logger.spacing.info("Requesting menu bar refresh for \(logString(for: app))")
        app.terminate()
        for attempt in 0..<30 {
            if app.isTerminated {
                return
            }
            if attempt == 10, app.bundleIdentifier == "com.apple.controlcenter" {
                app.forceTerminate()
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard app.isTerminated else {
            Logger.spacing.warning("Application did not quit; sign out may be required: \(logString(for: app))")
            throw CocoaError(.userCancelled)
        }
    }

    /// Asynchronously launches the app at the given URL.
    private nonisolated func launchApp(at applicationURL: URL, bundleIdentifier: String) async throws {
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
            Logger.spacing.debug("Application \"\(logString(for: app))\" is already open, so skipping launch")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        configuration.createsNewApplicationInstance = false
        configuration.promptsUserIfNeeded = false
        try await NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration)
    }

    /// Asynchronously relaunches the given app.
    private func relaunchApp(_ app: NSRunningApplication) async throws {
        struct RelaunchError: Error { }
        guard
            let url = app.bundleURL,
            let bundleIdentifier = app.bundleIdentifier
        else {
            throw RelaunchError()
        }
        try await signalAppToQuit(app)
        if app.isTerminated {
            try await launchApp(at: url, bundleIdentifier: bundleIdentifier)
        } else {
            throw RelaunchError()
        }
    }

    /// 写入明确的偏移后尝试刷新菜单栏；返回 false 表示已保存但需手动重新登录。
    func applyOffset(_ offset: Int) async throws -> Bool {
        try MenuBarSpacingPreferences().apply(offset: offset)
        Logger.spacing.info("Saved and verified menu bar spacing offset: \(offset)")

        var refreshed = true
        // Tahoe 的窗口所属进程是控制中心，不能再据此批量重启第三方应用。
        if #unavailable(macOS 26.0) {
            let items = MenuBarItem.getMenuBarItems(onScreenOnly: false, activeSpaceOnly: true)
            let pids = Set(items.map { $0.ownerPID })
            refreshed = await withTaskGroup(of: Bool.self) { group in
                for pid in pids {
                    guard
                        let app = NSRunningApplication(processIdentifier: pid),
                        app.bundleIdentifier != "com.apple.controlcenter",
                        app != .current
                    else {
                        continue
                    }
                    group.addTask { @MainActor in
                        do {
                            try await self.relaunchApp(app)
                            return true
                        } catch {
                            Logger.spacing.warning("Could not relaunch \(self.logString(for: app)): \(error)")
                            return false
                        }
                    }
                }
                var allSucceeded = true
                for await succeeded in group where !succeeded {
                    allSucceeded = false
                }
                return allSucceeded
            }
        }

        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first {
            do {
                try await signalAppToQuit(app)
            } catch {
                refreshed = false
                Logger.spacing.warning("Spacing was saved, but Control Center refresh failed: \(error)")
            }
        } else {
            refreshed = false
        }
        return refreshed
    }
}

// MARK: - Logger
private extension Logger {
    static let spacing = Logger(category: "Spacing")
}
