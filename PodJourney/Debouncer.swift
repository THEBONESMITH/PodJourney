//
//  Debouncer.swift
//  PodJourney
//
//  Created by . . on 28/03/2024.
//

import Foundation
import Combine

class Debouncer {
    private let interval: TimeInterval
    private var timer: Timer?
    
    init(interval: TimeInterval) {
        self.interval = interval
    }
    
    func debounce(action: @escaping () -> Void) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false, block: { _ in action() })
    }
}
