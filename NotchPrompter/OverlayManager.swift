//
//  OverlayManager.swift
//  NotchPrompter
//
//  Created by Mallikarjun Bhogavi on 02/01/26.
//
import AppKit
import SwiftUI

final class OverlayManager {
    private var stripPanel: KeyablePanel?
    private var notchPanel: KeyablePanel?
    private var leftResizePanel: KeyablePanel?
    private var rightResizePanel: KeyablePanel?
    private var bottomResizePanel: KeyablePanel?
    private var floatingPanel: KeyablePanel?
    private var stickyScreen: NSScreen?
    private var stickyResizeHandlesVisible = false
    private var isStickyResizeActive = false
    private var stickyMetrics = StickyNotchMetrics()

    var isVisible: Bool {
        stripPanel != nil || notchPanel != nil || floatingPanel != nil
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        hide()

        let targetScreen = ScreenSelection.currentTargetScreen() ?? NSScreen.main
        guard let screen = targetScreen else { return }

        switch OverlaySettings.getWindowMode() {
        case .sticky:
            showSticky(on: screen)
        case .floating:
            showFloating(on: screen)
        }
    }

    func hide() {
        stripPanel?.orderOut(nil); stripPanel = nil
        notchPanel?.orderOut(nil); notchPanel = nil
        leftResizePanel?.orderOut(nil); leftResizePanel = nil
        rightResizePanel?.orderOut(nil); rightResizePanel = nil
        bottomResizePanel?.orderOut(nil); bottomResizePanel = nil
        stickyScreen = nil
        stickyResizeHandlesVisible = false
        isStickyResizeActive = false

        if let fp = floatingPanel {
            UserDefaults.standard.set(Double(fp.frame.width), forKey: DefaultsKey.floatingWidthSaved)
            UserDefaults.standard.set(Double(fp.frame.height), forKey: DefaultsKey.floatingHeightSaved)
            UserDefaults.standard.set(Double(fp.frame.minX), forKey: DefaultsKey.floatingXSaved)
            UserDefaults.standard.set(Double(fp.frame.minY), forKey: DefaultsKey.floatingYSaved)
            fp.orderOut(nil)
        }
        floatingPanel = nil
    }

    // MARK: Sticky: strip (visual) + notchPanel (interactive, view-only)
    private func showSticky(on screen: NSScreen) {
        NotificationCenter.default.post(name: .overlayShowControlsInNotch, object: false)
        stickyScreen = screen

        let wSaved = CGFloat(UserDefaults.standard.double(forKey: DefaultsKey.notchWidthSaved))
        let hSaved = CGFloat(UserDefaults.standard.double(forKey: DefaultsKey.notchHeightSaved))
        let notchWidth: CGFloat = max(Layout.minNotchWidth, wSaved > 0 ? wSaved : Layout.defaultNotchWidth)
        let notchHeight: CGFloat = max(Layout.minNotchHeight, hSaved > 0 ? hSaved : Layout.defaultNotchHeight)
        stickyMetrics.width = notchWidth
        stickyMetrics.height = notchHeight

        let boxWidth: CGFloat = max(200, notchWidth - Layout.notchBoxInsetW)
        let boxHeight: CGFloat = max(90, notchHeight - Layout.notchBoxInsetH)

        // 1) Strip panel (background only)
        do {
            let stripView = NotchStripBackgroundNSView(
                metrics: stickyMetrics,
                topRadius: 14,
                shoulderRadius: 10
            )

            let sp = makePanel(
                frame: NSRect(x: screen.frame.minX,
                              y: screen.frame.maxY - Layout.stripHeight,
                              width: screen.frame.width,
                              height: Layout.stripHeight),
                resizable: false,
                shadow: false,
                clickThrough: true
            )

            stripView.frame = NSRect(origin: .zero, size: sp.frame.size)
            stripView.autoresizingMask = [.width, .height]
            sp.contentView = stripView

            sp.orderFrontRegardless()
            self.stripPanel = sp
        }

        guard let stripPanel = self.stripPanel else { return }
        let stripFrame = stripPanel.frame

        // 2) Notch panel (interactive content box)
        do {
            let notchContent = OverlayContentView(windowMode: .sticky)
            let notchHost = NSHostingView(rootView: notchContent)

            let frame = stickyContentFrame(stripFrame: stripFrame,
                                           notchWidth: notchWidth,
                                           notchHeight: notchHeight,
                                           boxWidth: boxWidth,
                                           boxHeight: boxHeight)

            let np = makePanel(
                frame: frame,
                resizable: false,
                shadow: false,
                clickThrough: false
            )

            notchHost.frame = NSRect(origin: .zero, size: np.frame.size)
            notchHost.autoresizingMask = [.width, .height]
            np.contentView = notchHost

            np.orderFrontRegardless()
            np.makeKeyAndOrderFront(nil as Any?)
            self.notchPanel = np
        }

        layoutStickyResizePanels(notchWidth: notchWidth, notchHeight: notchHeight, bringToFront: true)
        setStickyResizeHandlesVisible(false)
    }

