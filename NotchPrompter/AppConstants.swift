//
//  AppConstants.swift
//  NotchPrompter
//
//  Created by Mallikarjun Bhogavi on 05/01/26.
//
import Foundation
import AppKit

enum DefaultsKey {
    static let currentScript = "currentScript"
    static let rememberCurrentScript = "rememberCurrentScript"
    static let prompterSpeed = "prompterSpeed"
    static let prompterFontSize = "prompterFontSize"
    static let voiceFollowEnabled = "voiceFollowEnabled"
    static let selectedMicrophoneID = "selectedMicrophoneID"
    static let speechRecognitionMode = "speechRecognitionMode"

    static let notchWidthSaved = "notchWidthSaved"
    static let notchHeightSaved = "notchHeightSaved"

    static let selectedDisplayName = "selectedDisplayName"
    static let overlayWindowMode = "overlayWindowMode"

    static let floatingWidthSaved = "floatingWidthSaved"
    static let floatingHeightSaved = "floatingHeightSaved"
    static let floatingXSaved = "floatingXSaved"
    static let floatingYSaved = "floatingYSaved"
}

enum SpeechRecognitionMode: String, CaseIterable, Identifiable {
    case onDeviceOnly = "onDeviceOnly"
    case allowServerFallback = "allowServerFallback"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .onDeviceOnly:
            return "On-device only"
        case .allowServerFallback:
            return "Allow server fallback"
        }
    }

    var detail: String {
        switch self {
        case .onDeviceOnly:
            return "Keeps recognition local. Voice follow stays off if this Mac cannot run speech on-device."
        case .allowServerFallback:
            return "Lets macOS use Apple's servers when local recognition is unavailable. Script cue words may leave the device."
        }
    }

    static func fromDefaults() -> SpeechRecognitionMode {
        let raw = UserDefaults.standard.string(forKey: DefaultsKey.speechRecognitionMode) ?? Self.onDeviceOnly.rawValue
        return Self(rawValue: raw) ?? .onDeviceOnly
    }
}

extension Notification.Name {
    static let overlayShowControlsInNotch = Notification.Name("OverlayUI.showControlsInNotch")
    static let overlayShowStickyResizeHandles = Notification.Name("OverlayUI.showStickyResizeHandles")
    static let overlayToggle = Notification.Name("OverlayCommand.toggleOverlay")
    static let overlayRefresh = Notification.Name("OverlayCommand.refreshOverlay")
    static let overlayResizeStickyNotch = Notification.Name("OverlayCommand.resizeStickyNotch")
}

/// All UI/timing/layout constants
enum Layout {
    static let defaultScript = "Paste your script here."
    static let maxImportFileBytes = 2_000_000

    // ===== Sticky layout (used by OverlayManager) =====
    static let stripHeight: CGFloat = 260
    static let topInsetInStrip: CGFloat = 35
    static let notchBoxInsetW: CGFloat = 44
    static let notchBoxInsetH: CGFloat = 28
    static let stickyContentYOffset: CGFloat = -4

    // ===== Scroll =====
    static let tickHz: Double = 30
    static let maxDt: Double = 0.05
    static let lineSpacing: CGFloat = 6

    // ===== Overlay visuals =====
    static let stickyCornerRadius: CGFloat = 8
    static let floatingCornerRadius: CGFloat = 18
    static let stickyPadding: CGFloat = 10
    static let floatingPadding: CGFloat = 8

    // ===== Floating appearance =====
    static let floatingBackgroundOpacity: CGFloat = 0.65
    static let stickyBackgroundOpacity: CGFloat = 0.0
    static let floatingStrokeOpacity: CGFloat = 0.10
    static let controlsBackgroundOpacity: CGFloat = 0.55
    static let controlsCornerRadius: CGFloat = 12

    // ===== Sticky hotspot + mini controls =====
    static let stickyHotspotWidth: CGFloat = 180
    static let stickyHotspotHeight: CGFloat = 42
    static let stickyMiniControlsAutoHideSeconds: Double = 1.2
    static let stickyMiniControlsFadeIn: Double = 0.12
    static let stickyMiniControlsFadeOut: Double = 0.18

    // ===== Notch size bounds/defaults =====
    static let minNotchWidth: CGFloat = 260
    static let minNotchHeight: CGFloat = 90
    static let defaultNotchWidth: CGFloat = 360
    static let defaultNotchHeight: CGFloat = 130
}
