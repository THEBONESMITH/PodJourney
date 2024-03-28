//
//  FocusableView.swift
//  PodJourney
//
//  Created by . . on 28/03/2024.
//

import Foundation
import SwiftUI
import AppKit

struct FocusableView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = NSApplication.shared.windows.first {
                // Attempt to set the first responder or simulate a Tab press
                // This is a placeholder for where you'd add your logic
                window.selectNextKeyView(nil) // Example action, focusing the next key view
            }
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // Update logic if needed
    }
}