    func resizeStickyNotch(to size: CGSize, persist: Bool = true) {
        guard stickyScreen != nil,
              let stripPanel,
              let notchPanel,
              OverlaySettings.getWindowMode() == .sticky else { return }

        let notchWidth = min(900, max(Layout.minNotchWidth, size.width))
        let notchHeight = min(220, max(Layout.minNotchHeight, size.height))
        if persist {
            UserDefaults.standard.set(Double(notchWidth), forKey: DefaultsKey.notchWidthSaved)
            UserDefaults.standard.set(Double(notchHeight), forKey: DefaultsKey.notchHeightSaved)
        }
        stickyMetrics.width = notchWidth
        stickyMetrics.height = notchHeight
        if let stripView = stripPanel.contentView as? NotchStripBackgroundNSView {
            stripView.notchWidth = notchWidth
            stripView.notchHeight = notchHeight
        }

        let boxWidth = max(200, notchWidth - Layout.notchBoxInsetW)
        let boxHeight = max(90, notchHeight - Layout.notchBoxInsetH)
        let stripFrame = stripPanel.frame
        let frame = stickyContentFrame(stripFrame: stripFrame,
                                       notchWidth: notchWidth,
                                       notchHeight: notchHeight,
                                       boxWidth: boxWidth,
                                       boxHeight: boxHeight)

        notchPanel.setFrame(frame, display: false)
        notchPanel.contentView?.frame = NSRect(origin: .zero, size: frame.size)
        layoutStickyResizePanels(notchWidth: notchWidth, notchHeight: notchHeight, bringToFront: false)
    }

    func persistCurrentStickyNotchSize() {
        UserDefaults.standard.set(Double(stickyMetrics.width), forKey: DefaultsKey.notchWidthSaved)
        UserDefaults.standard.set(Double(stickyMetrics.height), forKey: DefaultsKey.notchHeightSaved)
    }

    func setStickyResizeHandlesVisible(_ visible: Bool) {
        stickyResizeHandlesVisible = visible
        [leftResizePanel, rightResizePanel, bottomResizePanel].forEach { panel in
            if let resizeView = panel?.contentView as? StickyResizeHandleNSView {
                resizeView.isGloballyVisible = visible
            }
            panel?.orderFrontRegardless()
        }
        if visible {
            notchPanel?.orderFrontRegardless()
            [leftResizePanel, rightResizePanel, bottomResizePanel].forEach {
                $0?.orderFrontRegardless()
            }
        }
    }

