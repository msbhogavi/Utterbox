//
//  OverlaySettings.swift
//  NotchPrompter
//
//  Created by Mallikarjun Bhogavi on 03/01/26.
//
import Foundation

enum OverlayWindowMode: String, CaseIterable, Identifiable {
    case sticky = "macBookCamera"
    case floating = "externalCamera"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sticky:
            return "MacBook Camera"
        case .floating:
            return "External Camera"
        }
    }

    var detail: String {
        switch self {
        case .sticky:
            return "Prompt from the notch/camera line."
        case .floating:
            return "Place the prompter near an external webcam."
        }
    }
}

enum OverlaySettings {
    static func getWindowMode() -> OverlayWindowMode {
        let raw = UserDefaults.standard.string(forKey: DefaultsKey.overlayWindowMode)
            ?? OverlayWindowMode.sticky.rawValue
        if raw == "Sticky (Notch)" { return .sticky }
        if raw == "Floating" { return .floating }
        return OverlayWindowMode(rawValue: raw) ?? .sticky
    }

    static func setWindowMode(_ mode: OverlayWindowMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: DefaultsKey.overlayWindowMode)
    }
}
