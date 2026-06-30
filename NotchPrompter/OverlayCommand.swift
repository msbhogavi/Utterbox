//
//  OverlayCommand.swift
//  NotchPrompter
//
//  Created by Mallikarjun Bhogavi on 02/01/26.
//

import Foundation

enum OverlayCommand {
    static let toggleEdit = Notification.Name("OverlayCommand.toggleEdit")
    static let togglePause = Notification.Name("OverlayCommand.togglePause")
    static let playPause = Notification.Name("OverlayCommand.playPause")
    static let resetToTop = Notification.Name("OverlayCommand.resetToTop")

    static let speedUp = Notification.Name("OverlayCommand.speedUp")
    static let speedDown = Notification.Name("OverlayCommand.speedDown")

    static let notchWider = Notification.Name("OverlayCommand.notchWider")
    static let notchNarrower = Notification.Name("OverlayCommand.notchNarrower")
    static let notchTaller = Notification.Name("OverlayCommand.notchTaller")
    static let notchShorter = Notification.Name("OverlayCommand.notchShorter")
}
