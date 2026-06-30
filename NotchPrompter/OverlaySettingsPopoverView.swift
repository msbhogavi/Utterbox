//
//  OverlaySettingsPopoverView.swift
//  NotchPrompter
//
//  Created by Mallikarjun Bhogavi on 05/01/26.
//
import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct OverlaySettingsPopoverView: View {
    enum SettingsContext { case sticky, floating }

    @ObservedObject var vm: PrompterViewModel
    let context: SettingsContext

    @Binding var showingImporter: Bool
    @Binding var showingExporter: Bool
    @Binding var exportDoc: TextFileDocument

    @Binding var windowModeSetting: OverlayWindowMode
    @Binding var availableDisplays: [String]
    @Binding var selectedDisplayName: String

    @Binding var notchWidth: CGFloat
    @Binding var notchHeight: CGFloat

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Settings").font(.headline).foregroundStyle(.white)

                GroupBox("Camera Placement") {
                    Picker("", selection: $windowModeSetting) {
                        ForEach(OverlayWindowMode.allCases) { m in
                            Text(m.displayName).tag(m)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.white)

                    Text(windowModeSetting.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.65))

                    Button("Apply camera placement") {
                        OverlaySettings.setWindowMode(windowModeSetting)
                        NotificationCenter.default.post(name: .overlayRefresh, object: nil)
                    }
                }
                .groupBoxStyle(DarkGroupBoxStyle())

                GroupBox("Display") {
                    Picker("", selection: $selectedDisplayName) {
                        ForEach(availableDisplays, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.white)
                    .disabled(availableDisplays.count <= 1)
                    .onChange(of: selectedDisplayName) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: DefaultsKey.selectedDisplayName)
                    }

                    Button("Apply display") {
                        UserDefaults.standard.set(selectedDisplayName, forKey: DefaultsKey.selectedDisplayName)
                        NotificationCenter.default.post(name: .overlayRefresh, object: nil)
                    }
                    .disabled(availableDisplays.count <= 1)
                }
                .groupBoxStyle(DarkGroupBoxStyle())

                if context == .sticky {
                    GroupBox("Notch Size (Sticky Mode)") {
                        HStack {
                            Text("Width").foregroundStyle(.white.opacity(0.85))
                            Spacer()
                            Button("−") { notchWidth = max(Layout.minNotchWidth, notchWidth - 20) }
                            Text("\(Int(notchWidth))")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .frame(width: 60, alignment: .center)
                                .foregroundStyle(.white.opacity(0.9))
                            Button("+") { notchWidth = min(900, notchWidth + 20) }
                        }

                        HStack {
                            Text("Height").foregroundStyle(.white.opacity(0.85))
                            Spacer()
                            Button("−") { notchHeight = max(Layout.minNotchHeight, notchHeight - 10) }
                            Text("\(Int(notchHeight))")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .frame(width: 60, alignment: .center)
                                .foregroundStyle(.white.opacity(0.9))
                            Button("+") { notchHeight = min(220, notchHeight + 10) }
                        }

                        Button("Apply notch size now") {
                            UserDefaults.standard.set(Double(notchWidth), forKey: DefaultsKey.notchWidthSaved)
                            UserDefaults.standard.set(Double(notchHeight), forKey: DefaultsKey.notchHeightSaved)
                            NotificationCenter.default.post(name: .overlayRefresh, object: nil)
                        }
                    }
                    .groupBoxStyle(DarkGroupBoxStyle())
                }

                GroupBox("Speed / Font") {
                    HStack {
                        Text("Speed").foregroundStyle(.white.opacity(0.85))
                        Spacer()
                        StepperView(value: $vm.speed, step: 5, min: 0, max: 300)
                    }
                    HStack {
                        Text("Font").foregroundStyle(.white.opacity(0.85))
                        Spacer()
                        StepperView(value: $vm.fontSize, step: 1, min: 12, max: 28)
                    }
                    Button("Reset to top") { vm.resetToTop() }
                }
                .groupBoxStyle(DarkGroupBoxStyle())

                GroupBox("Import / Export") {
                    Button("Import Script…") { showingImporter = true }
                    Button("Export Script…") {
                        exportDoc = TextFileDocument(text: vm.script)
                        showingExporter = true
                    }
                }
                .groupBoxStyle(DarkGroupBoxStyle())
            }
            .padding(8)
        }
        .background(Color.black.opacity(0.92))
    }
}

// Helpers (kept here to avoid missing symbols)
struct DarkGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            configuration.label
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            configuration.content
        }
        .padding(10)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct StepperView: View {
    @Binding var value: Double
    let step: Double
    let min: Double
    let max: Double
    var body: some View {
        HStack(spacing: 8) {
            Button("−") { value = Swift.max(min, value - step) }.buttonStyle(.bordered)
            Text("\(Int(value))")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .frame(width: 40, alignment: .center)
                .foregroundStyle(.white.opacity(0.9))
            Button("+") { value = Swift.min(max, value + step) }.buttonStyle(.bordered)
        }
    }
}

struct TextFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws { text = "" }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        .init(regularFileWithContents: text.data(using: .utf8) ?? Data())
    }
}
