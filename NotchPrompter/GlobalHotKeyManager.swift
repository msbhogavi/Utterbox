//
//  GlobalHotKeyManager.swift
//  NotchPrompter
//
//  Created by Mallikarjun Bhogavi on 02/01/26.
//
import Foundation
import Carbon
import AppKit

final class GlobalHotKeyManager {
    static let shared = GlobalHotKeyManager()

    private var hotKeyRefs: [EventHotKeyRef?] = []

    private enum HotKeyID: UInt32 {
        case toggleEditPrompt = 1
        case toggleOverlay = 2
        case playPause = 3
        case resetToTop = 4
        case speedUp = 5
        case speedDown = 6
        case notchHeightUp = 7
        case notchHeightDown = 8
        case notchWidthUp = 9
        case notchWidthDown = 10
    }

    func register() {
        unregisterAll()
        installHandlerIfNeeded()

        let appChord = UInt32(cmdKey) | UInt32(optionKey) | UInt32(controlKey)
        let appShiftChord = appChord | UInt32(shiftKey)

        // Control+Option+Command+P -> Toggle overlay
        registerHotKey(
            keyCode: UInt32(kVK_ANSI_P),
            modifiers: appChord,
            id: HotKeyID.toggleOverlay.rawValue
        )

        // Control+Option+Command+E -> Toggle edit/readiness
        registerHotKey(
            keyCode: UInt32(kVK_ANSI_E),
            modifiers: appChord,
            id: HotKeyID.toggleEditPrompt.rawValue
        )

        // Control+Option+Command+Space -> Play/Pause
        registerHotKey(
            keyCode: UInt32(kVK_Space),
            modifiers: appChord,
            id: HotKeyID.playPause.rawValue
        )

        // Control+Option+Command+R -> Reset to top
        registerHotKey(
            keyCode: UInt32(kVK_ANSI_R),
            modifiers: appChord,
            id: HotKeyID.resetToTop.rawValue
        )

        // Control+Option+Command+Up -> Speed up
        registerHotKey(
            keyCode: UInt32(kVK_UpArrow),
            modifiers: appChord,
            id: HotKeyID.speedUp.rawValue
        )

        // Control+Option+Command+Down -> Speed down
        registerHotKey(
            keyCode: UInt32(kVK_DownArrow),
            modifiers: appChord,
            id: HotKeyID.speedDown.rawValue
        )

        // Control+Option+Shift+Command+Up -> notch height up
        registerHotKey(
            keyCode: UInt32(kVK_UpArrow),
            modifiers: appShiftChord,
            id: HotKeyID.notchHeightUp.rawValue
        )

        // Control+Option+Shift+Command+Down -> notch height down
        registerHotKey(
            keyCode: UInt32(kVK_DownArrow),
            modifiers: appShiftChord,
            id: HotKeyID.notchHeightDown.rawValue
        )

        // Control+Option+Shift+Command+Right -> notch width up
        registerHotKey(
            keyCode: UInt32(kVK_RightArrow),
            modifiers: appShiftChord,
            id: HotKeyID.notchWidthUp.rawValue
        )

        // Control+Option+Shift+Command+Left -> notch width down
        registerHotKey(
            keyCode: UInt32(kVK_LeftArrow),
            modifiers: appShiftChord,
            id: HotKeyID.notchWidthDown.rawValue
        )
    }

    func unregisterAll() {
        for ref in hotKeyRefs {
            if let ref { UnregisterEventHotKey(ref) }
        }
        hotKeyRefs.removeAll()
    }

    private func registerHotKey(keyCode: UInt32, modifiers: UInt32, id: UInt32) {
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType("NTPR".fourCharCodeValue), id: id)

        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &hotKeyRef)
        if status == noErr {
            hotKeyRefs.append(hotKeyRef)
        } else {
            print("RegisterEventHotKey failed: \(status) for id=\(id)")
        }
    }

    private var handlerInstalled = false

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true

        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        InstallEventHandler(GetEventDispatcherTarget(), { (_, event, _) -> OSStatus in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )

            DispatchQueue.main.async {
                guard hotKeyID.signature == OSType("NTPR".fourCharCodeValue) else { return }

                switch hotKeyID.id {
                case HotKeyID.toggleEditPrompt.rawValue:
                    NotificationCenter.default.post(name: OverlayCommand.toggleEdit, object: nil)

                case HotKeyID.toggleOverlay.rawValue:
                    NotificationCenter.default.post(name: .overlayToggle, object: nil)

                case HotKeyID.playPause.rawValue:
                    NotificationCenter.default.post(name: OverlayCommand.playPause, object: nil)

                case HotKeyID.resetToTop.rawValue:
                    NotificationCenter.default.post(name: OverlayCommand.resetToTop, object: nil)

                case HotKeyID.speedUp.rawValue:
                    NotificationCenter.default.post(name: OverlayCommand.speedUp, object: nil)

                case HotKeyID.speedDown.rawValue:
                    NotificationCenter.default.post(name: OverlayCommand.speedDown, object: nil)

                case HotKeyID.notchHeightUp.rawValue:
                    NotificationCenter.default.post(name: OverlayCommand.notchTaller, object: nil)

                case HotKeyID.notchHeightDown.rawValue:
                    NotificationCenter.default.post(name: OverlayCommand.notchShorter, object: nil)

                case HotKeyID.notchWidthUp.rawValue:
                    NotificationCenter.default.post(name: OverlayCommand.notchWider, object: nil)

                case HotKeyID.notchWidthDown.rawValue:
                    NotificationCenter.default.post(name: OverlayCommand.notchNarrower, object: nil)

                default:
                    break
                }
            }

            return noErr
        }, 1, &eventSpec, nil, nil)
    }
}

private extension String {
    var fourCharCodeValue: FourCharCode {
        var result: FourCharCode = 0
        for scalar in unicodeScalars {
            result = (result << 8) + FourCharCode(scalar.value)
        }
        return result
    }
}
