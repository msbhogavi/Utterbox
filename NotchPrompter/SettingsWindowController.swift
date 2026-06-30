//
//  SettingsWindowController.swift
//  NotchPrompter
//
//  Created by Mallikarjun Bhogavi on 07/01/26.
//
import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private init() {
        let host = NSHostingController(rootView: SettingsRootView())

        let window = NSWindow(contentViewController: host)
        window.title = "Utterbox Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 720, height: 560))
        window.minSize = NSSize(width: 620, height: 480)
        window.isReleasedWhenClosed = false

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        guard let window else { return }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
