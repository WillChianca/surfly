//
//  Item.swift
//  surfly
//
//  Created by Wilton Junior on 26/10/2026.
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
