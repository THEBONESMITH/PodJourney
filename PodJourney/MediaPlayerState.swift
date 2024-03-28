//
//  MediaPlayerState.swift
//  PodJourney
//
//  Created by . . on 28/03/2024.
//

import Foundation
import AVFoundation

protocol MediaPlayerState {
    var mediaPlayer: MediaPlayer? { get set }
    init(mediaPlayer: MediaPlayer)
    // Other protocol requirements...
}

// Implementation of PlayingState
class PlayingState: MediaPlayerState {
    weak var mediaPlayer: MediaPlayer?
    
    required init(mediaPlayer: MediaPlayer) {
        self.mediaPlayer = mediaPlayer
        // Removed autoPlay check here since PlayingState now always means intent to play.
        startPlayback()
    }
    
    // Added method to start playback immediately when transitioning to this state.
    private func startPlayback() {
        guard let mediaPlayer = self.mediaPlayer else {
            print("PlayingState: MediaPlayer reference is nil.")
            return
        }
        
        // Ensuring playback starts only if explicitly requested by user action.
        mediaPlayer.player.play()
        print("PlayingState: Playback started.")
    }
    
    func play() {
        // It's already playing, but this print statement confirms that the method was called.
        print("MediaPlayer is already playing.")
    }
    
    // Inside the pause method of PlayingState
    func pause() {
        guard let mediaPlayer = self.mediaPlayer else { return }
        print("Pausing MediaPlayer from PlayingState.")
        mediaPlayer.player.pause()
        // Correctly pass the state type to the transition method
        mediaPlayer.transitionToState(PausedState.self)
    }
    
    func stop() {
        guard let mediaPlayer = self.mediaPlayer else { return }
        print("Stopping MediaPlayer from PlayingState.")
        mediaPlayer.player.pause()
        // Optionally reset the player item or perform other cleanup here if necessary
        
        // Transition to the StoppedState by passing the type itself, not an instance.
        mediaPlayer.transitionToState(StoppedState.self)
    }
}

// Implementation of PausedState
class PausedState: MediaPlayerState {
    weak var mediaPlayer: MediaPlayer?
    
    required init(mediaPlayer: MediaPlayer) {
        self.mediaPlayer = mediaPlayer
    }
    
    func play() {
        guard let mediaPlayer = self.mediaPlayer else { return }
        print("Resuming MediaPlayer from PausedState.")
        mediaPlayer.player.play()
        
        // Correctly pass the state type to the transition method
        mediaPlayer.transitionToState(PlayingState.self)
    }

    
    func pause() {
        print("MediaPlayer is already paused.")
    }
    
    func stop() {
        guard let mediaPlayer = self.mediaPlayer else { return }
        print("Stopping MediaPlayer from PausedState.")
        mediaPlayer.player.pause()
        // Transition to the StoppedState
        mediaPlayer.transitionToState(StoppedState.self)
    }
}

// Implementation of StoppedState
class StoppedState: MediaPlayerState {
    weak var mediaPlayer: MediaPlayer?
    
    required init(mediaPlayer: MediaPlayer) {
        self.mediaPlayer = mediaPlayer
    }
    
    func play() {
        guard let mediaPlayer = self.mediaPlayer, let url = mediaPlayer.currentMediaURL else { return }
        print("Starting playback from StoppedState.")
        let playerItem = AVPlayerItem(url: url)
        mediaPlayer.player.replaceCurrentItem(with: playerItem)
        mediaPlayer.player.play()
        // Transition to the PlayingState
        mediaPlayer.transitionToState(PlayingState.self)
    }
    
    func pause() {
        // Pausing in StoppedState doesn't make sense, so likely do nothing or log an error
        print("Attempting to pause when in StoppedState. No action taken.")
    }
    
    func stop() {
        // Already in StoppedState, so likely do nothing or reset playback to the beginning if needed
        print("MediaPlayer is already stopped.")
    }
}

class ReadyState: MediaPlayerState {
    weak var mediaPlayer: MediaPlayer?

    required init(mediaPlayer: MediaPlayer) {
        self.mediaPlayer = mediaPlayer
    }

    func play() {
        guard let mediaPlayer = self.mediaPlayer, let url = mediaPlayer.currentMediaURL else {
            print("URL for mediaPlayer is not set or mediaPlayer is nil.")
            return
        }

        // Update: This code no longer automatically starts playback.
        print("ReadyState: Preparing player for URL: \(url) without auto-playing.")

        // Prepare the player with the new episode URL but do not start playback.
        let playerItem = AVPlayerItem(url: url)
        mediaPlayer.player.replaceCurrentItem(with: playerItem)

        // Inform the rest of the app that the player is ready for a manual play command.
        print("Player is prepared and waiting for a manual play command.")

        // Note: No automatic transition to PlayingState here. Waiting for explicit user action.
    }

    func pause() {
        // Since ReadyState indicates readiness to play and not actually playing, pause might not do anything.
        print("Pause requested in ReadyState, but playback hasn't started. No action taken.")
    }

    func stop() {
        guard let mediaPlayer = self.mediaPlayer else {
            print("MediaPlayer is nil, cannot stop.")
            return
        }
        
        print("Stopping MediaPlayer from ReadyState.")
        mediaPlayer.player.pause()
        mediaPlayer.player.replaceCurrentItem(with: nil) // Optional: clear the current item if stopping from ReadyState
        mediaPlayer.transitionToState(StoppedState.self)
    }
}