    private func layoutStickyResizePanels(notchWidth: CGFloat, notchHeight: CGFloat, bringToFront: Bool) {
        guard let stripPanel, let notchPanel else { return }

        let stripFrame = stripPanel.frame
        let visualNotchFrame = NSRect(
            x: stripFrame.midX - notchWidth / 2,
            y: stripFrame.maxY - notchHeight,
            width: notchWidth,
            height: notchHeight
        )
        let sideWidth: CGFloat = 34
        let sideHeight: CGFloat = min(120, max(72, visualNotchFrame.height * 0.72))
        let sideY = visualNotchFrame.midY - sideHeight / 2
        let sideGap: CGFloat = 3

        let bottomWidth: CGFloat = min(150, max(92, visualNotchFrame.width * 0.32))
        let bottomHeight: CGFloat = 34
        let bottomGap: CGFloat = 3

        let leftFrame = NSRect(
            x: visualNotchFrame.minX - sideGap - sideWidth,
            y: sideY,
            width: sideWidth,
            height: sideHeight
        )
        let rightFrame = NSRect(
            x: visualNotchFrame.maxX + sideGap,
            y: sideY,
            width: sideWidth,
            height: sideHeight
        )
        let bottomFrame = NSRect(
            x: visualNotchFrame.midX - bottomWidth / 2,
            y: visualNotchFrame.minY - bottomGap - bottomHeight,
            width: bottomWidth,
            height: bottomHeight
        )

        leftResizePanel = makeOrUpdateResizePanel(leftResizePanel,
                                                  frame: leftFrame,
                                                  placement: .left,
                                                  notchWidth: notchWidth,
                                                  notchHeight: notchHeight)
        rightResizePanel = makeOrUpdateResizePanel(rightResizePanel,
                                                   frame: rightFrame,
                                                   placement: .right,
                                                   notchWidth: notchWidth,
                                                   notchHeight: notchHeight)
        bottomResizePanel = makeOrUpdateResizePanel(bottomResizePanel,
                                                    frame: bottomFrame,
                                                    placement: .bottom,
                                                    notchWidth: notchWidth,
                                                    notchHeight: notchHeight)

        if bringToFront {
            stripPanel.orderFrontRegardless()
            notchPanel.orderFrontRegardless()
        }
        [leftResizePanel, rightResizePanel, bottomResizePanel].forEach {
            $0?.level = .statusBar
        }
        if bringToFront {
            setStickyResizeHandlesVisible(stickyResizeHandlesVisible)
        }
    }

    private func makeOrUpdateResizePanel(_ panel: KeyablePanel?,
                                         frame: NSRect,
                                         placement: StickyResizePlacement,
                                         notchWidth: CGFloat,
                                         notchHeight: CGFloat) -> KeyablePanel {
        let p: KeyablePanel
        if let panel {
            p = panel
            p.setFrame(frame, display: false)
        } else {
            p = makePanel(frame: frame, resizable: false, shadow: false, clickThrough: false)
            let resizeView = StickyResizeHandleNSView(
                placement: placement,
                currentSize: { [weak self] in
                    self?.currentStickyNotchSize() ?? CGSize(width: notchWidth, height: notchHeight)
                },
                onHoverChanged: { hovering in
                    NotificationCenter.default.post(name: .overlayShowStickyResizeHandles, object: hovering)
                },
                onResizeBegan: { [weak self] in
                    self?.beginStickyResize()
                },
                onResize: { [weak self] nextSize in
                    self?.resizeStickyNotch(to: nextSize, persist: false)
                },
                onResizeEnded: { [weak self] in
                    self?.endStickyResize()
                }
            )
            p.contentView = resizeView
        }

        if let resizeView = p.contentView as? StickyResizeHandleNSView {
            resizeView.placement = placement
            resizeView.isGloballyVisible = stickyResizeHandlesVisible
            resizeView.frame = NSRect(origin: .zero, size: frame.size)
            resizeView.needsDisplay = true
            resizeView.window?.invalidateCursorRects(for: resizeView)
        }
        return p
    }

    private func currentStickyNotchSize() -> CGSize {
        CGSize(width: stickyMetrics.width, height: stickyMetrics.height)
    }

    private func stickyContentFrame(stripFrame: NSRect,
                                    notchWidth: CGFloat,
                                    notchHeight: CGFloat,
                                    boxWidth: CGFloat,
                                    boxHeight: CGFloat) -> NSRect {
        let notchFrame = NSRect(x: stripFrame.midX - notchWidth / 2,
                                y: stripFrame.maxY - notchHeight,
                                width: notchWidth,
                                height: notchHeight)
        return NSRect(x: notchFrame.midX - boxWidth / 2,
                      y: notchFrame.midY - boxHeight / 2 + Layout.stickyContentYOffset,
                      width: boxWidth,
                      height: boxHeight)
    }

