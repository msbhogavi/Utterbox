//
//  ContentView.swift
//  NotchPrompter
//
//  Created by Mallikarjun Bhogavi on 02/01/26.
//

import SwiftUI
import AppKit

struct ContentView: View {
    private var versionString: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Version \(v) (\(b))"
    }

    private var logoImage: NSImage? {
        // Prefer the renamed file: AppLogo.png
        if let url = Bundle.main.url(forResource: "AppLogo", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        // Fallback if you keep the original filename
        if let url = Bundle.main.url(forResource: "AppLogo@1x", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 18) {
            if let logoImage {
                Image(nsImage: logoImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 110, height: 110)
                    .padding(.top, 14)
            } else {
                Rectangle()
                    .fill(Color.black.opacity(0.06))
                    .frame(width: 110, height: 110)
                    .overlay(Text("Logo missing").font(.caption).foregroundStyle(.gray))
                    .padding(.top, 14)
            }

            VStack(spacing: 6) {
                Text("Utterbox")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.black)

                Text(versionString)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.gray)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Quirky by professional — made with love by Mallikarjun Bhogavi.")
                Text("• Use the menu bar icon to Toggle Prompter")
                Text("• MacBook Camera: notch-aligned prompting")
                Text("• External Camera: movable prompting near your webcam")
                Text("• You can minimize this window; the app keeps running.")
            }
            .font(.system(size: 13))
            .foregroundStyle(.black)
            .frame(maxWidth: 420, alignment: .leading)
            .padding(.horizontal, 10)

            Divider().padding(.horizontal, 10)

            VStack(alignment: .leading, spacing: 8) {
                Text("Suggestions / improvements:")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.black)

                Link("bhogavi.ms@gmail.com", destination: URL(string: "mailto:bhogavi.ms@gmail.com")!)
                    .font(.system(size: 13))
                    .foregroundStyle(.black)
            }
            .frame(maxWidth: 420, alignment: .leading)
            .padding(.horizontal, 10)

            Spacer(minLength: 6)

            HStack {
                Button("Minimize") {
                    NSApp.keyWindow?.performMiniaturize(nil)
                }

                Spacer()

                Button("Quit") {
                    NSApp.terminate(nil)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
        }
        .frame(width: 520, height: 520)
        .padding(.horizontal, 10)
        .background(Color.white)
    }
}
