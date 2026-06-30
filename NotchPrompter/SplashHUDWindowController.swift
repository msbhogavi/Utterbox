//
//  SplashHUDWindowController.swift
//  NotchPrompter
//
//  Created by Mallikarjun Bhogavi on 07/01/26.
//
import AppKit
import SwiftUI

final class SplashHUDWindowController {
    private var window: NSWindow?

    func showForTwoSeconds() {
        let view = SplashHUDView()
        let host = NSHostingView(rootView: view)

        let w: CGFloat = 280
        let h: CGFloat = 70

        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let x = screen.midX - w/2
        let y = screen.maxY - 140

        let win = NSWindow(
            contentRect: NSRect(x: x, y: y, width: w, height: h),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.level = .floating
        win.collectionBehavior = [.canJoinAllSpaces, .transient]
        win.contentView = host
        win.alphaValue = 0.0

        self.window = win
        win.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.20
            win.animator().alphaValue = 1.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.25
                win.animator().alphaValue = 0.0
            }, completionHandler: {
                win.orderOut(nil)
                self.window = nil
            })
        }
    }
}

private struct SplashHUDView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.75))
            VStack(spacing: 4) {
                Text("Utterbox")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Running in menu bar")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .padding(8)
    }
}
