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

    let position: TimeInterval
    let duration: TimeInterval

    /// When `position` was sampled, so the bar can advance between polls.
    let positionUpdatedAt: Date

    var hasContent: Bool { appIcon != nil || !title.isEmpty }

    /// Only scripted players report a timeline, so only they get a scrubber.
    var hasProgress: Bool { duration > 0 }

    /// Where the playhead sits now, carried forward since the last sample.
    func elapsed(at date: Date) -> TimeInterval {
        guard duration > 0 else { return 0 }
        let drift = isPlaying ? date.timeIntervalSince(positionUpdatedAt) : 0
        return min(max(position + drift, 0), duration)
    }
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

    /// Only meaningful for scripted players, others have no timeline to seek.
    func seek(to seconds: TimeInterval) {
        guard let info = info.value, info.isScriptable,
              let player = ScriptedPlayer.from(bundleID: info.bundleID)
        else { return }
        queue.async { [weak self] in
            ScriptPlayerReader.seek(to: seconds, for: player)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.refresh() }
        }
    }

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

            // Asked first, and directly: a paused app releases its output
            // stream, so CoreAudio stops reporting it while the track is
            // still loaded and worth showing.
            if let candidate = scriptedCandidate() {
                let artwork = artwork(for: candidate.track.artworkURL)
                publish(
                    pid: candidate.pid,
                    bundleID: candidate.player.rawValue,
                    track: candidate.track,
                    artwork: artwork,
                    scriptable: true
                )
                return
            }

            guard let process = AudioProcessReader.playingProcesses().first else {
                publish(nil)
                return
            }

            // Unknown player, the app identity is all we can honestly show.
            publish(
                pid: process.pid,
                bundleID: process.bundleID,
                track: nil,
                artwork: nil,
                scriptable: false
            )
        }
    }

    /// A playing player wins over a merely paused one.
    private func scriptedCandidate() -> (player: ScriptedPlayer, track: ScriptedTrack, pid: pid_t)? {
        var paused: (ScriptedPlayer, ScriptedTrack, pid_t)?
        for player in ScriptedPlayer.allCases {
            // Never script an app that is not already open, it would launch it.
            guard let app = NSRunningApplication
                .runningApplications(withBundleIdentifier: player.rawValue).first,
                let track = ScriptPlayerReader.track(for: player)
            else { continue }

            if track.isPlaying {
                return (player, track, app.processIdentifier)
            }
            if paused == nil {
                paused = (player, track, app.processIdentifier)
            }
        }
        return paused
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
        pid: pid_t,
        bundleID: String,
        track: ScriptedTrack?,
        artwork: NSImage?,
        scriptable: Bool
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let app = NSRunningApplication(processIdentifier: pid)
            let next = NowPlayingInfo(
                title: track?.title ?? "",
                artist: track?.artist ?? "",
                album: track?.album ?? "",
                artwork: artwork,
                appIcon: app?.icon,
                appName: app?.localizedName ?? "",
                bundleID: bundleID,
                // A scripted player reports real state, others are assumed live.
                isPlaying: track?.isPlaying ?? true,
                isScriptable: scriptable,
                position: track?.position ?? 0,
                duration: track?.duration ?? 0,
                positionUpdatedAt: Date()
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
