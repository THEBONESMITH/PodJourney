//
//  PodJourneyApp.swift
//  PodJourney
//
//  Created by . . on 28/03/2024.
//

import Cocoa
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    let mediaPlayer = MediaPlayer() // Ensuring MediaPlayer is accessible
    lazy var viewModel = PodcastViewModel(mediaPlayer: mediaPlayer)
    
    func applicationWillTerminate(_ notification: Notification) {
            // Explicitly stop the MediaPlayer when the app is about to terminate
            mediaPlayer.stop()
        }

    func windowWillClose(_ notification: Notification) {
        // Explicitly stop the MediaPlayer when the window closes
        mediaPlayer.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

@main
struct PodJourneyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    let mediaPlayer: MediaPlayer
    let viewModel: PodcastViewModel

    init() {
        mediaPlayer = MediaPlayer()
        viewModel = PodcastViewModel(mediaPlayer: mediaPlayer)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
        }
    }
}

