//
//  OverlayContentView.swift
//  NotchPrompter
//
//  Created by Mallikarjun Bhogavi on 02/01/26.
//
import SwiftUI
import Combine
import AppKit

struct OverlayContentView: View {
    let windowMode: OverlayWindowMode
    @StateObject private var vm = PrompterViewModel()
    @StateObject private var speech = SpeechVoiceActivityDetector()

    // Sticky-only mini controls auto-hide using Task
    @State private var showStickyMiniControls: Bool = false
    @State private var hideTask: Task<Void, Never>?
    @State private var hoveringStickyHotspot = false
    @State private var hoveringStickyControls = false
    @State private var selectedMicrophoneID =
        UserDefaults.standard.string(forKey: DefaultsKey.selectedMicrophoneID) ?? ""

    var body: some View {
        ZStack(alignment: .top) {

            contentBody
                .padding(windowMode == .sticky ? Layout.stickyPadding : Layout.floatingPadding)
                .background(backgroundForMode)
                .overlay(
                    RoundedRectangle(
                        cornerRadius: windowMode == .floating ? Layout.floatingCornerRadius : Layout.stickyCornerRadius,
                        style: .continuous
                    )
                    .stroke(Color.white.opacity(windowMode == .floating ? Layout.floatingStrokeOpacity : 0), lineWidth: 1)
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: windowMode == .floating ? Layout.floatingCornerRadius : Layout.stickyCornerRadius,
                        style: .continuous
                    )
                )
                .contentShape(Rectangle())
                .contextMenu {
                    Button(vm.isPlaying ? "Pause" : "Play") { vm.togglePlayback() }
                    Button(vm.isEditing ? "Done" : "Edit") { vm.toggleEditMode() }
                    Button("Reset to Top") { vm.resetToTop() }
                    if vm.isEditing {
                        Button("Undo") { vm.undoScriptEdit() }
                            .disabled(!vm.canUndoScriptEdit)
                        Button("Redo") { vm.redoScriptEdit() }
                            .disabled(!vm.canRedoScriptEdit)
                    }
                    Button(vm.voiceFollowEnabled ? "Voice Follow Off" : "Voice Follow On") {
                        vm.voiceFollowEnabled.toggle()
                    }
                }

            // Floating controls
            if windowMode == .floating {
                floatingControlsOverlay
                    .padding(.top, 6)
            }

            // Sticky hidden hotspot
            if windowMode == .sticky {
                stickyHotspot
            }

            // Sticky mini-controls (shown after hotspot hover/click)
            if windowMode == .sticky && showStickyMiniControls {
                stickyMiniControls
                    .padding(.top, 4)
                    .transition(.opacity)
                    .onHover { hovering in
                        hoveringStickyControls = hovering
                        if hovering {
                            revealStickyMiniControls()
                        } else {
                            scheduleStickyMiniControlsHide()
                        }
                    }
            }
        }
        .clipped()
        .onAppear {
            vm.startTicker()
            if windowMode == .sticky {
                vm.isEditing = false
                vm.play()
            }
            if vm.voiceFollowEnabled {
                startSpeech()
            }
        }
        .onDisappear {
            vm.stopTicker()
            speech.stop()
            NotificationCenter.default.post(name: .overlayShowStickyResizeHandles, object: false)
            hideTask?.cancel()
        }
        .onChange(of: vm.voiceFollowEnabled) { _, enabled in
            if enabled {
                startSpeech()
            } else {
                speech.stop()
            }
        }
        .onChange(of: vm.script) { _, _ in
            if vm.voiceFollowEnabled {
                startSpeech()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            let newMicrophoneID = UserDefaults.standard.string(forKey: DefaultsKey.selectedMicrophoneID) ?? ""
            guard newMicrophoneID != selectedMicrophoneID else { return }
            selectedMicrophoneID = newMicrophoneID
            if vm.voiceFollowEnabled {
                startSpeech()
            }
        }
        .onReceive(speech.$transcript) { text in
            vm.handleRecognizedSpeech(text)
        }
        .onReceive(NotificationCenter.default.publisher(for: OverlayCommand.playPause)) { _ in
            vm.togglePlayback()
        }
        .onReceive(NotificationCenter.default.publisher(for: OverlayCommand.togglePause)) { _ in
            vm.togglePlayback()
        }
        .onReceive(NotificationCenter.default.publisher(for: OverlayCommand.toggleEdit)) { _ in
            vm.toggleEditMode()
            revealStickyMiniControls()
        }
        .onReceive(NotificationCenter.default.publisher(for: OverlayCommand.resetToTop)) { _ in
            vm.resetToTop()
        }
        .onReceive(NotificationCenter.default.publisher(for: OverlayCommand.speedUp)) { _ in
            vm.adjustSpeed(by: 5)
        }
        .onReceive(NotificationCenter.default.publisher(for: OverlayCommand.speedDown)) { _ in
            vm.adjustSpeed(by: -5)
        }
    }

