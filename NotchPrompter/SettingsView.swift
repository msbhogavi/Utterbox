//
//  SettingsView.swift
//  NotchPrompter
//
//  Created by Mallikarjun Bhogavi on 02/01/26.
//



import SwiftUI

struct SettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Utterbox Settings")
                .font(.title2)

            Text("We’ll control the prompter from the menu bar next.")
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(20)
        .frame(width: 420, height: 200)
    }
}

#if canImport(PreviewsMacros)
#Preview {
    SettingsView()
}
#endif
