//
//  NotchPrompterApp.swift
//  NotchPrompter
//
//  Created by Mallikarjun Bhogavi on 06/01/26.
//

import SwiftUI

@main
struct NotchPrompterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