    private var backgroundForMode: Color {
        windowMode == .floating
            ? Color.black.opacity(Layout.floatingBackgroundOpacity)   // keep your darker floating overlay
            : Color.black.opacity(Layout.stickyBackgroundOpacity)
    }

    private func startSpeech() {
        speech.start(contextualStrings: vm.voiceContextualStrings,
                     selectedMicrophoneID: selectedMicrophoneID.isEmpty ? nil : selectedMicrophoneID)
    }

    @ViewBuilder
    private var contentBody: some View {
        if vm.isEditing {
            TextEditor(text: $vm.script)
                .font(.system(size: windowMode == .sticky ? CGFloat(vm.fontSize) : 14,
                              weight: .regular,
                              design: .monospaced))
                .foregroundStyle(.white)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
        } else {
            prompterView
        }
    }

    private var prompterView: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .topLeading) {
                Text(vm.script)
                    .font(.system(size: CGFloat(vm.fontSize), weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineSpacing(Layout.lineSpacing)
                    .frame(width: width, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .offset(y: -vm.offsetY)

                ManualScrollCatcher { deltaY in
                    vm.scrollManually(by: deltaY)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .onAppear {
                vm.viewportHeight = geo.size.height
                vm.prompterWidth = width
                vm.recomputeContentHeight(restoreRatio: nil)
            }
            .onChange(of: geo.size.height) { _, nv in vm.viewportHeight = nv }
            .onChange(of: width) { _, nv in
                vm.prompterWidth = nv
                vm.recomputeContentHeight(restoreRatio: nil)
            }
            .clipped()
        }
    }

    private var floatingControlsOverlay: some View {
        HStack(spacing: 10) {
            WindowDragHandle()
                .frame(width: 20, height: 20)
                .help("Drag prompter")

            sharedOverlayControls(showLabels: true)

            if vm.isEditing {
                Button {
                    vm.undoScriptEdit()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(!vm.canUndoScriptEdit)
                .help("Undo script edit")

                Button {
                    vm.redoScriptEdit()
                } label: {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                }
                .disabled(!vm.canRedoScriptEdit)
                .help("Redo script edit")
            }

            Button {
                vm.toggleEditMode()
            } label: {
                Label(vm.isEditing ? "Done" : "Edit",
                      systemImage: vm.isEditing ? "checkmark" : "pencil")
            }
            .help("Edit / Done")
        }
        .font(.system(size: 12, weight: .semibold, design: .monospaced))
        .foregroundStyle(.white.opacity(0.95))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.black.opacity(Layout.controlsBackgroundOpacity))
        .clipShape(RoundedRectangle(cornerRadius: Layout.controlsCornerRadius, style: .continuous))
    }

    private var stickyHotspot: some View {
        Color.clear
            .frame(width: Layout.stickyHotspotWidth, height: Layout.stickyHotspotHeight)
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onHover { hovering in
                hoveringStickyHotspot = hovering
                if hovering {
                    revealStickyMiniControls()
                } else {
                    scheduleStickyMiniControlsHide()
                }
            }
            .onTapGesture {
                revealStickyMiniControls()
            }
            .allowsHitTesting(!showStickyMiniControls && !vm.isEditing)
    }

    private var stickyMiniControls: some View {
        HStack(spacing: 8) {
            sharedOverlayControls(showLabels: false)

            if vm.isEditing {
                Button {
                    vm.undoScriptEdit()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .frame(width: 18, height: 18)
                        .accessibilityLabel(Text("Undo"))
                }
                .disabled(!vm.canUndoScriptEdit)
                .help("Undo script edit")

                Button {
                    vm.redoScriptEdit()
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                        .frame(width: 18, height: 18)
                        .accessibilityLabel(Text("Redo"))
                }
                .disabled(!vm.canRedoScriptEdit)
                .help("Redo script edit")
            }

            Button {
                vm.toggleEditMode()
            } label: {
                Image(systemName: vm.isEditing ? "checkmark" : "pencil")
                    .frame(width: 18, height: 18)
                    .accessibilityLabel(Text(vm.isEditing ? "Done" : "Edit"))
            }
            .help("Edit / Done")
        }
        .font(.system(size: 12, weight: .semibold, design: .monospaced))
        .foregroundStyle(.white.opacity(0.95))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: Layout.controlsCornerRadius, style: .continuous))
    }

    private func revealStickyMiniControls() {
        hideTask?.cancel()
        NotificationCenter.default.post(name: .overlayShowStickyResizeHandles, object: true)
        withAnimation(.easeOut(duration: Layout.stickyMiniControlsFadeIn)) {
            showStickyMiniControls = true
        }
    }

    private func scheduleStickyMiniControlsHide() {
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(Layout.stickyMiniControlsAutoHideSeconds * 1_000_000_000))
            guard !hoveringStickyHotspot, !hoveringStickyControls, !vm.isEditing else { return }
            NotificationCenter.default.post(name: .overlayShowStickyResizeHandles, object: false)
            withAnimation(.easeIn(duration: Layout.stickyMiniControlsFadeOut)) {
                showStickyMiniControls = false
            }
        }
    }

    private func sharedOverlayControls(showLabels: Bool) -> some View {
        HStack(spacing: 8) {
            Button {
                vm.togglePlayback()
            } label: {
                controlLabel(showLabels: showLabels,
                             text: vm.isPlaying ? "Pause" : "Play",
                             symbol: vm.isPlaying ? "pause.fill" : "play.fill")
            }
            .help("Play / Pause")

            Button {
                vm.resetToTop()
            } label: {
                controlLabel(showLabels: showLabels,
                             text: "Reset",
                             symbol: "arrow.up.to.line")
            }
            .help("Reset to top")

            Button {
                vm.voiceFollowEnabled.toggle()
            } label: {
                controlLabel(showLabels: showLabels,
                             text: vm.voiceFollowEnabled ? "Voice On" : "Voice",
                             symbol: vm.voiceFollowEnabled ? "waveform.circle.fill" : "waveform.circle")
            }
            .help(vm.voiceFollowEnabled ? voiceHelpText : "Follow spoken script")
        }
    }

    private var voiceHelpText: String {
        let level = Int(min(100, max(0, speech.inputLevel * 900)))
        let input = speech.activeInputName.isEmpty ? "selected input" : speech.activeInputName
        return "\(speech.statusText) - \(input) - level \(level)%"
    }

    @ViewBuilder
    private func controlLabel(showLabels: Bool, text: String, symbol: String) -> some View {
        if showLabels {
            Label(text, systemImage: symbol)
        } else {
            Image(systemName: symbol)
                .frame(width: 18, height: 18)
                .accessibilityLabel(Text(text))
        }
    }
}

private struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> DragHandleView {
        DragHandleView()
    }

    func updateNSView(_ nsView: DragHandleView, context: Context) {}
}

private final class DragHandleView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.white.withAlphaComponent(0.65).setStroke()

        let path = NSBezierPath()
        path.lineWidth = 1.5
        for y in stride(from: CGFloat(6), through: 14, by: 4) {
            path.move(to: CGPoint(x: 5, y: y))
            path.line(to: CGPoint(x: 15, y: y))
        }
        path.stroke()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        NSCursor.closedHand.set()
        window?.performDrag(with: event)
    }
}

private struct ManualScrollCatcher: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> ManualScrollView {
        let view = ManualScrollView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: ManualScrollView, context: Context) {
        nsView.onScroll = onScroll
    }
}

private final class ManualScrollView: NSView {
    var onScroll: ((CGFloat) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func scrollWheel(with event: NSEvent) {
        let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
        onScroll?(-event.scrollingDeltaY * multiplier)
    }
}