    private func beginStickyResize() {
        isStickyResizeActive = true
    }

    private func endStickyResize() {
        isStickyResizeActive = false
        persistCurrentStickyNotchSize()
        layoutStickyResizePanels(notchWidth: stickyMetrics.width,
                                 notchHeight: stickyMetrics.height,
                                 bringToFront: true)
    }

    // MARK: Floating: resizable
    private func showFloating(on screen: NSScreen) {
        NotificationCenter.default.post(name: .overlayShowControlsInNotch, object: true)

        let contentView = OverlayContentView(windowMode: .floating)
        let host = NSHostingView(rootView: contentView)

        let savedW = CGFloat(UserDefaults.standard.double(forKey: DefaultsKey.floatingWidthSaved))
        let savedH = CGFloat(UserDefaults.standard.double(forKey: DefaultsKey.floatingHeightSaved))
        let savedX = CGFloat(UserDefaults.standard.double(forKey: DefaultsKey.floatingXSaved))
        let savedY = CGFloat(UserDefaults.standard.double(forKey: DefaultsKey.floatingYSaved))

        let w = (savedW > 0 ? savedW : 560)
        let h = (savedH > 0 ? savedH : 360)

        let defaultX = screen.frame.midX - w / 2
        let defaultY = screen.frame.maxY - h - 120
        let savedOrigin = CGPoint(x: savedX, y: savedY)
        let hasSavedOrigin = savedX != 0 || savedY != 0
        let visibleFrame = screen.visibleFrame.insetBy(dx: 24, dy: 24)
        let savedFrame = NSRect(origin: savedOrigin, size: NSSize(width: w, height: h))
        let useSavedOrigin = hasSavedOrigin && visibleFrame.intersects(savedFrame)

        let x = useSavedOrigin ? savedX : defaultX
        let y = useSavedOrigin ? savedY : defaultY

        let p = makePanel(
            frame: NSRect(x: x, y: y, width: w, height: h),
            resizable: true,
            shadow: true,
            clickThrough: false
        )

        p.minSize = NSSize(width: 420, height: 260)
        p.isMovableByWindowBackground = true

        host.frame = NSRect(origin: .zero, size: p.frame.size)
        host.autoresizingMask = [.width, .height]
        p.contentView = host

        p.orderFrontRegardless()
        p.makeKeyAndOrderFront(nil as Any?)
        self.floatingPanel = p
    }

    // MARK: Panel factory
    private func makePanel(frame: NSRect, resizable: Bool, shadow: Bool, clickThrough: Bool) -> KeyablePanel {
        var style: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
        if resizable { style.insert(.resizable) }

        let p = KeyablePanel(contentRect: frame, styleMask: style, backing: .buffered, defer: false)

        p.isFloatingPanel = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = shadow
        p.hidesOnDeactivate = false
        p.isExcludedFromWindowsMenu = true
        p.sharingType = .none
        p.acceptsMouseMovedEvents = true

        p.ignoresMouseEvents = clickThrough
        return p
    }
}

// MARK: - Strip background
final class StickyNotchMetrics: ObservableObject {
    @Published var width: CGFloat = Layout.defaultNotchWidth
    @Published var height: CGFloat = Layout.defaultNotchHeight
}

struct NotchStripBackgroundView: View {
    @ObservedObject var metrics: StickyNotchMetrics
    let topRadius: CGFloat
    let shoulderRadius: CGFloat

    var body: some View {
        GeometryReader { geo in
            MacbookNotchFullWidth(
                notchWidth: metrics.width,
                notchHeight: metrics.height,
                topRadius: topRadius,
                shoulderRadius: shoulderRadius
            )
            .fill(Color.black)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .background(Color.clear)
    }
}

private final class NotchStripBackgroundNSView: NSView {
    var notchWidth: CGFloat {
        didSet { needsDisplay = true }
    }
    var notchHeight: CGFloat {
        didSet { needsDisplay = true }
    }
    let topRadius: CGFloat
    let shoulderRadius: CGFloat

