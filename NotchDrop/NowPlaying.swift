//
//  NowPlaying.swift
//  NotchDrop
//
//  Tracks whatever is making sound and, where possible, what it is playing.
//

import AppKit
import Combine
import Foundation

struct NowPlayingInfo: Equatable {
    let title: String
    let artist: String
    let album: String
    let artwork: NSImage?
    let appIcon: NSImage?
    let appName: String
    let bundleID: String
    let isPlaying: Bool

    /// True when we can drive the player precisely instead of faking key presses.
    let isScriptable: Bool

    var hasContent: Bool { appIcon != nil || !title.isEmpty }
}

class NowPlayingMonitor {
    static let shared = NowPlayingMonitor()

    let info: CurrentValueSubject<NowPlayingInfo?, Never> = .init(nil)

    private var refreshTimer: Timer?
    /// Polled rather than pushed, so keep it tight enough that the flash
    /// still feels like a reaction to the key press.
    private let refreshInterval: TimeInterval = 1
    private let queue = DispatchQueue(label: "wiki.qaq.NotchDrop.nowplaying")

    /// Artwork is fetched over the network, never download the same URL twice.
    private var artworkCache: (url: String, image: NSImage)?

    private init() {
        let timer = Timer(timeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
        refresh()
    }

    deinit {
        destroy()
    }

    func destroy() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Transport

    func togglePlayPause() { control("playpause") { MediaKeySender.togglePlayPause() } }
    func nextTrack() { control("next track") { MediaKeySender.nextTrack() } }
    func previousTrack() { control("previous track") { MediaKeySender.previousTrack() } }

    private func control(_ script: String, fallback: @escaping () -> Void) {
        let player = info.value.flatMap { $0.isScriptable ? ScriptedPlayer.from(bundleID: $0.bundleID) : nil }
        queue.async { [weak self] in
            if let player {
                ScriptPlayerReader.command(script, for: player)
            } else {
                fallback()
            }
            // Reflect the new state without waiting for the next tick.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.refresh() }
        }
    }

    // MARK: - Polling

    private func refresh() {
        queue.async { [weak self] in
            guard let self else { return }
            let processes = AudioProcessReader.playingProcesses()
            guard let process = processes.first else {
                publish(nil)
                return
            }

            if let player = ScriptedPlayer.from(bundleID: process.bundleID),
               let track = ScriptPlayerReader.track(for: player) {
                let artwork = artwork(for: track.artworkURL)
                publish(process: process, track: track, artwork: artwork, scriptable: true)
                return
            }

            // Unknown player, the app identity is all we can honestly show.
            publish(process: process, track: nil, artwork: nil, scriptable: false)
        }
    }

    private func artwork(for url: String) -> NSImage? {
        guard !url.isEmpty else { return nil }
        if let cache = artworkCache, cache.url == url { return cache.image }
        guard let link = URL(string: url),
              let data = try? Data(contentsOf: link),
              let image = NSImage(data: data)
        else { return nil }
        artworkCache = (url, image)
        return image
    }

    private func publish(
        process: AudioProcess,
        track: ScriptedTrack?,
        artwork: NSImage?,
        scriptable: Bool
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let app = NSRunningApplication(processIdentifier: process.pid)
            let next = NowPlayingInfo(
                title: track?.title ?? "",
                artist: track?.artist ?? "",
                album: track?.album ?? "",
                artwork: artwork,
                appIcon: app?.icon,
                appName: app?.localizedName ?? "",
                bundleID: process.bundleID,
                // A scripted player reports real state, others are assumed live.
                isPlaying: track?.isPlaying ?? true,
                isScriptable: scriptable
            )
            send(next.hasContent ? next : nil)
        }
    }

    private func publish(_ value: NowPlayingInfo?) {
        DispatchQueue.main.async { [weak self] in
            self?.send(value)
        }
    }

    private func send(_ value: NowPlayingInfo?) {
        guard value != info.value else { return }
        info.send(value)
    }
}
