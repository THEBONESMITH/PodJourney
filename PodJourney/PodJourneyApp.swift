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
    let viewModel = PodcastViewModel() // Initialize viewModel here

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
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
