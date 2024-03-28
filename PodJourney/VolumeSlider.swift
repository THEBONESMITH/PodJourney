//
//  VolumeSlider.swift
//  PodJourney
//
//  Created by . . on 28/03/2024.
//

import Foundation
import SwiftUI
import AppKit

struct VolumeSlider: View {
    @Binding var volume: Double // Current volume
    var maxValue: Double = 1.0 // Maximum value for volume
    var onVolumeChange: (Double) -> Void // Closure to call when volume changes

    var body: some View {
        HStack (spacing: 2) {
            // Mute symbol
            Image(systemName: "speaker.fill")
                .foregroundColor(.gray)
                .onTapGesture {
                    self.volume = 0
                    onVolumeChange(0)
                }

            // Volume slider
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .foregroundColor(.gray.opacity(0.3))
                        .frame(width: geometry.size.width, height: geometry.size.height) // Make it not as wide by adjusting the width
                    Rectangle()
                        .foregroundColor(.gray)
                        .frame(width: geometry.size.width * CGFloat(self.volume / maxValue), height: geometry.size.height)
                }
                .cornerRadius(45.0)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            // Calculate new volume based on the drag location, adjusted for the reduced width
                            let newVolume = max(0, min(maxValue, value.location.x / geometry.size.width * maxValue))
                            self.volume = newVolume // Update local volume
                            onVolumeChange(newVolume) // Call the onVolumeChange closure with the new volume
                        }
                )
            }
            .frame(height: 9) // Define a fixed height for the slider

            // Volume max symbol
            Image(systemName: "speaker.wave.3.fill")
                .foregroundColor(.gray)
                .onTapGesture {
                    self.volume = 1
                    onVolumeChange(1)
                }
        }
        .frame(height: 9) // Define a fixed height for the entire control
    }
}
