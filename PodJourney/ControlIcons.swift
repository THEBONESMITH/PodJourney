//
//  ControlIcons.swift
//  PodJourney
//
//  Created by . . on 28/03/2024.
//

import Foundation
import SwiftUI

struct PlayIconView: View {
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let size = min(geometry.size.width, geometry.size.height) * 0.8 // Slightly larger icon
                let startX = (geometry.size.width - size) / 2
                let startY = (geometry.size.height - size) / 2
                
                path.move(to: CGPoint(x: startX, y: startY + size))
                path.addLine(to: CGPoint(x: startX + size, y: startY + (size / 2)))
                path.addLine(to: CGPoint(x: startX, y: startY))
                path.closeSubpath()
            }
            .fill(Color.white)
        }
        // Adjust the frame size here if needed for consistent sizing
        .aspectRatio(1, contentMode: .fit)
        .frame(width: 40, height: 40) // Increased size for better visibility
    }
}

struct PauseIconView: View {
    var body: some View {
        GeometryReader { geometry in
            let barWidth = geometry.size.width * 0.3 // Slightly wider for better visibility
            let spacing = geometry.size.width * 0.1 // Adjusted spacing for centering
            HStack(spacing: spacing) {
                Rectangle()
                    .fill(Color.white)
                    .frame(width: barWidth, height: geometry.size.height * 0.6) // Adjusted for visibility
                Rectangle()
                    .fill(Color.white)
                    .frame(width: barWidth, height: geometry.size.height * 0.6)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center) // Ensure HStack is centered
        }
        // Adjust the frame size here if needed for consistent sizing
        .aspectRatio(1, contentMode: .fit)
        .frame(width: 40, height: 40) // Matching the play icon size for consistency
    }
}

// Polygon and CGFloat extension remains unchanged

struct Polygon: Shape {
    var triangleSides: Int
    
    func path(in rect: CGRect) -> Path {
        guard triangleSides >= 3 else { return Path() }
        
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        let extraAdjustment: CGFloat = triangleSides % 2 == 0 ? 0 : 90
        for i in 0..<triangleSides {
            let angle = ((CGFloat.pi * 2) / CGFloat(triangleSides)) * CGFloat(i) - CGFloat.pi / 2 + extraAdjustment.degreesToRadians
            let pt = CGPoint(
                x: center.x + rect.width/2 * cos(angle),
                y: center.y + rect.height/2 * sin(angle)
            )
            
            if i == 0 {
                path.move(to: pt)
            } else {
                path.addLine(to: pt)
            }
        }
        path.closeSubpath()
        return path
    }
}

extension CGFloat {
    var degreesToRadians: CGFloat {
        return self * .pi / 180
    }
}