    override var isFlipped: Bool { true }

    init(metrics: StickyNotchMetrics, topRadius: CGFloat, shoulderRadius: CGFloat) {
        self.notchWidth = metrics.width
        self.notchHeight = metrics.height
        self.topRadius = topRadius
        self.shoulderRadius = shoulderRadius
        super.init(frame: .zero)
        wantsLayer = true
        layer?.drawsAsynchronously = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.clear.setFill()
        bounds.fill()
        NSColor.black.setFill()
        notchPath(in: bounds).fill()
    }

    private func notchPath(in rect: CGRect) -> NSBezierPath {
        let path = NSBezierPath()
        let midX = rect.midX
        let notchLeft = midX - (notchWidth / 2)
        let notchRight = midX + (notchWidth / 2)

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.line(to: CGPoint(x: notchLeft - shoulderRadius, y: rect.minY))

        path.appendArc(withCenter: CGPoint(x: notchLeft - shoulderRadius, y: rect.minY + shoulderRadius),
                       radius: shoulderRadius,
                       startAngle: 270,
                       endAngle: 360,
                       clockwise: false)

        path.line(to: CGPoint(x: notchLeft, y: rect.minY + notchHeight - topRadius))

        path.appendArc(withCenter: CGPoint(x: notchLeft + topRadius, y: rect.minY + notchHeight - topRadius),
                       radius: topRadius,
                       startAngle: 180,
                       endAngle: 90,
                       clockwise: true)

        path.line(to: CGPoint(x: notchRight - topRadius, y: rect.minY + notchHeight))

        path.appendArc(withCenter: CGPoint(x: notchRight - topRadius, y: rect.minY + notchHeight - topRadius),
                       radius: topRadius,
                       startAngle: 90,
                       endAngle: 0,
                       clockwise: true)

        path.line(to: CGPoint(x: notchRight, y: rect.minY + shoulderRadius))

        path.appendArc(withCenter: CGPoint(x: notchRight + shoulderRadius, y: rect.minY + shoulderRadius),
                       radius: shoulderRadius,
                       startAngle: 180,
                       endAngle: 270,
                       clockwise: false)

        path.line(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.close()
        return path
    }
}

private enum StickyResizePlacement {
    case left
    case right
    case bottom

    var cursor: NSCursor {
        switch self {
        case .left, .right:
            return .resizeLeftRight
        case .bottom:
            return .resizeUpDown
        }
    }

    var helpText: String {
        switch self {
        case .left, .right:
            return "Drag to resize notch width"
        case .bottom:
            return "Drag to resize notch height"
        }
    }
}

private final class StickyResizeHandleNSView: NSView {
    var placement: StickyResizePlacement {
        didSet {
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }

    private let currentSize: () -> CGSize
    private let onHoverChanged: (Bool) -> Void
    private let onResizeBegan: () -> Void
    private let onResize: (CGSize) -> Void
    private let onResizeEnded: () -> Void
    private var dragStartSize: CGSize?
    private var dragStartLocation: NSPoint?
    private var isHovering = false
    private var isDragging = false
    var isGloballyVisible = false {
        didSet { needsDisplay = true }
    }

    init(placement: StickyResizePlacement,
         currentSize: @escaping () -> CGSize,
         onHoverChanged: @escaping (Bool) -> Void,
         onResizeBegan: @escaping () -> Void,
         onResize: @escaping (CGSize) -> Void,
         onResizeEnded: @escaping () -> Void) {
        self.placement = placement
        self.currentSize = currentSize
        self.onHoverChanged = onHoverChanged
        self.onResizeBegan = onResizeBegan
        self.onResize = onResize
        self.onResizeEnded = onResizeEnded
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited,
                                                 .mouseMoved,
                                                 .cursorUpdate,
                                                 .activeAlways,
                                                 .inVisibleRect,
                                                 .enabledDuringMouseDrag],
                                       owner: self,
                                       userInfo: nil))
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: placement.cursor)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        window?.invalidateCursorRects(for: self)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func cursorUpdate(with event: NSEvent) {
        placement.cursor.set()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        onHoverChanged(true)
        placement.cursor.set()
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        placement.cursor.set()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        if !isDragging {
            onHoverChanged(false)
        }
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        dragStartSize = currentSize()
        dragStartLocation = event.locationInWindow
        isDragging = true
        onResizeBegan()
        onHoverChanged(true)
        placement.cursor.set()
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStartSize, let dragStartLocation else { return }
        let point = event.locationInWindow
        let dx = point.x - dragStartLocation.x
        let dy = point.y - dragStartLocation.y

        switch placement {
        case .left:
            onResize(CGSize(width: dragStartSize.width - dx * 2, height: dragStartSize.height))
        case .right:
            onResize(CGSize(width: dragStartSize.width + dx * 2, height: dragStartSize.height))
        case .bottom:
            onResize(CGSize(width: dragStartSize.width, height: dragStartSize.height - dy))
        }
    }

