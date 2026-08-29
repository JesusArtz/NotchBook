//
//  NowPlaying+Sources.swift
//  NotchDrop
//
//  The three data sources behind now playing: CoreAudio tells us which app is
//  making sound, AppleScript enriches the players that speak it, and media keys
//  drive everything else.
//

import AppKit
import AudioToolbox
import CoreAudio
import Foundation

// MARK: - Which app is making sound

struct AudioProcess: Equatable {
    let pid: pid_t
    let bundleID: String
}

enum AudioProcessReader {
    /// Apps we would rather show when several hold an output stream at once.
    /// Media players first, then browsers, everything else falls to the end.
    private static let priority: [String] = [
        "com.spotify.client",
        "com.apple.Music",
        "com.apple.TV",
        "com.google.Chrome",
        "com.apple.Safari",
        "org.mozilla.firefox",
        "company.thebrowser.Browser",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "tv.plex.desktop",
        "com.colliderli.iina",
        "org.videolan.vlc",
    ]

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        .init(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    /// Every process currently writing to an output device, best candidate first.
    static func playingProcesses() -> [AudioProcess] {
        var listAddress = address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &listAddress, 0, nil, &size
        ) == noErr, size > 0 else { return [] }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var objects = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &listAddress, 0, nil, &size, &objects
        ) == noErr else { return [] }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        var found: [AudioProcess] = []

        for object in objects {
            guard isRunningOutput(object) else { continue }
            guard let pid = processID(object), pid != ownPID else { continue }
            guard let app = NSRunningApplication(processIdentifier: pid),
                  let bundleID = app.bundleIdentifier
            else { continue }
            found.append(.init(pid: pid, bundleID: bundleID))
        }

        return found.sorted { lhs, rhs in
            let l = priority.firstIndex(of: lhs.bundleID) ?? priority.count
            let r = priority.firstIndex(of: rhs.bundleID) ?? priority.count
            return l < r
        }
    }

    private static func isRunningOutput(_ object: AudioObjectID) -> Bool {
        var propertyAddress = address(kAudioProcessPropertyIsRunningOutput)
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &propertyAddress, 0, nil, &size, &running) == noErr
        else { return false }
        return running != 0
    }

    private static func processID(_ object: AudioObjectID) -> pid_t? {
        var propertyAddress = address(kAudioProcessPropertyPID)
        var pid: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(object, &propertyAddress, 0, nil, &size, &pid) == noErr
        else { return nil }
        return pid
    }
}

// MARK: - Players that speak AppleScript

enum ScriptedPlayer: String, CaseIterable {
    case spotify = "com.spotify.client"
    case music = "com.apple.Music"

    var applicationName: String {
        switch self {
        case .spotify: "Spotify"
        case .music: "Music"
        }
    }

    static func from(bundleID: String) -> ScriptedPlayer? {
        ScriptedPlayer(rawValue: bundleID)
    }
}

struct ScriptedTrack: Equatable {
    let title: String
    let artist: String
    let album: String
    let artworkURL: String
    let isPlaying: Bool
}

enum ScriptPlayerReader {
    /// One round trip returns every field, newline separated.
    private static func metadataScript(for player: ScriptedPlayer) -> String {
        // Spotify is the only one of the two exposing an artwork URL.
        let artwork = player == .spotify ? "artwork url of current track" : "\"\""
        return """
        tell application "\(player.applicationName)"
            if player state is stopped then return ""
            set theTitle to name of current track
            set theArtist to artist of current track
            set theAlbum to album of current track
            set theArtwork to \(artwork)
            set theState to player state as text
            return theTitle & linefeed & theArtist & linefeed & theAlbum & linefeed & theArtwork & linefeed & theState
        end tell
        """
    }

    /// Blocking, callers must stay off the main queue.
    static func track(for player: ScriptedPlayer) -> ScriptedTrack? {
        guard let output = run(metadataScript(for: player)) else { return nil }
        let fields = output.components(separatedBy: "\n")
        guard fields.count >= 5, !fields[0].isEmpty else { return nil }
        return .init(
            title: fields[0],
            artist: fields[1],
            album: fields[2],
            artworkURL: fields[3],
            isPlaying: fields[4] == "playing"
        )
    }

    static func command(_ command: String, for player: ScriptedPlayer) {
        _ = run("tell application \"\(player.applicationName)\" to \(command)")
    }

    @discardableResult
    private static func run(_ source: String) -> String? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&error)
        if let error {
            // -1743 is the user declining the automation prompt, nothing to retry.
            NSLog("[NowPlaying] AppleScript failed: %@", error)
            return nil
        }
        return result.stringValue
    }
}

// MARK: - Generic transport for everything else

enum MediaKeySender {
    private static let play: Int32 = 16
    private static let next: Int32 = 19
    private static let previous: Int32 = 20

    static func togglePlayPause() { post(play) }
    static func nextTrack() { post(next) }
    static func previousTrack() { post(previous) }

    /// Media keys travel as system defined events, one press plus one release.
    private static func post(_ key: Int32) {
        for isDown in [true, false] {
            let state = isDown ? 0xA : 0xB
            let flags = NSEvent.ModifierFlags(rawValue: UInt(state << 8))
            let data1 = Int((key << 16) | Int32(state << 8))
            guard let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: flags,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            ) else { continue }
            event.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}
