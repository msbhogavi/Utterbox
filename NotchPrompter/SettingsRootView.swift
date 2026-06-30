//
//  SettingsRootView.swift
//  NotchPrompter
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

private let settingsSpacing: CGFloat = 16
private let cardRadius: CGFloat = 10

struct SettingsCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let content: Content

    init(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
    }
}

struct SettingsRootView: View {
    @StateObject private var vm = PrompterViewModel()

    @State private var availableDisplays: [String] = []
    @State private var selectedDisplayName =
        UserDefaults.standard.string(forKey: DefaultsKey.selectedDisplayName) ?? ""

    @State private var windowModeSetting = OverlaySettings.getWindowMode()
    @State private var microphones: [MicrophoneDevice] = []
    @State private var selectedMicrophoneID =
        UserDefaults.standard.string(forKey: DefaultsKey.selectedMicrophoneID) ?? ""

    @State private var notchWidth: CGFloat = {
        let w = CGFloat(UserDefaults.standard.double(forKey: DefaultsKey.notchWidthSaved))
        return w > 0 ? w : Layout.defaultNotchWidth
    }()

    @State private var notchHeight: CGFloat = {
        let h = CGFloat(UserDefaults.standard.double(forKey: DefaultsKey.notchHeightSaved))
        return h > 0 ? h : Layout.defaultNotchHeight
    }()

    @State private var showingImporter = false
    @State private var showingExporter = false
    @State private var exportDoc = TextFileDocument(text: "")

