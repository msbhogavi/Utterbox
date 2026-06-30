//
//  ScreenSelection.swift
//  NotchPrompter
//
//  Created by Mallikarjun Bhogavi on 02/01/26.
//

import AppKit

enum ScreenSelection {
    static let defaultsKey = "selectedDisplayName"

    static func availableDisplayNames() -> [String] {
        NSScreen.screens.map { $0.localizedName }
    }

    static func currentTargetScreen() -> NSScreen? {
        let selectedName = UserDefaults.standard.string(forKey: defaultsKey)

        // Default: prefer Mac/built-in screen if possible
        if selectedName == nil || selectedName?.isEmpty == true {
            return NSScreen.screens.first(where: { nameLooksBuiltIn($0.localizedName) }) ?? NSScreen.main
        }

        if let selectedName {
            return NSScreen.screens.first(where: { $0.localizedName == selectedName }) ?? NSScreen.main
        }

        return NSScreen.main
    }

    private static func nameLooksBuiltIn(_ name: String) -> Bool {
        let n = name.lowercased()
        return n.contains("built") || n.contains("macbook") || n.contains("retina")
    }
}