    override func mouseUp(with event: NSEvent) {
        dragStartSize = nil
        dragStartLocation = nil
        isDragging = false
        onResizeEnded()
        onHoverChanged(isHovering)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.clear.setFill()
        bounds.fill()

        guard isGloballyVisible || isHovering || isDragging else { return }

        let alpha: CGFloat = (isHovering || isDragging) ? 0.92 : 0.48
        NSColor.white.withAlphaComponent(alpha).setFill()

        switch placement {
        case .left, .right:
            let x = placement == .left ? bounds.maxX - 5 : bounds.minX
            let barRect = NSRect(x: x,
                                 y: bounds.midY - min(52, bounds.height * 0.42),
                                 width: 5,
                                 height: min(104, bounds.height * 0.84))
            NSBezierPath(roundedRect: barRect, xRadius: 2.5, yRadius: 2.5).fill()
        case .bottom:
            let barRect = NSRect(x: bounds.midX - min(61, bounds.width * 0.40),
                                 y: bounds.maxY - 5,
                                 width: min(122, bounds.width * 0.80),
                                 height: 5)
            NSBezierPath(roundedRect: barRect, xRadius: 2.5, yRadius: 2.5).fill()
        }
    }
}

final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// Notch shape
struct MacbookNotchFullWidth: Shape {
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var topRadius: CGFloat
    var shoulderRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midX = rect.midX
        let notchLeft = midX - (notchWidth / 2)
        let notchRight = midX + (notchWidth / 2)

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: notchLeft - shoulderRadius, y: rect.minY))

        path.addArc(center: CGPoint(x: notchLeft - shoulderRadius, y: rect.minY + shoulderRadius),
                    radius: shoulderRadius,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(0),
                    clockwise: false)

        path.addLine(to: CGPoint(x: notchLeft, y: rect.minY + notchHeight - topRadius))

        path.addArc(center: CGPoint(x: notchLeft + topRadius, y: rect.minY + notchHeight - topRadius),
                    radius: topRadius,
                    startAngle: .degrees(180),
                    endAngle: .degrees(90),
                    clockwise: true)

        path.addLine(to: CGPoint(x: notchRight - topRadius, y: rect.minY + notchHeight))

        path.addArc(center: CGPoint(x: notchRight - topRadius, y: rect.minY + notchHeight - topRadius),
                    radius: topRadius,
                    startAngle: .degrees(90),
                    endAngle: .degrees(0),
                    clockwise: true)

        path.addLine(to: CGPoint(x: notchRight, y: rect.minY + shoulderRadius))

        path.addArc(center: CGPoint(x: notchRight + shoulderRadius, y: rect.minY + shoulderRadius),
                    radius: shoulderRadius,
                    startAngle: .degrees(180),
                    endAngle: .degrees(270),
                    clockwise: false)

        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
