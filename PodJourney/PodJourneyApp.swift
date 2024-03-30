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
    var window: NSWindow!
    // Assuming MediaPlayer initialization doesn't require additional parameters:
    let mediaPlayer = MediaPlayer()
    lazy var viewModel = PodcastViewModel(mediaPlayer: mediaPlayer)


    func applicationDidFinishLaunching(_ notification: Notification) {
            let contentView = ContentView().environmentObject(viewModel)
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false)
            window.center()
            window.setFrameAutosaveName("Main Window")
            window.contentView = NSHostingView(rootView: contentView)
            window.makeKeyAndOrderFront(nil)
        }

    func applicationWillTerminate(_ notification: Notification) {
        // Perform any final cleanup before the app is terminated
        viewModel.pausePlayback() // Ensure this method can be called from the main actor
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
            return true
        }
}

@main
struct PodJourneyApp: App {
    let mediaPlayer = MediaPlayer()
    let viewModel: PodcastViewModel

    init() {
        viewModel = PodcastViewModel(mediaPlayer: mediaPlayer)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
        }
    }
}


