//
//  MenuBarSpacingPreferences.swift
//  Ice
//
// 写入并校验当前主机的菜单栏间距，失败时恢复原值，避免界面误报成功。

import Foundation

/// 管理系统间距偏好；测试可指定独立域，避免改变用户的全局设置。
struct MenuBarSpacingPreferences {
    private let applicationID: CFString
    private let keys: [String] = ["NSStatusItemSpacing", "NSStatusItemSelectionPadding"]

    /// 默认使用当前用户、当前主机的全局偏好域。
    init(applicationID: CFString = kCFPreferencesAnyApplication) {
        self.applicationID = applicationID
    }

    /// 写入明确的间距偏移并核对结果；零值删除覆盖项，恢复系统默认。
    func apply(offset: Int) throws {
        guard (-16...16).contains(offset) else {
            throw NSError(domain: "MenuBarSpacingPreferences", code: 2, userInfo: [
                NSLocalizedDescriptionKey: String(localized: "Menu bar spacing must be between -16 and 16."),
            ])
        }
        let original = keys.map { read($0) }
        let expected: NSNumber? = offset == 0 ? nil : NSNumber(value: 16 + offset)
        for key in keys {
            write(expected, for: key)
        }
        guard synchronize(), keys.allSatisfy({ matches(read($0), expected: expected) }) else {
            for (key, value) in zip(keys, original) {
                write(value, for: key)
            }
            _ = synchronize()
            throw NSError(domain: "MenuBarSpacingPreferences", code: 1, userInfo: [
                NSLocalizedDescriptionKey: String(localized: "Unable to save menu bar spacing. Please try again."),
            ])
        }
    }

    /// 读取指定偏好，不混入其他主机或应用域的默认值。
    private func read(_ key: String) -> CFPropertyList? {
        CFPreferencesCopyValue(key as CFString, applicationID, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
    }

    /// 设置或删除单个偏好，稍后统一同步。
    private func write(_ value: CFPropertyList?, for key: String) {
        CFPreferencesSetValue(key as CFString, value, applicationID, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
    }

    /// 将当前域写入持久化存储并返回是否成功。
    private func synchronize() -> Bool {
        CFPreferencesSynchronize(applicationID, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
    }

    /// 区分删除成功与整数值写入成功，避免把缺失值误认为零。
    private func matches(_ actual: CFPropertyList?, expected: NSNumber?) -> Bool {
        if let expected {
            return (actual as? NSNumber) == expected
        }
        return actual == nil
    }
}
