//
//  AppDelegate.swift
//  NotchPrompter
//
//  Created by Mallikarjun Bhogavi on 02/01/26.
//
import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let overlayManager = OverlayManager()
    private let settingsWC = SettingsWindowController.shared
    private let splashWC = SplashHUDWindowController()

    private let state = AppState.shared

    private var overlayEnabledItem: NSMenuItem!
    private var launchAtLoginItem: NSMenuItem!
    private var stickyItem: NSMenuItem!
    private var floatingItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        splashWC.showForTwoSeconds()
        GlobalHotKeyManager.shared.register()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleOverlayToggle),
                                               name: .overlayToggle,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleOverlayRefresh),
                                               name: .overlayRefresh,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleStickyNotchResize(_:)),
                                               name: .overlayResizeStickyNotch,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleStickyResizeHandleVisibility(_:)),
                                               name: .overlayShowStickyResizeHandles,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(makeNotchWider),
                                               name: OverlayCommand.notchWider,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(makeNotchNarrower),
                                               name: OverlayCommand.notchNarrower,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(makeNotchTaller),
                                               name: OverlayCommand.notchTaller,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(makeNotchShorter),
                                               name: OverlayCommand.notchShorter,
                                               object: nil)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let img = makeStatusIcon()
            img?.isTemplate = true
            img?.size = NSSize(width: 18, height: 18)
            button.image = img
        }

        let menu = NSMenu()

        overlayEnabledItem = NSMenuItem(title: "Overlay Enabled", action: #selector(toggleOverlayEnabled), keyEquivalent: "")
        overlayEnabledItem.target = self
        menu.addItem(overlayEnabledItem)

        menu.addItem(.separator())

        let modeMenu = NSMenu()
        stickyItem = NSMenuItem(title: OverlayWindowMode.sticky.displayName, action: #selector(setStickyMode), keyEquivalent: "")
        stickyItem.target = self
        floatingItem = NSMenuItem(title: OverlayWindowMode.floating.displayName, action: #selector(setFloatingMode), keyEquivalent: "")
        floatingItem.target = self
        modeMenu.addItem(stickyItem)
        modeMenu.addItem(floatingItem)

        let modeItem = NSMenuItem(title: "Camera Placement", action: nil, keyEquivalent: "")
        modeItem.submenu = modeMenu
        menu.addItem(modeItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu

        state.windowMode = OverlaySettings.getWindowMode()
        refreshMenuChecks()
    }

    private func makeStatusIcon() -> NSImage? {
        if let assetImage = NSImage(named: "StatusIcon") {
            return assetImage
        }

        if let url = Bundle.main.url(forResource: "StatusIcon", withExtension: "pdf"),
           let pdfImage = NSImage(contentsOf: url) {
            return pdfImage
        }

        return NSImage(systemSymbolName: "text.alignleft", accessibilityDescription: "Utterbox")
    }

    @objc private func toggleOverlayEnabled() {
        if overlayManager.isVisible {
            overlayManager.hide()
            state.overlayEnabled = false
        } else {
            overlayManager.show()
            state.overlayEnabled = true
        }
        refreshMenuChecks()
    }

    @objc private func handleOverlayToggle() {
        toggleOverlayEnabled()
    }

    @objc private func handleOverlayRefresh() {
        state.windowMode = OverlaySettings.getWindowMode()
        guard state.overlayEnabled || overlayManager.isVisible else {
            refreshMenuChecks()
            return
        }

        overlayManager.show()
        state.overlayEnabled = true
        refreshMenuChecks()
    }

    @objc private func handleStickyNotchResize(_ note: Notification) {
        guard let size = note.object as? CGSize else { return }
        overlayManager.resizeStickyNotch(to: size)
        state.overlayEnabled = overlayManager.isVisible
        refreshMenuChecks()
    }

    @objc private func handleStickyResizeHandleVisibility(_ note: Notification) {
        let visible = (note.object as? Bool) ?? false
        overlayManager.setStickyResizeHandlesVisible(visible)
    }

    @objc private func setStickyMode() {
        OverlaySettings.setWindowMode(.sticky)
        state.windowMode = .sticky
        if state.overlayEnabled || overlayManager.isVisible {
            overlayManager.show()
            state.overlayEnabled = true
        }
        refreshMenuChecks()
    }

    @objc private func setFloatingMode() {
        OverlaySettings.setWindowMode(.floating)
        state.windowMode = .floating
        if state.overlayEnabled || overlayManager.isVisible {
            overlayManager.show()
            state.overlayEnabled = true
        }
        refreshMenuChecks()
    }

    @objc private func openSettings() {
        settingsWC.show()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            print("Launch at Login toggle failed: \(error)")
        }
        refreshMenuChecks()
    }

    private func refreshMenuChecks() {
        state.overlayEnabled = overlayManager.isVisible
        overlayEnabledItem.state = state.overlayEnabled ? .on : .off
        let mode = OverlaySettings.getWindowMode()
        stickyItem.state = (mode == .sticky) ? .on : .off
        floatingItem.state = (mode == .floating) ? .on : .off
        launchAtLoginItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        GlobalHotKeyManager.shared.unregisterAll()
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func makeNotchWider() {
        adjustSavedNotch(widthDelta: 20, heightDelta: 0)
    }

    @objc private func makeNotchNarrower() {
        adjustSavedNotch(widthDelta: -20, heightDelta: 0)
    }

    @objc private func makeNotchTaller() {
        adjustSavedNotch(widthDelta: 0, heightDelta: 10)
    }

    @objc private func makeNotchShorter() {
        adjustSavedNotch(widthDelta: 0, heightDelta: -10)
    }

    private func adjustSavedNotch(widthDelta: CGFloat, heightDelta: CGFloat) {
        let savedWidth = CGFloat(UserDefaults.standard.double(forKey: DefaultsKey.notchWidthSaved))
        let savedHeight = CGFloat(UserDefaults.standard.double(forKey: DefaultsKey.notchHeightSaved))
        let width = savedWidth > 0 ? savedWidth : Layout.defaultNotchWidth
        let height = savedHeight > 0 ? savedHeight : Layout.defaultNotchHeight

        let nextWidth = min(900, max(Layout.minNotchWidth, width + widthDelta))
        let nextHeight = min(220, max(Layout.minNotchHeight, height + heightDelta))
        UserDefaults.standard.set(Double(nextWidth), forKey: DefaultsKey.notchWidthSaved)
        UserDefaults.standard.set(Double(nextHeight), forKey: DefaultsKey.notchHeightSaved)
        handleOverlayRefresh()
    }
}