    private var versionString: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        return "Version \(v)"
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 260), spacing: settingsSpacing, alignment: .top)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Divider()

            ScrollView {
                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: settingsSpacing) {
                    placementCard
                    displayCard

                    if windowModeSetting == .sticky {
                        notchCard
                    } else {
                        floatingCard
                    }

                    deliveryCard
                    scriptCard
                    shortcutCard
                }
                .padding(.vertical, 4)
            }
        }
        .padding(20)
        .onAppear(perform: loadDisplays)
        .onAppear(perform: loadMicrophones)
        .onChange(of: selectedDisplayName) { _, newValue in
            UserDefaults.standard.set(newValue, forKey: DefaultsKey.selectedDisplayName)
            NotificationCenter.default.post(name: .overlayRefresh, object: nil)
        }
        .onChange(of: selectedMicrophoneID) { _, newValue in
            if newValue.isEmpty {
                UserDefaults.standard.removeObject(forKey: DefaultsKey.selectedMicrophoneID)
            } else {
                UserDefaults.standard.set(newValue, forKey: DefaultsKey.selectedMicrophoneID)
            }
        }
        .onChange(of: windowModeSetting) { _, newValue in
            OverlaySettings.setWindowMode(newValue)
            NotificationCenter.default.post(name: .overlayRefresh, object: nil)
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.plainText],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                vm.importFile(url: url)
            }
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDoc,
            contentType: .plainText,
            defaultFilename: "script"
        ) { _ in }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Utterbox")
                    .font(.system(size: 22, weight: .semibold))
                Text("Camera-aligned prompting - \(versionString)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                NotificationCenter.default.post(name: .overlayToggle, object: nil)
            } label: {
                Label("Show / Hide", systemImage: "rectangle.on.rectangle")
            }
        }
    }

    private var placementCard: some View {
        SettingsCard("Camera Placement", subtitle: "Choose the camera your eyes should align with.") {
            Picker("Camera", selection: $windowModeSetting) {
                ForEach(OverlayWindowMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(windowModeSetting.detail)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var displayCard: some View {
        SettingsCard("Display", subtitle: "The prompter opens on this screen.") {
            Picker("Target Display", selection: $selectedDisplayName) {
                ForEach(availableDisplays, id: \.self) {
                    Text($0).tag($0)
                }
            }
            .disabled(availableDisplays.count <= 1)
        }
    }

    private var notchCard: some View {
        SettingsCard("Notch Calibration", subtitle: "Fine tune the MacBook camera prompter.") {
            VStack(spacing: 12) {
                NumericControl(title: "Width", value: Int(notchWidth)) {
                    adjustNotch(widthDelta: -20, heightDelta: 0)
                } increment: {
                    adjustNotch(widthDelta: 20, heightDelta: 0)
                }

                NumericControl(title: "Height", value: Int(notchHeight)) {
                    adjustNotch(widthDelta: 0, heightDelta: -10)
                } increment: {
                    adjustNotch(widthDelta: 0, heightDelta: 10)
                }
            }
        }
    }

    private var floatingCard: some View {
        SettingsCard("Floating Prompter", subtitle: "Drag it beside your external webcam. Size and position are remembered.") {
            VStack(alignment: .leading, spacing: 10) {
                Label("Move the prompter by dragging its background.", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Button {
                    UserDefaults.standard.removeObject(forKey: DefaultsKey.floatingXSaved)
                    UserDefaults.standard.removeObject(forKey: DefaultsKey.floatingYSaved)
                    NotificationCenter.default.post(name: .overlayRefresh, object: nil)
                } label: {
                    Label("Reset Position", systemImage: "scope")
                }
            }
        }
    }

    private var deliveryCard: some View {
        SettingsCard("Delivery", subtitle: "Controls update the active prompter immediately.") {
            VStack(spacing: 12) {
                Toggle("Voice follow", isOn: $vm.voiceFollowEnabled)
                Text("When enabled, spoken sentences advance the prompter instead of the speed timer.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                StepperLine(title: "Speed", value: $vm.speed, step: 5, range: 0...300)
                    .disabled(vm.voiceFollowEnabled)
                StepperLine(title: "Font Size", value: $vm.fontSize, step: 1, range: 10...28)

                Divider()

                Picker("Microphone", selection: $selectedMicrophoneID) {
                    Text("System Default").tag("")
                    ForEach(microphones) { mic in
                        Text(mic.name).tag(mic.id)
                    }
                }

                Text(microphones.isEmpty ? "No microphone input found." : "Use System Default unless you need a specific external microphone.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    NotificationCenter.default.post(name: OverlayCommand.resetToTop, object: nil)
                } label: {
                    Label("Reset to Top", systemImage: "arrow.up.to.line")
                }
            }
        }
    }

    private var scriptCard: some View {
        SettingsCard("Script", subtitle: "Import plain text or export the current draft.") {
            HStack(spacing: 10) {
                Button("Import") { showingImporter = true }
                Button("Export") {
                    exportDoc = TextFileDocument(text: vm.script)
                    showingExporter = true
                }
            }
        }
    }

    private var shortcutCard: some View {
        SettingsCard("Shortcuts", subtitle: "Global controls for presenting without touching the overlay.") {
            VStack(alignment: .leading, spacing: 7) {
                ShortcutRow("Show / Hide", "Ctrl Opt Cmd P")
                ShortcutRow("Play / Pause", "Ctrl Opt Cmd Space")
                ShortcutRow("Edit / Done", "Ctrl Opt Cmd E")
                ShortcutRow("Reset", "Ctrl Opt Cmd R")
                ShortcutRow("Speed", "Ctrl Opt Cmd Up/Down")
                ShortcutRow("Notch Width", "Ctrl Opt Shift Cmd Left/Right")
                ShortcutRow("Notch Height", "Ctrl Opt Shift Cmd Up/Down")
            }
        }
    }

    private func loadDisplays() {
        availableDisplays = ScreenSelection.availableDisplayNames()
        if selectedDisplayName.isEmpty {
            selectedDisplayName =
                ScreenSelection.currentTargetScreen()?.localizedName
                ?? (availableDisplays.first ?? "")
            UserDefaults.standard.set(selectedDisplayName, forKey: DefaultsKey.selectedDisplayName)
        }
    }

    private func loadMicrophones() {
        microphones = MicrophoneCatalog.availableMicrophones()
        if !selectedMicrophoneID.isEmpty,
           !microphones.contains(where: { $0.id == selectedMicrophoneID }) {
            selectedMicrophoneID = ""
            UserDefaults.standard.removeObject(forKey: DefaultsKey.selectedMicrophoneID)
        }
    }

    private func adjustNotch(widthDelta: CGFloat, heightDelta: CGFloat) {
        notchWidth = min(900, max(Layout.minNotchWidth, notchWidth + widthDelta))
        notchHeight = min(220, max(Layout.minNotchHeight, notchHeight + heightDelta))
        UserDefaults.standard.set(Double(notchWidth), forKey: DefaultsKey.notchWidthSaved)
        UserDefaults.standard.set(Double(notchHeight), forKey: DefaultsKey.notchHeightSaved)
        NotificationCenter.default.post(name: .overlayRefresh, object: nil)
    }
}

private struct NumericControl: View {
    let title: String
    let value: Int
    let decrement: () -> Void
    let increment: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: decrement) {
                Image(systemName: "minus")
            }
            Text("\(value)")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .frame(width: 48)
            Button(action: increment) {
                Image(systemName: "plus")
            }
        }
    }
}

private struct StepperLine: View {
    let title: String
    @Binding var value: Double
    let step: Double
    let range: ClosedRange<Double>

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                value = max(range.lowerBound, value - step)
            } label: {
                Image(systemName: "minus")
            }
            Text("\(Int(value))")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .frame(width: 44)
            Button {
                value = min(range.upperBound, value + step)
            } label: {
                Image(systemName: "plus")
            }
        }
    }
}

private struct ShortcutRow: View {
    let title: String
    let shortcut: String

    init(_ title: String, _ shortcut: String) {
        self.title = title
        self.shortcut = shortcut
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer(minLength: 12)
            Text(shortcut)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

#if canImport(PreviewsMacros)
#Preview {
    SettingsRootView()
        .frame(width: 680, height: 560)
}
#endif
