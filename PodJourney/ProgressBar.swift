//
//  ProgressBar.swift
//  PodJourney
//
//  Created by . . on 28/03/2024.
//

import Foundation
import SwiftUI

struct ProgressBar: View {
    @Binding var progress: Double // Current progress
    var maxValue: Double // Maximum value for progress
    var onSeek: (Double) -> Void // Closure to call when seeking

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .foregroundColor(.gray.opacity(0.3))
                    .frame(width: geometry.size.width, height: geometry.size.height)
                Rectangle()
                    .foregroundColor(.blue)
                    .frame(width: geometry.size.width * CGFloat(self.progress / maxValue), height: geometry.size.height)
            }
            .cornerRadius(45.0)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // Calculate new progress based on the drag location
                        let newProgress = max(0, min(maxValue, value.location.x / geometry.size.width * maxValue))
                        self.progress = newProgress // Update local progress
                        onSeek(newProgress) // Call the onSeek closure with the new progress
                    }
            )
        }
        .frame(height: 9) // Define a fixed height for the progress bar
    }
}
