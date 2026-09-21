//
//  MenuBarSpacingTests.swift
//  Ice
//
// 在独立偏好域验证间距写入、重置和非法输入，不改变系统全局间距或重启应用。

import Foundation

/// 运行系统间距偏好存储的回归测试。
@main
private enum MenuBarSpacingTests {
    /// 逐项检查两项偏好是否一起更新，最后清理本次创建的测试域。
    static func main() throws {
        let domain = "com.jordanbaird.Ice.tests.spacing.\(UUID().uuidString)" as CFString
        let preferences = MenuBarSpacingPreferences(applicationID: domain)
        let keys = ["NSStatusItemSpacing", "NSStatusItemSelectionPadding"]
        defer {
            for key in keys {
                CFPreferencesSetValue(key as CFString, nil, domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
            }
            CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        }
        let cases: [(offset: Int, expected: Int?)] = [(0, nil), (-6, 10), (-16, 0), (16, 32), (2, 18), (0, nil), (0, nil)]
        for test in cases {
            try preferences.apply(offset: test.offset)
            for key in keys {
                let actual = CFPreferencesCopyValue(key as CFString, domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost) as? NSNumber
                guard actual?.intValue == test.expected else {
                    throw NSError(domain: "MenuBarSpacingTests", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "Unexpected value for \(key), offset \(test.offset): \(String(describing: actual))",
                    ])
                }
            }
            print("PASS: both preferences for offset \(test.offset)")
        }
        try preferences.apply(offset: -6)
        for invalid in [-17, 17, Int.min, Int.max] {
            var rejected = false
            do {
                try preferences.apply(offset: invalid)
            } catch {
                rejected = true
            }
            guard rejected else {
                throw NSError(domain: "MenuBarSpacingTests", code: 2)
            }
            for key in keys {
                let actual = CFPreferencesCopyValue(key as CFString, domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost) as? NSNumber
                guard actual?.intValue == 10 else {
                    throw NSError(domain: "MenuBarSpacingTests", code: 3)
                }
            }
            print("PASS: invalid offset preserves both preferences: \(invalid)")
        }
        print("All 11 menu bar spacing regression cases passed.")
    }
}
