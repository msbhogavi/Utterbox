//
//  AppState.swift
//  NotchPrompter
//
//  Created by Mallikarjun Bhogavi on 07/01/26.
//
import Foundation
import Combine

final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var overlayEnabled: Bool = false
    @Published var windowMode: OverlayWindowMode = OverlaySettings.getWindowMode()

    private init() {}
}
