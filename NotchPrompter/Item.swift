//
//  Item.swift
//  NotchPrompter
//
//  Created by Mallikarjun Bhogavi on 06/01/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
